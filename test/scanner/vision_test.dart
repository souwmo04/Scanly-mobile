import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scanly/core/vision/contours.dart';
import 'package:scanly/core/vision/document_detector.dart';
import 'package:scanly/core/vision/edge_detector.dart';
import 'package:scanly/core/vision/gray_image.dart';
import 'package:scanly/core/vision/homography.dart';
import 'package:scanly/core/vision/quad.dart';

/// Renders a synthetic photo: [background] everywhere, the [doc] polygon
/// filled with [paper], optional text-like dark lines and Gaussian-ish
/// noise.
GrayImage scene({
  int width = 640,
  int height = 480,
  required Quad doc,
  int background = 60,
  int paper = 235,
  bool text = false,
  int noise = 0,
  int seed = 1,
}) {
  final img = GrayImage(width, height);
  final rnd = math.Random(seed);
  final poly = doc.points;
  bool inside(double x, double y) {
    var c = false;
    for (var i = 0, j = 3; i < 4; j = i++) {
      final pi = poly[i];
      final pj = poly[j];
      if ((pi.y > y) != (pj.y > y) &&
          x < (pj.x - pi.x) * (y - pi.y) / (pj.y - pi.y) + pi.x) {
        c = !c;
      }
    }
    return c;
  }

  final (dw, dh) = doc.outputSize;
  final h = Homography.fromQuads(doc, Quad.fullFrame(dw, dh));
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var v = background;
      if (inside(x + 0.5, y + 0.5)) {
        v = paper;
        if (text) {
          // Lines of "text" in document space.
          final p = h.apply(Pt(x + 0.5, y + 0.5));
          final line = (p.y / 14).floor();
          final inBand = p.y % 14 < 3;
          final margin = p.x > dw * 0.1 && p.x < dw * 0.9;
          if (line > 1 && inBand && margin && (p.x ~/ 9) % 7 != 0) v = 40;
        }
      }
      if (noise > 0) v += rnd.nextInt(noise * 2 + 1) - noise;
      img.set(x, y, v.clamp(0, 255));
    }
  }
  return img;
}

/// Paints a busy desk over [img] outside [keepOut]: random dark and light
/// strokes, blocks and short scribbles, like a notebook spiral, cables,
/// fabric and other papers around the page.
void clutter(GrayImage img, {Quad? keepOut, int seed = 7, int count = 260}) {
  final rnd = math.Random(seed);
  bool inside(double x, double y) {
    final q = keepOut;
    if (q == null) return false;
    final poly = q.points;
    var c = false;
    for (var i = 0, j = 3; i < 4; j = i++) {
      final pi = poly[i];
      final pj = poly[j];
      if ((pi.y > y) != (pj.y > y) &&
          x < (pj.x - pi.x) * (y - pi.y) / (pj.y - pi.y) + pi.x) {
        c = !c;
      }
    }
    return c;
  }

  for (var n = 0; n < count; n++) {
    final x0 = rnd.nextDouble() * img.width;
    final y0 = rnd.nextDouble() * img.height;
    final angle = rnd.nextDouble() * math.pi;
    final len = 10 + rnd.nextDouble() * 90;
    final thick = 1 + rnd.nextInt(5);
    final v = rnd.nextBool() ? rnd.nextInt(60) : 160 + rnd.nextInt(95);
    for (var s = 0; s < len; s++) {
      for (var t = 0; t < thick; t++) {
        final x = x0 + math.cos(angle) * s - math.sin(angle) * t;
        final y = y0 + math.sin(angle) * s + math.cos(angle) * t;
        if (x < 0 || y < 0 || x >= img.width || y >= img.height) continue;
        if (inside(x, y)) continue;
        img.set(x.toInt(), y.toInt(), v);
      }
    }
  }
}

/// Max corner error relative to the frame diagonal.
double cornerError(Quad found, Quad expected, int w, int h) =>
    found.maxCornerDistance(expected) / math.sqrt(w * w + h * h);

void main() {
  const detector = DocumentDetector();

  group('Quad', () {
    test('orders corners clockwise from top-left', () {
      final q = Quad.fromUnordered(const [
        Pt(90, 80),
        Pt(10, 10),
        Pt(15, 85),
        Pt(100, 5),
      ]);
      expect(q.topLeft, const Pt(10, 10));
      expect(q.topRight, const Pt(100, 5));
      expect(q.bottomRight, const Pt(90, 80));
      expect(q.bottomLeft, const Pt(15, 85));
    });

    test('area, convexity and angles', () {
      final square = Quad.fullFrame(10, 10);
      expect(square.area, 100);
      expect(square.isConvex, isTrue);
      expect(square.angles, everyElement(closeTo(90, 1e-9)));

      const bowtie = Quad(Pt(0, 0), Pt(10, 10), Pt(10, 0), Pt(0, 10));
      expect(bowtie.isConvex, isFalse);
    });

    test('validator rejects tiny, skinny and sharp shapes', () {
      const v = QuadValidator();
      expect(v.check(Quad.fullFrame(20, 20), 640, 480), 'too small');
      expect(v.check(Quad.fullFrame(640, 480), 640, 480), 'fills the frame');
      expect(
        v.check(
          const Quad(Pt(0, 200), Pt(600, 200), Pt(600, 260), Pt(0, 260)),
          640,
          480,
        ),
        isNotNull,
      );
      expect(
        v.check(
          const Quad(Pt(100, 100), Pt(500, 120), Pt(480, 400), Pt(110, 380)),
          640,
          480,
        ),
        isNull,
      );
    });

    test('round-trips through a list', () {
      final q = Quad.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      expect(q.toList(), [1, 2, 3, 4, 5, 6, 7, 8]);
    });
  });

  group('Homography', () {
    test('maps every source corner onto the target corner', () {
      const from = Quad(Pt(120, 80), Pt(520, 60), Pt(560, 420), Pt(90, 440));
      final to = Quad.fullFrame(420, 594);
      final h = Homography.fromQuads(from, to);
      for (var i = 0; i < 4; i++) {
        final mapped = h.apply(from.points[i]);
        expect(mapped.x, closeTo(to.points[i].x, 1e-6));
        expect(mapped.y, closeTo(to.points[i].y, 1e-6));
      }
    });

    test('rejects degenerate quads', () {
      const line = Quad(Pt(0, 0), Pt(1, 1), Pt(2, 2), Pt(3, 3));
      expect(
        () => Homography.fromQuads(line, Quad.fullFrame(10, 10)),
        throwsArgumentError,
      );
    });
  });

  group('image operations', () {
    test('Y-plane sampling respects row stride and step', () {
      // 4×2 image with 2 bytes of row padding.
      final plane = Uint8List.fromList([1, 2, 3, 4, 0, 0, 5, 6, 7, 8, 0, 0]);
      final img = GrayImage.fromLumaPlane(
        plane,
        width: 4,
        height: 2,
        rowStride: 6,
      );
      expect(img.data, [1, 2, 3, 4, 5, 6, 7, 8]);
      final half = GrayImage.fromLumaPlane(
        plane,
        width: 4,
        height: 2,
        rowStride: 6,
        step: 2,
      );
      expect((half.width, half.height), (2, 1));
      expect(half.data, [1, 3]);
    });

    test('BGRA conversion uses luma weights', () {
      final white = GrayImage.fromFourChannel(
        Uint8List.fromList([255, 255, 255, 255]),
        width: 1,
        height: 1,
        rowStride: 4,
        bgra: true,
      );
      expect(white.data.single, greaterThan(250));
      final blueBgra = GrayImage.fromFourChannel(
        Uint8List.fromList([255, 0, 0, 255]),
        width: 1,
        height: 1,
        rowStride: 4,
        bgra: true,
      );
      expect(blueBgra.data.single, lessThan(40));
    });

    test('rotate and downscale', () {
      final img = GrayImage(3, 2, Uint8List.fromList([1, 2, 3, 4, 5, 6]));
      expect(img.rotate(1).data, [4, 1, 5, 2, 6, 3]);
      expect(img.rotate(4).data, img.data);
      final big = GrayImage(1000, 500)..data.fillRange(0, 500000, 100);
      final small = big.downscale(320);
      expect(small.width, lessThanOrEqualTo(320));
      expect(small.data.every((v) => v == 100), isTrue);
    });

    test('Canny finds a clean border and nothing on a flat frame', () {
      final flat = GrayImage(100, 100)..data.fillRange(0, 10000, 128);
      expect(EdgeDetector.canny(flat).data.every((v) => v == 0), isTrue);

      final img = scene(
        width: 160,
        height: 120,
        doc: Quad.fullFrame(1, 1)
            .scale(80, 60)
            .let(
              (q) => Quad(
                q.topLeft + const Pt(40, 30),
                q.topRight + const Pt(40, 30),
                q.bottomRight + const Pt(40, 30),
                q.bottomLeft + const Pt(40, 30),
              ),
            ),
      );
      final edges = EdgeDetector.canny(EdgeDetector.gaussianBlur(img));
      final count = edges.data.where((v) => v != 0).length;
      // Roughly the 280 px perimeter, thin (non-max suppressed).
      expect(count, inInclusiveRange(200, 700));
    });

    test('convex hull and polygon approximation', () {
      final pts = [
        for (var x = 0; x <= 10; x++) Pt(x.toDouble(), 0),
        for (var y = 0; y <= 10; y++) Pt(10, y.toDouble()),
        for (var x = 0; x <= 10; x++) Pt(x.toDouble(), 10),
        for (var y = 0; y <= 10; y++) Pt(0, y.toDouble()),
        const Pt(5, 5),
      ];
      final hull = Contours.convexHull(pts);
      expect(hull, hasLength(4));
      expect(Contours.hullToQuad(hull), hasLength(4));
    });
  });

  group('DocumentDetector', () {
    void expectDetects(GrayImage img, Quad truth, {double tolerance = 0.02}) {
      final d = detector.detect(img);
      expect(d, isNotNull, reason: 'document not found');
      expect(
        cornerError(d!.quad, truth, img.width, img.height),
        lessThan(tolerance),
        reason: 'found ${d.quad}, expected $truth',
      );
      expect(d.confidence, greaterThanOrEqualTo(0.55));
    }

    test('upright page on a dark desk', () {
      const truth = Quad(Pt(150, 60), Pt(490, 60), Pt(490, 420), Pt(150, 420));
      expectDetects(scene(doc: truth), truth);
    });

    test('tilted page with perspective', () {
      const truth = Quad(Pt(170, 50), Pt(500, 90), Pt(460, 440), Pt(110, 400));
      expectDetects(scene(doc: truth, text: true), truth);
    });

    test('rotated page with text and sensor noise', () {
      const truth = Quad(Pt(320, 30), Pt(560, 230), Pt(330, 450), Pt(90, 250));
      expectDetects(scene(doc: truth, text: true, noise: 12), truth);
    });

    test('white paper on a white surface (low contrast)', () {
      const truth = Quad(Pt(140, 70), Pt(500, 80), Pt(510, 410), Pt(130, 400));
      expectDetects(
        scene(doc: truth, background: 212, paper: 240, noise: 4),
        truth,
        tolerance: 0.03,
      );
    });

    test('portrait frame, page filling most of it', () {
      const truth = Quad(Pt(40, 60), Pt(440, 70), Pt(430, 600), Pt(50, 590));
      expectDetects(scene(width: 480, height: 640, doc: truth), truth);
    });

    test('result is in the coordinates of the input frame', () {
      const truth = Quad(
        Pt(300, 120),
        Pt(980, 120),
        Pt(980, 840),
        Pt(300, 840),
      );
      final big = scene(width: 1280, height: 960, doc: truth);
      expectDetects(big, truth);
      final d = detector.detect(big)!;
      expect((d.frameWidth, d.frameHeight), (1280, 960));
      expect(d.normalized.topLeft.x, closeTo(300 / 1280, 0.02));
    });

    test('returns null when there is no document', () {
      final empty = GrayImage(640, 480)..data.fillRange(0, 640 * 480, 90);
      expect(detector.detect(empty), isNull);

      final noisy = scene(
        doc: Quad.fullFrame(0.1, 0.1),
        background: 128,
        paper: 128,
        noise: 30,
      );
      expect(detector.detect(noisy), isNull);
    });

    test('analyses a 1280x720 frame quickly', () {
      const truth = Quad(
        Pt(400, 100),
        Pt(900, 120),
        Pt(880, 650),
        Pt(380, 630),
      );
      final frame = scene(width: 1280, height: 720, doc: truth, text: true);
      detector.detect(frame); // warm up the JIT
      final watch = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        detector.detect(frame);
      }
      // Generous bound for a debug-mode JIT on CI; release AOT is faster.
      expect(watch.elapsedMilliseconds / 5, lessThan(250));
    });

    test('a busy desk with no page gives no outline', () {
      for (var seed = 1; seed <= 16; seed++) {
        final img = GrayImage(640, 480)..data.fillRange(0, 640 * 480, 110);
        clutter(img, seed: seed, count: 400);
        final d = detector.detect(img);
        expect(d, isNull, reason: 'seed $seed found ${d?.quad}');
      }
    });

    test('page with handwriting on a busy desk: right outline or none', () {
      const truth = Quad(Pt(150, 70), Pt(480, 90), Pt(470, 430), Pt(130, 410));
      for (var seed = 1; seed <= 16; seed++) {
        final img = scene(doc: truth, text: true, noise: 8, background: 95);
        clutter(img, keepOut: truth, seed: seed, count: 300);
        final d = detector.detect(img);
        if (d == null) continue;
        expect(
          cornerError(d.quad, truth, img.width, img.height),
          lessThan(0.04),
          reason: 'seed $seed found ${d.quad}',
        );
      }
    });

    test('a page on a busy desk is still found', () {
      const truth = Quad(Pt(150, 70), Pt(480, 90), Pt(470, 430), Pt(130, 410));
      var found = 0;
      for (var seed = 1; seed <= 6; seed++) {
        final img = scene(doc: truth, text: true, noise: 8, background: 70);
        clutter(img, keepOut: truth, seed: seed, count: 120);
        final d = detector.detect(img);
        if (d != null &&
            cornerError(d.quad, truth, img.width, img.height) < 0.04) {
          found++;
        }
      }
      expect(found, greaterThanOrEqualTo(4));
    });

    test('ignores a small card far from document size', () {
      const card = Quad(Pt(300, 220), Pt(360, 220), Pt(360, 260), Pt(300, 260));
      expect(detector.detect(scene(doc: card)), isNull);
    });
  });

  group('StabilityTracker', () {
    final quad = Quad.fullFrame(0.6, 0.8)
        .scale(1)
        .let(
          (q) => Quad(
            q.topLeft + const Pt(0.2, 0.1),
            q.topRight + const Pt(0.2, 0.1),
            q.bottomRight + const Pt(0.2, 0.1),
            q.bottomLeft + const Pt(0.2, 0.1),
          ),
        );

    test('becomes stable after enough steady frames', () {
      final t = StabilityTracker(requiredFrames: 3);
      t.add(quad);
      expect(t.isStable, isFalse);
      t
        ..add(quad)
        ..add(quad)
        ..add(quad);
      expect(t.isStable, isTrue);
      expect(t.progress, 1);
    });

    test('movement or a lost document resets progress', () {
      final t = StabilityTracker(requiredFrames: 3)
        ..add(quad)
        ..add(quad);
      expect(t.progress, greaterThan(0));
      t.add(quad.scale(1.2));
      expect(t.progress, 0);
      t
        ..add(quad)
        ..add(quad)
        ..add(null);
      expect(t.progress, 0);
      expect(t.isStable, isFalse);
    });

    test('tiny jitter still counts as steady', () {
      final t = StabilityTracker(requiredFrames: 2)
        ..add(quad)
        ..add(quad.scale(1.005))
        ..add(quad.scale(0.997));
      expect(t.isStable, isTrue);
    });
  });
}

extension<T> on T {
  R let<R>(R Function(T it) f) => f(this);
}
