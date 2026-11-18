import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/ocr_result.dart';
import '../../shared/providers/core_providers.dart';
import '../../shared/providers/ocr_providers.dart';
import '../settings/settings_controller.dart';

/// Progress of the background OCR queue.
@immutable
class OcrQueueState {
  const OcrQueueState({
    this.currentPageId,
    this.queuedPageIds = const {},
    this.done = 0,
    this.total = 0,
    this.failed = 0,
    this.lastError,
    this.cancelling = false,
  });

  /// Page being recognised right now.
  final String? currentPageId;

  /// Pages waiting or in progress in this run (includes [currentPageId]).
  final Set<String> queuedPageIds;

  /// Pages finished in this run (successfully or not).
  final int done;

  /// Pages in this run: finished, current and waiting.
  final int total;

  /// Pages that failed in this run.
  final int failed;

  /// Message of the most recent failure.
  final String? lastError;

  /// A cancel was requested; the current page is still finishing.
  final bool cancelling;

  bool get isActive => queuedPageIds.isNotEmpty;

  bool isQueued(String pageId) => queuedPageIds.contains(pageId);
}

class _Job {
  _Job(this.pageId, this.language);

  final String pageId;
  OcrLanguage? language;
}

/// Recognises page text in the background, strictly one page at a time.
///
/// Every queued page is marked pending in the database first, so work that
/// is interrupted (app closed, cancelled) can be resumed later with
/// [resumeUnfinished]. Pages are marked processing while recognised and
/// done or failed afterwards. Pages deleted mid-run are skipped.
class OcrQueue extends Notifier<OcrQueueState> {
  final _jobs = ListQueue<_Job>();
  String? _current;
  bool _running = false;
  bool _cancelRequested = false;
  int _done = 0;
  int _failed = 0;
  String? _lastError;

  /// Completes when the current run finishes (for tests and callers that
  /// want to wait).
  Completer<void>? _idle;

  @override
  OcrQueueState build() => const OcrQueueState();

  /// Future that completes once the queue has nothing left to do.
  Future<void> get whenIdle => _idle?.future ?? Future.value();

  /// Queues every page of [documentId] in page order.
  Future<void> enqueueDocument(String documentId, {OcrLanguage? language}) {
    return _guard(() async {
      final pages = await ref
          .read(documentRepositoryProvider)
          .getPages(documentId);
      if (!ref.mounted) return;
      await _enqueue([for (final p in pages) p.id], language);
    });
  }

  /// Queues [pageIds] in the given order. A page that is already waiting
  /// keeps its place but takes the new [language]; a page being recognised
  /// right now runs again afterwards (its image may have changed).
  Future<void> enqueuePages(List<String> pageIds, {OcrLanguage? language}) =>
      _guard(() => _enqueue(pageIds, language));

  /// Recognises a page again after its image changed (edited), when it had
  /// text before or [autoOcr] is on. Uses the language it was recognised in.
  Future<void> pageImageChanged(String pageId, {required bool autoOcr}) {
    return _guard(() async {
      final previous = await ref.read(ocrRepositoryProvider).getForPage(pageId);
      if (!ref.mounted || (previous == null && !autoOcr)) return;
      OcrLanguage? language;
      for (final l in OcrLanguage.values) {
        if (languageCodeOf(l) == previous?.languageCode) language = l;
      }
      await _enqueue([pageId], language);
    });
  }

  /// Queues the pages of [documentId] whose recognition failed.
  Future<void> retryFailed(String documentId, {OcrLanguage? language}) {
    return _guard(() async {
      final repo = ref.read(ocrRepositoryProvider);
      final pages = await ref
          .read(documentRepositoryProvider)
          .getPages(documentId);
      final failed = <String>[];
      for (final p in pages) {
        if ((await repo.getForPage(p.id))?.status == OcrStatus.failed) {
          failed.add(p.id);
        }
      }
      if (!ref.mounted) return;
      await _enqueue(failed, language);
    });
  }

  /// Resumes pages left pending or processing (e.g. the app was closed
  /// mid-run). Safe to call more than once.
  Future<void> resumeUnfinished() {
    return _guard(() async {
      final ids = await ref.read(ocrRepositoryProvider).unfinishedPages();
      if (!ref.mounted) return;
      await _enqueue(ids, null, onlyNew: true);
    });
  }

  /// Stops after the current page. Waiting pages stay pending so they can
  /// be resumed later.
  void cancel() {
    if (!_running || _cancelRequested) return;
    _cancelRequested = true;
    _publish();
  }

  Future<void> _enqueue(
    List<String> pageIds,
    OcrLanguage? language, {
    bool onlyNew = false,
  }) async {
    final ids = <String>[];
    for (final id in pageIds) {
      if (ids.contains(id)) continue;
      final waiting = _jobs.where((j) => j.pageId == id).firstOrNull;
      if (waiting != null) {
        if (!onlyNew) waiting.language = language;
        continue;
      }
      if (onlyNew && id == _current) continue;
      ids.add(id);
    }
    if (ids.isEmpty) return;
    await ref.read(ocrRepositoryProvider).markPending(ids);
    if (!ref.mounted) return;
    if (!_running) {
      _done = 0;
      _failed = 0;
      _lastError = null;
    }
    for (final id in ids) {
      _jobs.add(_Job(id, language));
    }
    _publish();
    if (!_running) unawaited(_run());
  }

  Future<void> _run() async {
    _running = true;
    _cancelRequested = false;
    final idle = _idle = Completer<void>();
    try {
      while (ref.mounted && _jobs.isNotEmpty && !_cancelRequested) {
        final job = _jobs.removeFirst();
        _current = job.pageId;
        _publish();
        await _process(job);
        if (!ref.mounted) return;
        _current = null;
        _done++;
        _publish();
      }
      if (ref.mounted && _cancelRequested && _jobs.isNotEmpty) {
        final remaining = [for (final j in _jobs) j.pageId];
        _jobs.clear();
        await _guard(
          () => ref.read(ocrRepositoryProvider).markPending(remaining),
        );
      }
    } finally {
      _running = false;
      _current = null;
      if (ref.mounted) {
        _cancelRequested = false;
        _publish();
        // Pages queued while the cancel was finishing start a new run.
        if (_jobs.isNotEmpty) unawaited(_run());
      }
      idle.complete();
    }
  }

  Future<void> _process(_Job job) async {
    final repo = ref.read(ocrRepositoryProvider);
    try {
      final page = await ref
          .read(documentRepositoryProvider)
          .getPage(job.pageId);
      if (page == null || !ref.mounted) return; // Deleted meanwhile.
      await repo.markProcessing(job.pageId);
      if (!ref.mounted) return;
      final language =
          job.language ?? ref.read(settingsControllerProvider).ocrLanguage;
      final OcrResult result;
      try {
        result = await ref
            .read(ocrEngineProvider)
            .recognize(page.displayPath, language);
      } on Object catch (error) {
        if (!ref.mounted) return;
        _failed++;
        _lastError = describeError(error);
        await repo.markFailed(job.pageId, _lastError!);
        return;
      }
      if (!ref.mounted) return;
      await repo.saveResult(job.pageId, result);
    } on NotFoundException {
      // The page was deleted while it was being recognised.
    } on Object catch (error) {
      debugPrint('OCR of page ${job.pageId} failed: $error');
      if (!ref.mounted) return;
      _failed++;
      _lastError = describeError(error);
      try {
        await repo.markFailed(job.pageId, _lastError!);
      } on Object {
        // Nothing more to do; the page stays pending and resumes later.
      }
    }
  }

  void _publish() {
    if (!ref.mounted) return;
    final queued = <String>{?_current, for (final j in _jobs) j.pageId};
    state = OcrQueueState(
      currentPageId: _current,
      queuedPageIds: queued,
      done: _done,
      total: _done + queued.length,
      failed: _failed,
      lastError: _lastError,
      cancelling: _cancelRequested,
    );
  }

  /// Background work must never throw into the UI.
  Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
    } on Object catch (error) {
      debugPrint('OCR queue error: $error');
      if (ref.mounted) {
        _lastError = describeError(error);
        _publish();
      }
    }
  }
}

/// The app-wide OCR queue and its progress.
final ocrQueueProvider = NotifierProvider<OcrQueue, OcrQueueState>(
  OcrQueue.new,
);

/// Stored OCR state of one page, updated live.
final pageOcrProvider = StreamProvider.autoDispose.family<PageOcr?, String>(
  (ref, pageId) => ref.watch(ocrRepositoryProvider).watchForPage(pageId),
);

/// Stored OCR state of every page of a document, keyed by page id.
final documentOcrProvider = StreamProvider.autoDispose
    .family<Map<String, PageOcr>, String>(
      (ref, documentId) =>
          ref.watch(ocrRepositoryProvider).watchForDocument(documentId),
    );

/// Short label of an OCR language, as shown in pickers.
String ocrLanguageLabel(OcrLanguage language) => switch (language) {
  OcrLanguage.english => 'English',
  OcrLanguage.bangla => 'বাংলা (Bangla)',
  OcrLanguage.mixed => 'Bangla + English',
};
