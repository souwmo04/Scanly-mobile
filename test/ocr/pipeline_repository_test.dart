import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanly/core/errors/app_exception.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/data/repositories/drift_ocr_repository.dart';
import 'package:scanly/data/repositories/drift_search_repository.dart';
import 'package:scanly/domain/entities/ocr_result.dart';
import 'package:scanly/domain/entities/search_result.dart';

import 'pipeline_fakes.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DriftOcrRepository repo;
  late DriftSearchRepository search;
  var now = DateTime(2026, 1, 1, 10);

  setUp(() {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    now = DateTime(2026, 1, 1, 10);
    repo = DriftOcrRepository(
      db,
      clock: () => now = now.add(const Duration(seconds: 1)),
    );
    search = DriftSearchRepository(db);
  });

  tearDown(() => db.close());

  OcrResult result(String text, {String code = 'eng'}) => OcrResult(
    text: text,
    lines: [
      OcrLine(text.split('\n').first, const OcrBox(0.1, 0.2, 0.8, 0.3)),
      if (text.contains('\n')) OcrLine(text.split('\n').last),
    ],
    languageCode: code,
    engine: OcrEngineId.tesseract,
  );

  test('saveResult stores text, lines and language and indexes it', () async {
    final pages = await insertDocument(db, 'doc', pages: 2);
    await repo.markPending(pages);
    await repo.saveResult(pages[1], result('Monthly rent\nশুভ নববর্ষ'));

    final stored = await repo.getForPage(pages[1]);
    expect(stored!.status, OcrStatus.done);
    expect(stored.text, 'Monthly rent\nশুভ নববর্ষ');
    expect(stored.languageCode, 'eng');
    expect(stored.engine, OcrEngineId.tesseract);
    expect(stored.errorMessage, isNull);
    expect(stored.lines, [
      const OcrLine('Monthly rent', OcrBox(0.1, 0.2, 0.8, 0.3)),
      const OcrLine('শুভ নববর্ষ'),
    ]);

    final hits = await search.search('rent');
    final page = hits.singleWhere((h) => h.kind == SearchMatchKind.pageText);
    expect(page.documentId, 'doc');
    expect(page.pageNumber, 2);

    final bangla = await search.search('নববর্ষ');
    expect(
      bangla.where((h) => h.kind == SearchMatchKind.pageText),
      hasLength(1),
    );
  });

  test('saving again replaces the indexed text', () async {
    final pages = await insertDocument(db, 'doc', pages: 1);
    await repo.saveResult(pages[0], result('alpha'));
    await repo.saveResult(pages[0], result('beta'));
    expect(await search.search('alpha'), isEmpty);
    expect(await search.search('beta'), hasLength(1));
  });

  test('saveResult for a missing page throws NotFound', () async {
    await expectLater(
      repo.saveResult('nope', result('x')),
      throwsA(isA<NotFoundException>()),
    );
  });

  test('markFailed keeps the previous text and stores the error', () async {
    final pages = await insertDocument(db, 'doc', pages: 1);
    await repo.saveResult(pages[0], result('kept text'));
    await repo.markFailed(pages[0], 'Model missing');

    final stored = await repo.getForPage(pages[0]);
    expect(stored!.status, OcrStatus.failed);
    expect(stored.text, 'kept text');
    expect(stored.errorMessage, 'Model missing');
    expect(await search.search('kept'), hasLength(1));

    // A new pending mark clears the error but keeps the text.
    await repo.markPending(pages);
    final pending = await repo.getForPage(pages[0]);
    expect(pending!.status, OcrStatus.pending);
    expect(pending.errorMessage, isNull);
    expect(pending.text, 'kept text');
  });

  test(
    'unfinishedPages lists pending and processing pages, oldest first',
    () async {
      final a = await insertDocument(db, 'a', pages: 3);
      final b = await insertDocument(db, 'b', pages: 1);
      await repo.markPending([b[0]]);
      await repo.markPending([a[0], a[1], a[2]]);
      await repo.markProcessing(a[0]);
      await repo.saveResult(a[1], result('done'));
      await repo.markFailed(a[2], 'boom');

      expect(await repo.unfinishedPages(), [b[0], a[0]]);
    },
  );

  test(
    'pagesNeedingOcr lists missing, pending and failed pages in order',
    () async {
      final pages = await insertDocument(db, 'doc', pages: 4);
      await repo.saveResult(pages[0], result('done'));
      await repo.markFailed(pages[1], 'boom');
      await repo.markPending([pages[3]]);
      expect(await repo.pagesNeedingOcr('doc'), [pages[1], pages[2], pages[3]]);
    },
  );

  test('marks for missing pages are ignored', () async {
    await repo.markPending(['ghost']);
    await repo.markProcessing('ghost');
    await repo.markFailed('ghost', 'x');
    expect(await repo.getForPage('ghost'), isNull);
  });

  test('watchForDocument emits every page row of the document', () async {
    final pages = await insertDocument(db, 'doc', pages: 2);
    await insertDocument(db, 'other', pages: 1);
    await repo.markPending(['other-p0']);
    final stream = repo.watchForDocument('doc');
    expect(await stream.first, isEmpty);

    await repo.markPending(pages);
    await repo.saveResult(pages[0], result('hi'));
    final map = await stream.first;
    expect(map.keys, unorderedEquals(pages));
    expect(map[pages[0]]!.status, OcrStatus.done);
    expect(map[pages[1]]!.status, OcrStatus.pending);
  });

  test('deleting a page removes its OCR row', () async {
    final pages = await insertDocument(db, 'doc', pages: 2);
    await repo.saveResult(pages[0], result('gone soon'));
    await (db.delete(db.pages)..where((p) => p.id.equals(pages[0]))).go();
    expect(await repo.getForPage(pages[0]), isNull);
    expect(await repo.unfinishedPages(), isEmpty);
  });

  test('malformed stored lines decode to no lines', () {
    expect(DriftOcrRepository.decodeLines('{oops'), isEmpty);
    expect(DriftOcrRepository.decodeLines(null), isEmpty);
    final json = DriftOcrRepository.encodeLines([
      const OcrLine('a', OcrBox(0, 0, 1, 1)),
      const OcrLine('b'),
    ]);
    expect(json, '[{"t":"a","b":[0.0,0.0,1.0,1.0]},{"t":"b"}]');
    expect(DriftOcrRepository.decodeLines(json), [
      const OcrLine('a', OcrBox(0, 0, 1, 1)),
      const OcrLine('b'),
    ]);
  });
}
