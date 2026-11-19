import 'dart:math' as math;

import 'contours.dart';
import 'edge_detector.dart';
import 'gray_image.dart';
import 'quad.dart';

/// A detected document outline.
class Detection {
  const Detection({
    required this.quad,
    required this.confidence,
    required this.frameWidth,
    required this.frameHeight,
  });

  /// Corners in the coordinates of the analysed frame.
  final Quad quad;

  /// 0–1: share of the outline backed by real edges.
  final double confidence;
  final int frameWidth;
  final int frameHeight;

  /// Corners scaled to 0–1 of the frame size.
  Quad get normalized => quad.scale(1 / frameWidth, 1 / frameHeight);
}

/// Finds the document in a grayscale frame.
///
/// Pipeline: downscale → Gaussian blur → Canny → dilate → connected edge
/// components → convex hull → 4-corner approximation → geometric validation
/// → edge-support confidence. The best candidate (area × confidence) wins.
class DocumentDetector {
  const DocumentDetector({
    this.workingSize = 320,
    this.validator = const QuadValidator(),
    this.minConfidence = 0.55,
    this.maxCandidates = 6,
  });

  /// Longest side, in pixels, of the image actually analysed.
  final int workingSize;
  final QuadValidator validator;
  final double minConfidence;
  final int maxCandidates;

  /// Returns the document outline in [image] coordinates, or null.
  ///
  /// Candidates come from two sources: hulls of connected edge components,
  /// and hulls of large bright regions (paper is usually the biggest bright
  /// area, and this still works when the page border touches clutter).
  /// A candidate must then be backed by real edges along every side, by a
  /// clear margin over what a random line would score in this frame. That
  /// rejects outlines that only "hit edges" because the scene is busy
  /// (textured desks, fabric, handwriting).
  Detection? detect(GrayImage image) {
    final small = image.downscale(workingSize);
    final scaleX = image.width / small.width;
    final scaleY = image.height / small.height;

    final blurred = EdgeDetector.gaussianBlur(small);
    final edges = EdgeDetector.canny(blurred);
    final closed = EdgeDetector.dilate(edges);
    final fw = small.width.toDouble();
    final fh = small.height.toDouble();

    // How often an arbitrary point is near an edge here. On a clean desk
    // this is small; on a busy scene any line scores well by chance.
    final chance = _chanceSupport(edges);
    if (chance > 0.6) return null;

    final candidates = <Quad>[];
    void addHull(List<Pt> points) {
      final corners = Contours.hullToQuad(Contours.convexHull(points));
      if (corners != null) candidates.add(Quad.fromUnordered(corners));
    }

    final components = Contours.components(
      closed,
      minPixels: (small.width + small.height) ~/ 4,
    );
    for (final component in components.take(maxCandidates)) {
      addHull(component.points);
    }
    for (final region in _brightRegions(blurred).take(3)) {
      addHull(region.points);
    }

    Detection? best;
    var bestScore = 0.0;
    for (final rough in candidates) {
      if (!validator.isValid(rough, fw, fh)) continue;
      final quad = _refine(rough, edges);
      if (!validator.isValid(quad, fw, fh)) continue;
      if (_cornersOnBorder(quad, fw, fh) >= 2) continue;
      final sides = Contours.sideSupport(edges, quad);
      final confidence = sides.reduce((a, b) => a + b) / 4;
      final weakest = sides.reduce(math.min);
      if (confidence < math.max(minConfidence, chance + 0.4)) continue;
      if (weakest < math.max(0.35, chance + 0.15)) continue;
      final score = quad.area * confidence;
      if (score > bestScore) {
        bestScore = score;
        best = Detection(
          quad: quad.scale(scaleX, scaleY),
          confidence: confidence,
          frameWidth: image.width,
          frameHeight: image.height,
        );
      }
    }
    return best;
  }

  /// Nudges each corner (one pixel at a time, a few rounds) to where the two
  /// sides meeting there are best backed by edges. Hulls are often a few
  /// pixels off: inset after erosion, or pulled out by a blob touching the
  /// page.
  static Quad _refine(Quad quad, GrayImage edges, {int rounds = 6}) {
    final p = List.of(quad.points);
    double sideScore(int i) =>
        Contours.segmentSupport(edges, p[i], p[(i + 1) % 4]);
    for (var r = 0; r < rounds; r++) {
      var moved = false;
      for (var c = 0; c < 4; c++) {
        final prev = (c + 3) % 4;
        var best = sideScore(prev) + sideScore(c);
        var bestPt = p[c];
        final origin = p[c];
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            p[c] = Pt(origin.x + dx, origin.y + dy);
            final s = sideScore(prev) + sideScore(c);
            if (s > best + 1e-9) {
              best = s;
              bestPt = p[c];
            }
          }
        }
        p[c] = bestPt;
        if (bestPt != origin) moved = true;
      }
      if (!moved) break;
    }
    return Quad.fromUnordered(p);
  }

  /// Share of grid points within the support radius of an edge pixel.
  static double _chanceSupport(GrayImage edges) {
    var hits = 0;
    var total = 0;
    for (var y = 2; y < edges.height - 2; y += 4) {
      for (var x = 2; x < edges.width - 2; x += 4) {
        total++;
        if (Contours.nearEdge(edges, x, y, Contours.supportRadius)) hits++;
      }
    }
    return total == 0 ? 0 : hits / total;
  }

  /// Corners lying on the frame edge: the hull of something cut off by the
  /// frame (or of clutter spanning it), not a whole page.
  static int _cornersOnBorder(Quad quad, double w, double h) {
    final margin = math.max(2.0, math.min(w, h) * 0.012);
    var n = 0;
    for (final p in quad.points) {
      if (p.x < margin ||
          p.y < margin ||
          p.x > w - margin ||
          p.y > h - margin) {
        n++;
      }
    }
    return n;
  }

  /// Large bright connected regions (Otsu threshold, then eroded twice so
  /// thin bright clutter touching the page doesn't join it), largest first.
  static List<EdgeComponent> _brightRegions(GrayImage blurred) {
    final threshold = _otsu(blurred);
    final w = blurred.width;
    final h = blurred.height;
    var mask = GrayImage(w, h);
    for (var i = 0; i < blurred.data.length; i++) {
      mask.data[i] = blurred.data[i] > threshold ? 255 : 0;
    }
    mask = _erode(_erode(mask));
    return Contours.components(mask, minPixels: (w * h * 0.1).round());
  }

  static int _otsu(GrayImage img) {
    final hist = List<int>.filled(256, 0);
    for (final v in img.data) {
      hist[v]++;
    }
    final total = img.data.length;
    var sum = 0.0;
    for (var i = 0; i < 256; i++) {
      sum += i * hist[i];
    }
    var sumB = 0.0;
    var weightB = 0;
    var best = 0.0;
    var threshold = 127;
    for (var t = 0; t < 256; t++) {
      weightB += hist[t];
      if (weightB == 0) continue;
      final weightF = total - weightB;
      if (weightF == 0) break;
      sumB += t * hist[t];
      final meanB = sumB / weightB;
      final meanF = (sum - sumB) / weightF;
      final between = weightB * weightF * (meanB - meanF) * (meanB - meanF);
      if (between > best) {
        best = between;
        threshold = t;
      }
    }
    return threshold;
  }

  static GrayImage _erode(GrayImage src) {
    final w = src.width;
    final h = src.height;
    final out = GrayImage(w, h);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        var keep = true;
        for (var dy = -1; dy <= 1 && keep; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (src.data[(y + dy) * w + x + dx] == 0) {
              keep = false;
              break;
            }
          }
        }
        if (keep) out.data[y * w + x] = 255;
      }
    }
    return out;
  }
}

/// Decides when a live detection has been steady long enough to capture.
///
/// A frame counts as steady when every corner moved less than [tolerance]
/// (fraction of the frame diagonal) since the previous detection. After
/// [requiredFrames] consecutive steady frames, [isStable] becomes true.
class StabilityTracker {
  StabilityTracker({this.tolerance = 0.02, this.requiredFrames = 6});

  final double tolerance;
  final int requiredFrames;

  Quad? _last;
  int _steady = 0;

  bool get isStable => _steady >= requiredFrames;

  /// 0–1 progress towards [isStable], for a capture indicator.
  double get progress => (_steady / requiredFrames).clamp(0.0, 1.0);

  /// Feeds the latest normalised detection (or null when nothing was found).
  void add(Quad? normalizedQuad) {
    if (normalizedQuad == null) {
      reset();
      return;
    }
    final last = _last;
    // Normalised coordinates: the diagonal of the unit square is √2.
    if (last != null &&
        last.maxCornerDistance(normalizedQuad) < tolerance * 1.4142) {
      _steady++;
    } else {
      _steady = 0;
    }
    _last = normalizedQuad;
  }

  void reset() {
    _last = null;
    _steady = 0;
  }
}
