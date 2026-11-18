import 'package:drift/drift.dart';

import '../../domain/entities/folder.dart';
import '../../domain/entities/scan_document.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/repositories/search_repository.dart';
import '../database/app_database.dart';

class DriftSearchRepository implements SearchRepository {
  DriftSearchRepository(this._db);

  final AppDatabase _db;

  /// Most folders returned by one search.
  static const _folderLimit = 20;

  @override
  Future<List<SearchResult>> search(String query, {int limit = 50}) async {
    final text = normalizeQuery(query);
    final match = buildMatchExpression(text);
    if (match == null) return const [];

    final results = <SearchResult>[];

    // Folder names: small table, a simple LIKE is enough and handles any
    // script without tokenizer concerns.
    final folderRows = await _db
        .customSelect(
          r"SELECT id, name FROM folders WHERE name LIKE ? ESCAPE '\' "
          'ORDER BY name COLLATE NOCASE LIMIT 10',
          variables: [Variable.withString(_likePattern(text))],
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

  @override
  Future<GroupedSearchResults> searchGrouped(
    String query, {
    SearchFilter filter = SearchFilter.all,
    int documentLimit = 50,
    int pagesPerDocument = 30,
  }) async {
    final text = normalizeQuery(query);
    final match = buildMatchExpression(text);
    if (match == null) return GroupedSearchResults.empty(text, filter);

    final folders = switch (filter) {
      SearchFilter.all || SearchFilter.folders => await _matchingFolders(text),
      SearchFilter.documents || SearchFilter.text => const <Folder>[],
    };
    if (filter == SearchFilter.folders) {
      return GroupedSearchResults(
        query: text,
        filter: filter,
        folders: folders,
        documents: const [],
      );
    }

    // Restricting the index kind in SQL keeps the filter (and the cap) exact.
    final kind = switch (filter) {
      SearchFilter.documents => SearchIndexKind.title,
      SearchFilter.text => SearchIndexKind.page,
      SearchFilter.all || SearchFilter.folders => null,
    };
    final kindClause = kind == null ? '' : 'AND kind = ?';
    final kindVars = [if (kind != null) Variable.withString(kind)];

    // One row per document: best (lowest) FTS rank of any of its hits.
    final ranked = await _db
        .customSelect(
          '''
SELECT d.*, f.name AS folder_name
FROM (
  SELECT document_id, MIN(rank) AS best
  FROM search_index
  WHERE search_index MATCH ? $kindClause
  GROUP BY document_id
) h
JOIN documents d ON d.id = h.document_id
LEFT JOIN folders f ON f.id = d.folder_id
ORDER BY h.best, d.updated_at DESC, d.id
LIMIT ?''',
          variables: [
            Variable.withString(match),
            ...kindVars,
            // One extra row tells whether the list was capped.
            Variable.withInt(documentLimit + 1),
          ],
          readsFrom: {_db.documents, _db.folders},
        )
        .get();

    final isCapped = ranked.length > documentLimit;
    final docRows = ranked.take(documentLimit).toList();
    if (docRows.isEmpty) {
      return GroupedSearchResults(
        query: text,
        filter: filter,
        folders: folders,
        documents: const [],
      );
    }

    final ids = [for (final row in docRows) row.read<String>('id')];
    final placeholders = List.filled(ids.length, '?').join(', ');
    final hitRows = await _db
        .customSelect(
          '''
SELECT document_id, kind, page_number,
       CASE WHEN kind = '${SearchIndexKind.title}'
            THEN highlight(search_index, 4, ?, ?)
            ELSE snippet(search_index, 4, ?, ?, '…', 12)
       END AS snip
FROM search_index
WHERE search_index MATCH ? $kindClause AND document_id IN ($placeholders)
ORDER BY document_id, page_number''',
          variables: [
            Variable.withString(SearchResult.highlightStart),
            Variable.withString(SearchResult.highlightEnd),
            Variable.withString(SearchResult.highlightStart),
            Variable.withString(SearchResult.highlightEnd),
            Variable.withString(match),
            ...kindVars,
            for (final id in ids) Variable.withString(id),
          ],
        )
        .get();

    final titles = <String, String>{};
    final pages = <String, List<PageSearchHit>>{};
    final pageCounts = <String, int>{};
    for (final row in hitRows) {
      final docId = row.read<String>('document_id');
      final snip = row.read<String>('snip');
      if (row.read<String>('kind') == SearchIndexKind.title) {
        titles[docId] = snip;
        continue;
      }
      pageCounts[docId] = (pageCounts[docId] ?? 0) + 1;
      final list = pages.putIfAbsent(docId, () => []);
      if (list.length < pagesPerDocument) {
        list.add(
          PageSearchHit(
            pageNumber: row.read<int>('page_number'),
            snippet: snip,
          ),
        );
      }
    }

    final documents = <DocumentSearchHit>[];
    for (final row in docRows) {
      final doc = _toDocument(_db.documents.map(row.data));
      final indexedTitle = titles[doc.id];
      documents.add(
        DocumentSearchHit(
          document: doc,
          folderName: row.readNullable<String>('folder_name'),
          // The index copy of the title should match the stored one; fall
          // back to the plain title if it is ever out of date.
          highlightedTitle: indexedTitle == null
              ? null
              : stripHighlight(indexedTitle) == doc.title
              ? indexedTitle
              : doc.title,
          pages: pages[doc.id] ?? const [],
          pageMatchCount: pageCounts[doc.id] ?? 0,
        ),
      );
    }

    return GroupedSearchResults(
      query: text,
      filter: filter,
      folders: folders,
      documents: documents,
      isCapped: isCapped,
    );
  }

  @override
  Future<SearchCounts> countMatches(String query) async {
    final text = normalizeQuery(query);
    final match = buildMatchExpression(text);
    if (match == null) return SearchCounts.zero;

    final folderRow = await _db
        .customSelect(
          r"SELECT COUNT(*) AS c FROM folders WHERE name LIKE ? ESCAPE '\'",
          variables: [Variable.withString(_likePattern(text))],
          readsFrom: {_db.folders},
        )
        .getSingle();

    final docRow = await _db
        .customSelect(
          '''
SELECT
  COUNT(DISTINCT CASE WHEN s.kind = '${SearchIndexKind.title}'
                      THEN s.document_id END) AS titles,
  COUNT(DISTINCT CASE WHEN s.kind = '${SearchIndexKind.page}'
                      THEN s.document_id END) AS texts,
  COUNT(DISTINCT s.document_id) AS docs
FROM (
  SELECT document_id, kind FROM search_index WHERE search_index MATCH ?
) s
JOIN documents d ON d.id = s.document_id''',
          variables: [Variable.withString(match)],
          readsFrom: {_db.documents},
        )
        .getSingle();

    return SearchCounts(
      documents: docRow.read<int>('titles'),
      text: docRow.read<int>('texts'),
      folders: folderRow.read<int>('c'),
      allDocuments: docRow.read<int>('docs'),
    );
  }

  Future<List<Folder>> _matchingFolders(String text) async {
    final rows = await _db
        .customSelect(
          '''
SELECT f.*,
       (SELECT COUNT(*) FROM documents d WHERE d.folder_id = f.id)
         AS document_count
FROM folders f
WHERE f.name LIKE ? ESCAPE '\\'
ORDER BY f.name COLLATE NOCASE
LIMIT $_folderLimit''',
          variables: [Variable.withString(_likePattern(text))],
          readsFrom: {_db.folders, _db.documents},
        )
        .get();
    return [
      for (final row in rows)
        _toFolder(_db.folders.map(row.data), row.read<int>('document_count')),
    ];
  }

  /// Trims [input], collapses runs of whitespace and cuts it to
  /// [SearchRepository.maxQueryLength] characters.
  static String normalizeQuery(String input) {
    final collapsed = input.trim().replaceAll(RegExp(r'\s+'), ' ');
    final runes = collapsed.runes;
    if (runes.length <= SearchRepository.maxQueryLength) return collapsed;
    return String.fromCharCodes(runes.take(SearchRepository.maxQueryLength))
        .trimRight();
  }

  /// Removes highlight markers from an FTS snippet.
  static String stripHighlight(String snippet) => snippet
      .replaceAll(SearchResult.highlightStart, '')
      .replaceAll(SearchResult.highlightEnd, '');

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

  static String _likePattern(String text) => '%${_escapeLike(text)}%';

  static String _escapeLike(String input) => input
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  static ScanDocument _toDocument(DocumentRow row) => ScanDocument(
    id: row.id,
    folderId: row.folderId,
    title: row.title,
    pageCount: row.pageCount,
    pdfPath: row.pdfPath,
    thumbnailPath: row.thumbnailPath,
    fileSize: row.fileSize,
    isFavorite: row.isFavorite,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  static Folder _toFolder(FolderRow row, int documentCount) => Folder(
    id: row.id,
    name: row.name,
    colorIndex: row.color,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    documentCount: documentCount,
  );
}
