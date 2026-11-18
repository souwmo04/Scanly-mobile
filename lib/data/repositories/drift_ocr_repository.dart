import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/entities/ocr_result.dart';
import '../../domain/repositories/ocr_repository.dart';
import '../database/app_database.dart';

/// Stores OCR results in the `page_ocr` table and keeps the FTS search index
/// in sync, in the same transaction.
///
/// Rows use the page id as their primary key, so there is exactly one row per
/// page. Rows of deleted pages disappear through the foreign-key cascade.
class DriftOcrRepository implements OcrRepository {
  DriftOcrRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  @override
  Future<PageOcr?> getForPage(String pageId) async {
    final row = await _rowQuery(pageId).getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  @override
  Stream<PageOcr?> watchForPage(String pageId) =>
      _rowQuery(pageId)
          .watchSingleOrNull()
          .map((row) => row == null ? null : _toEntity(row));

  SimpleSelectStatement<$PageOcrTable, PageOcrRow> _rowQuery(String pageId) =>
      _db.select(_db.pageOcr)..where((o) => o.pageId.equals(pageId));

  @override
  Stream<Map<String, PageOcr>> watchForDocument(String documentId) {
    final query = _db.select(_db.pageOcr).join([
      innerJoin(_db.pages, _db.pages.id.equalsExp(_db.pageOcr.pageId)),
    ])..where(_db.pages.documentId.equals(documentId));
    return query.watch().map(
      (rows) => {
        for (final row in rows)
          row.readTable(_db.pageOcr).pageId: _toEntity(
            row.readTable(_db.pageOcr),
          ),
      },
    );
  }

  @override
  Future<void> markPending(List<String> pageIds) async {
    if (pageIds.isEmpty) return;
    await _db.transaction(() async {
      for (final id in pageIds.toSet()) {
        await _upsert(
          id,
          PageOcrCompanion(
            status: Value(OcrStatus.pending.name),
            errorMessage: const Value(null),
            updatedAt: Value(_clock()),
          ),
        );
      }
    });
  }

  @override
  Future<void> markProcessing(String pageId) => _upsert(
    pageId,
    PageOcrCompanion(
      status: Value(OcrStatus.processing.name),
      updatedAt: Value(_clock()),
    ),
  );

  @override
  Future<void> saveResult(String pageId, OcrResult result) async {
    await _db.transaction(() async {
      final page = await (_db.select(
        _db.pages,
      )..where((pg) => pg.id.equals(pageId))).getSingleOrNull();
      if (page == null) throw const NotFoundException('Page not found.');
      await _upsert(
        pageId,
        PageOcrCompanion(
          extractedText: Value(result.text),
          detectedLanguage: Value(result.languageCode),
          engine: Value(result.engine),
          status: Value(OcrStatus.done.name),
          lines: Value(encodeLines(result.lines)),
          errorMessage: const Value(null),
          updatedAt: Value(_clock()),
        ),
      );
      await _db.indexPageText(
        documentId: page.documentId,
        pageId: pageId,
        pageNumber: page.pageOrder + 1,
        text: result.text,
      );
    });
  }

  @override
  Future<void> markFailed(String pageId, String message) => _upsert(
    pageId,
    PageOcrCompanion(
      status: Value(OcrStatus.failed.name),
      errorMessage: Value(message),
      updatedAt: Value(_clock()),
    ),
  );

  @override
  Future<List<String>> pagesNeedingOcr(String documentId) async {
    final rows = await _db
        .customSelect(
          'SELECT p.id AS id FROM pages p '
          'LEFT JOIN page_ocr o ON o.page_id = p.id '
          'WHERE p.document_id = ? '
          "AND (o.id IS NULL OR o.status IN ('pending', 'failed')) "
          'ORDER BY p.page_order',
          variables: [Variable.withString(documentId)],
          readsFrom: {_db.pages, _db.pageOcr},
        )
        .get();
    return [for (final row in rows) row.read<String>('id')];
  }

  @override
  Future<List<String>> unfinishedPages() async {
    final rows = await _db
        .customSelect(
          'SELECT o.page_id AS id FROM page_ocr o '
          'JOIN pages p ON p.id = o.page_id '
          "WHERE o.status IN ('pending', 'processing') "
          'ORDER BY o.updated_at, p.document_id, p.page_order',
          readsFrom: {_db.pages, _db.pageOcr},
        )
        .get();
    return [for (final row in rows) row.read<String>('id')];
  }

  /// Updates the page's row, or creates it when missing. Does nothing when
  /// the page itself no longer exists.
  Future<void> _upsert(String pageId, PageOcrCompanion values) {
    return _db.transaction(() async {
      final updated = await (_db.update(
        _db.pageOcr,
      )..where((o) => o.pageId.equals(pageId))).write(values);
      if (updated > 0) return;
      final page = await (_db.select(
        _db.pages,
      )..where((pg) => pg.id.equals(pageId))).getSingleOrNull();
      if (page == null) return;
      await _db
          .into(_db.pageOcr)
          .insert(
            values.copyWith(
              id: Value(pageId),
              pageId: Value(pageId),
              engine: values.engine.present ? values.engine : const Value(''),
              updatedAt: values.updatedAt.present
                  ? values.updatedAt
                  : Value(_clock()),
            ),
          );
    });
  }

  PageOcr _toEntity(PageOcrRow row) => PageOcr(
    pageId: row.pageId,
    status: OcrStatus.values.asNameMap()[row.status] ?? OcrStatus.pending,
    text: row.extractedText,
    lines: decodeLines(row.lines),
    updatedAt: row.updatedAt,
    languageCode: row.detectedLanguage,
    engine: row.engine.isEmpty ? null : row.engine,
    errorMessage: row.errorMessage,
  );

  /// Lines as JSON `[{"t": text, "b": [l, t, r, b]?}]`.
  static String encodeLines(List<OcrLine> lines) => jsonEncode([
    for (final line in lines)
      {'t': line.text, if (line.box != null) 'b': line.box!.toList()},
  ]);

  /// Reads stored lines; malformed JSON yields no lines rather than an error.
  static List<OcrLine> decodeLines(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      final lines = <OcrLine>[];
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        final text = map['t'] as String? ?? '';
        final box = map['b'] as List<dynamic>?;
        lines.add(
          OcrLine(
            text,
            box == null || box.length != 4
                ? null
                : OcrBox(
                    (box[0] as num).toDouble(),
                    (box[1] as num).toDouble(),
                    (box[2] as num).toDouble(),
                    (box[3] as num).toDouble(),
                  ),
          ),
        );
      }
      return lines;
    } on Object {
      return const [];
    }
  }
}
