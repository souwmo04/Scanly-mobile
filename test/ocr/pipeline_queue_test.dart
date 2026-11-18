import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanly/core/services/storage_service.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/data/repositories/drift_search_repository.dart';
import 'package:scanly/domain/entities/app_settings.dart';
import 'package:scanly/domain/entities/ocr_result.dart';
import 'package:scanly/domain/repositories/ocr_repository.dart';
import 'package:scanly/features/ocr/ocr_queue.dart';
import 'package:scanly/features/settings/settings_controller.dart';
import 'package:scanly/shared/providers/core_providers.dart';
import 'package:scanly/shared/providers/ocr_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pipeline_fakes.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late FakeOcrEngine engine;
  late ProviderContainer container;
  late List<OcrQueueState> states;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    engine = FakeOcrEngine();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        storageServiceProvider.overrideWithValue(
          StorageService(Directory.systemTemp),
        ),
        appDatabaseProvider.overrideWithValue(db),
        ocrEngineProvider.overrideWithValue(engine),
      ],
    );
    states = [];
    container.listen(
      ocrQueueProvider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  OcrQueue queue() => container.read(ocrQueueProvider.notifier);
  OcrRepository repo() => container.read(ocrRepositoryProvider);
  Future<OcrStatus?> statusOf(String pageId) async =>
      (await repo().getForPage(pageId))?.status;

  test('processes pages one at a time, in order, with progress', () async {
    final pages = await insertDocument(db, 'doc');
    await queue().enqueueDocument('doc');
    expect(container.read(ocrQueueProvider).isActive, isTrue);
    await queue().whenIdle;

    expect(engine.calls.map((c) => c.$1), pages.map(imagePathOf));
    expect(engine.maxConcurrent, 1);
    for (final id in pages) {
      expect(await statusOf(id), OcrStatus.done);
    }
    final finalState = container.read(ocrQueueProvider);
    expect(finalState.isActive, isFalse);
    expect(finalState.done, 3);
    expect(finalState.total, 3);

    // Progress went page by page.
    final current = states.map((s) => s.currentPageId).whereType<String>();
    expect(current.toSet().toList(), pages);
    expect(states.map((s) => s.done).toSet(), containsAll([0, 1, 2, 3]));

    // Text is searchable.
    final hits = await DriftSearchRepository(db).search('doc-p2');
    expect(hits.single.pageNumber, 3);
  });

  test('pages are processing while recognised', () async {
    final pages = await insertDocument(db, 'doc', pages: 2);
    engine.gate = Completer<void>();
    await queue().enqueuePages(pages);
    await engine.started.future;
    expect(await statusOf(pages[0]), OcrStatus.processing);
    expect(await statusOf(pages[1]), OcrStatus.pending);
    expect(container.read(ocrQueueProvider).currentPageId, pages[0]);
    engine.gate!.complete();
    await queue().whenIdle;
    expect(await statusOf(pages[1]), OcrStatus.done);
  });

  test('failures are recorded and failed pages can be retried', () async {
    final pages = await insertDocument(db, 'doc');
    engine.failures.add(imagePathOf(pages[1]));
    await queue().enqueueDocument('doc');
    await queue().whenIdle;

    final failed = await repo().getForPage(pages[1]);
    expect(failed!.status, OcrStatus.failed);
    expect(failed.errorMessage, 'The OCR model could not be loaded.');
    expect(await statusOf(pages[2]), OcrStatus.done);
    final state = container.read(ocrQueueProvider);
    expect(state.failed, 1);
    expect(state.lastError, 'The OCR model could not be loaded.');

    engine.calls.clear();
    await queue().retryFailed('doc');
    await queue().whenIdle;
    expect(engine.calls.map((c) => c.$1), [imagePathOf(pages[1])]);
    expect(await statusOf(pages[1]), OcrStatus.done);
  });

  test(
    'cancel stops after the current page and leaves the rest pending',
    () async {
      final pages = await insertDocument(db, 'doc');
      engine.gate = Completer<void>();
      await queue().enqueueDocument('doc');
      await engine.started.future;

      queue().cancel();
      expect(container.read(ocrQueueProvider).cancelling, isTrue);
      engine.gate!.complete();
      await queue().whenIdle;

      expect(engine.calls, hasLength(1));
      expect(await statusOf(pages[0]), OcrStatus.done);
      expect(await statusOf(pages[1]), OcrStatus.pending);
      expect(await statusOf(pages[2]), OcrStatus.pending);
      expect(container.read(ocrQueueProvider).isActive, isFalse);

      // Resume picks up where it stopped.
      engine.gate = null;
      await queue().resumeUnfinished();
      await queue().whenIdle;
      expect(engine.calls.map((c) => c.$1), pages.map(imagePathOf));
      expect(await statusOf(pages[2]), OcrStatus.done);
    },
  );

  test('resumeUnfinished continues pending and interrupted pages', () async {
    final pages = await insertDocument(db, 'doc');
    await repo().markPending(pages);
    await repo().markProcessing(pages[0]); // App closed mid-run.
    await repo().saveResult(
      pages[2],
      const OcrResult(
        text: 'already',
        lines: [],
        languageCode: 'eng',
        engine: OcrEngineId.mlKit,
      ),
    );

    await queue().resumeUnfinished();
    await queue().whenIdle;
    expect(
      engine.calls.map((c) => c.$1),
      unorderedEquals([imagePathOf(pages[0]), imagePathOf(pages[1])]),
    );
    for (final id in pages) {
      expect(await statusOf(id), OcrStatus.done);
    }
  });

  test('a page deleted mid-run is skipped without failing the run', () async {
    final pages = await insertDocument(db, 'doc');
    engine.gate = Completer<void>();
    await queue().enqueueDocument('doc');
    await engine.started.future;

    // Delete the page being recognised and one still waiting.
    await (db.delete(
      db.pages,
    )..where((p) => p.id.isIn([pages[0], pages[1]]))).go();
    engine.gate!.complete();
    await queue().whenIdle;

    expect(engine.calls.map((c) => c.$1), [
      imagePathOf(pages[0]),
      imagePathOf(pages[2]),
    ]);
    expect(await statusOf(pages[0]), isNull);
    expect(await statusOf(pages[2]), OcrStatus.done);
    expect(container.read(ocrQueueProvider).failed, 0);
  });

  test('uses the language from settings unless one is given', () async {
    final pages = await insertDocument(db, 'doc', pages: 1);
    await container
        .read(settingsControllerProvider.notifier)
        .update((s) => s.copyWith(ocrLanguage: OcrLanguage.bangla));
    await queue().enqueuePages(pages);
    await queue().whenIdle;
    expect(engine.calls.single.$2, OcrLanguage.bangla);
    expect((await repo().getForPage(pages[0]))!.languageCode, 'ben');

    await queue().enqueuePages(pages, language: OcrLanguage.english);
    await queue().whenIdle;
    expect(engine.calls.last.$2, OcrLanguage.english);
    expect((await repo().getForPage(pages[0]))!.languageCode, 'eng');
  });

  test(
    're-queueing a waiting page keeps one job with the new language',
    () async {
      final pages = await insertDocument(db, 'doc', pages: 2);
      engine.gate = Completer<void>();
      await queue().enqueuePages(pages);
      await engine.started.future;
      await queue().enqueuePages([pages[1]], language: OcrLanguage.english);
      expect(container.read(ocrQueueProvider).total, 2);
      engine.gate!.complete();
      await queue().whenIdle;
      expect(engine.calls, hasLength(2));
      expect(engine.calls.last.$2, OcrLanguage.english);
    },
  );

  test('pageImageChanged re-runs recognised pages in their language', () async {
    final pages = await insertDocument(db, 'doc', pages: 2);
    await queue().enqueuePages([pages[0]], language: OcrLanguage.english);
    await queue().whenIdle;
    engine.calls.clear();

    await queue().pageImageChanged(pages[0], autoOcr: false);
    await queue().whenIdle;
    expect(engine.calls.single, (imagePathOf(pages[0]), OcrLanguage.english));

    // Never recognised and auto OCR off: nothing to do.
    await queue().pageImageChanged(pages[1], autoOcr: false);
    await queue().whenIdle;
    expect(engine.calls, hasLength(1));

    await queue().pageImageChanged(pages[1], autoOcr: true);
    await queue().whenIdle;
    expect(engine.calls, hasLength(2));
  });
}
