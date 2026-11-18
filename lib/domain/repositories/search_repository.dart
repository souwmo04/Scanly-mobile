import '../entities/search_result.dart';

abstract interface class SearchRepository {
  /// Longest query that is searched; longer input is cut to this length.
  static const maxQueryLength = 100;

  /// Searches document titles, folder names and OCR text.
  Future<List<SearchResult>> search(String query, {int limit = 50});

  /// Searches like [search] but groups matches by document: one entry per
  /// document with its title match and matching pages, plus matching folders.
  ///
  /// [filter] is applied in the query. At most [documentLimit] documents are
  /// returned (most relevant first, then most recently updated); when more
  /// match, [GroupedSearchResults.isCapped] is `true`. Each document carries
  /// at most [pagesPerDocument] page snippets.
  Future<GroupedSearchResults> searchGrouped(
    String query, {
    SearchFilter filter = SearchFilter.all,
    int documentLimit = 50,
    int pagesPerDocument = 30,
  });

  /// Counts matches for every [SearchFilter] at once.
  Future<SearchCounts> countMatches(String query);
}
