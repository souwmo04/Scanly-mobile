import 'dart:io';

import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scanly/core/errors/app_exception.dart';
import 'package:scanly/core/services/storage_service.dart';
import 'package:scanly/core/vision/quad.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/data/repositories/drift_document_repository.dart';
import 'package:scanly/data/repositories/drift_folder_repository.dart';
import 'package:scanly/data/repositories/drift_ocr_repository.dart';
import 'package:scanly/domain/entities/ocr_result.dart';
import 'package:scanly/domain/entities/page_edits.dart';
import 'package:scanly/domain/entities/scan_page.dart';
import 'package:scanly/domain/repositories/document_repository.dart';
import 'package:scanly/domain/repositories/ocr_repository.dart';
import 'package:scanly/domain/usecases/duplicate_document.dart';

/// Wraps the real repository and fails [saveResult] on demand.
class _FailingOcr implements OcrRepository {
  _FailingOcr(this._inner);

  final OcrRepository _inner;

  @override
  Future<void> saveResult(String pageId, OcrResult result) =>
      throw const DatabaseException('Disk full.');

  @override
  Future<PageOcr?> getForPage(String pageId) => _inner.getForPage(pageId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory sandbox;
  late StorageService storage;
  late AppDatabase db;
  late DriftDocumentRepository documents;
  late DriftOcrRepository ocr;
  late DuplicateDocumentUseCase duplicate;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scanly_duplicate_test');
    storage = StorageService(Directory(p.join(sandbox.path, 'scanly')));
    await storage.ensureInitialized();
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    documents = DriftDocumentRepository(db, storage);
    ocr = DriftOcrRepository(db);
    duplicate = DuplicateDocumentUseCase(
      documents: documents,
      storage: storage,
      ocr: ocr,
    );
  });

  tearDown(() async {
    await db.close();
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  /// A page with original, processed and thumbnail files of distinct bytes.
  Future<NewPage> page(String docId, int seed, {bool processed = true}) async {
    final id = storage.newId();
    final original = storage.pagePath(docId, id, DocumentFileKind.original);
    final thumb = storage.pagePath(docId, id, DocumentFileKind.thumbnail);
    await storage.writeBytes(original, List.filled(20, seed));
    await storage.writeBytes(thumb, [seed, 1]);
    String? processedPath;
    if (processed) {
      processedPath = storage.pagePath(docId, id, DocumentFileKind.processed);
      await storage.writeBytes(processedPath, List.filled(10, seed + 1));
    }
    return NewPage(
      id: id,
      originalPath: original,
      processedPath: processedPath,
      thumbnailPath: thumb,
      width: 100,
      height: 140,
    );
  }

  final crop = Quad.fromList([0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9]);

  /// Two pages: the first edited and recognised, the second untouched.
  Future<(String, List<NewPage>)> source({String? folderId}) async {
    final id = storage.newId();
    final pages = [await page(id, 3), await page(id, 7, processed: false)];
    await documents.createDocument(
      id: id,
      title: 'Lease',
      pages: pages,
      folderId: folderId,
    );
    await documents.updatePage(
      pages[0].id,
      PageUpdate(
        processedPath: pages[0].processedPath,
        thumbnailPath: pages[0].thumbnailPath!,
        width: 80,
        height: 110,
        edits: PageEdits(
          corners: crop,
          rotation: 90,
          filter: PageFilter.blackWhite,
          brightness: 0.25,
          contrast: -0.5,
          sharpness: 0.4,
        ),
      ),
    );
    await ocr.saveResult(
      pages[0].id,
      const OcrResult(
        text: 'Monthly rent\nDeposit',
        lines: [
          OcrLine('Monthly rent', OcrBox(0.1, 0.1, 0.6, 0.15)),
          OcrLine('Deposit'),
        ],
        languageCode: 'ben+eng',
        engine: OcrEngineId.tesseract,
      ),
    );
    return (id, pages);
  }

  Future<List<String>> indexedPageText(String documentId) async {
    final rows = await db
        .customSelect(
          'SELECT content FROM search_index '
          "WHERE document_id = ? AND kind = 'page'",
          variables: [Variable.withString(documentId)],
        )
        .get();
    return [for (final row in rows) row.read<String>('content')];
  }

  test('copies every page file under new ids into "<title> (copy)"', () async {
    final folders = DriftFolderRepository(db, storage);
    final folder = await folders.createFolder(name: 'Home', colorIndex: 1);
    final (sourceId, sourcePages) = await source(folderId: folder.id);

    final copyId = await duplicate(sourceId);

    expect(copyId, isNot(sourceId));
    final copy = (await documents.getDocument(copyId))!;
    expect(copy.title, 'Lease (copy)');
    expect(copy.folderId, folder.id);
    expect(copy.pageCount, 2);

    final copies = await documents.getPages(copyId);
    expect(copies, hasLength(2));
    final copyDir = storage.documentDir(copyId).path;
    for (var i = 0; i < 2; i++) {
      final src = sourcePages[i];
      final dst = copies[i];
      expect(dst.id, isNot(src.id));
      expect(p.isWithin(copyDir, dst.originalPath), isTrue);
      expect(
        File(dst.originalPath).readAsBytesSync(),
        File(src.originalPath).readAsBytesSync(),
      );
      expect(
        File(dst.thumbnailPath!).readAsBytesSync(),
        File(src.thumbnailPath!).readAsBytesSync(),
      );
    }
    expect(p.isWithin(copyDir, copies[0].processedPath!), isTrue);
    expect(
      File(copies[0].processedPath!).readAsBytesSync(),
      File(sourcePages[0].processedPath!).readAsBytesSync(),
    );
    expect(copies[1].processedPath, isNull);
    expect(copy.thumbnailPath, copies[0].thumbnailPath);
    expect(copy.fileSize, greaterThan(0));
  });

  test('the copy survives deleting the source', () async {
    final (sourceId, _) = await source();
    final copyId = await duplicate(sourceId);

    await documents.deleteDocuments([sourceId]);

    expect(storage.documentDir(sourceId).existsSync(), isFalse);
    final copies = await documents.getPages(copyId);
    for (final page in copies) {
      expect(File(page.originalPath).existsSync(), isTrue);
      expect(File(page.thumbnailPath!).existsSync(), isTrue);
    }
    expect(File(copies[0].processedPath!).existsSync(), isTrue);
    expect(await indexedPageText(copyId), ['Monthly rent\nDeposit']);
  });

  test('preserves each page\'s edits and OCR text, lines and engine', () async {
    final (sourceId, _) = await source();
    final copyId = await duplicate(sourceId);

    final copies = await documents.getPages(copyId);
    final edited = copies[0];
    expect(edited.cropCorners, crop);
    expect(edited.rotation, 90);
    expect(edited.filter, PageFilter.blackWhite);
    expect(edited.brightness, 0.25);
    expect(edited.contrast, -0.5);
    expect(edited.sharpness, 0.4);
    expect(edited.width, 80);
    expect(edited.height, 110);
    expect(copies[1].rotation, 0);
    expect(copies[1].filter, PageFilter.original);

    final text = (await ocr.getForPage(edited.id))!;
    expect(text.status, OcrStatus.done);
    expect(text.text, 'Monthly rent\nDeposit');
    expect(text.lines, const [
      OcrLine('Monthly rent', OcrBox(0.1, 0.1, 0.6, 0.15)),
      OcrLine('Deposit'),
    ]);
    expect(text.languageCode, 'ben+eng');
    expect(text.engine, OcrEngineId.tesseract);
    // The unrecognised page stays unrecognised.
    expect(await ocr.getForPage(copies[1].id), isNull);
    // Searchable straight away.
    expect(await indexedPageText(copyId), ['Monthly rent\nDeposit']);
  });

  test('long titles are shortened to fit the suffix', () {
    final title = DuplicateDocumentUseCase.copyTitle('x' * 200);
    expect(title.length, 200);
    expect(title, endsWith(' (copy)'));
  });

  test('a missing original removes the files copied so far', () async {
    final (sourceId, sourcePages) = await source();
    File(sourcePages[1].originalPath).deleteSync();
    final before = await documents.watchDocuments().first;

    await expectLater(duplicate(sourceId), throwsA(isA<StorageException>()));

    final after = await documents.watchDocuments().first;
    expect(after.map((d) => d.id), before.map((d) => d.id));
    final dirs = storage.documentsDir.listSync().map((e) => p.basename(e.path));
    expect(dirs, [sourceId]);
  });

  test('a failure after the document is created deletes it again', () async {
    final (sourceId, _) = await source();
    final failing = DuplicateDocumentUseCase(
      documents: documents,
      storage: storage,
      ocr: _FailingOcr(ocr),
    );

    await expectLater(failing(sourceId), throwsA(isA<DatabaseException>()));

    final all = await documents.watchDocuments().first;
    expect(all.map((d) => d.id), [sourceId]);
    final dirs = storage.documentsDir.listSync().map((e) => p.basename(e.path));
    expect(dirs, [sourceId]);
    // The source is untouched.
    expect(await documents.getPages(sourceId), hasLength(2));
    expect(await indexedPageText(sourceId), ['Monthly rent\nDeposit']);
  });

  test('unknown documents are reported', () async {
    await expectLater(duplicate('missing'), throwsA(isA<NotFoundException>()));
  });
}
