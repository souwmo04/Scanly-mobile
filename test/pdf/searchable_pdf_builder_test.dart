import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:scanly/core/services/pdf_builder.dart';
import 'package:scanly/domain/entities/app_settings.dart';
import 'package:scanly/domain/entities/ocr_result.dart';
import 'package:scanly/domain/services/pdf_service.dart';

import 'searchable_helpers.dart';

void main() {
  late Directory sandbox;
  late DiskFontLoader fontLoader;
  late PdfBuilder builder;
  const options = PdfExportOptions();
  const bangla = 'বাংলাদেশ সরকার';

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scanly_searchable');
    fontLoader = DiskFontLoader();
    builder = PdfBuilder(bengaliFont: fontLoader.call, compress: false);
  });

  tearDown(() async {
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  String photo(String name, {int width = 600, int height = 900}) {
    final image = img.Image(width: width, height: height)
      ..clear(img.ColorRgb8(230, 230, 230));
    final path = p.join(sandbox.path, name);
    File(path).writeAsBytesSync(img.encodeJpg(image));
    return path;
  }

  Future<PdfInspector> build(
    List<PdfPageText?> texts, {
    PdfBuilder? using,
    PdfExportOptions opts = options,
    int width = 600,
    int height = 900,
  }) async {
    final paths = [
      for (var i = 0; i < texts.length; i++)
        photo('p$i.jpg', width: width, height: height),
    ];
    final Uint8List bytes = await (using ?? builder).build(
      paths,
      options: opts,
      pageTexts: texts,
    );
    return PdfInspector(bytes);
  }

  /// Advance width of [text] in Helvetica at [size], unscaled.
  double helveticaWidth(String text, double size) =>
      PdfFont.helvetica(PdfDocument()).stringMetrics(text).advanceWidth * size;

  test(
    'boxed English line: invisible, inside its box, spans the width',
    () async {
      const box = OcrBox(0.1, 0.2, 0.7, 0.25);
      final pdf = await build([
        const PdfPageText(
          lines: [OcrLine('Hello World (draft)', box)],
          text: 'Hello World (draft)',
        ),
      ]);
      final page = pdf.pages.single;
      final shown = pdf.textOf(page);
      expect(shown, hasLength(1));
      final t = shown.single;
      expect(t.renderMode, 3);
      expect(pdf.contentOf(page), contains('3 Tr'));
      expect(t.text, 'Hello World (draft)');
      expect(pdf.fonts[t.fontName], contains('/Helvetica'));

      final layout = PdfBuilder.layoutFor(options, 600, 900);
      final left = layout.x + box.left * layout.width;
      final right = layout.x + box.right * layout.width;
      final top = layout.y + (1 - box.top) * layout.height;
      final bottom = layout.y + (1 - box.bottom) * layout.height;
      expect(t.x, closeTo(left, 0.01));
      expect(t.y, greaterThan(bottom));
      expect(t.y, lessThan(top));
      expect(t.size, closeTo((top - bottom) * PdfBuilder.boxFontRatio, 0.01));
      // Tz stretches the run to the box width.
      final drawn = helveticaWidth(t.text, t.size) * t.scale!;
      expect(drawn, closeTo(right - left, 0.05));
      // Wrapped in q … Q so the text state does not leak.
      expect(
        pdf.contentOf(page),
        matches(RegExp(r'q\s.*BT.*ET.*Q', dotAll: true)),
      );
      expect(pdf.embedsFontFile, isFalse);
      expect(fontLoader.loads, 0);
    },
  );

  test(
    'boxes follow the image placement on landscape original pages',
    () async {
      const box = OcrBox(0.5, 0.5, 1, 0.6);
      const opts = PdfExportOptions(pageSize: PdfPageSize.original);
      final pdf = await build(
        [
          const PdfPageText(lines: [OcrLine('Invoice', box)]),
        ],
        opts: opts,
        width: 900,
        height: 600,
      );
      final t = pdf.textOf(pdf.pages.single).single;
      final layout = PdfBuilder.layoutFor(opts, 900, 600);
      expect(t.x, closeTo(layout.width / 2, 0.01));
      expect(t.y, inExclusiveRange(layout.height * 0.4, layout.height * 0.5));
      expect(
        helveticaWidth('Invoice', t.size) * t.scale!,
        closeTo(layout.width / 2, 0.05),
      );
    },
  );

  test('Bengali text maps back to its code points via ToUnicode', () async {
    final pdf = await build([
      const PdfPageText(
        lines: [OcrLine(bangla, OcrBox(0.1, 0.1, 0.9, 0.15))],
        text: bangla,
      ),
    ]);
    final shown = pdf.textOf(pdf.pages.single);
    expect(shown, hasLength(1));
    final t = shown.single;
    expect(t.renderMode, 3);
    expect(t.text, bangla);
    expect(t.text.runes.toList(), bangla.runes.toList());
    final font = pdf.fonts[t.fontName]!;
    expect(font, contains('/Type0'));
    expect(font, contains('/Identity-H'));
    expect(font, contains('/ToUnicode'));
    expect(pdf.embedsFontFile, isTrue);
    expect(fontLoader.loads, 1);
  });

  test('mixed lines are split into script runs in reading order', () async {
    const line = 'Total: ১২৩ টাকা।  Paid';
    final pdf = await build([
      const PdfPageText(lines: [OcrLine(line, OcrBox(0.1, 0.3, 0.9, 0.34))]),
    ]);
    final shown = pdf.textOf(pdf.pages.single);
    expect(shown.length, greaterThanOrEqualTo(3));
    expect(shown.map((s) => s.text).join(), line);
    expect(pdf.fonts[shown.first.fontName], contains('/Helvetica'));
    expect(pdf.fonts[shown[1].fontName], contains('/Type0'));
    // Runs advance left to right on one baseline.
    for (var i = 1; i < shown.length; i++) {
      expect(shown[i].x, greaterThan(shown[i - 1].x));
      expect(shown[i].y, closeTo(shown[0].y, 0.001));
    }
  });

  test('lines without boxes are spread top to bottom over the image', () async {
    final pdf = await build([
      const PdfPageText(
        lines: [],
        text: 'First line\nSecond line\nThird line\n',
      ),
    ]);
    final shown = pdf.textOf(pdf.pages.single);
    expect(shown.map((s) => s.text), [
      'First line',
      'Second line',
      'Third line',
    ]);
    final layout = PdfBuilder.layoutFor(options, 600, 900);
    for (final s in shown) {
      expect(s.renderMode, 3);
      expect(s.x, closeTo(layout.x, 0.01));
      expect(s.y, inExclusiveRange(layout.y, layout.y + layout.height));
      expect(s.size, lessThanOrEqualTo(PdfBuilder.maxUnboxedFontSize));
    }
    expect(shown[0].y, greaterThan(shown[1].y));
    expect(shown[1].y, greaterThan(shown[2].y));
    // Each line sits in its third of the image.
    final third = layout.height / 3;
    for (var i = 0; i < 3; i++) {
      final slotTop = layout.y + layout.height - i * third;
      expect(shown[i].y, inExclusiveRange(slotTop - third, slotTop));
    }
  });

  test('long unboxed lines are shrunk to the image width', () async {
    final long = List.filled(40, 'word').join(' ');
    final pdf = await build([
      PdfPageText(lines: [OcrLine(long)]),
    ]);
    final t = pdf.textOf(pdf.pages.single).single;
    final layout = PdfBuilder.layoutFor(options, 600, 900);
    expect(t.scale, lessThan(1));
    expect(
      helveticaWidth(long, t.size) * t.scale!,
      closeTo(layout.width, 0.05),
    );
  });

  test('pages without OCR have no text operators', () async {
    final pdf = await build([
      null,
      const PdfPageText(lines: [OcrLine('Page two')]),
      const PdfPageText(lines: [OcrLine('   ')]),
    ]);
    final pages = pdf.pages;
    expect(pages, hasLength(3));
    expect(pdf.contentOf(pages[0]), isNot(contains('BT')));
    expect(pdf.contentOf(pages[0]), isNot(contains('Tf')));
    expect(pdf.textOf(pages[1]).single.text, 'Page two');
    expect(pdf.contentOf(pages[2]), isNot(contains('BT')));
    expect(pdf.embedsFontFile, isFalse);
  });

  test('typographic punctuation stays in Helvetica without the font', () async {
    final pdf = await build([
      const PdfPageText(lines: [OcrLine('“Quoted” – it’s fine…\tok')]),
    ]);
    final t = pdf.textOf(pdf.pages.single).single;
    expect(t.text, '"Quoted" - it\'s fine... ok');
    expect(pdf.embedsFontFile, isFalse);
    expect(fontLoader.loads, 0);
  });

  test('unsupported characters never crash the export', () async {
    final pdf = await build([
      const PdfPageText(lines: [OcrLine('Emoji 😀 漢字 € end\u0001')]),
    ]);
    final text = pdf.textOf(pdf.pages.single).map((s) => s.text).join();
    // Characters outside the BMP, control characters and characters neither
    // font has a glyph for are dropped; the Latin text survives.
    expect(text, startsWith('Emoji '));
    expect(text, endsWith(' end'));
    expect(text, isNot(contains('😀')));
    expect(text, isNot(contains('漢')));
    expect(text, isNot(contains('\u0001')));
    // The font was loaded but, with nothing drawn from it, not embedded.
    expect(fontLoader.loads, 1);
    expect(pdf.embedsFontFile, isFalse);
  });

  test('a missing font drops Bengali but keeps the rest', () async {
    final broken = PdfBuilder(
      bengaliFont: () async => throw const FileSystemException('gone'),
      compress: false,
    );
    final pdf = await build([
      const PdfPageText(lines: [OcrLine('Name: $bangla')]),
    ], using: broken);
    final shown = pdf.textOf(pdf.pages.single);
    expect(shown.map((s) => s.text).join(), 'Name:');
    expect(pdf.embedsFontFile, isFalse);
  });

  test('the font program is a subset', () async {
    final pdf = await build([
      const PdfPageText(lines: [OcrLine(bangla)]),
    ]);
    final fontFile = RegExp(r'/Length1\s+(\d+)')
        .firstMatch(pdf.source)!
        .group(1)!;
    final full = File(bengaliFontPath).lengthSync();
    expect(int.parse(fontFile), lessThan(full));
  });

  test('PdfPageText.fromOcr keeps only finished, non-empty results', () {
    PageOcr ocr(OcrStatus status, String text) => PageOcr(
      pageId: 'p',
      status: status,
      text: text,
      lines: const [],
      updatedAt: DateTime(2026),
    );
    expect(PdfPageText.fromOcr(null), isNull);
    expect(PdfPageText.fromOcr(ocr(OcrStatus.pending, 'x')), isNull);
    expect(PdfPageText.fromOcr(ocr(OcrStatus.failed, 'x')), isNull);
    expect(PdfPageText.fromOcr(ocr(OcrStatus.done, '  ')), isNull);
    expect(PdfPageText.fromOcr(ocr(OcrStatus.done, 'x'))!.text, 'x');
  });
}
