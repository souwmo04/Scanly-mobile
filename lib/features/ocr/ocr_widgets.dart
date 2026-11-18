import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_spacing.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/ocr_result.dart';
import '../../domain/entities/scan_page.dart';
import '../../shared/widgets/action_sheet.dart';
import 'ocr_queue.dart';

/// Asks which language to recognise. Resolves to `null` if dismissed.
Future<OcrLanguage?> pickOcrLanguage(
  BuildContext context, {
  String title = 'Recognize text',
}) {
  return showActionSheet<OcrLanguage>(
    context,
    title: title,
    actions: const [
      SheetAction(
        value: OcrLanguage.english,
        label: 'English',
        icon: Icons.translate_rounded,
      ),
      SheetAction(
        value: OcrLanguage.bangla,
        label: 'বাংলা (Bangla)',
        icon: Icons.translate_rounded,
      ),
      SheetAction(
        value: OcrLanguage.mixed,
        label: 'Bangla + English',
        icon: Icons.translate_rounded,
      ),
    ],
  );
}

/// One-line summary of a document's text recognition, with the action that
/// fits (stop, resume, retry or view). Shows nothing for documents that
/// were never processed.
class DocumentOcrStatus extends ConsumerWidget {
  const DocumentOcrStatus({
    required this.documentId,
    required this.pages,
    required this.onViewText,
    super.key,
  });

  final String documentId;
  final List<ScanPage> pages;
  final VoidCallback onViewText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ocr = ref.watch(documentOcrProvider(documentId));
    final queue = ref.watch(ocrQueueProvider);
    return ocr.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const _StatusRow(
        icon: Icons.error_outline_rounded,
        label: 'Text status unavailable',
        isError: true,
      ),
      data: (rows) {
        final states = [
          for (final p in pages)
            if (rows[p.id] != null) (id: p.id, ocr: rows[p.id]!),
        ];
        if (states.isEmpty) return const SizedBox.shrink();
        final notifier = ref.read(ocrQueueProvider.notifier);

        final queued = states.where((s) => queue.isQueued(s.id)).length;
        final finished = states
            .where(
              (s) =>
                  s.ocr.status == OcrStatus.done ||
                  s.ocr.status == OcrStatus.failed,
            )
            .length;
        if (queued > 0) {
          return _StatusRow(
            icon: Icons.document_scanner_outlined,
            label: queue.cancelling
                ? 'Stopping…'
                : 'Recognizing text… $finished/${states.length}',
            progress: states.isEmpty ? null : finished / states.length,
            actionLabel: queue.cancelling ? null : 'Stop',
            onAction: notifier.cancel,
          );
        }

        final waiting = [
          for (final s in states)
            if (s.ocr.status == OcrStatus.pending ||
                s.ocr.status == OcrStatus.processing)
              s.id,
        ];
        if (waiting.isNotEmpty) {
          return _StatusRow(
            icon: Icons.pause_circle_outline_rounded,
            label: 'Text recognition paused',
            actionLabel: 'Resume',
            onAction: () => notifier.enqueuePages(waiting),
          );
        }

        final failed = states
            .where((s) => s.ocr.status == OcrStatus.failed)
            .length;
        if (failed > 0) {
          return _StatusRow(
            icon: Icons.error_outline_rounded,
            label: failed == states.length
                ? 'Text recognition failed'
                : 'Text recognition failed on '
                      '${failed == 1 ? '1 page' : '$failed pages'}',
            isError: true,
            actionLabel: 'Retry',
            onAction: () => notifier.retryFailed(documentId),
          );
        }
        return _StatusRow(
          icon: Icons.check_circle_outline_rounded,
          label: 'Text recognized',
          actionLabel: 'View text',
          onAction: onViewText,
        );
      },
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    this.progress,
    this.actionLabel,
    this.onAction,
    this.isError = false,
  });

  final IconData icon;
  final String label;
  final double? progress;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = isError ? scheme.error : scheme.onSurfaceVariant;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
          vertical: AppSpacing.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (actionLabel != null && onAction != null)
                  TextButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ),
            if (progress != null)
              // Determinate on purpose: no endless animation.
              LinearProgressIndicator(
                value: progress,
                borderRadius: AppRadius.smAll,
              ),
          ],
        ),
      ),
    );
  }
}
