import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/scan_document.dart';
import '../../domain/entities/scan_page.dart';
import '../../shared/providers/core_providers.dart';
import '../../shared/providers/library_providers.dart';
import '../../shared/widgets/state_views.dart';
import '../library/document_actions.dart';

/// Shows a document's pages with swipe navigation and pinch-to-zoom.
///
/// PDF rendering, sharing and printing are added in the PDF milestone; this
/// screen displays the stored page images directly.
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
              'rename' => _rename(),
              'delete' => _delete(),
              _ => null,
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: pages.isEmpty
          ? const EmptyState(
              icon: Icons.insert_drive_file_outlined,
              title: 'No pages',
              message: 'This document has no pages.',
            )
          : Column(
              children: [
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
