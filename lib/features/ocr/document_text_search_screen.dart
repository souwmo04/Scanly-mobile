import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_spacing.dart';
import '../../domain/entities/ocr_result.dart';
import '../../domain/entities/scan_page.dart';
import '../../shared/providers/scanner_providers.dart';
import '../../shared/widgets/state_views.dart';
import 'ocr_queue.dart';
import 'ocr_text_search.dart';
import 'ocr_widgets.dart';

/// Searches the recognised text of one document. Pops with the zero-based
/// index of the chosen page.
class DocumentTextSearchScreen extends ConsumerStatefulWidget {
  const DocumentTextSearchScreen({required this.documentId, super.key});

  final String documentId;

  @override
  ConsumerState<DocumentTextSearchScreen> createState() =>
      _DocumentTextSearchScreenState();
}

class _DocumentTextSearchScreenState
    extends ConsumerState<DocumentTextSearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _recognize() async {
    final language = await pickOcrLanguage(context);
    if (language == null) return;
    await ref
        .read(ocrQueueProvider.notifier)
        .enqueueDocument(widget.documentId, language: language);
  }

  @override
  Widget build(BuildContext context) {
    final pages = ref.watch(pagesProvider(widget.documentId));
    final ocr = ref.watch(documentOcrProvider(widget.documentId));
    final combined = switch ((pages, ocr)) {
      (AsyncData(value: final p), AsyncData(value: final o)) =>
        AsyncValue<(List<ScanPage>, Map<String, PageOcr>)>.data((p, o)),
      (AsyncError(:final error, :final stackTrace), _) ||
      (
        _,
        AsyncError(:final error, :final stackTrace),
      ) => AsyncValue<(List<ScanPage>, Map<String, PageOcr>)>.error(
        error,
        stackTrace,
      ),
      _ => const AsyncValue<(List<ScanPage>, Map<String, PageOcr>)>.loading(),
    };

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search in document',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(_controller.clear),
            ),
        ],
      ),
      body: AsyncValueView(
        value: combined,
        onRetry: () {
          ref
            ..invalidate(pagesProvider(widget.documentId))
            ..invalidate(documentOcrProvider(widget.documentId));
        },
        data: (data) => _results(data.$1, data.$2),
      ),
    );
  }

  Widget _results(List<ScanPage> pages, Map<String, PageOcr> ocr) {
    final hasText = pages.any((p) => (ocr[p.id]?.text ?? '').isNotEmpty);
    if (!hasText) {
      final working = pages.any(
        (p) =>
            ocr[p.id]?.status == OcrStatus.pending ||
            ocr[p.id]?.status == OcrStatus.processing,
      );
      return working
          ? const EmptyState(
              icon: Icons.document_scanner_outlined,
              title: 'Recognizing text…',
              message: 'You can search as soon as the text is ready.',
            )
          : EmptyState(
              icon: Icons.text_snippet_outlined,
              title: 'No recognized text',
              message: 'Recognize the text of this document to search it.',
              actionLabel: 'Recognize text',
              onAction: () => unawaited(_recognize()),
            );
    }
    final query = _controller.text.trim();
    if (query.isEmpty) {
      return const EmptyState(
        icon: Icons.search_rounded,
        title: 'Search this document',
        message: 'Find words in the recognized text of every page.',
      );
    }
    final matches = searchPageTexts(pages, ocr, query);
    if (matches.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matches',
        message: 'No page contains “$query”.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: matches.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _MatchTile(
        match: matches[i],
        onTap: () => context.pop(matches[i].pageIndex),
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.match, required this.onTap});

  final PageTextMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final s = match.snippet;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
      ),
      title: Text(
        match.count > 1
            ? 'Page ${match.pageNumber} · ${match.count} matches'
            : 'Page ${match.pageNumber}',
      ),
      subtitle: Text.rich(
        TextSpan(
          style: base,
          children: [
            TextSpan(text: s.substring(0, match.matchStart)),
            TextSpan(
              text: s.substring(match.matchStart, match.matchEnd),
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
                backgroundColor: scheme.primaryContainer,
              ),
            ),
            TextSpan(text: s.substring(match.matchEnd)),
          ],
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }
}
