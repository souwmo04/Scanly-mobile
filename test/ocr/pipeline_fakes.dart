import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:scanly/core/errors/app_exception.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/domain/entities/app_settings.dart';
import 'package:scanly/domain/entities/ocr_result.dart';
import 'package:scanly/domain/services/ocr_engine.dart';

/// Engine that returns `text of <path>` and records every call.
class FakeOcrEngine implements OcrEngine {
  final calls = <(String, OcrLanguage)>[];

  /// Paths whose next recognition fails (one failure per entry).
  final failures = <String>[];

  /// Custom text per path.
  final texts = <String, String>{};

  /// When set, every call waits for it.
  Completer<void>? gate;

  /// Completes when a call starts (reset by the test).
  Completer<void> started = Completer<void>();

  int _active = 0;
  int maxConcurrent = 0;

  @override
  Future<OcrResult> recognize(String imagePath, OcrLanguage language) async {
    calls.add((imagePath, language));
    _active++;
    if (_active > maxConcurrent) maxConcurrent = _active;
    if (!started.isCompleted) started.complete();
    try {
      await gate?.future;
      if (failures.remove(imagePath)) {
        throw const StorageException('The OCR model could not be loaded.');
      }
      final text = texts[imagePath] ?? 'text of $imagePath';
      return OcrResult(
        text: text,
        lines: [
          for (final line in text.split('\n'))
            OcrLine(line, const OcrBox(0.1, 0.1, 0.9, 0.2)),
        ],
        languageCode: languageCodeOf(language),
        engine: OcrEngineId.tesseract,
      );
    } finally {
      _active--;
    }
  }
}

/// Inserts a document with [pages] pages whose images are `/img/<id>-p<i>`.
Future<List<String>> insertDocument(
  AppDatabase db,
  String id, {
  int pages = 3,
  String title = 'Lease',
}) async {
  await db
      .into(db.documents)
      .insert(
        DocumentsCompanion.insert(
          id: id,
          title: title,
          pageCount: Value(pages),
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
  final ids = <String>[];
  for (var i = 0; i < pages; i++) {
    final pageId = '$id-p$i';
    ids.add(pageId);
    await db
        .into(db.pages)
        .insert(
          PagesCompanion.insert(
            id: pageId,
            documentId: id,
            pageOrder: i,
            originalPath: imagePathOf(pageId),
            width: 400,
            height: 600,
            createdAt: DateTime(2026),
          ),
        );
  }
  return ids;
}

String imagePathOf(String pageId) => '/img/$pageId.jpg';
