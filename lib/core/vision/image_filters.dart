import 'dart:math' as math;
import 'dart:typed_data';

/// Filter presets, mirroring `PageFilter` in the domain layer (kept separate
/// so this file stays free of app dependencies and can run in isolates).
enum FilterKind { original, grayscale, blackWhite, enhanced, colorDocument }

/// Pixel operations on interleaved RGBA buffers (4 bytes per pixel, row
/// length = width × 4). All functions modify [rgba] in place and are meant
/// to run in a background isolate.
abstract final class ImageFilters {
  /// Applies a filter preset, then brightness/contrast and sharpening.
  static void apply(
    Uint8List rgba,
    int width,
    int height, {
    required FilterKind filter,
    double brightness = 0,
    double contrast = 0,
    double sharpness = 0,
  }) {
    switch (filter) {
      case FilterKind.original:
        break;
      case FilterKind.grayscale:
        grayscale(rgba);
      case FilterKind.blackWhite:
        grayscale(rgba);
        adaptiveThreshold(rgba, width, height);
      case FilterKind.enhanced:
        autoLevels(rgba);
        whitenPaper(rgba);
        sharpen(rgba, width, height, 0.5);
      case FilterKind.colorDocument:
        autoLevels(rgba);
        saturate(rgba, 1.35);
        whitenPaper(rgba);
    }
    if (brightness != 0 || contrast != 0) {
      brightnessContrast(rgba, brightness, contrast);
    }
    // Sharpening a binarised page only adds halos.
    if (sharpness > 0 && filter != FilterKind.blackWhite) {
      sharpen(rgba, width, height, sharpness * 1.5);
    }
  }

  /// BT.601 luma, written to R, G and B.
  static void grayscale(Uint8List rgba) {
    for (var i = 0; i < rgba.length; i += 4) {
      final y = (rgba[i] * 77 + rgba[i + 1] * 150 + rgba[i + 2] * 29) >> 8;
      rgba[i] = y;
      rgba[i + 1] = y;
      rgba[i + 2] = y;
    }
  }

  /// Bradley–Roth adaptive threshold using an integral image: a pixel turns
  /// black if it is [percent]% darker than the mean of its neighbourhood.
  /// Handles uneven lighting and shadows far better than a global cut-off.
  /// Expects a grayscale image (R = G = B).
  static void adaptiveThreshold(
    Uint8List rgba,
    int width,
    int height, {
    double windowFraction = 1 / 16,
    double percent = 12,
  }) {
    final integral = Uint32List((width + 1) * (height + 1));
    final stride = width + 1;
    for (var y = 0; y < height; y++) {
      var rowSum = 0;
      for (var x = 0; x < width; x++) {
        rowSum += rgba[(y * width + x) * 4];
        integral[(y + 1) * stride + x + 1] =
            integral[y * stride + x + 1] + rowSum;
      }
    }
    final half = math.max(
      4,
      (math.max(width, height) * windowFraction / 2).round(),
    );
    final factor = 1 - percent / 100;
    for (var y = 0; y < height; y++) {
      final y0 = math.max(0, y - half);
      final y1 = math.min(height, y + half + 1);
      for (var x = 0; x < width; x++) {
        final x0 = math.max(0, x - half);
        final x1 = math.min(width, x + half + 1);
        final count = (y1 - y0) * (x1 - x0);
        final sum =
            integral[y1 * stride + x1] -
            integral[y0 * stride + x1] -
            integral[y1 * stride + x0] +
            integral[y0 * stride + x0];
        final i = (y * width + x) * 4;
        final v = rgba[i] * count < sum * factor ? 0 : 255;
        rgba[i] = v;
        rgba[i + 1] = v;
        rgba[i + 2] = v;
      }
    }
  }

  /// Stretches each channel so the darkest 0.5 % and brightest 0.5 % of
  /// pixels map to 0 and 255. Removes colour casts and grey, flat scans.
  static void autoLevels(Uint8List rgba, {double clip = 0.005}) {
    final pixels = rgba.length ~/ 4;
    if (pixels == 0) return;
    for (var c = 0; c < 3; c++) {
      final hist = Int32List(256);
      for (var i = c; i < rgba.length; i += 4) {
        hist[rgba[i]]++;
      }
      final cut = (pixels * clip).floor();
      var low = 0;
      var acc = 0;
      while (low < 255 && acc + hist[low] <= cut) {
        acc += hist[low++];
      }
      var high = 255;
      acc = 0;
      while (high > 0 && acc + hist[high] <= cut) {
        acc += hist[high--];
      }
      if (high - low < 16) continue; // nearly flat channel: leave it
      final lut = Uint8List(256);
      for (var v = 0; v < 256; v++) {
        lut[v] = ((v - low) * 255 / (high - low)).round().clamp(0, 255);
      }
      for (var i = c; i < rgba.length; i += 4) {
        rgba[i] = lut[rgba[i]];
      }
    }
  }

  /// Pushes near-white paper tones to pure white so pages look clean,
  /// without touching ink.
  static void whitenPaper(Uint8List rgba, {int from = 200, int reach = 25}) {
    // Identity below [from]; above it, rise steeply so that [from] + [reach]
    // already maps to pure white.
    final lut = Uint8List(256);
    for (var v = 0; v < 256; v++) {
      lut[v] = v < from
          ? v
          : math.min(255, from + ((v - from) * (255 - from) / reach).round());
    }
    for (var i = 0; i < rgba.length; i += 4) {
      rgba[i] = lut[rgba[i]];
      rgba[i + 1] = lut[rgba[i + 1]];
      rgba[i + 2] = lut[rgba[i + 2]];
    }
  }

  /// Scales colourfulness around each pixel's luma.
  static void saturate(Uint8List rgba, double amount) {
    for (var i = 0; i < rgba.length; i += 4) {
      final y = (rgba[i] * 77 + rgba[i + 1] * 150 + rgba[i + 2] * 29) >> 8;
      for (var c = 0; c < 3; c++) {
        rgba[i + c] = (y + (rgba[i + c] - y) * amount).round().clamp(0, 255);
      }
    }
  }

  /// [brightness] −1…1 shifts by up to ±100 levels; [contrast] −1…1 scales
  /// around mid-grey by 0.3×…2.5×.
  static void brightnessContrast(
    Uint8List rgba,
    double brightness,
    double contrast,
  ) {
    final shift = brightness.clamp(-1.0, 1.0) * 100;
    final c = contrast.clamp(-1.0, 1.0);
    final scale = c >= 0 ? 1 + c * 1.5 : 1 + c * 0.7;
    final lut = Uint8List(256);
    for (var v = 0; v < 256; v++) {
      lut[v] = ((v - 128) * scale + 128 + shift).round().clamp(0, 255);
    }
    for (var i = 0; i < rgba.length; i += 4) {
      rgba[i] = lut[rgba[i]];
      rgba[i + 1] = lut[rgba[i + 1]];
      rgba[i + 2] = lut[rgba[i + 2]];
    }
  }

  /// Unsharp mask with a 3×3 box blur: `out = in + amount × (in − blur)`.
  static void sharpen(Uint8List rgba, int width, int height, double amount) {
    if (amount <= 0 || width < 3 || height < 3) return;
    final src = Uint8List.fromList(rgba);
    final row = width * 4;
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final i = y * row + x * 4;
        for (var c = 0; c < 3; c++) {
          final p = i + c;
          final sum =
              src[p - row - 4] +
              src[p - row] +
              src[p - row + 4] +
              src[p - 4] +
              src[p] +
              src[p + 4] +
              src[p + row - 4] +
              src[p + row] +
              src[p + row + 4];
          final blur = sum / 9;
          rgba[p] = (src[p] + amount * (src[p] - blur)).round().clamp(0, 255);
        }
      }
    }
  }
}
