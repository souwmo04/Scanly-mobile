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
    final rows =
        await (_db.select(_db.pages)
              ..where((pg) => pg.documentId.equals(documentId))
              ..orderBy([(pg) => OrderingTerm.asc(pg.pageOrder)]))
            .get();
    return rows.map(_toPage).toList();
  }

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
        final page = pages[i];
        await _db
            .into(_db.pages)
            .insert(
              PagesCompanion.insert(
                id: page.id,
                documentId: id,
                pageOrder: i,
                originalPath: page.originalPath,
                processedPath: Value(page.processedPath),
                thumbnailPath: Value(page.thumbnailPath),
                cropCorners: Value(
                  page.cropCorners == null
                      ? null
                      : jsonEncode(page.cropCorners!.toList()),
                ),
                width: page.width,
                height: page.height,
                createdAt: now,
              ),
            );
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
