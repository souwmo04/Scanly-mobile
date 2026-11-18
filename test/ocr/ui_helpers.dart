import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scanly/app.dart';
import 'package:scanly/core/routing/app_router.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/domain/services/document_scanner.dart';
import 'package:scanly/domain/usecases/import_pages.dart';
import 'package:scanly/features/ocr/ocr_queue.dart';
import 'package:scanly/features/pdf_viewer/pdf_page_renderer.dart';
import 'package:scanly/shared/providers/core_providers.dart';
import 'package:scanly/shared/providers/ocr_providers.dart';
import 'package:scanly/shared/providers/pdf_providers.dart';
import 'package:scanly/shared/providers/scanner_providers.dart';
import 'package:scanly/shared/providers/share_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pdf/ui_test_helpers.dart';
import 'pipeline_fakes.dart';

/// Google scanner stand-in that returns [paths] once.
class FakeScanner implements DocumentScanner {
  FakeScanner(this.paths);

  final List<String> paths;

  @override
  bool get isSupported => true;

  @override
  Future<ScanResult> scan({
    required int pageLimit,
    required bool allowGalleryImport,
  }) async => ScanResult.completed(paths);
}

/// Saves scans as rows only (no image decoding): new documents get one
/// page per source; appends add pages; retakes keep the page.
class FakeImport implements ImportPagesUseCase {
  FakeImport(this.db);

  final AppDatabase db;
  int _documents = 0;

  @override
  Future<String> call(
    List<PageSource> sources, {
    required String title,
    String? folderId,
    bool deleteSources = false,
    int jpegQuality = 88,
    ImportProgress? onProgress,
  }) async {
    final id = 'scan${++_documents}';
    await insertDocument(db, id, pages: sources.length, title: title);
    return id;
  }

  @override
  Future<void> appendTo(
    String documentId,
    List<PageSource> sources, {
    bool deleteSources = false,
    int jpegQuality = 88,
    ImportProgress? onProgress,
  }) async {
    final existing = await (db.select(
      db.pages,
    )..where((p) => p.documentId.equals(documentId))).get();
    for (var i = 0; i < sources.length; i++) {
      final order = existing.length + i;
      await db
          .into(db.pages)
          .insert(
            PagesCompanion.insert(
              id: '$documentId-p$order',
              documentId: documentId,
              pageOrder: order,
              originalPath: imagePathOf('$documentId-p$order'),
              width: 400,
              height: 600,
              createdAt: DateTime(2026),
            ),
          );
    }
    await (db.update(
      db.documents,
    )..where((d) => d.id.equals(documentId))).write(
      DocumentsCompanion(pageCount: Value(existing.length + sources.length)),
    );
  }

  @override
  Future<void> replacePage(
    String pageId,
    PageSource source, {
    bool deleteSource = false,
    int jpegQuality = 88,
  }) async {}
}

/// In-memory app with a fake OCR engine and fakes for scanning and PDFs.
class OcrTestApp {
  late Directory sandbox;
  late TestStorage storage;
  late SharedPreferences prefs;
  late AppDatabase db;
  late FakeOcrEngine engine;
  late FakePdfService pdf;
  late GoRouter router;
  late ProviderContainer container;

  Future<void> setUp({Map<String, Object> prefsValues = const {}}) async {
    sandbox = await Directory.systemTemp.createTemp('scanly_ocr_ui');
    storage = TestStorage(Directory('${sandbox.path}/scanly'));
    await storage.ensureInitialized();
    SharedPreferences.setMockInitialValues(prefsValues);
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    engine = FakeOcrEngine();
    pdf = FakePdfService(db);
  }

  Future<void> tearDown() async {
    await db.close().timeout(const Duration(seconds: 5));
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  }

  OcrQueue get queue => container.read(ocrQueueProvider.notifier);

  Future<void> pump(
    WidgetTester tester, {
    String? location,
    List<String> scans = const [],
  }) async {
    router = createRouter();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          storageServiceProvider.overrideWithValue(storage),
          appDatabaseProvider.overrideWithValue(db),
          ocrEngineProvider.overrideWithValue(engine),
          documentPdfServiceProvider.overrideWithValue(pdf),
          shareServiceProvider.overrideWithValue(FakeShareService()),
          pdfPageRendererProvider.overrideWithValue(FakeRenderer()),
          documentScannerProvider.overrideWithValue(FakeScanner(scans)),
          importPagesProvider.overrideWithValue(FakeImport(db)),
          availableCamerasProvider.overrideWithValue(
            () async => <CameraDescription>[],
          ),
          routerProvider.overrideWithValue(router),
        ],
        child: const ScanlyApp(),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(ScanlyApp)),
    );
    if (location != null) {
      unawaited(router.push(location));
      await tester.pumpAndSettle();
    }
  }
}
