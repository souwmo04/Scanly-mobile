import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../vision/document_detector.dart';
import '../vision/gray_image.dart';
import '../vision/quad.dart';
import 'page_renderer.dart';

/// Finds and flattens documents in still photos.
///
/// * Detection decodes a small copy (≤ [analysisSize] px) through the
///   platform codec, which also applies EXIF rotation, and runs the
///   pure-Dart [DocumentDetector] in a background isolate.
/// * Flattening is a [PageRenderer] render with only a crop.
class PageCropper {
  const PageCropper({
    this.detector = const DocumentDetector(),
    this.renderer = const PageRenderer(),
    this.analysisSize = 720,
    this.maxOutputSide = 4096,
  });

  final DocumentDetector detector;
  final PageRenderer renderer;
  final int analysisSize;

  /// Longest side of a flattened page; keeps memory bounded on huge photos.
  final int maxOutputSide;

  /// Detects the document in the image at [path]. Returns its corners
  /// normalised to 0–1 of the displayed image, or null if none is found.
  Future<Quad?> detect(String path) async {
    final frame = await PageRenderer.decodeImage(path, maxSide: analysisSize);
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
  }) => renderer.render(
    path,
    corners: corners,
    maxSide: maxOutputSide,
    jpegQuality: jpegQuality,
  );
}
