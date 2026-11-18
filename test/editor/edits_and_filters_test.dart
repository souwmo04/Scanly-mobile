import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scanly/core/vision/image_filters.dart';
import 'package:scanly/core/vision/quad.dart';
import 'package:scanly/domain/entities/page_edits.dart';
import 'package:scanly/domain/entities/scan_page.dart';

/// Solid RGBA image.
Uint8List solid(int w, int h, int r, int g, int b) {
  final out = Uint8List(w * h * 4);
  for (var i = 0; i < out.length; i += 4) {
    out
      ..[i] = r
      ..[i + 1] = g
      ..[i + 2] = b
      ..[i + 3] = 255;
  }
  return out;
}

void main() {
  group('PageEdits', () {
    test('initial edits are the identity', () {
      final edits = PageEdits.initial();
      expect(edits.isIdentity, isTrue);
      expect(edits.copyWith(contrast: 0.2).isIdentity, isFalse);
    });

    test('rotation wraps in quarter turns both ways', () {
      final e = PageEdits.initial();
      expect(e.rotated().rotation, 90);
      expect(e.rotated(clockwise: false).rotation, 270);
      expect(e.rotated().rotated().rotated().rotated().rotation, 0);
    });

    test('reads stored values from a page', () {
      final page = ScanPage(
        id: 'p',
        documentId: 'd',
        pageOrder: 0,
        originalPath: '/o.jpg',
        width: 1,
        height: 1,
        rotation: 180,
        filter: PageFilter.blackWhite,
        createdAt: DateTime(2026),
        cropCorners: Quad.fromList([0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9]),
        brightness: 0.3,
        sharpness: 0.5,
      );
      final edits = PageEdits.fromPage(page);
      expect(edits.rotation, 180);
      expect(edits.filter, PageFilter.blackWhite);
      expect(edits.corners.topLeft, const Pt(0.1, 0.1));
      expect(
        (edits.brightness, edits.contrast, edits.sharpness),
        (0.3, 0, 0.5),
      );
    });
  });

  group('EditHistory', () {
    test('undo and redo walk the history', () {
      final h = EditHistory(1)
        ..push(2)
        ..push(3);
      expect(h.canRedo, isFalse);
      expect(h.undo(), 2);
      expect(h.undo(), 1);
      expect(h.canUndo, isFalse);
      expect(h.undo(), 1);
      expect(h.redo(), 2);
      expect(h.isChanged, isTrue);
    });

    test('a new edit after undo discards the redo branch', () {
      final h = EditHistory('a')
        ..push('b')
        ..push('c')
        ..undo()
        ..push('x');
      expect(h.current, 'x');
      expect(h.canRedo, isFalse);
      expect(h.undo(), 'b');
    });

    test('ignores no-op pushes and supports replace', () {
      final h = EditHistory(0)..push(0);
      expect(h.canUndo, isFalse);
      h
        ..push(1)
        ..replace(5);
      expect(h.current, 5);
      expect(h.undo(), 0);
    });

    test('isChanged is false after undoing back to the start', () {
      final h = EditHistory(1)
        ..push(2)
        ..undo();
      expect(h.isChanged, isFalse);
    });

    test('keeps at most limit states', () {
      final h = EditHistory(0, limit: 3);
      for (var i = 1; i <= 10; i++) {
        h.push(i);
      }
      var undos = 0;
      while (h.canUndo) {
        h.undo();
        undos++;
      }
      expect(undos, 2);
      expect(h.isChanged, isTrue); // 8 ≠ initial 0
    });
  });

  group('ImageFilters', () {
    test('grayscale uses luma weights', () {
      final px = solid(1, 1, 255, 0, 0);
      ImageFilters.grayscale(px);
      expect(px[0], px[1]);
      expect(px[0], inInclusiveRange(70, 80));
    });

    test('adaptive threshold keeps text dark under a shadow gradient', () {
      // 200×100 page whose brightness falls from 240 to 120 left→right
      // (a shadow), with a dark "text" bar on the shaded side.
      const w = 200;
      const h = 100;
      final px = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          var v = (240 - x * 120 / w).round();
          if (x >= 150 && x < 170 && y >= 40 && y < 50) v -= 70; // ink
          final i = (y * w + x) * 4;
          px
            ..[i] = v
            ..[i + 1] = v
            ..[i + 2] = v
            ..[i + 3] = 255;
        }
      }
      ImageFilters.adaptiveThreshold(px, w, h);
      int at(int x, int y) => px[(y * w + x) * 4];
      expect(at(160, 45), 0, reason: 'ink must stay black');
      expect(at(190, 10), 255, reason: 'shaded paper must turn white');
      expect(at(10, 10), 255);
      expect(px.where((v) => v != 0 && v != 255), isEmpty);
    });

    test('auto levels stretches a flat, grey scan', () {
      final px = Uint8List(100 * 4);
      for (var i = 0; i < 100; i++) {
        final v = 90 + i; // 90…189
        px
          ..[i * 4] = v
          ..[i * 4 + 1] = v
          ..[i * 4 + 2] = v
          ..[i * 4 + 3] = 255;
      }
      ImageFilters.autoLevels(px);
      expect(px[0], lessThan(10));
      expect(px[99 * 4], greaterThan(245));
    });

    test('whiten paper pushes light tones to white, keeps ink', () {
      final px = Uint8List.fromList([230, 230, 230, 255, 40, 40, 40, 255]);
      ImageFilters.whitenPaper(px);
      expect(px.sublist(0, 3), [255, 255, 255]);
      expect(px.sublist(4, 7), [40, 40, 40]);
    });

    test('brightness and contrast', () {
      final px = solid(1, 1, 100, 128, 200);
      ImageFilters.brightnessContrast(px, 0.5, 0);
      expect(px.sublist(0, 3), [150, 178, 250]);

      final c = solid(1, 1, 100, 128, 156);
      ImageFilters.brightnessContrast(c, 0, 1);
      expect(c[1], 128, reason: 'mid-grey is the pivot');
      expect(c[0], lessThan(100));
      expect(c[2], greaterThan(156));
    });

    test('sharpen increases edge contrast and leaves flat areas', () {
      const w = 6;
      const h = 3;
      final px = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final v = x < 3 ? 100 : 160;
          final i = (y * w + x) * 4;
          px
            ..[i] = v
            ..[i + 1] = v
            ..[i + 2] = v;
        }
      }
      ImageFilters.sharpen(px, w, h, 1);
      int at(int x) => px[(w + x) * 4];
      expect(at(1), 100);
      expect(at(2), lessThan(100));
      expect(at(3), greaterThan(160));
    });

    test('presets produce valid output', () {
      for (final kind in FilterKind.values) {
        final px = solid(8, 8, 180, 170, 150);
        ImageFilters.apply(
          px,
          8,
          8,
          filter: kind,
          brightness: 0.1,
          sharpness: 0.3,
        );
        expect(px.length, 8 * 8 * 4);
      }
      final bw = solid(8, 8, 180, 170, 150);
      ImageFilters.apply(bw, 8, 8, filter: FilterKind.blackWhite);
      for (var i = 0; i < bw.length; i += 4) {
        expect(bw[i], anyOf(0, 255));
      }
    });
  });
}
