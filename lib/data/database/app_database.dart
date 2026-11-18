import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Kinds of rows in the `search_index` FTS5 table.
abstract final class SearchIndexKind {
  static const title = 'title';
  static const page = 'page';
}

@DriftDatabase(tables: [Folders, Documents, Pages, PageOcr])
class AppDatabase extends _$AppDatabase {
  /// Opens the on-device database in the app-private support directory.
  AppDatabase()
    : super(
        driftDatabase(
          name: 'scanly',
          native: const DriftNativeOptions(
            databaseDirectory: getApplicationSupportDirectory,
          ),
        ),
      );

  /// Uses a custom executor, e.g. `NativeDatabase.memory()` in tests.
  AppDatabase.forExecutor(super.executor);

  @override
  int get schemaVersion => 1;

  /// Full-text index over document titles and page OCR text.
  ///
  /// The default unicode61 categories (`L* N* Co`) treat combining marks as
  /// separators, which would split Bengali words at every vowel sign
  /// (e.g. "বাংলা" contains U+09BE, category Mc). Adding `M*` keeps them
  /// inside tokens. `remove_diacritics 0` stops folding of marks.
  static const _createSearchIndex = '''
CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
  document_id UNINDEXED,
  page_id UNINDEXED,
  page_number UNINDEXED,
  kind UNINDEXED,
  content,
  tokenize = "unicode61 remove_diacritics 0 categories 'L* N* Co M*'"
)''';

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(_createSearchIndex);
    },
    onUpgrade: (m, from, to) async {
      // Future schema changes are applied step by step here, e.g.
      // `if (from < 2) await m.addColumn(...)`.
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // Safety net in case the index was lost (e.g. a restored backup).
      await customStatement(_createSearchIndex);
    },
  );

  // ---------------------------------------------------------------------------
  // Search index maintenance. FTS tables have no foreign keys, so callers must
  // keep these in sync inside the same transaction as the source rows.
  // ---------------------------------------------------------------------------

  Future<void> indexDocumentTitle(String documentId, String title) async {
    await customStatement(
      'DELETE FROM search_index WHERE document_id = ? AND kind = ?',
      [documentId, SearchIndexKind.title],
    );
    await customStatement(
      'INSERT INTO search_index (document_id, page_id, page_number, kind, '
      'content) VALUES (?, NULL, 0, ?, ?)',
      [documentId, SearchIndexKind.title, title],
    );
  }

  Future<void> indexPageText({
    required String documentId,
    required String pageId,
    required int pageNumber,
    required String text,
  }) async {
    await customStatement('DELETE FROM search_index WHERE page_id = ?', [
      pageId,
    ]);
    if (text.trim().isEmpty) return;
    await customStatement(
      'INSERT INTO search_index (document_id, page_id, page_number, kind, '
      'content) VALUES (?, ?, ?, ?, ?)',
      [documentId, pageId, pageNumber, SearchIndexKind.page, text],
    );
  }

  Future<void> removeDocumentsFromIndex(List<String> documentIds) async {
    for (final id in documentIds) {
      await customStatement('DELETE FROM search_index WHERE document_id = ?', [
        id,
      ]);
    }
  }

  /// Deletes every row in every table, including the search index.
  Future<void> deleteEverything() {
    return transaction(() async {
      await customStatement('DELETE FROM search_index');
      await delete(pageOcr).go();
      await delete(pages).go();
      await delete(documents).go();
      await delete(folders).go();
    });
  }
}
