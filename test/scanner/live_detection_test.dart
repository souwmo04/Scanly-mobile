import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanly/core/vision/document_detector.dart';
import 'package:scanly/core/vision/quad.dart';
import 'package:scanly/features/scanner/live_detection.dart';

/// Builds a YUV420 camera frame (luminance plane only matters) of a
/// landscape sensor image: dark background with a light page.
CameraImage yuvFrame({
  int width = 640,
  int height = 480,
  int rowPadding = 32,
  required Quad page,
}) {
  final stride = width + rowPadding;
  final y = Uint8List(stride * height);
  final pts = page.points;
  bool inside(double x, double yy) {
    var c = false;
    for (var i = 0, j = 3; i < 4; j = i++) {
      final a = pts[i];
      final b = pts[j];
      if ((a.y > yy) != (b.y > yy) &&
          x < (b.x - a.x) * (yy - a.y) / (b.y - a.y) + a.x) {
        c = !c;
      }
    }
    return c;
  }

  for (var row = 0; row < height; row++) {
    for (var col = 0; col < width; col++) {
      y[row * stride + col] = inside(col + 0.5, row + 0.5) ? 230 : 50;
    }
  }
  return CameraImage.fromPlatformInterface(
    CameraImageData(
      format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
      planes: [
        CameraImagePlane(bytes: y, bytesPerRow: stride),
        CameraImagePlane(
          bytes: Uint8List(stride * height ~/ 4),
          bytesPerRow: stride ~/ 2,
        ),
        CameraImagePlane(
          bytes: Uint8List(stride * height ~/ 4),
          bytesPerRow: stride ~/ 2,
        ),
      ],
      width: width,
      height: height,
    ),
  );
}

/// Waits for the controller's next notification.
Future<void> nextUpdate(LiveDetectionController c) {
  final done = Completer<void>();
  void listener() {
    c.removeListener(listener);
    done.complete();
  }

  c.addListener(listener);
  return done.future.timeout(const Duration(seconds: 10));
}

void main() {
  // Landscape sensor frame; page spans x 160–480, y 60–420.
  const page = Quad(Pt(160, 60), Pt(480, 70), Pt(470, 420), Pt(170, 410));

  test('reports the page in upright portrait coordinates', () async {
    final live = LiveDetectionController(
      sensorOrientation: 90,
      minInterval: Duration.zero,
    );
    addTearDown(live.dispose);

    final update = nextUpdate(live);
    live.onFrame(yuvFrame(page: page));
    await update;

    final q = live.quad;
    expect(q, isNotNull);
    // Rotating 90° clockwise maps sensor (x, y) to portrait
    // (1 - y/h, x/w): the sensor's bottom-left corner becomes top-left.
    expect(q!.topLeft.x, closeTo(1 - 410 / 480, 0.04));
    expect(q.topLeft.y, closeTo(170 / 640, 0.04));
    expect(q.bottomRight.x, closeTo(1 - 70 / 480, 0.04));
    expect(q.bottomRight.y, closeTo(480 / 640, 0.04));
  });

  test('becomes stable after steady frames, resets on demand', () async {
    final live = LiveDetectionController(
      sensorOrientation: 0,
      minInterval: Duration.zero,
      tracker: StabilityTracker(requiredFrames: 2),
    );
    addTearDown(live.dispose);

    for (var i = 0; i < 3; i++) {
      final update = nextUpdate(live);
      live.onFrame(yuvFrame(page: page));
      await update;
    }
    expect(live.isStable, isTrue);
    expect(live.stability, 1);

    live.reset();
    expect(live.quad, isNull);
    expect(live.isStable, isFalse);
  });

  test('skips frames while busy or inside the throttle interval', () async {
    final live = LiveDetectionController(
      sensorOrientation: 0,
      minInterval: const Duration(seconds: 30),
    );
    addTearDown(live.dispose);
    var updates = 0;
    live.addListener(() => updates++);

    final first = nextUpdate(live);
    live
      ..onFrame(yuvFrame(page: page))
      ..onFrame(yuvFrame(page: page))
      ..onFrame(yuvFrame(page: page));
    await first;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(updates, 1);
  });

  test('reports no document for an empty frame', () async {
    final live = LiveDetectionController(
      sensorOrientation: 90,
      minInterval: Duration.zero,
    );
    addTearDown(live.dispose);
    final update = nextUpdate(live);
    live.onFrame(yuvFrame(page: Quad.fullFrame(0.5, 0.5)));
    await update;
    expect(live.quad, isNull);
  });
}
