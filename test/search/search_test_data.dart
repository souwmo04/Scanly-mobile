import 'package:drift/drift.dart' show Value;
import 'package:scanly/data/database/app_database.dart';

/// Inserts documents, pages and folders straight into the database and keeps
/// the search index in sync, without touching the filesystem.
class SearchSeed {
  SearchSeed(this.db);

  final AppDatabase db;

  Future<void> folder(String id, String name, {int color = 0}) async {
    await db
        .into(db.folders)
        .insert(
          FoldersCompanion.insert(
            id: id,
            name: name,
            color: Value(color),
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        );
  }

  /// Creates a document. [pageTexts] maps one-based page numbers to OCR
  /// text; the document gets as many pages as the highest key (at least 1).
  Future<void> document(
    String id,
    String title, {
    Map<int, String> pageTexts = const {},
    String? folderId,
    DateTime? updatedAt,
  }) async {
    final pageCount = pageTexts.keys.fold(1, (a, b) => a > b ? a : b);
    await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            id: id,
            title: title,
            folderId: Value(folderId),
            pageCount: Value(pageCount),
            createdAt: DateTime(2026),
            updatedAt: updatedAt ?? DateTime(2026),
          ),
        );
    await db.indexDocumentTitle(id, title);
    for (var n = 1; n <= pageCount; n++) {
      await db
          .into(db.pages)
          .insert(
            PagesCompanion.insert(
              id: '$id-p$n',
              documentId: id,
              pageOrder: n - 1,
              originalPath: '/none/$id-$n.jpg',
              width: 100,
              height: 140,
              createdAt: DateTime(2026),
            ),
          );
      final text = pageTexts[n];
      if (text != null) {
        await db.indexPageText(
          documentId: id,
          pageId: '$id-p$n',
          pageNumber: n,
          text: text,
        );
      }
    }
  }
}
