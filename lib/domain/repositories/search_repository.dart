import '../entities/search_result.dart';

abstract interface class SearchRepository {
  /// Searches document titles, folder names and OCR text.
  Future<List<SearchResult>> search(String query, {int limit = 50});
}
