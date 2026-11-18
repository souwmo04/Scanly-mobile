import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:scanly/app.dart';
import 'package:scanly/core/errors/app_exception.dart';
import 'package:scanly/core/routing/app_router.dart';
import 'package:scanly/core/services/storage_service.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/domain/services/pdf_service.dart';
import 'package:scanly/features/pdf_viewer/pdf_page_renderer.dart';
import 'package:scanly/shared/providers/core_providers.dart';
import 'package:scanly/shared/providers/pdf_providers.dart';
import 'package:scanly/shared/providers/share_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Storage whose async disk scans/deletes return immediately, so repository
/// calls complete inside widget tests' fake async zone.
class TestStorage extends StorageService {
  TestStorage(super.root);

  @override
  Future<int> sizeOf([Directory? directory]) async => 0;

  @override
  Future<void> deleteFile(String path) async {}

  @override
  Future<void> deleteDocumentFiles(String documentId) async {}
}

typedef EnsureCall = ({
  String documentId,
  PdfExportOptions? options,
  bool force,
});

/// Records calls; no real PDF is written.
class FakePdfService implements DocumentPdfService {
  FakePdfService(this.db);

  final AppDatabase db;
  final ensureCalls = <EnsureCall>[];
  final mergeCalls = <(List<String>, String)>[];
  final splitCalls = <(String, List<int>)>[];

  /// Progress reported by [ensurePdf] before it waits on [gate].
  (int, int)? progress;

  /// When set, [ensurePdf] waits for it before returning.
  Completer<void>? gate;

  /// Number of upcoming [ensurePdf] calls that fail.
  int failuresLeft = 0;

  String pathFor(String id) => '/pdfs/$id.pdf';

  @override
  Future<String> ensurePdf(
    String documentId, {
    PdfExportOptions? options,
    bool force = false,
    PdfProgress? onProgress,
  }) async {
    ensureCalls.add((documentId: documentId, options: options, force: force));
    final report = progress;
    if (report != null) onProgress?.call(report.$1, report.$2);
    await gate?.future;
    if (failuresLeft > 0) {
      failuresLeft--;
      throw const StorageException('Not enough space for the PDF.');
    }
    return pathFor(documentId);
  }

  @override
  Future<String> mergeDocuments(
    List<String> documentIds, {
    required String title,
  }) async {
    mergeCalls.add((documentIds, title));
    await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            id: 'merged',
            title: title,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        );
    return 'merged';
  }

  @override
  Future<List<String>> splitDocument(
    String documentId,
    List<int> partStarts,
  ) async {
    splitCalls.add((documentId, partStarts));
    return [for (var i = 0; i <= partStarts.length; i++) 'part$i'];
  }
}

class FakeShareService implements ShareService {
  final shared = <(List<String>, String?)>[];
  final printed = <(String, String)>[];

  @override
  Future<void> shareFiles(
    List<String> paths, {
    String? subject,
    Rect? origin,
  }) async => shared.add((paths, subject));

  @override
  Future<void> printPdf(String path, {required String jobName}) async =>
      printed.add((path, jobName));
}

final tinyPng = Uint8List.fromList(
  img.encodePng(img.Image(width: 2, height: 3)),
);

/// Renders every page as a tiny PNG and records which pages were rendered.
class FakeRenderer implements PdfPageRenderer {
  FakeRenderer({this.available = true});

  final bool available;
  final opened = <String>[];
  final rendered = <int>[];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<OpenedPdf> open(String path) async {
    opened.add(path);
    return _FakeOpenedPdf(this);
  }
}

class _FakeOpenedPdf implements OpenedPdf {
  _FakeOpenedPdf(this.renderer);

  final FakeRenderer renderer;

  @override
  int get sizeBytes => 2048;

  @override
  Future<RenderedPdfPage> renderPage(
    int index, {
    required int targetWidth,
  }) async {
    renderer.rendered.add(index);
    return RenderedPdfPage(
      image: MemoryImage(tinyPng),
      width: 200,
      height: 300,
    );
  }

  @override
  void dispose() {}
}

/// In-memory app with fakes for everything PDF-related.
class PdfTestApp {
  late Directory sandbox;
  late TestStorage storage;
  late SharedPreferences prefs;
  late AppDatabase db;
  late FakePdfService pdf;
  late FakeShareService share;
  late FakeRenderer renderer;
  late String imagePath;

  Future<void> setUp({Map<String, Object> prefsValues = const {}}) async {
    sandbox = await Directory.systemTemp.createTemp('scanly_pdf_ui');
    storage = TestStorage(Directory('${sandbox.path}/scanly'));
    await storage.ensureInitialized();
    SharedPreferences.setMockInitialValues(prefsValues);
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    pdf = FakePdfService(db);
    share = FakeShareService();
    renderer = FakeRenderer();
    imagePath = '${sandbox.path}/page.png';
    File(imagePath).writeAsBytesSync(tinyPng);
  }

  Future<void> tearDown() async {
    await db.close().timeout(const Duration(seconds: 5));
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  }

  Future<void> insertDocument(
    String id, {
    required String title,
    required int pages,
    DateTime? updatedAt,
  }) async {
    await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            id: id,
            title: title,
            pageCount: Value(pages),
            createdAt: DateTime(2026),
            updatedAt: updatedAt ?? DateTime(2026),
          ),
        );
    for (var i = 0; i < pages; i++) {
      await db
          .into(db.pages)
          .insert(
            PagesCompanion.insert(
              id: '$id-p$i',
              documentId: id,
              pageOrder: i,
              originalPath: imagePath,
              width: 400,
              height: 600,
              createdAt: DateTime(2026),
            ),
          );
    }
  }

  /// Pumps the app and, if given, opens [location]. Returns the router.
  Future<void> pump(WidgetTester tester, {String? location}) async {
    final router = createRouter();
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
          documentPdfServiceProvider.overrideWithValue(pdf),
          shareServiceProvider.overrideWithValue(share),
          pdfPageRendererProvider.overrideWithValue(renderer),
          routerProvider.overrideWithValue(router),
        ],
        child: const ScanlyApp(),
      ),
    );
    await tester.pumpAndSettle();
    if (location != null) {
      unawaited(router.push(location));
      await tester.pumpAndSettle();
    }
  }
}
