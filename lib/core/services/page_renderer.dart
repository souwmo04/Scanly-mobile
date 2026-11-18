import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

import '../errors/app_exception.dart';
import '../vision/homography.dart';
import '../vision/image_filters.dart';
import '../vision/quad.dart';

/// Renders a page image from its untouched original:
/// crop (perspective) → rotate → filter → brightness/contrast → sharpen.
///
/// Geometry is drawn with Flutter's renderer (GPU on devices); pixel filters
/// and JPEG encoding run in a background isolate. The same function produces
/// the editor preview (small [maxSide]) and the saved page (full size), so
/// what users see is what gets saved.
class PageRenderer {
  const PageRenderer();

  Future<Uint8List> render(
    String originalPath, {
    required Quad corners,
    int rotation = 0,
    FilterKind filter = FilterKind.original,
    double brightness = 0,
    double contrast = 0,
    double sharpness = 0,
    int maxSide = 4096,
    int jpegQuality = 88,
  }) async {
    final source = await decodeImage(originalPath, maxSide: maxSide);
    ui.Image? output;
    try {
      final pixelQuad = corners.scale(
        source.width.toDouble(),
        source.height.toDouble(),
      );
      var (cropW, cropH) = pixelQuad.outputSize;
      final longest = math.max(cropW, cropH);
      if (longest > maxSide) {
        final s = maxSide / longest;
        cropW *= s;
        cropH *= s;
      }
      final cw = math.max(1, cropW.round());
      final ch = math.max(1, cropH.round());

      final Homography transform;
      try {
        transform = Homography.fromQuads(
          pixelQuad,
          Quad.fullFrame(cw.toDouble(), ch.toDouble()),
        );
      } on ArgumentError catch (e) {
        throw ValidationException('The crop corners are not a valid shape.', e);
      }

      final turns = ((rotation % 360) ~/ 90) % 4;
      final width = turns.isOdd ? ch : cw;
      final height = turns.isOdd ? cw : ch;

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      // Rotate the cropped page clockwise by [turns] quarter turns.
      switch (turns) {
        case 1:
          canvas
            ..translate(ch.toDouble(), 0)
            ..rotate(math.pi / 2);
        case 2:
          canvas
            ..translate(cw.toDouble(), ch.toDouble())
            ..rotate(math.pi);
        case 3:
          canvas
            ..translate(0, cw.toDouble())
            ..rotate(3 * math.pi / 2);
      }
      canvas
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
        throw const StorageException('Could not read the page pixels.');
      }
      final pixels = rgba.buffer.asUint8List();
      final needsFilters =
          filter != FilterKind.original ||
          brightness != 0 ||
          contrast != 0 ||
          sharpness != 0;
      return await Isolate.run(() {
        if (needsFilters) {
          ImageFilters.apply(
            pixels,
            width,
            height,
            filter: filter,
            brightness: brightness,
            contrast: contrast,
            sharpness: sharpness,
          );
        }
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
  static Future<ui.Image> decodeImage(
    String path, {
    required int maxSide,
  }) async {
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
