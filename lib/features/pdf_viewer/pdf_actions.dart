import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../domain/entities/scan_page.dart';
import '../../domain/services/pdf_service.dart';
import '../../shared/providers/core_providers.dart';
import '../../shared/providers/pdf_providers.dart';
import '../../shared/providers/share_providers.dart';
import '../../shared/widgets/dialogs.dart';
import 'pdf_labels.dart';
import 'split_document_sheet.dart';

/// Progress of a running task: `(done, total)`, or `null` before it starts.
typedef TaskProgress = ({int done, int total});

/// Shows a modal progress dialog while [task] runs. [label] turns the latest
/// progress into the message shown. Errors are rethrown.
Future<T> runWithProgressDialog<T>(
  BuildContext context, {
  required Future<T> Function(void Function(int done, int total) report) task,
  required String Function(TaskProgress? progress) label,
}) async {
  final progress = ValueNotifier<TaskProgress?>(null);
  final navigator = Navigator.of(context, rootNavigator: true);
  final dialog = showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: ValueListenableBuilder<TaskProgress?>(
        valueListenable: progress,
        builder: (context, value, _) => _ProgressDialog(
          message: label(value),
          value: value == null || value.total <= 0
              ? null
              : value.done / value.total,
        ),
      ),
    ),
  );
  unawaited(dialog.whenComplete(progress.dispose));
  try {
    return await task((done, total) {
      progress.value = (done: done, total: total);
    });
  } finally {
    navigator.pop();
  }
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.message, this.value});

  final String message;
  final double? value;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(value: value),
          const SizedBox(height: AppSpacing.lg),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// Creates (or reuses) the document's PDF with a progress dialog. Returns
/// its path, or `null` after showing the error.
Future<String?> createPdfWithProgress(
  BuildContext context,
  WidgetRef ref,
  String documentId, {
  PdfExportOptions? options,
  bool force = false,
}) async {
  final service = ref.read(documentPdfServiceProvider);
  try {
    return await runWithProgressDialog(
      context,
      label: (p) =>
          p == null ? 'Creating PDF…' : pdfProgressLabel(p.done, p.total),
      task: (report) => service.ensurePdf(
        documentId,
        options: options,
        force: force,
        onProgress: report,
      ),
    );
  } on Object catch (error) {
    if (context.mounted) {
      showMessage(context, 'Could not create the PDF. ${_reason(error)}');
    }
    return null;
  }
}

/// Creates the PDF if needed and opens the share sheet.
Future<void> sharePdf(
  BuildContext context,
  WidgetRef ref, {
  required String documentId,
  required String title,
}) async {
  final shareService = ref.read(shareServiceProvider);
  final path = await createPdfWithProgress(context, ref, documentId);
  if (path == null || !context.mounted) return;
  await shareFileSafely(context, shareService, path, title);
}

/// Creates the PDF if needed and opens the print dialog.
Future<void> printDocumentPdf(
  BuildContext context,
  WidgetRef ref, {
  required String documentId,
  required String title,
}) async {
  final shareService = ref.read(shareServiceProvider);
  final path = await createPdfWithProgress(context, ref, documentId);
  if (path == null || !context.mounted) return;
  await printFileSafely(context, shareService, path, title);
}

/// Opens the share sheet for [path], reporting failures as a snackbar.
Future<void> shareFileSafely(
  BuildContext context,
  ShareService service,
  String path,
  String title,
) async {
  try {
    // Anchor for the iPad share popover: the screen that started the share.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    await service.shareFiles([path], subject: title, origin: origin);
  } on Object {
    if (context.mounted) showMessage(context, 'Could not open the share sheet');
  }
}

/// Opens the print dialog for [path], reporting failures as a snackbar.
Future<void> printFileSafely(
  BuildContext context,
  ShareService service,
  String path,
  String title,
) async {
  try {
    await service.printPdf(path, jobName: title);
  } on Object {
    if (context.mounted) showMessage(context, 'Could not open printing');
  }
}

/// Lets the user choose split points, then splits the document. Returns the
/// new document ids, or `null` if cancelled or failed.
Future<List<String>?> splitDocumentFlow(
  BuildContext context,
  WidgetRef ref, {
  required String documentId,
  required List<ScanPage> pages,
}) async {
  final service = ref.read(documentPdfServiceProvider);
  final partStarts = await showSplitDocumentSheet(context, pages: pages);
  if (partStarts == null || partStarts.isEmpty || !context.mounted) {
    return null;
  }
  try {
    final ids = await runWithProgressDialog(
      context,
      label: (_) => 'Splitting document…',
      task: (_) => service.splitDocument(documentId, partStarts),
    );
    if (context.mounted) {
      showMessage(context, 'Split into ${ids.length} documents');
    }
    return ids;
  } on Object catch (error) {
    if (context.mounted) {
      showMessage(context, 'Could not split the document. ${_reason(error)}');
    }
    return null;
  }
}

/// Asks for a title and merges [ids], in that order, into a new document.
/// [onMerged] runs before navigation (e.g. to clear a selection). Opens the
/// new document and returns `true` on success.
Future<bool> mergeDocumentsFlow(
  BuildContext context,
  WidgetRef ref,
  List<String> ids, {
  VoidCallback? onMerged,
}) async {
  if (ids.length < 2) return false;
  final service = ref.read(documentPdfServiceProvider);
  final repo = ref.read(documentRepositoryProvider);
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.of(context);

  final first = await repo.getDocument(ids.first);
  if (!context.mounted) return false;
  final title = await showTextInputDialog(
    context,
    title: 'Merge ${ids.length} documents',
    confirmLabel: 'Merge',
    initialValue: first == null ? 'Merged document' : '${first.title} (merged)',
    hintText: 'Title of the merged document',
  );
  if (title == null || !context.mounted) return false;

  final String newId;
  try {
    newId = await runWithProgressDialog(
      context,
      label: (_) => 'Merging documents…',
      task: (_) => service.mergeDocuments(ids, title: title),
    );
  } on Object catch (error) {
    if (context.mounted) {
      showMessage(context, 'Could not merge documents. ${_reason(error)}');
    }
    return false;
  }
  onMerged?.call();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text('Merged ${ids.length} documents into "$title"')),
    );
  unawaited(router.push(Routes.document(newId)));
  return true;
}

String _reason(Object error) =>
    error is AppException ? error.message : 'Please try again.';
