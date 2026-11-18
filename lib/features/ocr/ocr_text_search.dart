import '../../domain/entities/ocr_result.dart';
import '../../domain/entities/scan_page.dart';

/// A page whose recognised text contains the search query.
class PageTextMatch {
  const PageTextMatch({
    required this.pageIndex,
    required this.snippet,
    required this.matchStart,
    required this.matchEnd,
    required this.count,
  });

  /// Zero-based index of the page in the document.
  final int pageIndex;

  /// Text around the first match, on one line.
  final String snippet;

  /// Position of the first match inside [snippet].
  final int matchStart;
  final int matchEnd;

  /// Number of matches on the page.
  final int count;

  int get pageNumber => pageIndex + 1;
}

/// Finds the pages whose OCR text contains [query], in page order.
///
/// Matching ignores case and runs of whitespace, and treats composed and
/// decomposed Bengali vowel signs (e.g. ো vs ে + া) and zero-width joiners
/// as equal, so text typed on any keyboard finds what the engine produced.
List<PageTextMatch> searchPageTexts(
  List<ScanPage> pages,
  Map<String, PageOcr> ocr,
  String query, {
  int context = 40,
}) {
  final needle = foldForSearch(normalizeForSearch(query).trim());
  if (needle.isEmpty) return const [];
  final matches = <PageTextMatch>[];
  for (var i = 0; i < pages.length; i++) {
    final text = ocr[pages[i].id]?.text;
    if (text == null || text.isEmpty) continue;
    final normalized = normalizeForSearch(text);
    final folded = foldForSearch(normalized);
    final first = folded.indexOf(needle);
    if (first < 0) continue;
    var count = 0;
    for (var at = first; at >= 0; at = folded.indexOf(needle, at + 1)) {
      count++;
    }
    final start = (first - context).clamp(0, normalized.length);
    final end = (first + needle.length + context).clamp(0, normalized.length);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < normalized.length ? '…' : '';
    matches.add(
      PageTextMatch(
        pageIndex: i,
        snippet: '$prefix${normalized.substring(start, end)}$suffix',
        matchStart: prefix.length + first - start,
        matchEnd: prefix.length + first - start + needle.length,
        count: count,
      ),
    );
  }
  return matches;
}

const _decompositions = {
  0x09CB: [0x09C7, 0x09BE], // ো
  0x09CC: [0x09C7, 0x09D7], // ৌ
  0x09DC: [0x09A1, 0x09BC], // ড়
  0x09DD: [0x09A2, 0x09BC], // ঢ়
  0x09DF: [0x09AF, 0x09BC], // য়
};

/// Decomposes Bengali precomposed letters, drops zero-width (non-)joiners
/// and collapses whitespace to single spaces.
String normalizeForSearch(String input) {
  final out = StringBuffer();
  var lastWasSpace = false;
  for (final rune in input.runes) {
    if (rune == 0x200C || rune == 0x200D) continue;
    final isSpace =
        rune == 0x20 ||
        rune == 0x09 ||
        rune == 0x0A ||
        rune == 0x0D ||
        rune == 0xA0;
    if (isSpace) {
      if (!lastWasSpace) out.write(' ');
      lastWasSpace = true;
      continue;
    }
    lastWasSpace = false;
    final parts = _decompositions[rune];
    if (parts != null) {
      parts.forEach(out.writeCharCode);
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

/// Lower-cases [input] without changing its length, so positions in the
/// result are valid in the input.
String foldForSearch(String input) {
  final out = StringBuffer();
  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    final lower = char.toLowerCase();
    out.write(lower.length == char.length ? lower : char);
  }
  return out.toString();
}
