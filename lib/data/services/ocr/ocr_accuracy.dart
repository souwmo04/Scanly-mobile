/// OCR accuracy metrics (pure Dart).
///
/// Both metrics compare a [reference] (ground truth) with a [hypothesis]
/// (engine output) after whitespace normalisation: every run of whitespace
/// becomes one space and the ends are trimmed, so line-wrapping differences
/// do not count as errors.
library;

final _whitespace = RegExp(r'\s+');

/// Collapses whitespace runs to single spaces and trims.
String normaliseWhitespace(String text) =>
    text.replaceAll(_whitespace, ' ').trim();

/// Edit distance (insertions, deletions, substitutions; each costs 1).
int levenshtein<T>(List<T> a, List<T> b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  var current = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      final deletion = previous[j] + 1;
      final insertion = current[j - 1] + 1;
      final substitution = previous[j - 1] + cost;
      var best = deletion < insertion ? deletion : insertion;
      if (substitution < best) best = substitution;
      current[j] = best;
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}

double _rate(int edits, int referenceLength, int hypothesisLength) {
  if (referenceLength == 0) return hypothesisLength == 0 ? 0 : 1;
  return edits / referenceLength;
}

/// Character error rate: edit distance over Unicode code points (runes)
/// divided by the reference length. 0 is perfect; it can exceed 1 when the
/// hypothesis has many insertions. Bengali vowel signs, hasanta, ZWJ and
/// ZWNJ are separate code points, so each one wrong counts as one error.
double characterErrorRate(String reference, String hypothesis) {
  final ref = normaliseWhitespace(reference).runes.toList();
  final hyp = normaliseWhitespace(hypothesis).runes.toList();
  return _rate(levenshtein(ref, hyp), ref.length, hyp.length);
}

List<String> _words(String text) {
  final normalised = normaliseWhitespace(text);
  return normalised.isEmpty ? const [] : normalised.split(' ');
}

/// Word error rate: edit distance over space-separated words divided by
/// the number of reference words.
double wordErrorRate(String reference, String hypothesis) {
  final ref = _words(reference);
  final hyp = _words(hypothesis);
  return _rate(levenshtein(ref, hyp), ref.length, hyp.length);
}
