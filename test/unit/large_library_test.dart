import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scanly/core/services/storage_service.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/data/repositories/drift_document_repository.dart';
import 'package:scanly/data/repositories/drift_folder_repository.dart';
import 'package:scanly/data/repositories/drift_ocr_repository.dart';
import 'package:scanly/data/repositories/drift_search_repository.dart';
import 'package:scanly/domain/entities/search_result.dart';
import 'package:scanly/domain/repositories/document_repository.dart';
import 'package:scanly/domain/repositories/folder_repository.dart';

/// Large-library behaviour: 1,000 documents, 5,000 pages with OCR text and
/// 20 folders. The bounds are deliberately generous (CI machines and debug
/// mode are slow); they catch accidental full scans or N+1 query patterns,
/// which take tens of seconds at this size, not small regressions.
///
/// Timings are printed so docs/PERFORMANCE.md can quote them.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const documentCount = 1000;
  const pagesPerDocument = 5;
  const folderCount = 20;
  const bound = Duration(seconds: 3);

  late Directory sandbox;
  late AppDatabase db;
  late DriftDocumentRepository documents;
  late DriftFolderRepository folders;
  late DriftSearchRepository search;
  late DriftOcrRepository ocr;

  final words = [
    'invoice',
    'receipt',
    'contract',
    'statement',
    'electricity',
    'insurance',
    'passport',
    'warranty',
    'salary',
    'medical',
  ];

  String pageText(int doc, int page) {
    final a = words[(doc + page) % words.length];
    final b = words[(doc * 7 + page * 3) % words.length];
    return 'Page $page of document $doc. This $a mentions the $b and '
        'some ordinary filler text about payments, dates and addresses. '
        'বাংলা লেখা $doc';
  }

  Future<void> seed() async {
    final base = DateTime(2026);
    await db.batch((b) {
      b.insertAll(db.folders, [
        for (var f = 0; f < folderCount; f++)
          FoldersCompanion.insert(
            id: 'f$f',
            name: 'Folder $f',
            createdAt: base,
            updatedAt: base,
          ),
      ]);
      b.insertAll(db.documents, [
        for (var d = 0; d < documentCount; d++)
          DocumentsCompanion.insert(
            id: 'd$d',
            title: 'Document $d ${words[d % words.length]}',
            folderId: Value(d % 2 == 0 ? 'f${d % folderCount}' : null),
            pageCount: const Value(pagesPerDocument),
            isFavorite: Value(d % 25 == 0),
            createdAt: base.add(Duration(minutes: d)),
            updatedAt: base.add(Duration(minutes: d)),
          ),
      ]);
      b.insertAll(db.pages, [
        for (var d = 0; d < documentCount; d++)
          for (var n = 0; n < pagesPerDocument; n++)
            PagesCompanion.insert(
              id: 'd$d-p$n',
              documentId: 'd$d',
              pageOrder: n,
              originalPath: '/none/d$d-$n.jpg',
              width: 2480,
              height: 3508,
              createdAt: base,
            ),
      ]);
      b.insertAll(db.pageOcr, [
        for (var d = 0; d < documentCount; d++)
          for (var n = 0; n < pagesPerDocument; n++)
            PageOcrCompanion.insert(
              id: 'o-d$d-p$n',
              pageId: 'd$d-p$n',
              extractedText: Value(pageText(d, n + 1)),
              engine: 'test',
              status: const Value('done'),
              updatedAt: base,
            ),
      ]);
    });
    await db.transaction(() async {
      for (var d = 0; d < documentCount; d++) {
        await db.indexDocumentTitle(
          'd$d',
          'Document $d ${words[d % words.length]}',
        );
        for (var n = 1; n <= pagesPerDocument; n++) {
          await db.customStatement(
            'INSERT INTO search_index (document_id, page_id, page_number, '
            'kind, content) VALUES (?, ?, ?, ?, ?)',
            ['d$d', 'd$d-p${n - 1}', n, SearchIndexKind.page, pageText(d, n)],
          );
        }
      }
    });
  }

  setUpAll(() async {
    sandbox = await Directory.systemTemp.createTemp('scanly_large_library');
    final storage = StorageService(Directory(p.join(sandbox.path, 'scanly')));
    await storage.ensureInitialized();
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    documents = DriftDocumentRepository(db, storage);
    folders = DriftFolderRepository(db, storage);
    search = DriftSearchRepository(db);
    ocr = DriftOcrRepository(db);
    final watch = Stopwatch()..start();
    await seed();
    // ignore: avoid_print
    print('large library: seeded in ${watch.elapsedMilliseconds} ms');
  });

  tearDownAll(() async {
    await db.close();
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  Future<T> timed<T>(String label, Future<T> Function() body) async {
    final watch = Stopwatch()..start();
    final result = await body();
    watch.stop();
    // ignore: avoid_print
    print('large library: $label ${watch.elapsedMilliseconds} ms');
    expect(
      watch.elapsed,
      lessThan(bound),
      reason: '$label took ${watch.elapsedMilliseconds} ms',
    );
    return result;
  }

  test('the seed has the expected size', () async {
    final pageRows = await db
        .customSelect('SELECT COUNT(*) c FROM pages')
        .getSingle();
    final ocrRows = await db
        .customSelect('SELECT COUNT(*) c FROM page_ocr')
        .getSingle();
    final indexRows = await db
        .customSelect('SELECT COUNT(*) c FROM search_index')
        .getSingle();
    expect(pageRows.read<int>('c'), documentCount * pagesPerDocument);
    expect(ocrRows.read<int>('c'), documentCount * pagesPerDocument);
    expect(indexRows.read<int>('c'), documentCount * (pagesPerDocument + 1));
  });

  test('watchDocuments emits the whole library quickly', () async {
    for (final sort in DocumentSort.values) {
      final all = await timed(
        'watchDocuments(${sort.name})',
        () => documents.watchDocuments(sort: sort).first,
      );
      expect(all, hasLength(documentCount));
    }
    final recent = await timed(
      'watchDocuments(limit 6)',
      () => documents.watchDocuments(limit: 6).first,
    );
    expect(recent.first.id, 'd${documentCount - 1}');
    final favorites = await timed(
      'watchDocuments(favorites)',
      () => documents.watchDocuments(favoritesOnly: true).first,
    );
    expect(favorites, hasLength(documentCount ~/ 25));
    final inFolder = await timed(
      'watchDocuments(folder)',
      () => documents.watchDocuments(folderId: 'f0').first,
    );
    // Even documents go to folder f(d % 20): f0 holds every 20th.
    expect(inFolder, hasLength(documentCount ~/ folderCount));
    expect(
      await timed(
        'watchDocumentCount',
        () => documents.watchDocumentCount().first,
      ),
      documentCount,
    );
  });

  test('folder document counts are correct and fast', () async {
    for (final sort in FolderSort.values) {
      final list = await timed(
        'watchFolders(${sort.name})',
        () => folders.watchFolders(sort: sort).first,
      );
      expect(list, hasLength(folderCount));
      expect(
        list.fold<int>(0, (sum, f) => sum + f.documentCount),
        documentCount ~/ 2,
      );
    }
  });

  test('searchGrouped stays fast and capped', () async {
    final all = await timed(
      'searchGrouped(invoice)',
      () => search.searchGrouped('invoice'),
    );
    expect(all.documents, hasLength(50));
    expect(all.isCapped, isTrue);

    final text = await timed(
      'searchGrouped(text: "electricity mentions")',
      () => search.searchGrouped(
        'electricity mentions',
        filter: SearchFilter.text,
      ),
    );
    expect(text.documents, isNotEmpty);

    final bangla = await timed(
      'searchGrouped(বাংলা)',
      () => search.searchGrouped('বাংলা'),
    );
    expect(bangla.documents, hasLength(50));

    final prefix = await timed(
      'searchGrouped(prefix "rec")',
      () => search.searchGrouped('rec'),
    );
    expect(prefix.documents, isNotEmpty);

    final none = await timed(
      'searchGrouped(no match)',
      () => search.searchGrouped('zebra'),
    );
    expect(none.documents, isEmpty);
  });

  test('countMatches counts every filter over the whole library', () async {
    final counts = await timed(
      'countMatches(invoice)',
      () => search.countMatches('invoice'),
    );
    expect(counts.documents, documentCount ~/ words.length);
    expect(counts.text, greaterThan(counts.documents));
    expect(counts.allDocuments, greaterThanOrEqualTo(counts.text));
    final folderCounts = await timed(
      'countMatches(folder)',
      () => search.countMatches('folder'),
    );
    expect(folderCounts.folders, folderCount);
  });

  test('OCR bookkeeping queries stay fast', () async {
    expect(await timed('unfinishedPages', ocr.unfinishedPages), isEmpty);
    expect(
      await timed(
        'pagesNeedingOcr',
        () => ocr.pagesNeedingOcr('d${documentCount ~/ 2}'),
      ),
      isEmpty,
    );
    final map = await timed(
      'watchForDocument',
      () => ocr.watchForDocument('d1').first,
    );
    expect(map, hasLength(pagesPerDocument));
    // Re-indexing one page deletes by the UNINDEXED page_id column, which
    // scans the FTS table; measured here so a regression is visible.
    await timed(
      'indexPageText (one page)',
      () => db.indexPageText(
        documentId: 'd3',
        pageId: 'd3-p0',
        pageNumber: 1,
        text: 'replaced invoice text',
      ),
    );
  });

  test('a page-ordered document loads quickly', () async {
    final pages = await timed('getPages', () => documents.getPages('d500'));
    expect(pages.map((p) => p.pageOrder), [0, 1, 2, 3, 4]);
  });
}
