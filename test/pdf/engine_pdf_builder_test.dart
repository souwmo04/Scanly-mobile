import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:scanly/core/errors/app_exception.dart';
import 'package:scanly/core/services/pdf_builder.dart';
import 'package:scanly/domain/entities/app_settings.dart';
import 'package:scanly/domain/services/pdf_service.dart';

/// Number of page objects (`/Type /Page`, not `/Pages`) in a PDF.
int pdfPageCount(Uint8List bytes) =>
    RegExp(r'/Type\s*/Page(?![A-Za-z])')
        .allMatches(latin1.decode(bytes))
        .length;

/// Width and height of every page's MediaBox, in order of appearance.
List<(double, double)> mediaBoxes(Uint8List bytes) => [
  for (final m in RegExp(
    r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]',
  ).allMatches(latin1.decode(bytes)))
    (double.parse(m.group(1)!), double.parse(m.group(2)!)),
];

/// Writes a noisy, photo-like JPEG so compression levels differ in size.
String writePhoto(
  String dir,
  String name, {
  int width = 600,
  int height = 900,
}) {
  final random = math.Random(width * 31 + height);
  final image = img.Image(width: width, height: height);
  for (final pixel in image) {
    final base = (pixel.x * 255 ~/ width + pixel.y * 255 ~/ height) ~/ 2;
    final n = random.nextInt(60) - 30;
    pixel
      ..r = (base + n).clamp(0, 255)
      ..g = (base - n).clamp(0, 255)
      ..b = (255 - base + n).clamp(0, 255);
  }
  final path = p.join(dir, name);
  File(path).writeAsBytesSync(img.encodeJpg(image, quality: 95));
  return path;
}

void main() {
  late Directory sandbox;
  const builder = PdfBuilder();

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scanly_pdf_builder');
  });

  tearDown(() async {
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  void expectSize((double, double) box, double w, double h) {
    expect(box.$1, closeTo(w, 0.5));
    expect(box.$2, closeTo(h, 0.5));
  }

  test('writes one page per image and reports progress', () async {
    final paths = [
      for (var i = 0; i < 3; i++) writePhoto(sandbox.path, 'p$i.jpg'),
    ];
    final progress = <(int, int)>[];
    final bytes = await builder.build(
      paths,
      options: const PdfExportOptions(),
      title: 'Receipts',
      onProgress: (done, total) => progress.add((done, total)),
    );
    final text = latin1.decode(bytes);
    expect(text, startsWith('%PDF-'));
    expect(pdfPageCount(bytes), 3);
    expect(progress, [(0, 3), (1, 3), (2, 3), (3, 3)]);
    expect(text, matches(RegExp(r'/Title\s*\(Receipts\)')));
    expect(text, matches(RegExp(r'/Creator\s*\(Scanly\)')));
  });

  test('A4 and Letter pages, portrait and landscape', () async {
    final tall = writePhoto(sandbox.path, 'tall.jpg');
    final a4 = mediaBoxes(
      await builder.build([tall], options: const PdfExportOptions()),
    );
    expectSize(a4.single, PdfPageFormat.a4.width, PdfPageFormat.a4.height);

    final letter = mediaBoxes(
      await builder.build([
        tall,
      ], options: const PdfExportOptions(pageSize: PdfPageSize.letter)),
    );
    expectSize(letter.single, 612, 792);

    final landscape = mediaBoxes(
      await builder.build(
        [tall],
        options: const PdfExportOptions(orientation: PdfOrientation.landscape),
      ),
    );
    expectSize(
      landscape.single,
      PdfPageFormat.a4.height,
      PdfPageFormat.a4.width,
    );
  });

  test('auto orientation follows each image', () async {
    final tall = writePhoto(sandbox.path, 'tall.jpg');
    final wide = writePhoto(sandbox.path, 'wide.jpg', width: 900, height: 600);
    final boxes = mediaBoxes(
      await builder.build([
        tall,
        wide,
      ], options: const PdfExportOptions(pageSize: PdfPageSize.letter)),
    );
    expect(boxes, hasLength(2));
    expectSize(boxes[0], 612, 792);
    expectSize(boxes[1], 792, 612);

    final portrait = mediaBoxes(
      await builder.build(
        [wide],
        options: const PdfExportOptions(
          pageSize: PdfPageSize.letter,
          orientation: PdfOrientation.portrait,
        ),
      ),
    );
    expectSize(portrait.single, 612, 792);
  });

  test('original size uses the image aspect ratio at 150 dpi', () async {
    final photo = writePhoto(sandbox.path, 'o.jpg', width: 600, height: 900);
    final boxes = mediaBoxes(
      await builder.build([
        photo,
      ], options: const PdfExportOptions(pageSize: PdfPageSize.original)),
    );
    // 600 × 900 px at 150 dpi = 4 × 6 inches.
    expectSize(boxes.single, 288, 432);
  });

  test('layout fits the image inside the margins, centred', () {
    final layout = PdfBuilder.layoutFor(const PdfExportOptions(), 1000, 1000);
    expect(layout.width, closeTo(PdfPageFormat.a4.width - 36, 0.01));
    expect(layout.height, closeTo(layout.width, 0.01));
    expect(layout.x, closeTo(PdfBuilder.margin, 0.01));
    expect(
      layout.y,
      closeTo((PdfPageFormat.a4.height - layout.height) / 2, 0.01),
    );

    final huge = PdfBuilder.layoutFor(
      const PdfExportOptions(pageSize: PdfPageSize.original),
      100000,
      50000,
    );
    expect(huge.format.width, closeTo(PdfBuilder.maxPagePoints, 0.01));
    expect(huge.format.height, closeTo(PdfBuilder.maxPagePoints / 2, 0.01));
    expect(huge.x, 0);
  });

  test('high compression gives a smaller file than low', () async {
    final photo = writePhoto(sandbox.path, 'c.jpg', width: 1200, height: 1700);
    final low = await builder.build([
      photo,
    ], options: const PdfExportOptions(compression: ImageCompression.low));
    final high = await builder.build([
      photo,
    ], options: const PdfExportOptions(compression: ImageCompression.high));
    expect(high.length, lessThan(low.length));
  });

  test('large images are downscaled to about 200 dpi on the page', () async {
    final big = writePhoto(sandbox.path, 'big.jpg', width: 2400, height: 3400);
    final a5 = await builder.build([
      big,
    ], options: const PdfExportOptions(pageSize: PdfPageSize.a5));
    final text = latin1.decode(a5);
    final width = int.parse(
      RegExp(r'/Width\s+(\d+)').firstMatch(text)!.group(1)!,
    );
    final height = int.parse(
      RegExp(r'/Height\s+(\d+)').firstMatch(text)!.group(1)!,
    );
    // A5 is 5.8 × 8.3 in; minus margins the image box is about 7.8 in tall.
    expect(math.max(width, height), lessThan(1700));
    expect(math.max(width, height), greaterThan(1400));
    expect(width / height, closeTo(2400 / 3400, 0.01));
  });

  test('rejects an empty list and missing files', () async {
    await expectLater(
      builder.build([], options: const PdfExportOptions()),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      builder.build([
        p.join(sandbox.path, 'nope.jpg'),
      ], options: const PdfExportOptions()),
      throwsA(isA<StorageException>()),
    );
  });
}
