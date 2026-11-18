import 'dart:math' as math;
import 'dart:typed_data';

/// 8-bit single-channel image stored row by row (no padding).
///
/// Document detection works on small grayscale frames (about 320 px on the
/// long side), so every operation here is simple, allocation-light Dart that
/// runs in a background isolate in a few milliseconds.
class GrayImage {
  GrayImage(this.width, this.height, [Uint8List? data])
    : data = data ?? Uint8List(width * height) {
    if (this.data.length != width * height) {
      throw ArgumentError(
        'Expected ${width * height} bytes, got ${this.data.length}',
      );
    }
  }

  final int width;
  final int height;
  final Uint8List data;

  int get(int x, int y) => data[y * width + x];

  void set(int x, int y, int value) => data[y * width + x] = value;

  /// Builds a grayscale image from a luminance plane (e.g. the Y plane of a
  /// YUV420 camera frame), sampling every [step]-th pixel. [rowStride] is the
  /// number of bytes per row in [plane], which may include padding.
  factory GrayImage.fromLumaPlane(
    Uint8List plane, {
    required int width,
    required int height,
    required int rowStride,
    int step = 1,
  }) {
    final outW = width ~/ step;
    final outH = height ~/ step;
    final out = Uint8List(outW * outH);
    var i = 0;
    for (var y = 0; y < outH; y++) {
      final row = y * step * rowStride;
      for (var x = 0; x < outW; x++) {
        out[i++] = plane[row + x * step];
      }
    }
    return GrayImage(outW, outH, out);
  }

  /// Builds a grayscale image from 4-byte pixels (RGBA or BGRA), sampling
  /// every [step]-th pixel. Uses integer BT.601 luma weights.
  factory GrayImage.fromFourChannel(
    Uint8List pixels, {
    required int width,
    required int height,
    required int rowStride,
    bool bgra = false,
    int step = 1,
  }) {
    final outW = width ~/ step;
    final outH = height ~/ step;
    final out = Uint8List(outW * outH);
    final rOff = bgra ? 2 : 0;
    final bOff = bgra ? 0 : 2;
    var i = 0;
    for (var y = 0; y < outH; y++) {
      final row = y * step * rowStride;
      for (var x = 0; x < outW; x++) {
        final p = row + x * step * 4;
        out[i++] =
            (pixels[p + rOff] * 77 +
                pixels[p + 1] * 150 +
                pixels[p + bOff] * 29) >>
            8;
      }
    }
    return GrayImage(outW, outH, out);
  }

  /// Area-averaging downscale so the longest side is at most [maxSide].
  GrayImage downscale(int maxSide) {
    final longest = math.max(width, height);
    if (longest <= maxSide) return this;
    final factor = (longest / maxSide).ceil();
    final outW = width ~/ factor;
    final outH = height ~/ factor;
    final out = Uint8List(outW * outH);
    final area = factor * factor;
    for (var y = 0; y < outH; y++) {
      for (var x = 0; x < outW; x++) {
        var sum = 0;
        for (var dy = 0; dy < factor; dy++) {
          final row = (y * factor + dy) * width + x * factor;
          for (var dx = 0; dx < factor; dx++) {
            sum += data[row + dx];
          }
        }
        out[y * outW + x] = sum ~/ area;
      }
    }
    return GrayImage(outW, outH, out);
  }

  /// Rotates clockwise by [quarterTurns] × 90°.
  GrayImage rotate(int quarterTurns) {
    final turns = quarterTurns % 4;
    if (turns == 0) return this;
    final outW = turns.isOdd ? height : width;
    final outH = turns.isOdd ? width : height;
    final out = Uint8List(outW * outH);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final (nx, ny) = switch (turns) {
          1 => (height - 1 - y, x),
          2 => (width - 1 - x, height - 1 - y),
          _ => (y, width - 1 - x),
        };
        out[ny * outW + nx] = data[y * width + x];
      }
    }
    return GrayImage(outW, outH, out);
  }
}
