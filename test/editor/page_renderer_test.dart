import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:scanly/core/services/page_renderer.dart';
import 'package:scanly/core/vision/image_filters.dart';
import 'package:scanly/core/vision/quad.dart';

void main() {
  late Directory sandbox;
  late String photo;
  const renderer = PageRenderer();

  /// 400×300 photo: red top-left quadrant, everything else light grey, a
  /// dark line of "text" in the middle.
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scanly_render_test');
    final image = img.Image(width: 400, height: 300)
      ..clear(img.ColorRgb8(210, 210, 205));
    img.fillRect(
      image,
      x1: 0,
      y1: 0,
      x2: 199,
      y2: 149,
      color: img.ColorRgb8(220, 30, 30),
    );
    img.fillRect(
      image,
      x1: 120,
      y1: 200,
      x2: 280,
      y2: 210,
      color: img.ColorRgb8(30, 30, 30),
    );
    photo = p.join(sandbox.path, 'page.jpg');
    File(photo).writeAsBytesSync(img.encodeJpg(image, quality: 95));
  });

  tearDown(() async {
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  Future<img.Image> render({
    Quad? corners,
    int rotation = 0,
    FilterKind filter = FilterKind.original,
    double brightness = 0,
    int maxSide = 4096,
  }) async => img.decodeJpg(
    await renderer.render(
      photo,
      corners: corners ?? Quad.fullFrame(1, 1),
      rotation: rotation,
      filter: filter,
      brightness: brightness,
      maxSide: maxSide,
    ),
  )!;

  bool isRed(img.Pixel px) => px.r > 150 && px.g < 100 && px.b < 100;

  test('full frame without edits reproduces the photo', () async {
    final out = await render();
    expect((out.width, out.height), (400, 300));
    expect(isRed(out.getPixel(20, 20)), isTrue);
    expect(isRed(out.getPixel(380, 280)), isFalse);
  });

  test('crop keeps only the selected region', () async {
    // Top-left quadrant only → all red.
    final out = await render(
      corners: Quad.fromList([0, 0, 0.5, 0, 0.5, 0.5, 0, 0.5]),
    );
    expect((out.width, out.height), (200, 150));
    expect(isRed(out.getPixel(100, 75)), isTrue);
    expect(isRed(out.getPixel(190, 140)), isTrue);
  });

  test('rotation turns the page clockwise in quarter turns', () async {
    final r90 = await render(rotation: 90);
    expect((r90.width, r90.height), (300, 400));
    // Top-left red quadrant moves to the top-right after 90° clockwise.
    expect(isRed(r90.getPixel(280, 20)), isTrue);
    expect(isRed(r90.getPixel(20, 20)), isFalse);

    final r180 = await render(rotation: 180);
    expect((r180.width, r180.height), (400, 300));
    expect(isRed(r180.getPixel(380, 280)), isTrue);

    final r270 = await render(rotation: 270);
    expect((r270.width, r270.height), (300, 400));
    expect(isRed(r270.getPixel(20, 380)), isTrue);
  });

  test('grayscale and black & white filters', () async {
    final gray = await render(filter: FilterKind.grayscale);
    final px = gray.getPixel(20, 20);
    expect((px.r - px.g).abs(), lessThan(6));

    final bw = await render(filter: FilterKind.blackWhite);
    final ink = bw.getPixel(200, 205);
    final paper = bw.getPixel(300, 100);
    expect(ink.r, lessThan(60));
    expect(paper.r, greaterThan(200));
  });

  test('brightness lightens the page', () async {
    final normal = await render();
    final bright = await render(brightness: 0.5);
    expect(
      bright.getPixel(200, 205).r,
      greaterThan(normal.getPixel(200, 205).r + 30),
    );
  });

  test('preview size limits output', () async {
    final out = await render(maxSide: 100, rotation: 90);
    expect(out.height, lessThanOrEqualTo(100));
    expect(out.width, lessThanOrEqualTo(100));
  });
}
