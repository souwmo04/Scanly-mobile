import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../core/services/storage_service.dart';
import '../../core/vision/quad.dart';
import '../../domain/entities/scan_document.dart';
import '../../domain/entities/scan_page.dart';
import '../../domain/repositories/document_repository.dart';
import '../database/app_database.dart';

class DriftDocumentRepository implements DocumentRepository {
  DriftDocumentRepository(this._db, this._storage, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final StorageService _storage;
  final DateTime Function() _clock;

  @override
  Stream<List<ScanDocument>> watchDocuments({
    DocumentSort sort = DocumentSort.updatedNewest,
    String? folderId,
    bool favoritesOnly = false,
    int? limit,
  }) {
    final query = _db.select(_db.documents);
    if (folderId != null) {
      query.where((d) => d.folderId.equals(folderId));
    }
    if (favoritesOnly) {
      query.where((d) => d.isFavorite.equals(true));
    }
    query.orderBy([(d) => _ordering(d, sort)]);
    if (limit != null) query.limit(limit);
    return query.watch().map((rows) => rows.map(_toEntity).toList());
  }

  OrderingTerm _ordering($DocumentsTable d, DocumentSort sort) {
    return switch (sort) {
      DocumentSort.updatedNewest => OrderingTerm.desc(d.updatedAt),
      DocumentSort.createdNewest => OrderingTerm.desc(d.createdAt),
      DocumentSort.createdOldest => OrderingTerm.asc(d.createdAt),
      DocumentSort.titleAZ => OrderingTerm.asc(d.title.collate(Collate.noCase)),
      DocumentSort.sizeLargest => OrderingTerm.desc(d.fileSize),
    };
  }

  @override
  Stream<int> watchDocumentCount() {
    final count = _db.documents.id.count();
    final query = _db.selectOnly(_db.documents)..addColumns([count]);
    return query.watchSingle().map((row) => row.read(count) ?? 0);
  }

  @override
  Future<ScanDocument?> getDocument(String id) async {
    final row = await (_db.select(
      _db.documents,
    )..where((d) => d.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  @override
  Future<List<ScanPage>> getPages(String documentId) async {
    final rows = await _pagesQuery(documentId).get();
    return rows.map(_toPage).toList();
  }

  SimpleSelectStatement<$PagesTable, PageRow> _pagesQuery(String documentId) =>
      _db.select(_db.pages)
        ..where((pg) => pg.documentId.equals(documentId))
        ..orderBy([(pg) => OrderingTerm.asc(pg.pageOrder)]);

  @override
  Stream<List<ScanPage>> watchPages(String documentId) =>
      _pagesQuery(documentId).watch().map((rows) => rows.map(_toPage).toList());

  @override
  Future<ScanPage?> getPage(String pageId) async {
    final row = await (_db.select(
      _db.pages,
    )..where((pg) => pg.id.equals(pageId))).getSingleOrNull();
    return row == null ? null : _toPage(row);
  }

  Future<PageRow> _requirePage(String pageId) async {
    final row = await (_db.select(
      _db.pages,
    )..where((pg) => pg.id.equals(pageId))).getSingleOrNull();
    if (row == null) throw const NotFoundException('Page not found.');
    return row;
  }

  @override
  Future<void> updatePage(String pageId, PageUpdate update) async {
    final e = update.edits;
    await _db.transaction(() async {
      final row = await _requirePage(pageId);
      await (_db.update(_db.pages)..where((pg) => pg.id.equals(pageId))).write(
        PagesCompanion(
          processedPath: Value(update.processedPath),
          thumbnailPath: Value(update.thumbnailPath),
          width: Value(update.width),
          height: Value(update.height),
          cropCorners: Value(
            e.isFullFrame ? null : jsonEncode(e.corners.toList()),
          ),
          rotation: Value(e.rotation),
          filterType: Value(e.filter.name),
          brightness: Value(e.brightness),
          contrast: Value(e.contrast),
          sharpness: Value(e.sharpness),
        ),
      );
      await _refreshDocument(row.documentId);
    });
  }

  @override
  Future<void> addPages(String documentId, List<NewPage> pages) async {
    if (pages.isEmpty) return;
    final now = _clock();
    await _db.transaction(() async {
      if (await getDocument(documentId) == null) {
        throw const NotFoundException('Document not found.');
      }
      final existing = await getPages(documentId);
      for (var i = 0; i < pages.length; i++) {
        await _db
            .into(_db.pages)
            .insert(
              _pageCompanion(pages[i], documentId, existing.length + i, now),
            );
      }
      await _refreshDocument(documentId);
    });
  }

  @override
  Future<ScanPage> replacePage(String pageId, NewPage replacement) async {
    late PageRow old;
    await _db.transaction(() async {
      old = await _requirePage(pageId);
      await (_db.update(_db.pages)..where((pg) => pg.id.equals(pageId))).write(
        PagesCompanion(
          originalPath: Value(replacement.originalPath),
          processedPath: Value(replacement.processedPath),
          thumbnailPath: Value(replacement.thumbnailPath),
          width: Value(replacement.width),
          height: Value(replacement.height),
          cropCorners: Value(
            replacement.cropCorners == null
                ? null
                : jsonEncode(replacement.cropCorners!.toList()),
          ),
          rotation: const Value(0),
          filterType: Value(PageFilter.original.name),
          brightness: const Value(0),
          contrast: const Value(0),
          sharpness: const Value(0),
        ),
      );
      // The old text belongs to the old image.
      await (_db.delete(
        _db.pageOcr,
      )..where((o) => o.pageId.equals(pageId))).go();
      await _db.indexPageText(
        documentId: old.documentId,
        pageId: pageId,
        pageNumber: old.pageOrder + 1,
        text: '',
      );
      await _refreshDocument(old.documentId);
    });
    return _toPage(old);
  }

  @override
  Future<void> deletePage(String pageId) async {
    late PageRow row;
    await _db.transaction(() async {
      row = await _requirePage(pageId);
      final siblings = await getPages(row.documentId);
      if (siblings.length <= 1) {
        throw const ValidationException(
          'A document needs at least one page. Delete the document instead.',
        );
      }
      await _db.indexPageText(
        documentId: row.documentId,
        pageId: pageId,
        pageNumber: 0,
        text: '',
      );
      await (_db.delete(_db.pages)..where((pg) => pg.id.equals(pageId))).go();
      await _writeOrder(
        row.documentId,
        siblings.where((s) => s.id != pageId).map((s) => s.id).toList(),
      );
      await _refreshDocument(row.documentId);
    });
    for (final path in [
      row.originalPath,
      row.processedPath,
      row.thumbnailPath,
    ]) {
      if (path != null) await _storage.deleteFile(path);
    }
    await _refreshSize(row.documentId);
  }

  @override
  Future<void> reorderPages(String documentId, List<String> pageIds) async {
    await _db.transaction(() async {
      final current = (await getPages(documentId)).map((p) => p.id).toSet();
      if (current.length != pageIds.length || !current.containsAll(pageIds)) {
        throw const ValidationException('The page list is out of date.');
      }
      await _writeOrder(documentId, pageIds);
      await _refreshDocument(documentId);
    });
  }

  /// Writes page_order 0…n-1 and keeps search result page numbers in sync.
  Future<void> _writeOrder(String documentId, List<String> pageIds) async {
    for (var i = 0; i < pageIds.length; i++) {
      await (_db.update(_db.pages)..where((pg) => pg.id.equals(pageIds[i])))
          .write(PagesCompanion(pageOrder: Value(i)));
      await _db.customStatement(
        'UPDATE search_index SET page_number = ? WHERE page_id = ?',
        [i + 1, pageIds[i]],
      );
    }
  }

  /// Recomputes page count, cover thumbnail and modification time.
  Future<void> _refreshDocument(String documentId) async {
    final pages = await getPages(documentId);
    await (_db.update(
      _db.documents,
    )..where((d) => d.id.equals(documentId))).write(
      DocumentsCompanion(
        pageCount: Value(pages.length),
        thumbnailPath: Value(pages.isEmpty ? null : pages.first.thumbnailPath),
        updatedAt: Value(_clock()),
      ),
    );
    await _refreshSize(documentId);
  }

  Future<void> _refreshSize(String documentId) async {
    final size = await _storage.sizeOf(_storage.documentDir(documentId));
    await (_db.update(_db.documents)..where((d) => d.id.equals(documentId)))
        .write(DocumentsCompanion(fileSize: Value(size)));
  }

  PagesCompanion _pageCompanion(
    NewPage page,
    String documentId,
    int order,
    DateTime now,
  ) => PagesCompanion.insert(
    id: page.id,
    documentId: documentId,
    pageOrder: order,
    originalPath: page.originalPath,
    processedPath: Value(page.processedPath),
    thumbnailPath: Value(page.thumbnailPath),
    width: page.width,
    height: page.height,
    cropCorners: Value(
      page.cropCorners == null ? null : jsonEncode(page.cropCorners!.toList()),
    ),
    createdAt: now,
  );

  @override
  Future<ScanDocument> createDocument({
    required String id,
    required String title,
    required List<NewPage> pages,
    String? folderId,
  }) async {
    final cleanTitle = _validateTitle(title);
    final now = _clock();
    final size = await _storage.sizeOf(_storage.documentDir(id));

    await _db.transaction(() async {
      await _db
          .into(_db.documents)
          .insert(
            DocumentsCompanion.insert(
              id: id,
              folderId: Value(folderId),
              title: cleanTitle,
              pageCount: Value(pages.length),
              thumbnailPath: Value(
                pages.isEmpty ? null : pages.first.thumbnailPath,
              ),
              fileSize: Value(size),
              createdAt: now,
              updatedAt: now,
            ),
          );
      for (var i = 0; i < pages.length; i++) {
        await _db.into(_db.pages).insert(_pageCompanion(pages[i], id, i, now));
      }
      await _db.indexDocumentTitle(id, cleanTitle);
    });

    final created = await getDocument(id);
    if (created == null) {
      throw const DatabaseException('The document could not be saved.');
    }
    return created;
  }

  @override
  Future<void> rename(String id, String title) async {
    final cleanTitle = _validateTitle(title);
    await _db.transaction(() async {
      final updated =
          await (_db.update(
            _db.documents,
          )..where((d) => d.id.equals(id))).write(
            DocumentsCompanion(
              title: Value(cleanTitle),
              updatedAt: Value(_clock()),
            ),
          );
      if (updated == 0) {
        throw const NotFoundException('Document not found.');
      }
      await _db.indexDocumentTitle(id, cleanTitle);
    });
  }

  @override
  Future<void> setFavorite(String id, {required bool isFavorite}) async {
    // Favoriting is not an edit, so updatedAt is left unchanged.
    await (_db.update(_db.documents)..where((d) => d.id.equals(id))).write(
      DocumentsCompanion(isFavorite: Value(isFavorite)),
    );
  }

  @override
  Future<void> moveToFolder(List<String> ids, String? folderId) async {
    if (ids.isEmpty) return;
    await (_db.update(_db.documents)..where((d) => d.id.isIn(ids))).write(
      DocumentsCompanion(folderId: Value(folderId), updatedAt: Value(_clock())),
    );
  }

  @override
  Future<void> deleteDocuments(List<String> ids) async {
    if (ids.isEmpty) return;
    // Rows first, in one transaction. Pages and OCR rows cascade via foreign
    // keys. Files are removed only after the commit succeeds, so a failure
    // can never leave database rows pointing at deleted files.
    await _db.transaction(() async {
      await _db.removeDocumentsFromIndex(ids);
      await (_db.delete(_db.documents)..where((d) => d.id.isIn(ids))).go();
    });
    for (final id in ids) {
      await _storage.deleteDocumentFiles(id);
    }
  }

  String _validateTitle(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Please enter a name.');
    }
    if (trimmed.length > 200) {
      throw const ValidationException('Names can be at most 200 characters.');
    }
    return trimmed;
  }

  ScanDocument _toEntity(DocumentRow row) => ScanDocument(
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

  ScanPage _toPage(PageRow row) => ScanPage(
    id: row.id,
    documentId: row.documentId,
    pageOrder: row.pageOrder,
    originalPath: row.originalPath,
    processedPath: row.processedPath,
    thumbnailPath: row.thumbnailPath,
    width: row.width,
    height: row.height,
    rotation: row.rotation,
    filter:
        PageFilter.values.asNameMap()[row.filterType] ?? PageFilter.original,
    cropCorners: _parseCorners(row.cropCorners),
    brightness: row.brightness,
    contrast: row.contrast,
    sharpness: row.sharpness,
    createdAt: row.createdAt,
  );

  /// Reads stored crop corners; ignores malformed values rather than
  /// failing to open the document.
  static Quad? _parseCorners(String? json) {
    if (json == null) return null;
    try {
      final values = (jsonDecode(json) as List<dynamic>)
          .map((v) => (v as num).toDouble())
          .toList();
      return Quad.fromList(values);
    } on Object {
      return null;
    }
  }
}
