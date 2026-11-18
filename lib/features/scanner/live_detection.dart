import 'dart:isolate';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/vision/document_detector.dart';
import '../../core/vision/gray_image.dart';
import '../../core/vision/quad.dart';

/// Runs document detection on live camera frames and decides when the
/// document has been steady long enough for automatic capture.
///
/// * Frames are throttled: at most one is analysed at a time and no more
///   often than [minInterval]. Full-resolution frames are never processed;
///   each frame is subsampled to about [analysisSide] px on the long side
///   while still inside the camera callback, then analysed in a background
///   isolate.
/// * Detected corners are reported normalised (0–1) in the upright,
///   portrait coordinates of the preview.
class LiveDetectionController extends ChangeNotifier {
  LiveDetectionController({
    required this.sensorOrientation,
    this.detector = const DocumentDetector(),
    this.minInterval = const Duration(milliseconds: 150),
    this.analysisSide = 480,
    StabilityTracker? tracker,
  }) : _tracker = tracker ?? StabilityTracker();

  /// Clockwise rotation (degrees) from the sensor image to the upright
  /// screen, from `CameraDescription.sensorOrientation`.
  final int sensorOrientation;
  final DocumentDetector detector;
  final Duration minInterval;
  final int analysisSide;
  final StabilityTracker _tracker;

  bool _busy = false;
  bool _disposed = false;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);
  Quad? _quad;

  /// Latest document outline (normalised, upright), or null.
  Quad? get quad => _quad;

  /// 0–1 progress towards a steady document.
  double get stability => _tracker.progress;

  bool get isStable => _tracker.isStable;

  /// Camera stream callback. Cheap when a frame is skipped.
  void onFrame(CameraImage image) {
    if (_busy || _disposed) return;
    final now = DateTime.now();
    if (now.difference(_lastRun) < minInterval) return;
    _lastRun = now;

    final gray = _toGray(image);
    if (gray == null) return;
    _busy = true;
    _analyse(gray);
  }

  Future<void> _analyse(GrayImage frame) async {
    final turns = (sensorOrientation ~/ 90) % 4;
    final detector = this.detector;
    try {
      final normalized = await Isolate.run(() {
        final upright = frame.rotate(turns);
        return detector.detect(upright)?.normalized;
      });
      if (_disposed) return;
      _quad = normalized;
      _tracker.add(normalized);
      notifyListeners();
    } on Object {
      // A dropped frame is harmless; the next one will be analysed.
    } finally {
      _busy = false;
    }
  }

  /// Clears the outline and stability (e.g. right after a capture).
  void reset() {
    _quad = null;
    _tracker.reset();
    if (!_disposed) notifyListeners();
  }

  GrayImage? _toGray(CameraImage image) {
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    final longest = math.max(image.width, image.height);
    final step = math.max(1, longest ~/ analysisSide);
    switch (image.format.group) {
      case ImageFormatGroup.yuv420:
      case ImageFormatGroup.nv21:
        // The first plane is luminance on both layouts.
        return GrayImage.fromLumaPlane(
          plane.bytes,
          width: image.width,
          height: image.height,
          rowStride: plane.bytesPerRow,
          step: step,
        );
      case ImageFormatGroup.bgra8888:
        return GrayImage.fromFourChannel(
          plane.bytes,
          width: image.width,
          height: image.height,
          rowStride: plane.bytesPerRow,
          bgra: true,
          step: step,
        );
      case ImageFormatGroup.jpeg || ImageFormatGroup.unknown:
        return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Paints the live document outline over the camera preview.
class DocumentOutlinePainter extends CustomPainter {
  DocumentOutlinePainter({
    required this.quad,
    required this.stability,
    required this.color,
  });

  /// Normalised corners, or null to paint nothing.
  final Quad? quad;

  /// 0–1; the outline fills in as the document holds still.
  final double stability;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final q = quad;
    if (q == null) return;
    final p = q.scale(size.width, size.height).points;
    final path = Path()..moveTo(p[0].x, p[0].y);
    for (final pt in p.skip(1)) {
      path.lineTo(pt.x, pt.y);
    }
    path.close();

    canvas
      ..drawPath(
        path,
        Paint()..color = color.withValues(alpha: 0.12 + 0.18 * stability),
      )
      ..drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round,
      );
    final dot = Paint()..color = color;
    for (final pt in p) {
      canvas.drawCircle(Offset(pt.x, pt.y), 7, dot);
    }
  }

  @override
  bool shouldRepaint(DocumentOutlinePainter old) =>
      old.quad != quad || old.stability != stability || old.color != color;
}
