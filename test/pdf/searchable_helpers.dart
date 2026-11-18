import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:scanly/domain/entities/ocr_result.dart';
import 'package:scanly/domain/repositories/ocr_repository.dart';

/// In-memory [OcrRepository]: only [getForPage] matters to the PDF service.
class FakeOcrRepository implements OcrRepository {
  final results = <String, PageOcr>{};
  bool fail = false;

  void put(
    String pageId,
    String text, {
    List<OcrLine> lines = const [],
    OcrStatus status = OcrStatus.done,
    DateTime? updatedAt,
  }) {
    results[pageId] = PageOcr(
      pageId: pageId,
      status: status,
      text: text,
      lines: lines,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  Future<PageOcr?> getForPage(String pageId) async {
    if (fail) throw StateError('database closed');
    return results[pageId];
  }

  @override
  Stream<PageOcr?> watchForPage(String pageId) => Stream.value(results[pageId]);

  @override
  Stream<Map<String, PageOcr>> watchForDocument(String documentId) =>
      Stream.value(Map.of(results));

  @override
  Future<void> markPending(List<String> pageIds) async {}

  @override
  Future<void> markProcessing(String pageId) async {}

  @override
  Future<void> saveResult(String pageId, OcrResult result) async {}

  @override
  Future<void> markFailed(String pageId, String message) async {}

  @override
  Future<List<String>> pagesNeedingOcr(String documentId) async => const [];

  @override
  Future<List<String>> unfinishedPages() async => const [];
}

/// Path of the bundled Bengali font, read from disk in tests.
const bengaliFontPath = 'assets/fonts/NotoSansBengali-Regular.ttf';

/// Font loader for tests: reads [bengaliFontPath] and counts loads.
class DiskFontLoader {
  int loads = 0;

  Future<ByteData> call() async {
    loads++;
    final bytes = await File(bengaliFontPath).readAsBytes();
    return ByteData.sublistView(bytes);
  }
}

/// One text-showing operation of an uncompressed PDF content stream.
class ShownText {
  ShownText({
    required this.fontName,
    required this.size,
    required this.x,
    required this.y,
    required this.scale,
    required this.renderMode,
    required this.text,
  });

  final String fontName;
  final double size;
  final double x;
  final double y;
  final double? scale;
  final int renderMode;

  /// Decoded text: literal strings as Latin-1, hex strings through the
  /// font's ToUnicode CMap.
  final String text;

  @override
  String toString() =>
      'ShownText($fontName $size at ($x, $y) Tz $scale Tr $renderMode "$text")';
}

/// Minimal reader for PDFs written with `compress: false`.
class PdfInspector {
  PdfInspector(Uint8List bytes) : source = latin1.decode(bytes) {
    for (final m in RegExp(
      r'(\d+) 0 obj(.*?)endobj',
      dotAll: true,
    ).allMatches(source)) {
      objects[int.parse(m.group(1)!)] = m.group(2)!;
    }
  }

  final String source;
  final objects = <int, String>{};

  /// Page dictionaries, in page-tree order.
  List<String> get pages {
    final tree = objects.values.firstWhere(
      (o) => RegExp(r'/Type\s*/Pages\b').hasMatch(o),
    );
    final kids = RegExp(r'/Kids\s*\[([^\]]*)\]').firstMatch(tree)!.group(1)!;
    return [
      for (final m in RegExp(r'(\d+) 0 R').allMatches(kids))
        objects[int.parse(m.group(1)!)]!,
    ];
  }

  /// Concatenated content streams of [page].
  String contentOf(String page) {
    final refs = <int>[];
    final array = RegExp(r'/Contents\s*\[([^\]]*)\]').firstMatch(page);
    if (array != null) {
      refs.addAll([
        for (final m in RegExp(r'(\d+) 0 R').allMatches(array.group(1)!))
          int.parse(m.group(1)!),
      ]);
    } else {
      final single = RegExp(r'/Contents\s+(\d+) 0 R').firstMatch(page);
      if (single != null) refs.add(int.parse(single.group(1)!));
    }
    final out = StringBuffer();
    for (final ref in refs) {
      final obj = objects[ref]!;
      final m = RegExp(
        r'stream\r?\n(.*)\r?\nendstream',
        dotAll: true,
      ).firstMatch(obj);
      out.writeln(m?.group(1) ?? '');
    }
    return out.toString();
  }

  /// Font objects keyed by their resource name (`/F12`).
  Map<String, String> get fonts => {
    for (final o in objects.values)
      if (RegExp(r'/Type\s*/Font\b').hasMatch(o) &&
          RegExp(r'/Name\s*/(F\d+)').hasMatch(o))
        '/${RegExp(r'/Name\s*/(F\d+)').firstMatch(o)!.group(1)!}': o,
  };

  /// Whether a TrueType font program is embedded.
  bool get embedsFontFile => source.contains('/FontFile2');

  /// CID → Unicode map of the font named [fontName], or null.
  Map<int, int>? toUnicode(String fontName) {
    final font = fonts[fontName];
    if (font == null) return null;
    final ref = RegExp(r'/ToUnicode\s+(\d+) 0 R').firstMatch(font);
    if (ref == null) return null;
    final cmap = objects[int.parse(ref.group(1)!)]!;
    return {
      for (final m in RegExp(
        r'<([0-9A-Fa-f]{4})>\s*<([0-9A-Fa-f]{4,})>',
      ).allMatches(cmap.split('beginbfchar').last))
        int.parse(m.group(1)!, radix: 16): int.parse(m.group(2)!, radix: 16),
    };
  }

  /// Every `BT … ET` text operation on [page], decoded.
  List<ShownText> textOf(String page) {
    final content = contentOf(page);
    final shown = <ShownText>[];
    for (final block in RegExp(
      r'BT (.*?)ET',
      dotAll: true,
    ).allMatches(content)) {
      final b = block.group(1)!;
      final tf = RegExp(r'(/F\d+) ([\d.]+) Tf').firstMatch(b)!;
      final tz = RegExp(r'([\d.]+) Tz').firstMatch(b);
      final tr = RegExp(r'(\d) Tr').firstMatch(b);
      final td = RegExp(r'(-?[\d.]+) (-?[\d.]+) Td').firstMatch(b)!;
      final tj = RegExp(r'\[(.*)\]TJ', dotAll: true).firstMatch(b)!.group(1)!;
      final fontName = tf.group(1)!;
      String text;
      if (tj.startsWith('<')) {
        final map = toUnicode(fontName) ?? const {};
        final hex = tj.substring(1, tj.indexOf('>'));
        final codes = <int>[
          for (var i = 0; i + 4 <= hex.length; i += 4)
            map[int.parse(hex.substring(i, i + 4), radix: 16)] ?? 0xFFFD,
        ];
        text = String.fromCharCodes(codes);
      } else {
        text = tj
            .substring(1, tj.lastIndexOf(')'))
            .replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!);
      }
      shown.add(
        ShownText(
          fontName: fontName,
          size: double.parse(tf.group(2)!),
          x: double.parse(td.group(1)!),
          y: double.parse(td.group(2)!),
          scale: tz == null ? null : double.parse(tz.group(1)!) / 100,
          renderMode: tr == null ? 0 : int.parse(tr.group(1)!),
          text: text,
        ),
      );
    }
    return shown;
  }
}
