/// Pure-Dart clean-up applied to the raw output of every OCR engine.
///
/// Rules, in order:
/// * line endings (`\r\n`, `\r`, U+2028, U+2029) become `\n`;
/// * control characters are removed, tabs and exotic spaces (NBSP, thin
///   space, ideographic space…) become a plain space;
/// * stray zero-width characters (ZWSP, BOM, word joiner, soft hyphen,
///   direction marks) are removed, but ZWJ (U+200D) and ZWNJ (U+200C) are
///   kept because they select Bengali conjunct / ya-phala forms;
/// * runs of spaces collapse to one and every line is trimmed;
/// * lines with no letter or digit (e.g. `— _ ~ |`) are dropped as noise.
///   Bengali digits (০–৯) count as digits and the দাঁড়ি (।) is kept inside
///   lines;
/// * runs of blank lines collapse to a single paragraph break, and leading
///   and trailing blank lines are removed.
library;

final _lineBreaks = RegExp('\r\n|\r|\u2028|\u2029');

/// C0/C1 controls except `\n` and `\t` (tab is turned into a space below).
final _controls = RegExp(
  '[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]',
);

/// Tabs and Unicode spaces that should read as a normal space.
final _spaces = RegExp('[\t\u00A0\u1680\u2000-\u200A\u202F\u205F\u3000]');

/// Invisible characters with no meaning in recognised text. ZWNJ (U+200C)
/// and ZWJ (U+200D) are deliberately absent.
final _zeroWidth = RegExp('[\u200B\u200E\u200F\u2060\uFEFF\u00AD\u180E]');

final _spaceRuns = RegExp(' {2,}');

/// Any letter or digit in any script (Bengali digits are `\p{Nd}`).
final _content = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Cleans one line. Returns an empty string when the line is blank or noise.
String cleanOcrLine(String line) {
  final cleaned = line
      .replaceAll(_controls, '')
      .replaceAll(_spaces, ' ')
      .replaceAll(_zeroWidth, '')
      .replaceAll(_spaceRuns, ' ')
      .trim();
  if (!_content.hasMatch(cleaned)) return '';
  return cleaned;
}

/// Cleans multi-line engine output. Paragraph breaks (blank lines) survive
/// as a single empty line; no other empty lines remain.
String cleanOcrText(String raw) {
  final out = <String>[];
  var pendingBreak = false;
  for (final line in raw.replaceAll(_lineBreaks, '\n').split('\n')) {
    final cleaned = cleanOcrLine(line);
    if (cleaned.isEmpty) {
      // Noise lines count as breaks only if the raw line was blank, so a
      // stray "—" between two lines of one paragraph does not split it.
      if (line.trim().isEmpty && out.isNotEmpty) pendingBreak = true;
      continue;
    }
    if (pendingBreak) out.add('');
    pendingBreak = false;
    out.add(cleaned);
  }
  return out.join('\n');
}

/// Non-empty cleaned lines of [raw], in order.
List<String> cleanOcrLines(String raw) =>
    cleanOcrText(raw).split('\n').where((l) => l.isNotEmpty).toList();
