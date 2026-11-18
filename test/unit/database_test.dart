import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scanly/core/errors/app_exception.dart';
import 'package:scanly/core/services/storage_service.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/data/repositories/drift_document_repository.dart';
import 'package:scanly/data/repositories/drift_folder_repository.dart';
import 'package:scanly/data/repositories/drift_search_repository.dart';
import 'package:scanly/domain/entities/search_result.dart';
import 'package:scanly/domain/repositories/document_repository.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory sandbox;
  late AppDatabase db;
  late StorageService storage;
  late DriftDocumentRepository documents;
  late DriftFolderRepository folders;
  late DriftSearchRepository search;
  var tick = 0;
  DateTime clock() => DateTime(2026, 1, 1).add(Duration(minutes: tick++));

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scanly_db_test');
    storage = StorageService(Directory(p.join(sandbox.path, 'scanly')));
    await storage.ensureInitialized();
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    documents = DriftDocumentRepository(db, storage, clock: clock);
    folders = DriftFolderRepository(db, storage, clock: clock);
    search = DriftSearchRepository(db);
  });

  tearDown(() async {
    await db.close();
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  /// Writes a real page file and returns a [NewPage] pointing at it.
  Future<NewPage> makePage(String docId) async {
    final pageId = storage.newId();
    final path = storage.pagePath(docId, pageId, DocumentFileKind.original);
    await storage.writeBytes(path, List.filled(10, 1));
    return NewPage(id: pageId, originalPath: path, width: 100, height: 140);
  }

  Future<String> createDoc(
    String title, {
    int pages = 1,
    String? folderId,
  }) async {
    final id = storage.newId();
    final newPages = [for (var i = 0; i < pages; i++) await makePage(id)];
    await documents.createDocument(
      id: id,
      title: title,
      pages: newPages,
      folderId: folderId,
    );
    return id;
  }

  group('documents', () {
    test('create stores pages in order and records file size', () async {
      final id = await createDoc('Invoice', pages: 3);

      final doc = await documents.getDocument(id);
      expect(doc, isNotNull);
      expect(doc!.title, 'Invoice');
      expect(doc.pageCount, 3);
      expect(doc.fileSize, 30);

      final pages = await documents.getPages(id);
      expect(pages.map((pg) => pg.pageOrder), [0, 1, 2]);
    });

    test('rejects empty titles', () {
      expect(
        () => documents.createDocument(id: 'x', title: '   ', pages: const []),
        throwsA(isA<ValidationException>()),
      );
    });

    test('watchDocuments sorts and filters favorites', () async {
      final a = await createDoc('Bravo');
      await createDoc('Alpha');
      await documents.setFavorite(a, isFavorite: true);

      final byTitle = await documents
          .watchDocuments(sort: DocumentSort.titleAZ)
          .first;
      expect(byTitle.map((d) => d.title), ['Alpha', 'Bravo']);

      final favorites = await documents
          .watchDocuments(favoritesOnly: true)
          .first;
      expect(favorites.map((d) => d.id), [a]);
    });

    test('watchDocumentCount updates', () async {
      expect(await documents.watchDocumentCount().first, 0);
      await createDoc('One');
      await createDoc('Two');
      expect(await documents.watchDocumentCount().first, 2);
    });

    test('rename updates title and search index', () async {
      final id = await createDoc('Old name');
      await documents.rename(id, 'Tax return 2026');

      expect((await documents.getDocument(id))!.title, 'Tax return 2026');
      expect(await search.search('old'), isEmpty);
      final hits = await search.search('tax');
      expect(hits.single.documentId, id);
    });

    test('rename of a missing document throws', () {
      expect(
        () => documents.rename('missing', 'x'),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('delete cascades pages, OCR rows, index and files', () async {
      final id = await createDoc('Receipt', pages: 2);
      final pages = await documents.getPages(id);
      await db
          .into(db.pageOcr)
          .insert(
            PageOcrCompanion.insert(
              id: 'ocr1',
              pageId: pages.first.id,
              engine: 'test',
              updatedAt: DateTime(2026),
            ),
          );
      await db.indexPageText(
        documentId: id,
        pageId: pages.first.id,
        pageNumber: 1,
        text: 'grocery total',
      );

      await documents.deleteDocuments([id]);

      expect(await documents.getDocument(id), isNull);
      expect(await db.select(db.pages).get(), isEmpty);
      expect(await db.select(db.pageOcr).get(), isEmpty);
      expect(await search.search('grocery'), isEmpty);
      expect(await search.search('receipt'), isEmpty);
      expect(storage.documentDir(id).existsSync(), isFalse);
    });
  });

  group('folders', () {
    test('create, count documents, rename and recolor', () async {
      final folder = await folders.createFolder(name: 'Bills', colorIndex: 2);
      await createDoc('Electricity', folderId: folder.id);
      await createDoc('Water', folderId: folder.id);
      await createDoc('Loose');

      final all = await folders.watchFolders().first;
      expect(all.single.documentCount, 2);

      await folders.updateFolder(
        folder.id,
        name: 'Utility bills',
        colorIndex: 4,
      );
      final updated = await folders.getFolder(folder.id);
      expect(updated!.name, 'Utility bills');
      expect(updated.colorIndex, 4);
    });

    test('deleting a folder keeps its documents at the root', () async {
      final folder = await folders.createFolder(name: 'Temp', colorIndex: 0);
      final docId = await createDoc('Keep me', folderId: folder.id);

      await folders.deleteFolder(folder.id);

      final doc = await documents.getDocument(docId);
      expect(doc, isNotNull);
      expect(doc!.folderId, isNull);
    });

    test('moveToFolder moves several documents', () async {
      final folder = await folders.createFolder(name: 'Work', colorIndex: 1);
      final a = await createDoc('A');
      final b = await createDoc('B');
      await documents.moveToFolder([a, b], folder.id);

      final inFolder = await documents
          .watchDocuments(folderId: folder.id)
          .first;
      expect(inFolder.map((d) => d.id).toSet(), {a, b});
    });
  });

  group('search', () {
    test('finds title prefixes and folder names', () async {
      await folders.createFolder(name: 'Medical', colorIndex: 0);
      await createDoc('Passport scan');

      final titleHits = await search.search('pass');
      expect(titleHits.single.kind, SearchMatchKind.title);

      final folderHits = await search.search('medi');
      expect(folderHits.single.kind, SearchMatchKind.folder);
    });

    test('returns page number and highlighted snippet for OCR text', () async {
      final id = await createDoc('Letter', pages: 2);
      final pages = await documents.getPages(id);
      await db.indexPageText(
        documentId: id,
        pageId: pages[1].id,
        pageNumber: 2,
        text: 'Please pay the outstanding balance by Friday.',
      );

      final hit = (await search.search('balance')).single;
      expect(hit.kind, SearchMatchKind.pageText);
      expect(hit.pageNumber, 2);
      expect(hit.title, 'Letter');
      expect(
        hit.snippet,
        contains(
          '${SearchResult.highlightStart}balance${SearchResult.highlightEnd}',
        ),
      );
    });

    test(
      'keeps Bengali words intact (vowel signs are not separators)',
      () async {
        final id = await createDoc('জন্ম নিবন্ধন সনদ');
        final pages = await documents.getPages(id);
        await db.indexPageText(
          documentId: id,
          pageId: pages.first.id,
          pageNumber: 1,
          text: 'গণপ্রজাতন্ত্রী বাংলাদেশ সরকার জন্ম নিবন্ধন',
        );

        // Whole word containing vowel signs (া U+09BE, ে U+09C7).
        final bangladesh = await search.search('বাংলাদেশ');
        expect(bangladesh.single.pageNumber, 1);

        // Prefix of a word.
        expect(await search.search('বাংলা'), hasLength(1));

        // Bengali title search.
        final title = await search.search('নিবন্ধন');
        expect(title.map((r) => r.kind), contains(SearchMatchKind.title));

        // A vowel sign alone must not match every word.
        expect(await search.search('া'), isEmpty);
      },
    );

    test('handles mixed Bangla and English text', () async {
      final id = await createDoc('NID');
      final pages = await documents.getPages(id);
      await db.indexPageText(
        documentId: id,
        pageId: pages.first.id,
        pageNumber: 1,
        text: 'National ID Card জাতীয় পরিচয়পত্র Name: রহিম',
      );

      expect(await search.search('national'), hasLength(1));
      expect(await search.search('পরিচয়পত্র'), hasLength(1));
      expect(await search.search('card রহিম'), hasLength(1));
    });

    test('is safe against FTS syntax characters', () async {
      await createDoc('Report');
      expect(await search.search('"report'), hasLength(1));
      expect(await search.search('report AND OR NOT ('), isEmpty);
      expect(await search.search('   '), isEmpty);
      expect(await search.search('100%_'), isEmpty);
    });

    test('buildMatchExpression quotes and prefixes every term', () {
      expect(
        DriftSearchRepository.buildMatchExpression('tax  "2026"'),
        '"tax"* "2026"*',
      );
      expect(DriftSearchRepository.buildMatchExpression(''), isNull);
    });
  });

  test('deleteEverything empties all tables and the index', () async {
    await folders.createFolder(name: 'F', colorIndex: 0);
    await createDoc('Doc', pages: 2);

    await db.deleteEverything();

    expect(await db.select(db.folders).get(), isEmpty);
    expect(await db.select(db.documents).get(), isEmpty);
    expect(await db.select(db.pages).get(), isEmpty);
    expect(await search.search('doc'), isEmpty);
  });
}
