import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scanly/core/errors/app_exception.dart';
import 'package:scanly/core/services/storage_service.dart';
import 'package:scanly/core/vision/quad.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/data/repositories/drift_document_repository.dart';
import 'package:scanly/data/repositories/drift_search_repository.dart';
import 'package:scanly/domain/entities/page_edits.dart';
import 'package:scanly/domain/entities/scan_page.dart';
import 'package:scanly/domain/repositories/document_repository.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory sandbox;
  late StorageService storage;
  late AppDatabase db;
  late DriftDocumentRepository repo;
  late DriftSearchRepository search;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scanly_pages_test');
    storage = StorageService(Directory(p.join(sandbox.path, 'scanly')));
    await storage.ensureInitialized();
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    repo = DriftDocumentRepository(db, storage);
    search = DriftSearchRepository(db);
  });

  tearDown(() async {
    await db.close();
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  Future<NewPage> page(String docId, {int bytes = 10}) async {
    final id = storage.newId();
    final original = storage.pagePath(docId, id, DocumentFileKind.original);
    final thumb = storage.pagePath(docId, id, DocumentFileKind.thumbnail);
    await storage.writeBytes(original, List.filled(bytes, 1));
    await storage.writeBytes(thumb, [1]);
    return NewPage(
      id: id,
      originalPath: original,
      thumbnailPath: thumb,
      width: 100,
      height: 140,
    );
  }

  Future<(String, List<String>)> document(int pages) async {
    final id = storage.newId();
    final newPages = [for (var i = 0; i < pages; i++) await page(id)];
    await repo.createDocument(id: id, title: 'Doc', pages: newPages);
    return (id, newPages.map((pg) => pg.id).toList());
  }

  test('watchPages emits pages in order and reacts to changes', () async {
    final (id, pageIds) = await document(2);
    final stream = repo.watchPages(id);
    expect((await stream.first).map((pg) => pg.id), pageIds);

    await repo.reorderPages(id, pageIds.reversed.toList());
    expect((await stream.first).map((pg) => pg.id), pageIds.reversed);
  });

  test('updatePage stores edits and refreshes the cover', () async {
    final (id, pageIds) = await document(2);
    final processed = storage.pagePath(
      id,
      pageIds[0],
      DocumentFileKind.processed,
    );
    await storage.writeBytes(processed, List.filled(50, 2));
    final edits = PageEdits.initial().copyWith(
      corners: Quad.fromList([0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9]),
      rotation: 90,
      filter: PageFilter.enhanced,
      brightness: 0.2,
      contrast: -0.1,
      sharpness: 0.4,
    );

    await repo.updatePage(
      pageIds[0],
      PageUpdate(
        processedPath: processed,
        thumbnailPath: processed,
        width: 140,
        height: 100,
        edits: edits,
      ),
    );

    final updated = (await repo.getPage(pageIds[0]))!;
    expect(PageEdits.fromPage(updated), edits);
    expect(updated.displayPath, processed);
    expect((updated.width, updated.height), (140, 100));
    final doc = (await repo.getDocument(id))!;
    expect(doc.thumbnailPath, processed);
    expect(doc.fileSize, greaterThan(20));
  });

  test('full-frame edits store no crop corners', () async {
    final (_, pageIds) = await document(1);
    await repo.updatePage(
      pageIds.single,
      PageUpdate(
        processedPath: null,
        thumbnailPath: '/t.jpg',
        width: 1,
        height: 1,
        edits: PageEdits.initial(),
      ),
    );
    expect((await repo.getPage(pageIds.single))!.cropCorners, isNull);
  });

  test('addPages appends after existing pages', () async {
    final (id, pageIds) = await document(2);
    final extra = [await page(id), await page(id)];

    await repo.addPages(id, extra);

    final pages = await repo.getPages(id);
    expect(pages.map((pg) => pg.id), [...pageIds, ...extra.map((e) => e.id)]);
    expect(pages.map((pg) => pg.pageOrder), [0, 1, 2, 3]);
    expect((await repo.getDocument(id))!.pageCount, 4);
  });

  test('addPages to a missing document fails', () async {
    await expectLater(
      repo.addPages('missing', [await page('missing')]),
      throwsA(isA<NotFoundException>()),
    );
  });

  test('replacePage keeps position, resets edits and OCR text', () async {
    final (id, pageIds) = await document(3);
    await repo.updatePage(
      pageIds[1],
      PageUpdate(
        processedPath: null,
        thumbnailPath: '/t.jpg',
        width: 1,
        height: 1,
        edits: PageEdits.initial().copyWith(rotation: 180, brightness: 0.5),
      ),
    );
    await db.indexPageText(
      documentId: id,
      pageId: pageIds[1],
      pageNumber: 2,
      text: 'stale words',
    );

    final fresh = await page(id, bytes: 30);
    final old = await repo.replacePage(pageIds[1], fresh);

    expect(old.rotation, 180);
    final replaced = (await repo.getPage(pageIds[1]))!;
    expect(replaced.pageOrder, 1);
    expect(replaced.originalPath, fresh.originalPath);
    expect(PageEdits.fromPage(replaced).isIdentity, isTrue);
    expect(await search.search('stale'), isEmpty);
  });

  test('deletePage removes files, renumbers pages and search hits', () async {
    final (id, pageIds) = await document(3);
    await db.indexPageText(
      documentId: id,
      pageId: pageIds[2],
      pageNumber: 3,
      text: 'invoice total',
    );
    final victim = (await repo.getPage(pageIds[0]))!;

    await repo.deletePage(pageIds[0]);

    final pages = await repo.getPages(id);
    expect(pages.map((pg) => pg.id), pageIds.sublist(1));
    expect(pages.map((pg) => pg.pageOrder), [0, 1]);
    expect(File(victim.originalPath).existsSync(), isFalse);
    expect((await repo.getDocument(id))!.pageCount, 2);
    // The search hit now points at page 2.
    expect((await search.search('invoice')).single.pageNumber, 2);
  });

  test('the last page cannot be deleted', () async {
    final (_, pageIds) = await document(1);
    await expectLater(
      repo.deletePage(pageIds.single),
      throwsA(isA<ValidationException>()),
    );
  });

  test('reorderPages validates the page list', () async {
    final (id, pageIds) = await document(3);
    await expectLater(
      repo.reorderPages(id, pageIds.sublist(1)),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      repo.reorderPages(id, [...pageIds.sublist(1), 'other']),
      throwsA(isA<ValidationException>()),
    );
    await repo.reorderPages(id, [pageIds[2], pageIds[0], pageIds[1]]);
    final doc = (await repo.getDocument(id))!;
    final first = (await repo.getPages(id)).first;
    expect(first.id, pageIds[2]);
    expect(doc.thumbnailPath, first.thumbnailPath);
  });
}
