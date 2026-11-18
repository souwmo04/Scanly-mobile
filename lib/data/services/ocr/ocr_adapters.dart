import '../../../domain/entities/ocr_result.dart';

/// A recognised line with its bounding box in image pixels, as reported by
/// an engine that knows positions (ML Kit).
class PixelLine {
  const PixelLine(this.text, this.left, this.top, this.right, this.bottom);

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
}

/// Narrow seam over ML Kit's Latin text recognizer, so the routing and
/// mapping logic can be unit-tested on the host with a fake.
abstract interface class LatinTextRecognizer {
  /// Lines in reading order (block by block). Throws on any engine failure.
  Future<List<List<PixelLine>>> recognizeBlocks(String imagePath);
}

/// Narrow seam over the Tesseract plugin.
abstract interface class TesseractRunner {
  /// Plain recognised text for [languageCode] (`eng`, `ben`, `ben+eng`).
  /// Throws on any engine failure.
  Future<String> extractText(String imagePath, String languageCode);
}

/// Converts a pixel rectangle to an [OcrBox] normalised 0–1 to an image of
/// [width] × [height] pixels.
///
/// Coordinates are clamped to the image, swapped if reversed, and `null` is
/// returned when the size is unknown/invalid or nothing of the box lies
/// inside the image.
OcrBox? normalisePixelBox({
  required double left,
  required double top,
  required double right,
  required double bottom,
  required num width,
  required num height,
}) {
  if (width <= 0 || height <= 0) return null;
  final values = [left, top, right, bottom];
  if (values.any((v) => v.isNaN || v.isInfinite)) return null;
  double clamp(double v) => v.clamp(0.0, 1.0);
  var l = clamp(left / width);
  var r = clamp(right / width);
  var t = clamp(top / height);
  var b = clamp(bottom / height);
  if (l > r) (l, r) = (r, l);
  if (t > b) (t, b) = (b, t);
  if (r <= l || b <= t) return null;
  return OcrBox(l, t, r, b);
}
