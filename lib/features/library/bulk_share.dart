import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/providers/core_providers.dart';
import '../../shared/providers/pdf_providers.dart';
import '../../shared/providers/share_providers.dart';
import '../../shared/widgets/dialogs.dart';

/// A document whose PDF could not be created, with the reason.
typedef ShareFailure = ({String title, String reason});

/// Creates the PDF of every document in [ids], one after another, with a
/// cancellable progress dialog, then opens a single share sheet with all of
/// them. [origin] anchors the share popover on tablets.
///
/// Documents whose PDF fails are listed afterwards with the reason; nothing
/// is shared when all of them fail. Returns `true` if the share sheet was
/// opened.
Future<bool> shareDocumentsFlow(
  BuildContext context,
  WidgetRef ref,
  List<String> ids, {
  Rect? origin,
}) async {
  if (ids.isEmpty) return false;
  final documents = ref.read(documentRepositoryProvider);
  final pdfService = ref.read(documentPdfServiceProvider);
  final shareService = ref.read(shareServiceProvider);

  final progress = ValueNotifier<_ShareProgress>(
    _ShareProgress(index: 0, total: ids.length, title: ''),
  );
  var cancelled = false;
  var dialogOpen = true;
  final navigator = Navigator.of(context, rootNavigator: true);
  final dialog = showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: ValueListenableBuilder<_ShareProgress>(
        valueListenable: progress,
        builder: (context, value, _) => _ShareProgressDialog(
          progress: value,
          onCancel: () {
            cancelled = true;
            dialogOpen = false;
            Navigator.of(dialogContext).pop();
          },
        ),
      ),
    ),
  );
  unawaited(dialog.whenComplete(progress.dispose));

  final paths = <String>[];
  final failures = <ShareFailure>[];
  final titles = <String>[];
  try {
    for (var i = 0; i < ids.length && !cancelled; i++) {
      var title = 'Document ${i + 1}';
      try {
        final document = await documents.getDocument(ids[i]);
        if (document == null) {
          throw const NotFoundException('The document no longer exists.');
        }
        title = document.title;
        if (cancelled) break;
        progress.value = _ShareProgress(
          index: i,
          total: ids.length,
          title: title,
        );
        final path = await pdfService.ensurePdf(
          ids[i],
          onProgress: (done, total) {
            if (cancelled || total <= 0) return;
            progress.value = _ShareProgress(
              index: i,
              total: ids.length,
              title: title,
              pageFraction: done / total,
            );
          },
        );
        paths.add(path);
        titles.add(title);
      } on Object catch (error) {
        failures.add((title: title, reason: _reason(error)));
      }
    }
  } finally {
    if (dialogOpen) {
      dialogOpen = false;
      navigator.pop();
    }
  }

  if (!context.mounted) return false;
  if (cancelled) {
    showMessage(context, 'Sharing cancelled');
    return false;
  }
  if (paths.isEmpty) {
    await _showFailures(context, failures, sharedCount: 0);
    return false;
  }

  try {
    await shareService.shareFiles(
      paths,
      subject: paths.length == 1 ? titles.single : '${paths.length} documents',
      origin: origin,
    );
  } on Object {
    if (context.mounted) showMessage(context, 'Could not open the share sheet');
    return false;
  }
  if (failures.isNotEmpty && context.mounted) {
    await _showFailures(context, failures, sharedCount: paths.length);
  }
  return true;
}

/// Global rectangle of the widget behind [context], for share popovers.
Rect? originOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

Future<void> _showFailures(
  BuildContext context,
  List<ShareFailure> failures, {
  required int sharedCount,
}) {
  final total = sharedCount + failures.length;
  final String title;
  if (sharedCount == 0) {
    title = failures.length == 1
        ? 'Could not create the PDF'
        : 'Could not create the PDFs';
  } else {
    title = 'Shared $sharedCount of $total documents';
  }
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sharedCount == 0
                    ? 'Nothing was shared.'
                    : 'These documents were left out:',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              for (final failure in failures)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: failure.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: ': ${failure.reason}'),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}

class _ShareProgress {
  const _ShareProgress({
    required this.index,
    required this.total,
    required this.title,
    this.pageFraction = 0,
  });

  /// Zero-based index of the document being prepared.
  final int index;
  final int total;
  final String title;

  /// Progress within the current document, 0–1.
  final double pageFraction;

  double get overall => total <= 0 ? 0 : (index + pageFraction) / total;
}

class _ShareProgressDialog extends StatelessWidget {
  const _ShareProgressDialog({required this.progress, required this.onCancel});

  final _ShareProgress progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(value: progress.overall),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Preparing PDF ${progress.index + 1} of ${progress.total}…',
            textAlign: TextAlign.center,
          ),
          if (progress.title.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              progress.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      actions: [TextButton(onPressed: onCancel, child: const Text('Cancel'))],
    );
  }
}

String _reason(Object error) =>
    error is AppException ? error.message : 'Please try again.';
