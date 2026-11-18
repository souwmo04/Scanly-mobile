import 'dart:math' as math;
import 'dart:typed_data';

import 'gray_image.dart';
import 'quad.dart';

/// A group of 8-connected edge pixels.
class EdgeComponent {
  EdgeComponent(this.points);

  final List<Pt> points;
}

/// Contour helpers: connected components, convex hull and Douglas–Peucker
/// polygon simplification (equivalent to OpenCV's findContours / convexHull
/// / approxPolyDP for this use).
abstract final class Contours {
  /// Finds 8-connected components of non-zero pixels with at least
  /// [minPixels] pixels, largest first.
  static List<EdgeComponent> components(GrayImage edges, {int minPixels = 40}) {
    final w = edges.width;
    final h = edges.height;
    final d = edges.data;
    final visited = Uint8List(w * h);
    final result = <EdgeComponent>[];
    final stack = <int>[];

    for (var start = 0; start < d.length; start++) {
      if (d[start] == 0 || visited[start] != 0) continue;
      final points = <Pt>[];
      visited[start] = 1;
      stack.add(start);
      while (stack.isNotEmpty) {
        final p = stack.removeLast();
        final px = p % w;
        final py = p ~/ w;
        points.add(Pt(px.toDouble(), py.toDouble()));
        for (var dy = -1; dy <= 1; dy++) {
          final ny = py + dy;
          if (ny < 0 || ny >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = px + dx;
            if (nx < 0 || nx >= w) continue;
            final n = ny * w + nx;
            if (d[n] != 0 && visited[n] == 0) {
              visited[n] = 1;
              stack.add(n);
            }
          }
        }
      }
      if (points.length >= minPixels) result.add(EdgeComponent(points));
    }
    result.sort((a, b) => b.points.length.compareTo(a.points.length));
    return result;
  }

  /// Convex hull (Andrew's monotone chain), counter-clockwise in a y-up
  /// frame, i.e. clockwise on screen. No repeated end point.
  static List<Pt> convexHull(List<Pt> input) {
    if (input.length < 3) return List.of(input);
    final pts = List.of(input)
      ..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));

    double cross(Pt o, Pt a, Pt b) =>
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

    final lower = <Pt>[];
    for (final p in pts) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    final upper = <Pt>[];
    for (final p in pts.reversed) {
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  /// Simplifies a closed polygon with the Douglas–Peucker algorithm.
  static List<Pt> approxPolygon(List<Pt> closed, double epsilon) {
    if (closed.length <= 4) return List.of(closed);
    // Split the ring at the two points farthest apart, simplify each half.
    var a = 0;
    var b = 0;
    var best = -1.0;
    for (var i = 0; i < closed.length; i++) {
      for (var j = i + 1; j < closed.length; j++) {
        final dd = closed[i].distanceTo(closed[j]);
        if (dd > best) {
          best = dd;
          a = i;
          b = j;
        }
      }
    }
    final first = closed.sublist(a, b + 1);
    final second = [...closed.sublist(b), ...closed.sublist(0, a + 1)];
    final s1 = _douglasPeucker(first, epsilon);
    final s2 = _douglasPeucker(second, epsilon);
    return [...s1.sublist(0, s1.length - 1), ...s2.sublist(0, s2.length - 1)];
  }

  static List<Pt> _douglasPeucker(List<Pt> pts, double epsilon) {
    if (pts.length < 3) return pts;
    final start = pts.first;
    final end = pts.last;
    var index = 0;
    var maxDist = 0.0;
    for (var i = 1; i < pts.length - 1; i++) {
      final dist = _distanceToSegment(pts[i], start, end);
      if (dist > maxDist) {
        maxDist = dist;
        index = i;
      }
    }
    if (maxDist <= epsilon) return [start, end];
    final left = _douglasPeucker(pts.sublist(0, index + 1), epsilon);
    final right = _douglasPeucker(pts.sublist(index), epsilon);
    return [...left.sublist(0, left.length - 1), ...right];
  }

  static double _distanceToSegment(Pt p, Pt a, Pt b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return p.distanceTo(a);
    final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / len2).clamp(0.0, 1.0);
    return p.distanceTo(Pt(a.x + t * dx, a.y + t * dy));
  }

  /// Reduces a convex hull to four corners: simplifies with growing
  /// tolerance until four vertices remain. Returns null if that never
  /// happens (round or irregular shapes).
  static List<Pt>? hullToQuad(List<Pt> hull) {
    if (hull.length < 4) return null;
    var perimeter = 0.0;
    for (var i = 0; i < hull.length; i++) {
      perimeter += hull[i].distanceTo(hull[(i + 1) % hull.length]);
    }
    for (var f = 0.01; f <= 0.1; f += 0.005) {
      final approx = approxPolygon(hull, perimeter * f);
      if (approx.length == 4) return approx;
      if (approx.length < 4) return null;
    }
    return null;
  }

  /// Share of the quad outline that lies on (or within [radius] px of) an
  /// edge pixel. Real document borders score high; accidental shapes low.
  static double edgeSupport(GrayImage edges, Quad quad, {int radius = 2}) {
    final p = quad.points;
    var hits = 0;
    var total = 0;
    for (var i = 0; i < 4; i++) {
      final a = p[i];
      final b = p[(i + 1) % 4];
      final steps = math.max(1, a.distanceTo(b).round());
      for (var s = 0; s <= steps; s++) {
        final t = s / steps;
        final x = (a.x + (b.x - a.x) * t).round();
        final y = (a.y + (b.y - a.y) * t).round();
        total++;
        if (_nearEdge(edges, x, y, radius)) hits++;
      }
    }
    return total == 0 ? 0 : hits / total;
  }

  static bool _nearEdge(GrayImage edges, int x, int y, int r) {
    for (var dy = -r; dy <= r; dy++) {
      final ny = y + dy;
      if (ny < 0 || ny >= edges.height) continue;
      for (var dx = -r; dx <= r; dx++) {
        final nx = x + dx;
        if (nx < 0 || nx >= edges.width) continue;
        if (edges.data[ny * edges.width + nx] != 0) return true;
      }
    }
    return false;
  }
}
