import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_spacing.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/ocr_result.dart';
import '../../shared/providers/scanner_providers.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/state_views.dart';
import 'ocr_queue.dart';
import 'ocr_widgets.dart';

/// Recognised text of one page: selectable, copyable, and re-runnable in
/// another language.
class OcrTextScreen extends ConsumerWidget {
  const OcrTextScreen({
    required this.documentId,
    required this.pageId,
    super.key,
  });

  final String documentId;
  final String pageId;

  Future<void> _recognize(BuildContext context, WidgetRef ref) async {
    final language = await pickOcrLanguage(
      context,
      title: 'Recognize this page in',
    );
    if (language == null) return;
    await ref.read(ocrQueueProvider.notifier).enqueuePages([
      pageId,
    ], language: language);
  }

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) showMessage(context, 'Text copied');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ocr = ref.watch(pageOcrProvider(pageId));
    final pages = ref.watch(pagesProvider(documentId)).value;
    final index = pages?.indexWhere((p) => p.id == pageId) ?? -1;
    final queued = ref.watch(
      ocrQueueProvider.select((s) => s.isQueued(pageId)),
    );
    final value = ocr.value;
    final text = value?.status == OcrStatus.done ? value!.text : '';
    final busy =
        queued ||
        value?.status == OcrStatus.processing ||
        value?.status == OcrStatus.pending;

    return Scaffold(
      appBar: AppBar(
        title: Text(index < 0 ? 'Page text' : 'Page ${index + 1} text'),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            icon: const Icon(Icons.copy_rounded),
            onPressed: text.trim().isEmpty ? null : () => _copy(context, text),
          ),
          IconButton(
            tooltip: 'Recognize again',
            icon: const Icon(Icons.translate_rounded),
            onPressed: busy ? null : () => _recognize(context, ref),
          ),
        ],
      ),
      body: AsyncValueView<PageOcr?>(
        value: ocr,
        onRetry: () => ref.invalidate(pageOcrProvider(pageId)),
        data: (result) => _body(context, ref, result, queued: queued),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    PageOcr? result, {
    required bool queued,
  }) {
    void recognize() => unawaited(_recognize(context, ref));
    void resume() =>
        unawaited(ref.read(ocrQueueProvider.notifier).enqueuePages([pageId]));

    if (result == null) {
      return EmptyState(
        icon: Icons.text_snippet_outlined,
        title: 'Text not recognized yet',
        message: 'Recognize the text on this page to read, copy or search it.',
        actionLabel: 'Recognize text',
        onAction: recognize,
      );
    }
    switch (result.status) {
      case OcrStatus.processing when queued:
        return const LoadingState(message: 'Recognizing text…');
      case OcrStatus.pending when queued:
        return const LoadingState(message: 'Waiting to recognize text…');
      case OcrStatus.pending || OcrStatus.processing:
        return EmptyState(
          icon: Icons.pause_circle_outline_rounded,
          title: 'Text recognition paused',
          message: 'Recognition of this page was stopped before it finished.',
          actionLabel: 'Recognize now',
          onAction: resume,
        );
      case OcrStatus.failed:
        return EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Text recognition failed',
          message: result.errorMessage ?? 'The text could not be recognized.',
          actionLabel: 'Try again',
          onAction: recognize,
        );
      case OcrStatus.done:
        if (result.text.trim().isEmpty) {
          return EmptyState(
            icon: Icons.text_snippet_outlined,
            title: 'No text found on this page',
            message: 'Try another language if the page has text.',
            actionLabel: 'Try another language',
            onAction: recognize,
          );
        }
        return _TextView(result: result);
    }
  }
}

class _TextView extends StatelessWidget {
  const _TextView({required this.result});

  final PageOcr result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final language = _languageOf(result.languageCode);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.lg,
          AppSpacing.screenGutter,
          AppSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (language != null) ...[
              Text(
                'Recognized as ${ocrLanguageLabel(language)}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            SelectableText(
              result.text,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  static OcrLanguage? _languageOf(String? code) {
    for (final language in OcrLanguage.values) {
      if (languageCodeOf(language) == code) return language;
    }
    return null;
  }
}
