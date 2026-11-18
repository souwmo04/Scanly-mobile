import 'folder.dart';
import 'scan_document.dart';

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

/// Which kinds of matches a grouped search returns.
enum SearchFilter {
  /// Folders, title matches and text inside scans.
  all,

  /// Documents whose title matches.
  documents,

  /// Documents with matching recognised text on one or more pages.
  text,

  /// Folders whose name matches.
  folders,
}

/// One page of a document whose recognised text matches the query.
class PageSearchHit {
  const PageSearchHit({required this.pageNumber, required this.snippet});

  /// One-based page number.
  final int pageNumber;

  /// Text around the match, with [SearchResult.highlightStart] /
  /// [SearchResult.highlightEnd] markers around matched terms.
  final String snippet;
}

/// A document with everything in it that matched a query.
class DocumentSearchHit {
  const DocumentSearchHit({
    required this.document,
    required this.pages,
    required this.pageMatchCount,
    this.folderName,
    this.highlightedTitle,
  });

  final ScanDocument document;

  /// Name of the folder the document is in, if any.
  final String? folderName;

  /// The title with highlight markers when the title matched, else `null`.
  final String? highlightedTitle;

  /// Matching pages in page order. May be shorter than [pageMatchCount]
  /// when a document has very many matching pages.
  final List<PageSearchHit> pages;

  /// Total number of matching pages in the document.
  final int pageMatchCount;

  bool get titleMatched => highlightedTitle != null;
}

/// Number of matches for each [SearchFilter], independent of the filter in
/// use, so filter chips can show them.
class SearchCounts {
  const SearchCounts({
    required this.documents,
    required this.text,
    required this.folders,
    required this.allDocuments,
  });

  static const zero = SearchCounts(
    documents: 0,
    text: 0,
    folders: 0,
    allDocuments: 0,
  );

  /// Documents whose title matches.
  final int documents;

  /// Documents with matching page text.
  final int text;

  /// Folders whose name matches.
  final int folders;

  /// Distinct documents matching by title or text.
  final int allDocuments;

  /// Everything shown under [SearchFilter.all]: documents plus folders.
  int get all => allDocuments + folders;

  int forFilter(SearchFilter filter) => switch (filter) {
    SearchFilter.all => all,
    SearchFilter.documents => documents,
    SearchFilter.text => text,
    SearchFilter.folders => folders,
  };
}

/// Search results grouped by document, plus matching folders.
class GroupedSearchResults {
  const GroupedSearchResults({
    required this.query,
    required this.filter,
    required this.folders,
    required this.documents,
    this.isCapped = false,
  });

  const GroupedSearchResults.empty(this.query, this.filter)
    : folders = const [],
      documents = const [],
      isCapped = false;

  /// The normalised query that produced these results.
  final String query;
  final SearchFilter filter;

  /// Matching folders, alphabetically.
  final List<Folder> folders;

  /// Matching documents, most relevant first, then most recently updated.
  final List<DocumentSearchHit> documents;

  /// `true` when more documents matched than were returned.
  final bool isCapped;

  bool get isEmpty => folders.isEmpty && documents.isEmpty;
}
