import 'dart:math' as math;

/// A 2D point (double precision).
class Pt {
  const Pt(this.x, this.y);

  final double x;
  final double y;

  Pt operator -(Pt o) => Pt(x - o.x, y - o.y);
  Pt operator +(Pt o) => Pt(x + o.x, y + o.y);
  Pt scale(double sx, [double? sy]) => Pt(x * sx, y * (sy ?? sx));

  double distanceTo(Pt o) =>
      math.sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y));

  @override
  bool operator ==(Object other) => other is Pt && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

double _cross(Pt o, Pt a, Pt b) =>
    (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

/// A document outline: four corners in clockwise order starting top-left
/// (image coordinates, y pointing down).
class Quad {
  const Quad(this.topLeft, this.topRight, this.bottomRight, this.bottomLeft);

  /// Orders four arbitrary corners as top-left, top-right, bottom-right,
  /// bottom-left. Robust to rotation up to ±45°.
  factory Quad.fromUnordered(List<Pt> points) {
    if (points.length != 4) {
      throw ArgumentError('A quad needs exactly 4 points');
    }
    // Sort clockwise around the centroid, then rotate so the corner with the
    // smallest x + y (top-left) comes first.
    final cx = points.fold(0.0, (s, p) => s + p.x) / 4;
    final cy = points.fold(0.0, (s, p) => s + p.y) / 4;
    final sorted = List.of(points)
      ..sort(
        (a, b) => math
            .atan2(a.y - cy, a.x - cx)
            .compareTo(math.atan2(b.y - cy, b.x - cx)),
      );
    var start = 0;
    for (var i = 1; i < 4; i++) {
      if (sorted[i].x + sorted[i].y < sorted[start].x + sorted[start].y) {
        start = i;
      }
    }
    final o = [for (var i = 0; i < 4; i++) sorted[(start + i) % 4]];
    return Quad(o[0], o[1], o[2], o[3]);
  }

  /// The full rectangle `width × height`.
  factory Quad.fullFrame(double width, double height) =>
      Quad(const Pt(0, 0), Pt(width, 0), Pt(width, height), Pt(0, height));

  /// Parses `[x0, y0, x1, y1, x2, y2, x3, y3]`.
  factory Quad.fromList(List<double> v) {
    if (v.length != 8) throw ArgumentError('Expected 8 values');
    return Quad(Pt(v[0], v[1]), Pt(v[2], v[3]), Pt(v[4], v[5]), Pt(v[6], v[7]));
  }

  final Pt topLeft;
  final Pt topRight;
  final Pt bottomRight;
  final Pt bottomLeft;

  List<Pt> get points => [topLeft, topRight, bottomRight, bottomLeft];

  List<double> toList() => [
    for (final p in points) ...[p.x, p.y],
  ];

  /// Scales every coordinate, e.g. from detection size to full resolution
  /// or to normalised 0–1 coordinates.
  Quad scale(double sx, [double? sy]) => Quad(
    topLeft.scale(sx, sy),
    topRight.scale(sx, sy),
    bottomRight.scale(sx, sy),
    bottomLeft.scale(sx, sy),
  );

  /// Shoelace area (always positive).
  double get area {
    final p = points;
    var sum = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = p[i];
      final b = p[(i + 1) % 4];
      sum += a.x * b.y - b.x * a.y;
    }
    return sum.abs() / 2;
  }

  double get perimeter {
    final p = points;
    var sum = 0.0;
    for (var i = 0; i < 4; i++) {
      sum += p[i].distanceTo(p[(i + 1) % 4]);
    }
    return sum;
  }

  /// True if all turns go the same way (no self-intersection or dent).
  bool get isConvex {
    final p = points;
    var sign = 0;
    for (var i = 0; i < 4; i++) {
      final c = _cross(p[i], p[(i + 1) % 4], p[(i + 2) % 4]);
      if (c.abs() < 1e-9) return false;
      final s = c > 0 ? 1 : -1;
      if (sign == 0) {
        sign = s;
      } else if (s != sign) {
        return false;
      }
    }
    return true;
  }

  /// Interior angles in degrees, one per corner.
  List<double> get angles {
    final p = points;
    return [
      for (var i = 0; i < 4; i++)
        _angleAt(p[(i + 3) % 4], p[i], p[(i + 1) % 4]),
    ];
  }

  static double _angleAt(Pt prev, Pt corner, Pt next) {
    final a = prev - corner;
    final b = next - corner;
    final dot = a.x * b.x + a.y * b.y;
    final len =
        math.sqrt(a.x * a.x + a.y * a.y) * math.sqrt(b.x * b.x + b.y * b.y);
    if (len == 0) return 0;
    return math.acos((dot / len).clamp(-1.0, 1.0)) * 180 / math.pi;
  }

  /// Width and height of the flattened document: the longer of each pair of
  /// opposite sides.
  (double width, double height) get outputSize => (
    math.max(topLeft.distanceTo(topRight), bottomLeft.distanceTo(bottomRight)),
    math.max(topLeft.distanceTo(bottomLeft), topRight.distanceTo(bottomRight)),
  );

  /// Largest corner movement relative to [other].
  double maxCornerDistance(Quad other) {
    final a = points;
    final b = other.points;
    var maxD = 0.0;
    for (var i = 0; i < 4; i++) {
      maxD = math.max(maxD, a[i].distanceTo(b[i]));
    }
    return maxD;
  }

  @override
  bool operator ==(Object other) =>
      other is Quad &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);

  @override
  String toString() => 'Quad($topLeft, $topRight, $bottomRight, $bottomLeft)';
}

/// Rules a detected outline must satisfy to count as a document.
class QuadValidator {
  const QuadValidator({
    this.minAreaRatio = 0.12,
    this.maxAreaRatio = 0.985,
    this.minAngle = 45,
    this.maxAngle = 135,
    this.maxAspectRatio = 4.5,
    this.minSideRatio = 0.08,
  });

  /// Document area as a share of the frame.
  final double minAreaRatio;
  final double maxAreaRatio;

  /// Interior angle bounds in degrees (perspective skews right angles).
  final double minAngle;
  final double maxAngle;

  /// Longer side / shorter side of the flattened document.
  final double maxAspectRatio;

  /// Shortest side as a share of the frame's shorter dimension.
  final double minSideRatio;

  /// Returns null if valid, otherwise a short reason (useful in tests/logs).
  String? check(Quad quad, double frameWidth, double frameHeight) {
    if (!quad.isConvex) return 'not convex';
    final ratio = quad.area / (frameWidth * frameHeight);
    if (ratio < minAreaRatio) return 'too small';
    if (ratio > maxAreaRatio) return 'fills the frame';
    for (final a in quad.angles) {
      if (a < minAngle || a > maxAngle) return 'corner angle $a';
    }
    final (w, h) = quad.outputSize;
    final shorter = math.min(w, h);
    if (shorter <= 0) return 'degenerate';
    if (math.max(w, h) / shorter > maxAspectRatio) return 'aspect ratio';
    final p = quad.points;
    final minFrame = math.min(frameWidth, frameHeight);
    for (var i = 0; i < 4; i++) {
      if (p[i].distanceTo(p[(i + 1) % 4]) < minFrame * minSideRatio) {
        return 'side too short';
      }
    }
    return null;
  }

  bool isValid(Quad quad, double frameWidth, double frameHeight) =>
      check(quad, frameWidth, frameHeight) == null;
}
