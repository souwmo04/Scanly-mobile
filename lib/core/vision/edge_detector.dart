import 'dart:math' as math;
import 'dart:typed_data';

import 'gray_image.dart';

/// Classic image-processing steps used by the document detector:
/// Gaussian blur, Sobel gradients, Canny edges and morphological dilation.
abstract final class EdgeDetector {
  /// 5×5 Gaussian blur (σ ≈ 1.1) as two separable passes with integer
  /// weights 1-4-6-4-1. Borders are clamped.
  static GrayImage gaussianBlur(GrayImage src) {
    final w = src.width;
    final h = src.height;
    final tmp = Uint16List(w * h);
    final out = Uint8List(w * h);
    final d = src.data;

    int clampX(int x) => x < 0 ? 0 : (x >= w ? w - 1 : x);
    int clampY(int y) => y < 0 ? 0 : (y >= h ? h - 1 : y);

    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        tmp[row + x] =
            d[row + clampX(x - 2)] +
            4 * d[row + clampX(x - 1)] +
            6 * d[row + x] +
            4 * d[row + clampX(x + 1)] +
            d[row + clampX(x + 2)];
      }
    }
    for (var y = 0; y < h; y++) {
      final r0 = clampY(y - 2) * w;
      final r1 = clampY(y - 1) * w;
      final r2 = y * w;
      final r3 = clampY(y + 1) * w;
      final r4 = clampY(y + 2) * w;
      for (var x = 0; x < w; x++) {
        final sum =
            tmp[r0 + x] +
            4 * tmp[r1 + x] +
            6 * tmp[r2 + x] +
            4 * tmp[r3 + x] +
            tmp[r4 + x];
        out[r2 + x] = (sum + 128) >> 8; // weights total 16 × 16 = 256
      }
    }
    return GrayImage(w, h, out);
  }

  /// Canny edge detection. Returns a binary image (255 = edge).
  ///
  /// Thresholds adapt to the frame: the high threshold is the
  /// [highPercentile] of non-zero gradient magnitudes (with a floor so flat
  /// frames produce no edges) and the low threshold is [lowRatio] × high.
  /// Adaptive thresholds matter for low-contrast scenes such as white paper
  /// on a white desk.
  static GrayImage canny(
    GrayImage src, {
    double highPercentile = 0.85,
    double lowRatio = 0.4,
    int minHigh = 24,
  }) {
    final w = src.width;
    final h = src.height;
    final d = src.data;
    final mag = Int32List(w * h);
    final dir = Uint8List(w * h); // 0: 0°, 1: 45°, 2: 90°, 3: 135°

    // Sobel gradients (borders left at zero).
    final histogram = Int32List(2048);
    var nonZero = 0;
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final gx =
            -d[i - w - 1] -
            2 * d[i - 1] -
            d[i + w - 1] +
            d[i - w + 1] +
            2 * d[i + 1] +
            d[i + w + 1];
        final gy =
            -d[i - w - 1] -
            2 * d[i - w] -
            d[i - w + 1] +
            d[i + w - 1] +
            2 * d[i + w] +
            d[i + w + 1];
        final m = gx.abs() + gy.abs(); // L1 norm, fast and adequate
        mag[i] = m;
        if (m > 0) {
          histogram[math.min(m, 2047)]++;
          nonZero++;
        }
        // Quantise direction using tan(22.5°) ≈ 0.4142 ≈ 53/128.
        final ax = gx.abs();
        final ay = gy.abs();
        if (ay * 128 <= ax * 53) {
          dir[i] = 0;
        } else if (ax * 128 <= ay * 53) {
          dir[i] = 2;
        } else {
          dir[i] = (gx ^ gy) < 0 ? 3 : 1;
        }
      }
    }

    var high = minHigh;
    if (nonZero > 0) {
      final target = (nonZero * highPercentile).floor();
      var cumulative = 0;
      for (var m = 1; m < histogram.length; m++) {
        cumulative += histogram[m];
        if (cumulative >= target) {
          high = math.max(m, minHigh);
          break;
        }
      }
    }
    final low = math.max(1, (high * lowRatio).round());

    // Non-maximum suppression: 2 = strong, 1 = weak, 0 = none.
    final state = Uint8List(w * h);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final m = mag[i];
        if (m < low) continue;
        final (a, b) = switch (dir[i]) {
          0 => (mag[i - 1], mag[i + 1]),
          2 => (mag[i - w], mag[i + w]),
          // Same-sign gradient points along (+1, +1) in image coordinates.
          1 => (mag[i - w - 1], mag[i + w + 1]),
          _ => (mag[i - w + 1], mag[i + w - 1]),
        };
        if (m >= a && m > b) state[i] = m >= high ? 2 : 1;
      }
    }

    // Hysteresis: keep weak edges connected to strong ones.
    final out = Uint8List(w * h);
    final stack = <int>[];
    for (var i = 0; i < state.length; i++) {
      if (state[i] != 2 || out[i] != 0) continue;
      out[i] = 255;
      stack.add(i);
      while (stack.isNotEmpty) {
        final p = stack.removeLast();
        final px = p % w;
        final py = p ~/ w;
        for (var dy = -1; dy <= 1; dy++) {
          final ny = py + dy;
          if (ny < 0 || ny >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = px + dx;
            if (nx < 0 || nx >= w) continue;
            final n = ny * w + nx;
            if (state[n] != 0 && out[n] == 0) {
              out[n] = 255;
              stack.add(n);
            }
          }
        }
      }
    }
    return GrayImage(w, h, out);
  }

  /// 3×3 binary dilation; closes small gaps in document outlines.
  static GrayImage dilate(GrayImage src) {
    final w = src.width;
    final h = src.height;
    final d = src.data;
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (d[y * w + x] == 0) continue;
        for (var dy = -1; dy <= 1; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx;
            if (nx >= 0 && nx < w) out[ny * w + nx] = 255;
          }
        }
      }
    }
    return GrayImage(w, h, out);
  }
}
