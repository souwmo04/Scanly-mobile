import 'dart:typed_data';

import 'quad.dart';

/// Projective transform mapping one quadrilateral onto another.
///
/// Stored as the 3×3 matrix `[[a, b, c], [d, e, f], [g, h, 1]]` so that
/// `(x, y) → ((a·x + b·y + c) / w, (d·x + e·y + f) / w)` with
/// `w = g·x + h·y + 1`. This is the same maths as OpenCV's
/// getPerspectiveTransform.
class Homography {
  const Homography(this.m);

  /// Row-major `[a, b, c, d, e, f, g, h, 1]`.
  final List<double> m;

  /// Solves for the transform taking each corner of [from] to the matching
  /// corner of [to]. Throws [ArgumentError] for degenerate input.
  factory Homography.fromQuads(Quad from, Quad to) {
    final src = from.points;
    final dst = to.points;
    // Eight equations, eight unknowns (a..h).
    final rows = List.generate(8, (_) => List<double>.filled(9, 0));
    for (var i = 0; i < 4; i++) {
      final x = src[i].x;
      final y = src[i].y;
      final u = dst[i].x;
      final v = dst[i].y;
      rows[2 * i]
        ..[0] = x
        ..[1] = y
        ..[2] = 1
        ..[6] = -u * x
        ..[7] = -u * y
        ..[8] = u;
      rows[2 * i + 1]
        ..[3] = x
        ..[4] = y
        ..[5] = 1
        ..[6] = -v * x
        ..[7] = -v * y
        ..[8] = v;
    }
    final solution = _solve(rows);
    return Homography([...solution, 1]);
  }

  /// Maps a point through the transform.
  Pt apply(Pt p) {
    final w = m[6] * p.x + m[7] * p.y + m[8];
    return Pt(
      (m[0] * p.x + m[1] * p.y + m[2]) / w,
      (m[3] * p.x + m[4] * p.y + m[5]) / w,
    );
  }

  /// Column-major 4×4 matrix for `Canvas.transform`, acting on (x, y, 0, 1).
  Float64List toMatrix4() => Float64List.fromList([
    m[0], m[3], 0, m[6], // column 0
    m[1], m[4], 0, m[7], // column 1
    0, 0, 1, 0, // column 2
    m[2], m[5], 0, m[8], // column 3
  ]);

  /// Gaussian elimination with partial pivoting on an 8×9 augmented matrix.
  static List<double> _solve(List<List<double>> a) {
    const n = 8;
    for (var col = 0; col < n; col++) {
      var pivot = col;
      for (var r = col + 1; r < n; r++) {
        if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
      }
      if (a[pivot][col].abs() < 1e-12) {
        throw ArgumentError('Degenerate quadrilateral');
      }
      final tmp = a[col];
      a[col] = a[pivot];
      a[pivot] = tmp;
      for (var r = 0; r < n; r++) {
        if (r == col) continue;
        final factor = a[r][col] / a[col][col];
        if (factor == 0) continue;
        for (var c = col; c <= n; c++) {
          a[r][c] -= factor * a[col][c];
        }
      }
    }
    return [for (var i = 0; i < n; i++) a[i][n] / a[i][i]];
  }
}
