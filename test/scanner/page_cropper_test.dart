import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:scanly/core/services/page_cropper.dart';
import 'package:scanly/core/vision/quad.dart';

void main() {
  late Directory sandbox;
  const cropper = PageCropper();

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scanly_cropper_test');
  });

  tearDown(() async {
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  /// A 1200×900 "photo": dark desk with a tilted white page. The page has a
  /// red mark near its top-left corner and a blue mark near bottom-right so
  /// the flattened result can be checked for orientation.
  String makePhoto({int? exifOrientation}) {
    final photo = img.Image(width: 1200, height: 900)
      ..clear(img.ColorRgb8(50, 55, 60));
    const page = Quad(Pt(300, 120), Pt(900, 160), Pt(860, 820), Pt(260, 780));
    img.fillPolygon(
      photo,
      vertices: [for (final pt in page.points) img.Point(pt.x, pt.y)],
      color: img.ColorRgb8(240, 238, 230),
    );
    img.fillCircle(
      photo,
      x: 360,
      y: 200,
      radius: 25,
      color: img.ColorRgb8(220, 30, 30),
    );
    img.fillCircle(
      photo,
      x: 800,
      y: 740,
      radius: 25,
      color: img.ColorRgb8(30, 30, 220),
    );
    if (exifOrientation != null) {
      photo.exif.imageIfd.orientation = exifOrientation;
    }
    final path = p.join(sandbox.path, 'photo.jpg');
    File(path).writeAsBytesSync(img.encodeJpg(photo, quality: 92));
    return path;
  }

  test('detects the page in a still photo (normalised corners)', () async {
    final quad = await cropper.detect(makePhoto());
    expect(quad, isNotNull);
    expect(quad!.topLeft.x, closeTo(300 / 1200, 0.03));
    expect(quad.topLeft.y, closeTo(120 / 900, 0.03));
    expect(quad.bottomRight.x, closeTo(860 / 1200, 0.03));
    expect(quad.bottomRight.y, closeTo(820 / 900, 0.03));
  });

  test('returns null for a photo without a document', () async {
    final blank = img.Image(width: 800, height: 600)
      ..clear(img.ColorRgb8(120, 120, 120));
    final path = p.join(sandbox.path, 'blank.jpg');
    File(path).writeAsBytesSync(img.encodeJpg(blank));
    expect(await cropper.detect(path), isNull);
  });

  test('flattens the page upright, keeping marks in their corners', () async {
    final path = makePhoto();
    final quad = (await cropper.detect(path))!;

    final jpeg = await cropper.flatten(path, quad);
    final page = img.decodeJpg(jpeg)!;

    // About 600 × 660 px (longest opposite sides of the tilted page).
    expect(page.width, inInclusiveRange(560, 640));
    expect(page.height, inInclusiveRange(620, 700));

    // Mostly paper: the desk was cropped away.
    final centre = page.getPixel(page.width ~/ 2, page.height ~/ 2);
    expect(centre.r, greaterThan(200));

    // Red mark near top-left, blue near bottom-right.
    final red = page.getPixel(
      (page.width * 0.1).round(),
      (page.height * 0.1).round(),
    );
    expect(red.r, greaterThan(150));
    expect(red.b, lessThan(100));
    final blue = page.getPixel(
      (page.width * 0.9).round(),
      (page.height * 0.9).round(),
    );
    expect(blue.b, greaterThan(150));
    expect(blue.r, lessThan(100));
  });

  test('full-frame corners keep the whole image', () async {
    final path = makePhoto();
    final jpeg = await cropper.flatten(path, Quad.fullFrame(1, 1));
    final out = img.decodeJpg(jpeg)!;
    expect((out.width, out.height), (1200, 900));
  });

  test('applies EXIF rotation (photo stored sideways)', () async {
    // Orientation 6: stored landscape, displayed rotated 90° clockwise.
    final path = makePhoto(exifOrientation: 6);
    final whole = img.decodeJpg(
      await cropper.flatten(path, Quad.fullFrame(1, 1)),
    )!;
    expect((whole.width, whole.height), (900, 1200));
    expect(await cropper.detect(path), isNotNull);
  });

  test('caps output size for huge photos', () async {
    const small = PageCropper(maxOutputSide: 500);
    final jpeg = await small.flatten(makePhoto(), Quad.fullFrame(1, 1));
    final out = img.decodeJpg(jpeg)!;
    expect(out.width, lessThanOrEqualTo(500));
    expect(out.height, lessThanOrEqualTo(500));
  });
}
