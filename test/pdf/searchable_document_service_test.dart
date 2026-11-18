import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:scanly/core/services/pdf_builder.dart';
import 'package:scanly/core/services/storage_service.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/data/repositories/drift_document_repository.dart';
import 'package:scanly/data/services/pdf_document_service.dart';
import 'package:scanly/domain/entities/app_settings.dart';
import 'package:scanly/domain/entities/ocr_result.dart';
import 'package:scanly/domain/repositories/document_repository.dart';
import 'package:scanly/domain/repositories/settings_repository.dart';
import 'package:scanly/domain/services/pdf_service.dart';

import 'searchable_helpers.dart';

class _FakeSettings implements SettingsRepository {
  @override
  AppSettings load() => const AppSettings();

  @override
  Future<void> save(AppSettings settings) async {}
}

class _RecordingBuilder extends PdfBuilder {
  _RecordingBuilder(PdfFontLoader font)
    : super(bengaliFont: font, compress: false);

  int calls = 0;
  List<PdfPageText?> lastTexts = const [];

  @override
  Future<Uint8List> build(
    List<String> imagePaths, {
    required PdfExportOptions options,
    String? title,
    PdfProgress? onProgress,
    List<PdfPageText?> pageTexts = const [],
  }) {
    calls++;
    lastTexts = pageTexts;
    return super.build(
      imagePaths,
      options: options,
      title: title,
      onProgress: onProgress,
      pageTexts: pageTexts,
    );
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory sandbox;
  late StorageService storage;
  late AppDatabase db;
  late DriftDocumentRepository documents;
  late FakeOcrRepository ocr;
  late _RecordingBuilder builder;
  late PdfDocumentService service;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scanly_searchable_svc');
    storage = StorageService(Directory(p.join(sandbox.path, 'scanly')));
    await storage.ensureInitialized();
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    documents = DriftDocumentRepository(db, storage);
    ocr = FakeOcrRepository();
    builder = _RecordingBuilder(DiskFontLoader().call);
    service = PdfDocumentService(
      documents: documents,
      storage: storage,
      settings: _FakeSettings(),
      ocr: ocr,
      builder: builder,
    );
  });

  tearDown(() async {
    await db.close();
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  /// A document with [count] plain pages; returns its id and page ids.
  Future<(String, List<String>)> document(int count) async {
    final id = storage.newId();
    final pages = <NewPage>[];
    for (var i = 0; i < count; i++) {
      final pageId = storage.newId();
      final original = storage.pagePath(id, pageId, DocumentFileKind.original);
      final image = img.Image(width: 120, height: 160)
        ..clear(img.ColorRgb8(200, 200, 200));
      await storage.writeBytes(original, img.encodeJpg(image));
      pages.add(
        NewPage(id: pageId, originalPath: original, width: 120, height: 160),
      );
    }
    await documents.createDocument(id: id, title: 'Doc', pages: pages);
    return (id, [for (final page in pages) page.id]);
  }

  Future<List<String>> pageTexts(String path) async {
    final pdf = PdfInspector(File(path).readAsBytesSync());
    return [
      for (final page in pdf.pages)
        pdf.textOf(page).map((s) => s.text).join(' '),
    ];
  }

  test('passes only finished OCR to the builder', () async {
    final (id, pages) = await document(3);
    ocr
      ..put(pages[0], 'Hello there', lines: const [OcrLine('Hello there')])
      ..put(pages[1], 'Not yet', status: OcrStatus.processing);
    // pages[2] has no OCR at all.
    final path = await service.ensurePdf(id);
    expect(builder.lastTexts, hasLength(3));
    expect(builder.lastTexts[0]!.text, 'Hello there');
    expect(builder.lastTexts[1], isNull);
    expect(builder.lastTexts[2], isNull);
    expect(await pageTexts(path), ['Hello there', '', '']);
  });

  test('the PDF is rebuilt when OCR finishes or changes', () async {
    final (id, pages) = await document(2);
    ocr.put(pages[0], '', status: OcrStatus.pending);
    var path = await service.ensurePdf(id);
    expect(builder.calls, 1);
    expect(await pageTexts(path), ['', '']);

    // Still pending → still processing: same image-only PDF.
    ocr.put(pages[0], '', status: OcrStatus.processing);
    await service.ensurePdf(id);
    expect(builder.calls, 1);

    // OCR finishes → regenerated with the text layer.
    final done = DateTime(2026, 11, 18, 10);
    ocr.put(pages[0], 'বাংলাদেশ সরকার', updatedAt: done);
    path = await service.ensurePdf(id);
    expect(builder.calls, 2);
    expect(await pageTexts(path), ['বাংলাদেশ সরকার', '']);

    // Unchanged → cached.
    await service.ensurePdf(id);
    expect(builder.calls, 2);

    // Re-run (new updatedAt) → regenerated.
    ocr.put(
      pages[0],
      'বাংলাদেশ সরকার',
      updatedAt: done.add(const Duration(minutes: 1)),
    );
    await service.ensurePdf(id);
    expect(builder.calls, 3);

    // Same timestamp but corrected text → regenerated.
    ocr.put(
      pages[0],
      'Government of Bangladesh',
      updatedAt: done.add(const Duration(minutes: 1)),
    );
    path = await service.ensurePdf(id);
    expect(builder.calls, 4);
    expect(await pageTexts(path), ['Government of Bangladesh', '']);

    // OCR on the second page → regenerated.
    ocr.put(pages[1], 'Page two', updatedAt: done);
    path = await service.ensurePdf(id);
    expect(builder.calls, 5);
    expect(await pageTexts(path), ['Government of Bangladesh', 'Page two']);
  });

  test('a failing OCR lookup still exports the images', () async {
    final (id, pages) = await document(1);
    ocr
      ..put(pages[0], 'Text')
      ..fail = true;
    final path = await service.ensurePdf(id);
    expect(await pageTexts(path), ['']);

    // Once OCR is readable again the PDF picks the text up.
    ocr.fail = false;
    final again = await service.ensurePdf(id);
    expect(builder.calls, 2);
    expect(await pageTexts(again), ['Text']);
  });
}
