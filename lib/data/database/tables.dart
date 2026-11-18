import 'package:drift/drift.dart';

/// Drift table definitions. Column getters map to snake_case SQL columns
/// (for example `createdAt` becomes `created_at`).
///
/// Images and PDFs live on the filesystem; tables only store their paths.

@DataClassName('FolderRow')
class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  IntColumn get color => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('DocumentRow')
@TableIndex(name: 'idx_documents_folder', columns: {#folderId})
@TableIndex(name: 'idx_documents_updated', columns: {#updatedAt})
@TableIndex(name: 'idx_documents_favorite', columns: {#isFavorite})
class Documents extends Table {
  TextColumn get id => text()();
  TextColumn get folderId =>
      text().nullable().references(Folders, #id, onDelete: KeyAction.setNull)();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  IntColumn get pageCount => integer().withDefault(const Constant(0))();
  TextColumn get pdfPath => text().nullable()();
  TextColumn get thumbnailPath => text().nullable()();
  IntColumn get fileSize => integer().withDefault(const Constant(0))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('PageRow')
@TableIndex(name: 'idx_pages_document', columns: {#documentId, #pageOrder})
class Pages extends Table {
  TextColumn get id => text()();
  TextColumn get documentId =>
      text().references(Documents, #id, onDelete: KeyAction.cascade)();
  IntColumn get pageOrder => integer()();
  TextColumn get originalPath => text()();
  TextColumn get processedPath => text().nullable()();
  TextColumn get thumbnailPath => text().nullable()();
  IntColumn get width => integer()();
  IntColumn get height => integer()();
  IntColumn get rotation => integer().withDefault(const Constant(0))();
  TextColumn get filterType => text().withDefault(const Constant('original'))();

  /// Crop outline as JSON `[x0, y0, … x3, y3]`, normalised 0–1 to the original
  /// image (top-left, top-right, bottom-right, bottom-left). Null = no crop.
  /// Added in schema version 2.
  TextColumn get cropCorners => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('PageOcrRow')
@TableIndex(name: 'idx_page_ocr_page', columns: {#pageId}, unique: true)
class PageOcr extends Table {
  TextColumn get id => text()();
  TextColumn get pageId =>
      text().references(Pages, #id, onDelete: KeyAction.cascade)();
  TextColumn get extractedText => text().withDefault(const Constant(''))();
  TextColumn get detectedLanguage => text().nullable()();
  TextColumn get engine => text()();

  /// One of: pending, processing, done, failed.
  TextColumn get status => text().withDefault(const Constant('pending'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
