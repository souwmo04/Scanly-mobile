import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../domain/entities/scan_page.dart';
import '../../shared/providers/core_providers.dart';
import '../../shared/providers/library_providers.dart';
import '../../shared/providers/scanner_providers.dart';
import '../../shared/widgets/action_sheet.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/state_views.dart';
import '../ocr/ocr_queue.dart';
import '../settings/settings_controller.dart';

/// Grid of a document's pages: reorder by long-press dragging, and edit,
/// rotate, retake or delete each page. New pages can be scanned in.
class PageOrganizerScreen extends ConsumerStatefulWidget {
  const PageOrganizerScreen({required this.documentId, super.key});

  final String documentId;

  @override
  ConsumerState<PageOrganizerScreen> createState() =>
      _PageOrganizerScreenState();
}

enum _PageAction { edit, rotate, retake, delete }

class _PageOrganizerScreenState extends ConsumerState<PageOrganizerScreen> {
  /// Order shown while a drag is in progress or being saved.
  List<ScanPage>? _pendingOrder;
  int? _dragging;
  final Set<String> _busy = {};

  Future<void> _move(List<ScanPage> pages, int from, int to) async {
    if (from == to) return;
    final reordered = List.of(pages);
    final page = reordered.removeAt(from);
    reordered.insert(to, page);
    setState(() => _pendingOrder = reordered);
    unawaited(HapticFeedback.selectionClick());
    try {
      await ref
          .read(documentRepositoryProvider)
          .reorderPages(widget.documentId, reordered.map((p) => p.id).toList());
    } on Object catch (e) {
      if (mounted) showMessage(context, describeError(e));
    } finally {
      if (mounted) setState(() => _pendingOrder = null);
    }
  }

  Future<void> _run(String pageId, Future<void> Function() action) async {
    setState(() => _busy.add(pageId));
    try {
      await action();
    } on Object catch (e) {
      if (mounted) showMessage(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(pageId));
    }
  }

  Future<void> _showActions(ScanPage page, int number, int total) async {
    final action = await showActionSheet<_PageAction>(
      context,
      title: 'Page $number',
      actions: [
        const SheetAction(
          value: _PageAction.edit,
          label: 'Crop, filters and adjust',
          icon: Icons.tune_rounded,
        ),
        const SheetAction(
          value: _PageAction.rotate,
          label: 'Rotate right',
          icon: Icons.rotate_right_rounded,
        ),
        const SheetAction(
          value: _PageAction.retake,
          label: 'Retake',
          icon: Icons.camera_alt_outlined,
        ),
        if (total > 1)
          const SheetAction(
            value: _PageAction.delete,
            label: 'Delete page',
            icon: Icons.delete_outline_rounded,
            destructive: true,
          ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _PageAction.edit:
        await context.push(Routes.editPage(widget.documentId, page.id));
      case _PageAction.rotate:
        await _run(page.id, () async {
          await ref.read(editPageProvider).rotate(page);
          // The image changed, so its recognised text may be stale.
          await ref
              .read(ocrQueueProvider.notifier)
              .pageImageChanged(
                page.id,
                autoOcr: ref.read(settingsControllerProvider).autoOcr,
              );
        });
      case _PageAction.retake:
        await context.push(Routes.scanRetake(page.id));
      case _PageAction.delete:
        final confirmed = await showConfirmDialog(
          context,
          title: 'Delete page $number?',
          message: 'The page and its text are removed from this document.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (!confirmed) return;
        await _run(
          page.id,
          () => ref.read(documentRepositoryProvider).deletePage(page.id),
        );
    }
    ref.invalidate(documentDetailProvider(widget.documentId));
  }

  @override
  Widget build(BuildContext context) {
    final pages = ref.watch(pagesProvider(widget.documentId));
    final count = pages.value?.length;

    return Scaffold(
      appBar: AppBar(title: Text(count == null ? 'Pages' : 'Pages ($count)')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.scanAppend(widget.documentId)),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Add pages'),
      ),
      body: AsyncValueView(
        value: pages,
        data: (loaded) {
          final shown = _pendingOrder ?? loaded;
          if (shown.isEmpty) {
            return const EmptyState(
              icon: Icons.insert_drive_file_outlined,
              title: 'No pages',
              message: 'Add pages with the button below.',
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenGutter,
                  0,
                  AppSpacing.screenGutter,
                  AppSpacing.sm,
                ),
                child: Text(
                  'Tap a page for options. Press and hold to drag it to a '
                  'new position.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    AppSpacing.sm,
                    AppSpacing.screenGutter,
                    96,
                  ),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    childAspectRatio: 0.7,
                  ),
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final page = shown[i];
                    final tile = _PageTile(
                      page: page,
                      number: i + 1,
                      busy: _busy.contains(page.id),
                    );
                    return DragTarget<int>(
                      onWillAcceptWithDetails: (d) => d.data != i,
                      onAcceptWithDetails: (d) => _move(shown, d.data, i),
                      builder: (context, candidates, _) =>
                          LongPressDraggable<int>(
                            data: i,
                            onDragStarted: () {
                              HapticFeedback.mediumImpact();
                              setState(() => _dragging = i);
                            },
                            onDragEnd: (_) => setState(() => _dragging = null),
                            feedback: SizedBox(
                              width: 140,
                              height: 200,
                              child: Material(
                                elevation: 8,
                                borderRadius: AppRadius.lgAll,
                                child: tile,
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: 0.3,
                              child: tile,
                            ),
                            child: GestureDetector(
                              onTap: () =>
                                  _showActions(page, i + 1, shown.length),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                decoration: BoxDecoration(
                                  borderRadius: AppRadius.lgAll,
                                  border: Border.all(
                                    color:
                                        candidates.isNotEmpty && _dragging != i
                                        ? AppColors.amber
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                                child: tile,
                              ),
                            ),
                          ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    required this.page,
    required this.number,
    required this.busy,
  });

  final ScanPage page;
  final int number;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final thumb = page.thumbnailPath ?? page.displayPath;
    return Semantics(
      label: 'Page $number',
      button: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Image.file(
                File(thumb),
                fit: BoxFit.contain,
                cacheWidth: 360,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.broken_image_outlined, color: scheme.outline),
              ),
            ),
            Positioned(
              left: AppSpacing.sm,
              bottom: AppSpacing.sm,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: scheme.inverseSurface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '$number',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onInverseSurface,
                  ),
                ),
              ),
            ),
            if (busy)
              ColoredBox(
                color: scheme.surface.withValues(alpha: 0.6),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
