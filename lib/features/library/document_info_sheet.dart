import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/folder.dart';
import '../../domain/entities/ocr_result.dart';
import '../../domain/entities/scan_document.dart';
import '../../domain/entities/scan_page.dart';
import '../../shared/providers/library_providers.dart';
import '../../shared/providers/scanner_providers.dart';
import '../../shared/widgets/state_views.dart';
import '../ocr/ocr_queue.dart';
import 'library_use_cases.dart';

/// Shows details of a document: folder, pages, size, dates, text
/// recognition and where it is stored.
Future<void> showDocumentInfo(BuildContext context, String documentId) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => DocumentInfoSheet(documentId: documentId),
  );
}

class DocumentInfoSheet extends ConsumerWidget {
  const DocumentInfoSheet({required this.documentId, super.key});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(watchedDocumentProvider(documentId));
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: document.when(
          loading: () => const SizedBox(height: 240, child: LoadingState()),
          error: (error, _) => SizedBox(
            height: 320,
            child: ErrorState(
              error: error,
              onRetry: () =>
                  ref.invalidate(watchedDocumentProvider(documentId)),
            ),
          ),
          data: (doc) => doc == null
              ? const SizedBox(
                  height: 280,
                  child: EmptyState(
                    icon: Icons.description_outlined,
                    title: 'Document not found',
                    message: 'It may have been deleted.',
                    compact: true,
                  ),
                )
              : _InfoContent(document: doc),
        ),
      ),
    );
  }
}

class _InfoContent extends ConsumerWidget {
  const _InfoContent({required this.document});

  final ScanDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final folders = ref.watch(foldersProvider);
    final pages = ref.watch(pagesProvider(document.id));
    final ocr = ref.watch(documentOcrProvider(document.id));

    final folderLabel = document.folderId == null
        ? 'All files'
        : folders.when(
            loading: () => 'Loading…',
            error: (_, _) => 'Unavailable',
            data: (list) =>
                list
                    .where((Folder f) => f.id == document.folderId)
                    .firstOrNull
                    ?.name ??
                'All files',
          );

    final String textLabel;
    if (pages.hasError || ocr.hasError) {
      textLabel = 'Status unavailable';
    } else if (!pages.hasValue || !ocr.hasValue) {
      textLabel = 'Checking…';
    } else {
      textLabel = ocrSummary(pages.requireValue, ocr.requireValue);
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxl,
            0,
            AppSpacing.xxl,
            AppSpacing.sm,
          ),
          child: Semantics(
            header: true,
            child: Text(
              document.title,
              style: theme.textTheme.titleMedium,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        _InfoRow(
          icon: Icons.folder_outlined,
          label: 'Folder',
          value: folderLabel,
        ),
        _InfoRow(
          icon: Icons.description_outlined,
          label: 'Pages',
          value: pluralPages(document.pageCount),
        ),
        _InfoRow(
          icon: Icons.sd_storage_outlined,
          label: 'Size',
          value: formatBytes(document.fileSize),
        ),
        _InfoRow(
          icon: Icons.event_outlined,
          label: 'Created',
          value: formatInfoDate(document.createdAt),
        ),
        _InfoRow(
          icon: Icons.edit_calendar_outlined,
          label: 'Modified',
          value: formatInfoDate(document.updatedAt),
        ),
        _InfoRow(
          icon: Icons.text_snippet_outlined,
          label: 'Text recognition',
          value: textLabel,
        ),
        const _InfoRow(
          icon: Icons.smartphone_rounded,
          label: 'Stored',
          value: 'On this device',
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
      title: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      subtitle: Text(value, style: theme.textTheme.bodyLarge),
    );
  }
}

/// Full date and time, e.g. "Nov 19, 2026, 14:05".
String formatInfoDate(DateTime date) =>
    DateFormat.yMMMd().add_Hm().format(date);

/// One-line summary of the text recognition state of a document's pages.
String ocrSummary(List<ScanPage> pages, Map<String, PageOcr> ocr) {
  final total = pages.length;
  if (total == 0) return 'No pages';
  var done = 0;
  var running = 0;
  var failed = 0;
  for (final page in pages) {
    switch (ocr[page.id]?.status) {
      case OcrStatus.done:
        done++;
      case OcrStatus.pending || OcrStatus.processing:
        running++;
      case OcrStatus.failed:
        failed++;
      case null:
        break;
    }
  }
  if (running > 0) {
    return 'Recognizing text… $done of $total pages done';
  }
  if (done == 0 && failed == 0) return 'Not recognized yet';
  final buffer = StringBuffer(
    done == total
        ? (total == 1
              ? 'Text recognized on the page'
              : 'Text recognized on all $total pages')
        : 'Text recognized on $done of $total pages',
  );
  if (failed > 0) buffer.write(' · $failed failed');
  return buffer.toString();
}
