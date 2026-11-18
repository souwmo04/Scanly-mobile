import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/routing/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/scan_document.dart';
import '../../domain/entities/scan_page.dart';
import '../../shared/providers/core_providers.dart';
import '../../shared/providers/library_providers.dart';
import '../../shared/widgets/state_views.dart';
import '../library/document_actions.dart';
import '../ocr/ocr_queue.dart';
import '../ocr/ocr_widgets.dart';
import 'pdf_actions.dart';

/// Shows a document's pages with swipe navigation and pinch-to-zoom, and
/// links to the PDF viewer, sharing, printing and splitting.
class DocumentScreen extends ConsumerWidget {
  const DocumentScreen({required this.documentId, this.initialPage, super.key});

  final String documentId;

  /// One-based page to open at (from search results).
  final int? initialPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(documentDetailProvider(documentId));
    return detail.when(
      loading: () => Scaffold(appBar: AppBar(), body: const LoadingState()),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(
          error: error,
          onRetry: () => ref.invalidate(documentDetailProvider(documentId)),
        ),
      ),
      data: (value) {
        if (value == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.description_outlined,
              title: 'Document not found',
              message: 'It may have been deleted.',
            ),
          );
        }
        return _DocumentView(
          document: value.document,
          pages: value.pages,
          initialIndex: ((initialPage ?? 1) - 1).clamp(
            0,
            value.pages.isEmpty ? 0 : value.pages.length - 1,
          ),
        );
      },
    );
  }
}

class _DocumentView extends ConsumerStatefulWidget {
  const _DocumentView({
    required this.document,
    required this.pages,
    required this.initialIndex,
  });

  final ScanDocument document;
  final List<ScanPage> pages;
  final int initialIndex;

  @override
  ConsumerState<_DocumentView> createState() => _DocumentViewState();
}

class _DocumentViewState extends ConsumerState<_DocumentView> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _rename() async {
    final changed = await renameDocument(context, ref, widget.document);
    if (changed) ref.invalidate(documentDetailProvider(widget.document.id));
  }

  Future<void> _toggleFavorite() async {
    await ref
        .read(documentRepositoryProvider)
        .setFavorite(
          widget.document.id,
          isFavorite: !widget.document.isFavorite,
        );
    ref.invalidate(documentDetailProvider(widget.document.id));
  }

  Future<void> _delete() async {
    final deleted = await deleteDocuments(context, ref, [widget.document.id]);
    if (deleted && mounted) context.pop();
  }

  /// Opens [location] and reloads the document when the user comes back.
  Future<void> _openAndRefresh(String location) async {
    await context.push<Object?>(location);
    if (mounted) ref.invalidate(documentDetailProvider(widget.document.id));
  }

  void _openPdf() {
    _openAndRefresh(Routes.pdf(widget.document.id, page: _index + 1));
  }

  Future<void> _sharePdf() => sharePdf(
    context,
    ref,
    documentId: widget.document.id,
    title: widget.document.title,
  );

  Future<void> _printPdf() => printDocumentPdf(
    context,
    ref,
    documentId: widget.document.id,
    title: widget.document.title,
  );

  Future<void> _split() async {
    final ids = await splitDocumentFlow(
      context,
      ref,
      documentId: widget.document.id,
      pages: widget.pages,
    );
    if (ids != null && mounted) {
      ref.invalidate(documentDetailProvider(widget.document.id));
    }
  }

  Future<void> _recognizeText() async {
    final language = await pickOcrLanguage(context);
    if (language == null || !mounted) return;
    await ref
        .read(ocrQueueProvider.notifier)
        .enqueueDocument(widget.document.id, language: language);
  }

  Future<void> _openText() async {
    if (widget.pages.isEmpty) return;
    await context.push<Object?>(
      Routes.pageText(widget.document.id, widget.pages[_index].id),
    );
  }

  Future<void> _searchText() async {
    final index = await context.push<int>(
      Routes.documentSearch(widget.document.id),
    );
    if (index == null || !mounted || !_controller.hasClients) return;
    if (index < 0 || index >= widget.pages.length) return;
    _controller.jumpToPage(index);
  }

  void _editCurrentPage() {
    if (widget.pages.isEmpty) return;
    _openAndRefresh(
      Routes.editPage(widget.document.id, widget.pages[_index].id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doc = widget.document;
    final pages = widget.pages;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              '${pluralPages(doc.pageCount)} · ${formatBytes(doc.fileSize)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Search text',
            icon: const Icon(Icons.search_rounded),
            onPressed: pages.isEmpty ? null : _searchText,
          ),
          IconButton(
            tooltip: 'Edit page',
            icon: const Icon(Icons.tune_rounded),
            onPressed: pages.isEmpty ? null : _editCurrentPage,
          ),
          IconButton(
            tooltip: 'Pages',
            icon: const Icon(Icons.grid_view_rounded),
            onPressed: () => _openAndRefresh(Routes.pages(doc.id)),
          ),
          IconButton(
            tooltip: doc.isFavorite
                ? 'Remove from favorites'
                : 'Add to favorites',
            icon: Icon(
              doc.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
            ),
            onPressed: _toggleFavorite,
          ),
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (value) => switch (value) {
              'share' => _sharePdf(),
              'print' => _printPdf(),
              'split' => _split(),
              'ocr' => _recognizeText(),
              'text' => _openText(),
              'rename' => _rename(),
              'delete' => _delete(),
              _ => null,
            },
            itemBuilder: (context) => [
              if (pages.isNotEmpty) ...const [
                PopupMenuItem(value: 'share', child: Text('Share PDF')),
                PopupMenuItem(value: 'print', child: Text('Print')),
                PopupMenuItem(value: 'ocr', child: Text('Recognize text')),
                PopupMenuItem(value: 'text', child: Text('Page text')),
              ],
              if (pages.length > 1)
                const PopupMenuItem(
                  value: 'split',
                  child: Text('Split document'),
                ),
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      floatingActionButton: pages.isEmpty
          ? null
          : FloatingActionButton.extended(
              tooltip: 'Open PDF',
              onPressed: _openPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('PDF'),
            ),
      body: pages.isEmpty
          ? const EmptyState(
              icon: Icons.insert_drive_file_outlined,
              title: 'No pages',
              message: 'This document has no pages.',
            )
          : Column(
              children: [
                // At the top so the floating PDF button never covers its
                // action.
                DocumentOcrStatus(
                  documentId: doc.id,
                  pages: pages,
                  onViewText: () => unawaited(_openText()),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: pages.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => _PageImage(page: pages[i]),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    child: Text(
                      'Page ${_index + 1} of ${pages.length}',
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _PageImage extends StatelessWidget {
  const _PageImage({required this.page});

  final ScanPage page;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    // Decode at roughly screen resolution (x2 for zoom headroom) instead of
    // the full camera resolution, to keep memory use low.
    final decodeWidth = (media.size.width * media.devicePixelRatio * 2).round();

    return InteractiveViewer(
      maxScale: 5,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: RotatedBox(
              quarterTurns: page.rotation ~/ 90,
              child: Image.file(
                File(page.displayPath),
                cacheWidth: decodeWidth,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox(
                  width: 240,
                  height: 320,
                  child: EmptyState(
                    icon: Icons.broken_image_outlined,
                    title: 'Image missing',
                    message: 'This page file could not be loaded.',
                    compact: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
