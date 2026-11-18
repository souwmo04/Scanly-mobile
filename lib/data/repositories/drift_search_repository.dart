import 'package:drift/drift.dart';

import '../../domain/entities/search_result.dart';
import '../../domain/repositories/search_repository.dart';
import '../database/app_database.dart';

class DriftSearchRepository implements SearchRepository {
  DriftSearchRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<SearchResult>> search(String query, {int limit = 50}) async {
    final match = buildMatchExpression(query);
    if (match == null) return const [];

    final results = <SearchResult>[];

    // Folder names: small table, a simple LIKE is enough and handles any
    // script without tokenizer concerns.
    final like = '%${_escapeLike(query.trim())}%';
    final folderRows = await _db
        .customSelect(
          r"SELECT id, name FROM folders WHERE name LIKE ? ESCAPE '\' "
          'ORDER BY name COLLATE NOCASE LIMIT 10',
          variables: [Variable.withString(like)],
          readsFrom: {_db.folders},
        )
        .get();
    for (final row in folderRows) {
      results.add(
        SearchResult(
          kind: SearchMatchKind.folder,
          title: row.read<String>('name'),
          snippet: row.read<String>('name'),
          folderId: row.read<String>('id'),
        ),
      );
    }

    // Titles and OCR text via FTS5. The subquery keeps MATCH on the bare
    // FTS table, then joins documents for the current title.
    final rows = await _db
        .customSelect(
          '''
SELECT s.document_id, s.page_number, s.kind, s.snip, d.title
FROM (
  SELECT document_id, page_number, kind, rank,
         snippet(search_index, 4, ?, ?, '…', 12) AS snip
  FROM search_index
  WHERE search_index MATCH ?
  ORDER BY rank
  LIMIT ?
) s
JOIN documents d ON d.id = s.document_id
ORDER BY s.rank''',
          variables: [
            Variable.withString(SearchResult.highlightStart),
            Variable.withString(SearchResult.highlightEnd),
            Variable.withString(match),
            Variable.withInt(limit),
          ],
          readsFrom: {_db.documents},
        )
        .get();

    for (final row in rows) {
      final kind = row.read<String>('kind');
      final isTitle = kind == SearchIndexKind.title;
      results.add(
        SearchResult(
          kind: isTitle ? SearchMatchKind.title : SearchMatchKind.pageText,
          title: row.read<String>('title'),
          snippet: row.read<String>('snip'),
          documentId: row.read<String>('document_id'),
          pageNumber: isTitle ? null : row.read<int>('page_number'),
        ),
      );
    }
    return results;
  }

  /// Converts free text into a safe FTS5 query: every word is quoted (so
  /// operators and punctuation can't break the syntax) and prefix-matched.
  /// Returns `null` if there is nothing to search for.
  static String? buildMatchExpression(String input) {
    final terms = input
        .split(RegExp(r'\s+'))
        .map((t) => t.replaceAll('"', '').trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return null;
    return terms.map((t) => '"$t"*').join(' ');
  }

  static String _escapeLike(String input) => input
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}
