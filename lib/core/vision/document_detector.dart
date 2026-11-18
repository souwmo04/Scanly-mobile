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
  Detection? detect(GrayImage image) {
    final small = image.downscale(workingSize);
    final scaleX = image.width / small.width;
    final scaleY = image.height / small.height;

    final blurred = EdgeDetector.gaussianBlur(small);
    final edges = EdgeDetector.canny(blurred);
    final closed = EdgeDetector.dilate(edges);
    final fw = small.width.toDouble();
    final fh = small.height.toDouble();

    Detection? best;
    var bestScore = 0.0;
    final components = Contours.components(
      closed,
      minPixels: (small.width + small.height) ~/ 4,
    );
    for (final component in components.take(maxCandidates)) {
      final hull = Contours.convexHull(component.points);
      final corners = Contours.hullToQuad(hull);
      if (corners == null) continue;
      final quad = Quad.fromUnordered(corners);
      if (!validator.isValid(quad, fw, fh)) continue;
      final confidence = Contours.edgeSupport(closed, quad);
      if (confidence < minConfidence) continue;
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
