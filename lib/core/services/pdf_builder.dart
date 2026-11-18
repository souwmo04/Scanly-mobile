import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/entities/ocr_result.dart';
import '../../domain/services/pdf_service.dart';
import '../errors/app_exception.dart';
import 'image_service.dart';
import 'page_renderer.dart';

/// Where and how large one page image is drawn, in PDF points (1/72 inch).
typedef PdfPageLayout = ({
  PdfPageFormat format,
  double x,
  double y,
  double width,
  double height,
});

/// Loads the bytes of a TrueType font.
typedef PdfFontLoader = Future<ByteData> Function();

/// Recognised text of one page, drawn as an invisible, searchable layer.
@immutable
class PdfPageText {
  const PdfPageText({required this.lines, this.text = ''});

  /// Lines in reading order, with their boxes when the engine knows them.
  final List<OcrLine> lines;

  /// Full text with line breaks; used when [lines] has no text.
  final String text;

  /// Text of a finished OCR run, or null when [ocr] is missing, not
  /// [OcrStatus.done] or empty.
  static PdfPageText? fromOcr(PageOcr? ocr) {
    if (ocr == null || ocr.status != OcrStatus.done) return null;
    final text = PdfPageText(lines: ocr.lines, text: ocr.text);
    return text.isEmpty ? null : text;
  }

  bool get isEmpty =>
      lines.every((l) => l.text.trim().isEmpty) && text.trim().isEmpty;
}

/// Builds PDFs from page images, entirely on device.
///
/// * Fixed sizes (A4, A5, Letter, Legal) use the standard paper sizes with a
///   [margin] on every side; the image is fitted inside, keeping its aspect
///   ratio, and centred.
/// * [PdfPageSize.original] sizes each page to its image as if it had been
///   scanned at [originalDpi], with no margin. Pages are capped at
///   [maxPagePoints] (200 inches, the PDF viewer limit) and at least one
///   point on each side. The orientation option does not apply: the page
///   always follows the image.
/// * Orientation `auto` turns a page to landscape when its image is wider
///   than tall.
/// * Every image is decoded by the platform codec (EXIF orientation applied)
///   directly at the size needed for [targetDpi] on the page, so a 4000 px
///   photo is never held at full size, then re-encoded as JPEG at the
///   compression quality in a background isolate. Pages are processed one
///   at a time; only the compressed JPEGs are kept until the PDF is saved.
///
/// **Searchable text.** Pages with recognised text (see [build]'s
/// `pageTexts`) get an invisible text layer (text render mode 3) over the
/// image, so PDF readers can search, select and copy it:
/// * A line with a box is drawn at the box, mapped from the normalised image
///   coordinates into the image rectangle on the page. The font size follows
///   the box height and the line is scaled horizontally (`Tz`) to span the
///   box width.
/// * Lines without a box are spread top to bottom over the image, one slot
///   per line, in reading order, shrunk horizontally to fit the image width.
/// * Each line is split into runs by font: Bengali script (U+0980–U+09FF,
///   ZWJ/ZWNJ) and any other character Helvetica's WinAnsi encoding cannot
///   express use the embedded Bengali TrueType font (a subset CID font with
///   a ToUnicode map, so extraction yields the original code points);
///   Latin-1 text uses Helvetica. Common typographic punctuation (curly
///   quotes, dashes, ellipsis) is mapped to Latin-1 first. The TrueType font
///   is loaded only when some text needs it and embedded only when one of
///   its glyphs is drawn. Characters neither font covers (or all non-Latin
///   text, if the font cannot be loaded) are left out of the layer instead
///   of failing the export.
/// * Pages without text stay image-only.
class PdfBuilder {
  const PdfBuilder({
    this._images = const ImageService(),
    this._bengaliFont = bundledBengaliFont,
    this.compress = true,
  });

  final ImageService _images;
  final PdfFontLoader? _bengaliFont;

  /// Whether streams are deflated. Tests turn it off to read the content.
  final bool compress;

  /// Asset path of the font used for Bengali (and other non-Latin) text.
  static const bengaliFontAsset = 'assets/fonts/NotoSansBengali-Regular.ttf';

  /// Loads [bengaliFontAsset] from the app bundle.
  static Future<ByteData> bundledBengaliFont() =>
      rootBundle.load(bengaliFontAsset);

  /// Resolution assumed for [PdfPageSize.original] pages.
  static const double originalDpi = 150;

  /// Images are downscaled to at most this resolution on the page.
  static const double targetDpi = 200;

  /// Margin around the image on fixed paper sizes: 0.25 inch (6.35 mm).
  static const double margin = 18;

  /// Largest page side PDF viewers accept (200 inches).
  static const double maxPagePoints = 14400;

  /// Longest side, in pixels, an image is ever embedded at.
  static const int maxImageSide = 6000;

  /// Font size as a share of a line box's height.
  static const double boxFontRatio = 0.8;

  /// Baseline height above the box bottom, as a share of its height.
  static const double boxBaselineRatio = 0.2;

  /// Largest font size for lines spread without boxes.
  static const double maxUnboxedFontSize = 14;

  /// Writes a PDF with one page per image in [imagePaths], in order, and
  /// returns its bytes. [onProgress] is called after every page.
  ///
  /// [pageTexts], when given, holds each page's recognised text by index;
  /// null or missing entries mean no text layer for that page.
  Future<Uint8List> build(
    List<String> imagePaths, {
    required PdfExportOptions options,
    String? title,
    PdfProgress? onProgress,
    List<PdfPageText?> pageTexts = const [],
  }) async {
    if (imagePaths.isEmpty) {
      throw const ValidationException('There are no pages to export.');
    }
    final document = PdfDocument(
      version: PdfVersion.pdf_1_4,
      compress: compress,
    );
    // Registers itself as the document's /Info dictionary.
    PdfInfo(document, title: title, creator: 'Scanly', producer: 'Scanly');

    final total = imagePaths.length;
    final layers = <List<_TextLine>?>[
      for (var i = 0; i < total; i++)
        i < pageTexts.length ? _TextLine.split(pageTexts[i]) : null,
    ];
    final needsTtf = layers.any(
      (lines) => lines != null && lines.any((l) => l.needsTtf),
    );
    final fonts = _Fonts(document, needsTtf ? await _loadTtf() : null);

    onProgress?.call(0, total);
    for (var i = 0; i < total; i++) {
      await _addPage(document, imagePaths[i], options, layers[i], fonts);
      onProgress?.call(i + 1, total);
    }
    try {
      return await document.save();
    } on Object catch (e) {
      throw StorageException('The PDF could not be created.', e);
    }
  }

  Future<ByteData?> _loadTtf() async {
    final loader = _bengaliFont;
    if (loader == null) return null;
    try {
      return await loader();
    } on Object catch (e) {
      debugPrint('Scanly: the Bengali PDF font could not be loaded: $e');
      return null;
    }
  }

  Future<void> _addPage(
    PdfDocument document,
    String path,
    PdfExportOptions options,
    List<_TextLine>? text,
    _Fonts fonts,
  ) async {
    if (!File(path).existsSync()) {
      throw const StorageException('A page image is missing.');
    }
    final size = await _images.readSize(path);
    final planned = layoutFor(options, size.width, size.height);

    // Pixels needed for [targetDpi] across the longest side of the image box.
    final boxLongest = math.max(planned.width, planned.height);
    final neededSide = (boxLongest / PdfPageFormat.inch * targetDpi).ceil();
    final maxSide = math.max(1, math.min(neededSide, maxImageSide));

    final jpeg = await _encodePage(
      path,
      maxSide: maxSide,
      quality: options.compression.jpegQuality,
    );
    final image = PdfImage.jpeg(
      document,
      image: jpeg.bytes,
      orientation: PdfImageOrientation.topLeft,
    );
    // Place the image by its decoded size, which is exact after EXIF.
    final layout = layoutFor(options, jpeg.width, jpeg.height);
    final page = PdfPage(document, pageFormat: layout.format);
    final graphics = page.getGraphics()
      ..drawImage(image, layout.x, layout.y, layout.width, layout.height);
    if (text != null && text.isNotEmpty) {
      _drawTextLayer(graphics, fonts, text, layout);
    }
  }

  /// Draws [lines] invisibly over the image placed at [layout].
  static void _drawTextLayer(
    PdfGraphics graphics,
    _Fonts fonts,
    List<_TextLine> lines,
    PdfPageLayout layout,
  ) {
    final slot = layout.height / lines.length;
    // Text state (Tf, Tz, Tr) is graphics state: keep it inside q … Q.
    graphics.saveContext();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final runs = fonts.runsOf(line.text);
      if (runs.isEmpty) continue;
      final box = line.box;
      final double size;
      final double baseline;
      final double left;
      final double? targetWidth;
      if (box != null) {
        final top = layout.y + (1 - box.top) * layout.height;
        final bottom = layout.y + (1 - box.bottom) * layout.height;
        final height = top - bottom;
        size = height * boxFontRatio;
        baseline = bottom + height * boxBaselineRatio;
        left = layout.x + box.left * layout.width;
        targetWidth = (box.right - box.left) * layout.width;
      } else {
        // Slot i of n, counted from the top of the image.
        final top = layout.y + layout.height - i * slot;
        size = math.min(slot * boxFontRatio, maxUnboxedFontSize);
        baseline = top - slot / 2 - size * 0.3;
        left = layout.x;
        targetWidth = null;
      }
      if (size <= 0) continue;

      var natural = 0.0;
      for (final run in runs) {
        natural += run.font.stringMetrics(run.text).advanceWidth * size;
      }
      var scale = 1.0;
      if (natural > 0) {
        if (targetWidth != null) {
          scale = targetWidth / natural;
        } else if (natural > layout.width) {
          scale = layout.width / natural;
        }
      }
      scale = scale.clamp(0.01, 100.0);

      var x = left;
      for (final run in runs) {
        graphics.drawString(
          run.font,
          size,
          run.text,
          x,
          baseline,
          scale: scale,
          mode: PdfTextRenderingMode.invisible,
        );
        x += run.font.stringMetrics(run.text).advanceWidth * size * scale;
      }
    }
    graphics.restoreContext();
  }

  /// Page format and image placement for an image of
  /// [imageWidth]×[imageHeight] pixels.
  static PdfPageLayout layoutFor(
    PdfExportOptions options,
    int imageWidth,
    int imageHeight,
  ) {
    final iw = math.max(1, imageWidth).toDouble();
    final ih = math.max(1, imageHeight).toDouble();

    if (options.pageSize == PdfPageSize.original) {
      var w = iw / originalDpi * PdfPageFormat.inch;
      var h = ih / originalDpi * PdfPageFormat.inch;
      final longest = math.max(w, h);
      if (longest > maxPagePoints) {
        final s = maxPagePoints / longest;
        w *= s;
        h *= s;
      }
      w = math.max(1, w);
      h = math.max(1, h);
      return (format: PdfPageFormat(w, h), x: 0, y: 0, width: w, height: h);
    }

    final paper = switch (options.pageSize) {
      PdfPageSize.a4 => PdfPageFormat.a4,
      PdfPageSize.a5 => PdfPageFormat.a5,
      PdfPageSize.letter => PdfPageFormat.letter,
      PdfPageSize.legal => PdfPageFormat.legal,
      PdfPageSize.original => throw StateError('unreachable'),
    };
    final landscape = switch (options.orientation) {
      PdfOrientation.portrait => false,
      PdfOrientation.landscape => true,
      PdfOrientation.auto => iw > ih,
    };
    final turned = landscape ? paper.landscape : paper.portrait;
    final format = PdfPageFormat(turned.width, turned.height);

    final availW = format.width - 2 * margin;
    final availH = format.height - 2 * margin;
    final scale = math.min(availW / iw, availH / ih);
    final w = iw * scale;
    final h = ih * scale;
    return (
      format: format,
      x: (format.width - w) / 2,
      y: (format.height - h) / 2,
      width: w,
      height: h,
    );
  }

  static Future<({Uint8List bytes, int width, int height})> _encodePage(
    String path, {
    required int maxSide,
    required int quality,
  }) async {
    final ui.Image image = await PageRenderer.decodeImage(
      path,
      maxSide: maxSide,
    );
    try {
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) {
        throw const StorageException('Could not read the page pixels.');
      }
      final width = image.width;
      final height = image.height;
      final pixels = rgba.buffer.asUint8List();
      final bytes = await Isolate.run(
        () => _encodeJpeg(pixels, width, height, quality),
      );
      return (bytes: bytes, width: width, height: height);
    } finally {
      image.dispose();
    }
  }
}

Uint8List _encodeJpeg(Uint8List rgba, int width, int height, int quality) {
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    numChannels: 4,
  );
  return img.encodeJpg(image, quality: quality);
}

/// One line of the text layer: sanitised text and its box, if valid.
class _TextLine {
  _TextLine(this.text, this.box)
    : needsTtf = text.runes.any((r) => r != 0x20 && !_Fonts.isLatin(r));

  final String text;
  final OcrBox? box;

  /// Whether some character needs the TrueType font.
  final bool needsTtf;

  /// Lines of [page] (from its lines, or its text split at line breaks), or
  /// null when it has no drawable text.
  static List<_TextLine>? split(PdfPageText? page) {
    if (page == null) return null;
    final source = page.lines.any((l) => l.text.trim().isNotEmpty)
        ? page.lines
        : [for (final t in page.text.split('\n')) OcrLine(t)];
    final lines = <_TextLine>[
      for (final l in source) _TextLine(_Fonts.sanitise(l.text), _valid(l.box)),
    ];
    while (lines.isNotEmpty && lines.last.text.isEmpty) {
      lines.removeLast();
    }
    while (lines.isNotEmpty && lines.first.text.isEmpty) {
      lines.removeAt(0);
    }
    return lines.isEmpty ? null : lines;
  }

  static OcrBox? _valid(OcrBox? box) {
    if (box == null) return null;
    final l = box.left.clamp(0.0, 1.0);
    final t = box.top.clamp(0.0, 1.0);
    final r = box.right.clamp(0.0, 1.0);
    final b = box.bottom.clamp(0.0, 1.0);
    if (!(r > l) || !(b > t)) return null;
    return OcrBox(l, t, r, b);
  }
}

/// A piece of a line drawn with one font.
typedef _Run = ({PdfFont font, String text});

/// Fonts of one document, created when first used.
class _Fonts {
  _Fonts(this._document, this._ttfBytes);

  final PdfDocument _document;
  final ByteData? _ttfBytes;
  PdfFont? _helvetica;
  PdfTtfFont? _ttf;
  bool _ttfFailed = false;

  PdfFont get helvetica => _helvetica ??= PdfFont.helvetica(_document);

  /// Parsed TrueType font, used to check glyph coverage before the font is
  /// added to the document (an unused font would still be written).
  TtfParser? get _parser {
    if (_parsed != null || _ttfFailed) return _parsed;
    final bytes = _ttfBytes;
    if (bytes == null) {
      _ttfFailed = true;
      return null;
    }
    try {
      return _parsed = TtfParser(bytes);
    } on Object catch (e) {
      debugPrint('Scanly: the Bengali PDF font could not be read: $e');
      _ttfFailed = true;
      return null;
    }
  }

  TtfParser? _parsed;

  /// The TrueType font, added to the document on first use, when it has a
  /// glyph for [rune]; null otherwise.
  PdfTtfFont? ttfFor(int rune) {
    final parser = _parser;
    if (parser == null || !parser.charToGlyphIndexMap.containsKey(rune)) {
      return null;
    }
    try {
      return _ttf ??= PdfTtfFont(_document, _ttfBytes!);
    } on Object catch (e) {
      debugPrint('Scanly: the Bengali PDF font could not be read: $e');
      _ttfFailed = true;
      _parsed = null;
      return null;
    }
  }

  /// Characters Helvetica draws with WinAnsi codes equal to Latin-1.
  static bool isLatin(int r) =>
      (r >= 0x20 && r <= 0x7E) || (r >= 0xA0 && r <= 0xFF);

  /// Typographic punctuation OCR engines emit, mapped to Latin-1 so plain
  /// English text never needs the TrueType font.
  static const _replacements = <int, String>{
    0x2018: "'",
    0x2019: "'",
    0x201A: "'",
    0x201C: '"',
    0x201D: '"',
    0x201E: '"',
    0x2010: '-',
    0x2011: '-',
    0x2013: '-',
    0x2014: '-',
    0x2212: '-',
    0x2026: '...',
    0x2022: '·',
    0x00A0: ' ',
    0x2009: ' ',
    0x202F: ' ',
    0x09: ' ',
  };

  /// Removes characters no font can carry (controls, characters outside the
  /// Basic Multilingual Plane, lone surrogates) and trims the line.
  static String sanitise(String input) {
    final out = StringBuffer();
    for (final r in input.runes) {
      final replacement = _replacements[r];
      if (replacement != null) {
        out.write(replacement);
      } else if (r < 0x20 ||
          (r >= 0x7F && r < 0xA0) ||
          r > 0xFFFF ||
          (r >= 0xD800 && r <= 0xDFFF) ||
          r == 0xFEFF) {
        continue;
      } else {
        out.writeCharCode(r);
      }
    }
    return out.toString().trim();
  }

  /// Splits [text] into runs by font. Spaces stay in the current run when
  /// its font has a space glyph. Characters with no usable font are left
  /// out.
  List<_Run> runsOf(String text) {
    final runs = <_Run>[];
    PdfFont? current;
    final buffer = StringBuffer();
    void flush() {
      final font = current;
      if (font != null && buffer.isNotEmpty) {
        runs.add((font: font, text: buffer.toString()));
      }
      buffer.clear();
    }

    for (final r in text.runes) {
      final PdfFont? font;
      if (r == 0x20) {
        final c = current;
        font = c != null && c.isRuneSupported(0x20) ? c : helvetica;
      } else if (isLatin(r)) {
        font = helvetica;
      } else {
        // Bengali script, ZWJ/ZWNJ and anything else beyond Latin-1, when
        // the TrueType font has a glyph for it (the subsetter rejects
        // characters without one).
        font = ttfFor(r);
      }
      if (font == null) continue;
      if (!identical(font, current)) {
        flush();
        current = font;
      }
      buffer.writeCharCode(r);
    }
    flush();
    // Runs of spaces alone, and spaces at the line ends (left behind by
    // dropped characters), add nothing to search.
    runs.removeWhere((run) => run.text.trim().isEmpty);
    if (runs.isNotEmpty) {
      final first = runs.first;
      runs.first = (font: first.font, text: first.text.trimLeft());
      final last = runs.last;
      runs.last = (font: last.font, text: last.text.trimRight());
    }
    return runs;
  }
}
