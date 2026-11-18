import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

import '../errors/app_exception.dart';
import '../vision/document_detector.dart';
import '../vision/gray_image.dart';
import '../vision/homography.dart';
import '../vision/quad.dart';

/// Finds and flattens documents in still photos.
///
/// * Detection decodes a small copy (≤ [analysisSize] px) through the
///   platform codec, which also applies EXIF rotation, and runs the
///   pure-Dart [DocumentDetector] in a background isolate.
/// * Flattening draws the full-resolution photo through a projective
///   transform with Flutter's renderer (GPU on devices), then JPEG-encodes
///   the result in a background isolate.
class PageCropper {
  const PageCropper({
    this.detector = const DocumentDetector(),
    this.analysisSize = 720,
    this.maxOutputSide = 4096,
  });

  final DocumentDetector detector;
  final int analysisSize;

  /// Longest side of a flattened page; keeps memory bounded on huge photos.
  final int maxOutputSide;

  /// Detects the document in the image at [path]. Returns its corners
  /// normalised to 0–1 of the displayed image, or null if none is found.
  Future<Quad?> detect(String path) async {
    final frame = await _decode(path, maxSide: analysisSize);
    try {
      final rgba = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) return null;
      final width = frame.width;
      final height = frame.height;
      final pixels = rgba.buffer.asUint8List();
      final detector = this.detector;
      return await Isolate.run(() {
        final gray = GrayImage.fromFourChannel(
          pixels,
          width: width,
          height: height,
          rowStride: width * 4,
        );
        return detector.detect(gray)?.normalized;
      });
    } finally {
      frame.dispose();
    }
  }

  /// Flattens the region [corners] (normalised 0–1) of the image at [path]
  /// into an upright rectangle and returns it as JPEG bytes.
  Future<Uint8List> flatten(
    String path,
    Quad corners, {
    int jpegQuality = 88,
  }) async {
    final source = await _decode(path, maxSide: maxOutputSide);
    ui.Image? output;
    try {
      final pixelQuad = corners.scale(
        source.width.toDouble(),
        source.height.toDouble(),
      );
      var (outW, outH) = pixelQuad.outputSize;
      final longest = math.max(outW, outH);
      if (longest > maxOutputSide) {
        final s = maxOutputSide / longest;
        outW *= s;
        outH *= s;
      }
      final width = math.max(1, outW.round());
      final height = math.max(1, outH.round());

      final Homography transform;
      try {
        transform = Homography.fromQuads(
          pixelQuad,
          Quad.fullFrame(width.toDouble(), height.toDouble()),
        );
      } on ArgumentError catch (e) {
        throw ValidationException('The crop corners are not a valid shape.', e);
      }

      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
        ..transform(transform.toMatrix4())
        ..drawImage(
          source,
          ui.Offset.zero,
          ui.Paint()..filterQuality = ui.FilterQuality.high,
        );
      final picture = recorder.endRecording();
      output = await picture.toImage(width, height);
      picture.dispose();

      final rgba = await output.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) {
        throw const StorageException('Could not read the flattened page.');
      }
      final pixels = rgba.buffer.asUint8List();
      return await Isolate.run(() {
        final image = img.Image.fromBytes(
          width: width,
          height: height,
          bytes: pixels.buffer,
          numChannels: 4,
        );
        return img.encodeJpg(image, quality: jpegQuality);
      });
    } finally {
      output?.dispose();
      source.dispose();
    }
  }

  /// Decodes the image at [path] with EXIF rotation applied, limiting the
  /// longest side to [maxSide].
  static Future<ui.Image> _decode(String path, {required int maxSide}) async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width;
      final h = descriptor.height;
      final scale = math.max(w, h) > maxSide;
      final codec = await descriptor.instantiateCodec(
        targetWidth: scale && w >= h ? maxSide : null,
        targetHeight: scale && h > w ? maxSide : null,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } on Object catch (e) {
      throw StorageException('This image could not be opened.', e);
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}
