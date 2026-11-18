/// Where a search match was found.
enum SearchMatchKind { title, pageText, folder }

/// A single local search hit.
class SearchResult {
  const SearchResult({
    required this.kind,
    required this.title,
    required this.snippet,
    this.documentId,
    this.folderId,
    this.pageNumber,
  });

  final SearchMatchKind kind;

  /// Document title, or folder name for [SearchMatchKind.folder].
  final String title;

  /// Text around the match. Matched terms are wrapped in
  /// [highlightStart] / [highlightEnd] markers.
  final String snippet;
  final String? documentId;
  final String? folderId;

  /// One-based page number for page-text matches.
  final int? pageNumber;

  static const highlightStart = '\u0002';
  static const highlightEnd = '\u0003';
}
