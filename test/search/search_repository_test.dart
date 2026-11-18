import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/data/repositories/drift_search_repository.dart';
import 'package:scanly/domain/entities/search_result.dart';
import 'package:scanly/domain/repositories/search_repository.dart';

import 'search_test_data.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DriftSearchRepository search;
  late SearchSeed seed;

  const s = SearchResult.highlightStart;
  const e = SearchResult.highlightEnd;

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    search = DriftSearchRepository(db);
    seed = SearchSeed(db);
  });

  tearDown(() => db.close());

  group('searchGrouped', () {
    test('groups several page hits into one document', () async {
      await seed.folder('f1', 'Bills');
      await seed.document(
        'd1',
        'Electricity statement',
        folderId: 'f1',
        pageTexts: {
          1: 'Account summary and invoice number',
          3: 'Invoice details for March',
          4: 'Unrelated terms and conditions',
          5: 'Pay this invoice by Friday',
        },
      );

      final result = await search.searchGrouped('invoice');

      expect(result.documents, hasLength(1));
      final hit = result.documents.single;
      expect(hit.document.id, 'd1');
      expect(hit.document.pageCount, 5);
      expect(hit.folderName, 'Bills');
      expect(hit.titleMatched, isFalse);
      expect(hit.pageMatchCount, 3);
      expect(hit.pages.map((p) => p.pageNumber), [1, 3, 5]);
      for (final page in hit.pages) {
        expect(page.snippet.toLowerCase(), contains('${s}invoice$e'));
      }
    });

    test('highlights the whole title when the title matches', () async {
      await seed.document(
        'd1',
        'Passport renewal form',
        pageTexts: {2: 'Passport number field'},
      );

      final hit = (await search.searchGrouped('pass')).documents.single;

      expect(hit.highlightedTitle, '${s}Passport$e renewal form');
      expect(hit.pages.single.pageNumber, 2);
      expect(hit.folderName, isNull);
    });

    test('orders by relevance, then by most recently updated', () async {
      await seed.document(
        'weak',
        'Notes',
        pageTexts: {
          1:
              'tax mentioned once among many other words in a fairly long '
              'paragraph about groceries, travel, weather and more things',
        },
      );
      await seed.document('title', 'Tax return 2026');
      await seed.document(
        'older',
        'Letter A',
        pageTexts: {1: 'tax tax tax'},
        updatedAt: DateTime(2026, 1, 1),
      );
      await seed.document(
        'newer',
        'Letter B',
        pageTexts: {1: 'tax tax tax'},
        updatedAt: DateTime(2026, 6, 1),
      );

      final ids = (await search.searchGrouped('tax')).documents
          .map((d) => d.document.id)
          .toList();

      expect(ids.last, 'weak');
      // Identical text ranks equally, so the newer document comes first.
      expect(ids.indexOf('newer'), lessThan(ids.indexOf('older')));
      expect(ids, hasLength(4));
    });

    test('filters are applied in the query', () async {
      await seed.folder('f1', 'Receipts');
      await seed.document('t', 'Receipt from cafe');
      await seed.document('p', 'Scan 12', pageTexts: {1: 'Receipt total 450'});
      await seed.document(
        'both',
        'Receipt bundle',
        pageTexts: {2: 'another receipt'},
      );

      final all = await search.searchGrouped('receipt');
      expect(all.folders.map((f) => f.name), ['Receipts']);
      expect(all.documents.map((d) => d.document.id).toSet(), {
        't',
        'p',
        'both',
      });

      final titles = await search.searchGrouped(
        'receipt',
        filter: SearchFilter.documents,
      );
      expect(titles.folders, isEmpty);
      expect(titles.documents.map((d) => d.document.id).toSet(), {'t', 'both'});
      expect(titles.documents.every((d) => d.pages.isEmpty), isTrue);

      final text = await search.searchGrouped(
        'receipt',
        filter: SearchFilter.text,
      );
      expect(text.documents.map((d) => d.document.id).toSet(), {'p', 'both'});
      expect(text.documents.every((d) => !d.titleMatched), isTrue);

      final folders = await search.searchGrouped(
        'receipt',
        filter: SearchFilter.folders,
      );
      expect(folders.documents, isEmpty);
      expect(folders.folders.single.id, 'f1');
    });

    test('folder section includes document counts', () async {
      await seed.folder('f1', 'Medical', color: 3);
      await seed.folder('f2', 'Work');
      await seed.document('a', 'X-ray', folderId: 'f1');
      await seed.document('b', 'Prescription', folderId: 'f1');

      final result = await search.searchGrouped('medi');

      final folder = result.folders.single;
      expect(folder.name, 'Medical');
      expect(folder.colorIndex, 3);
      expect(folder.documentCount, 2);
      expect(result.documents, isEmpty);
    });

    test('caps the number of documents and reports it', () async {
      for (var i = 0; i < 5; i++) {
        await seed.document('d$i', 'Contract $i');
      }

      final capped = await search.searchGrouped('contract', documentLimit: 3);
      expect(capped.documents, hasLength(3));
      expect(capped.isCapped, isTrue);

      final exact = await search.searchGrouped('contract', documentLimit: 5);
      expect(exact.documents, hasLength(5));
      expect(exact.isCapped, isFalse);
    });

    test('limits page snippets but keeps the full page count', () async {
      await seed.document(
        'big',
        'Manual',
        pageTexts: {for (var n = 1; n <= 8; n++) n: 'warranty page $n'},
      );

      final hit = (await search.searchGrouped(
        'warranty',
        pagesPerDocument: 5,
      )).documents.single;

      expect(hit.pages, hasLength(5));
      expect(hit.pageMatchCount, 8);
    });

    test('handles Bengali, operators, quotes and % safely', () async {
      await seed.document(
        'bn',
        'জন্ম নিবন্ধন সনদ',
        pageTexts: {1: 'গণপ্রজাতন্ত্রী বাংলাদেশ সরকার'},
      );
      await seed.document('r', 'Report');
      await seed.folder('f', '100 percent');

      expect(
        (await search.searchGrouped('বাংলা'))
            .documents
            .single
            .pages
            .single
            .pageNumber,
        1,
      );
      expect(
        (await search.searchGrouped('নিবন্ধন')).documents.single.titleMatched,
        isTrue,
      );
      expect((await search.searchGrouped('"report')).documents, hasLength(1));
      expect(
        (await search.searchGrouped('report AND OR NOT (')).isEmpty,
        isTrue,
      );
      expect((await search.searchGrouped('100%_')).isEmpty, isTrue);
      expect((await search.searchGrouped('   ')).isEmpty, isTrue);
    });

    test('trims a very long query', () async {
      await seed.document('d', 'Insurance policy');
      final long = 'insurance ${'x' * 500}';

      final result = await search.searchGrouped(long);

      expect(result.query.length, SearchRepository.maxQueryLength);
      expect(result.query, startsWith('insurance x'));
    });
  });

  group('countMatches', () {
    test('counts every filter at once', () async {
      await seed.folder('f1', 'Tax');
      await seed.folder('f2', 'Taxes old');
      await seed.document('t', 'Tax return');
      await seed.document('p', 'Scan', pageTexts: {1: 'tax due', 2: 'tax'});
      await seed.document('both', 'Tax letter', pageTexts: {1: 'tax office'});

      final counts = await search.countMatches('tax');

      expect(counts.documents, 2);
      expect(counts.text, 2);
      expect(counts.folders, 2);
      expect(counts.allDocuments, 3);
      expect(counts.all, 5);
      expect(counts.forFilter(SearchFilter.text), 2);
    });

    test('is zero for a blank query', () async {
      final counts = await search.countMatches('  ');
      expect(counts.all, 0);
    });
  });

  test('normalizeQuery collapses whitespace and cuts long input', () {
    expect(DriftSearchRepository.normalizeQuery('  a   b \n c '), 'a b c');
    expect(
      DriftSearchRepository.normalizeQuery('y' * 300).length,
      SearchRepository.maxQueryLength,
    );
  });
}
