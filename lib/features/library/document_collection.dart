import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../domain/entities/scan_document.dart';
import '../../domain/repositories/document_repository.dart';
import '../../shared/providers/core_providers.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/document_card.dart';
import '../pdf_viewer/pdf_actions.dart';
import 'bulk_share.dart';
import 'document_actions.dart';
import 'library_controller.dart';

/// Selection state shared between a screen's app bar and its collection.
class SelectionController extends ChangeNotifier {
  final Set<String> _ids = {};

  Set<String> get ids => Set.unmodifiable(_ids);
  bool get isActive => _ids.isNotEmpty;
  int get count => _ids.length;

  bool contains(String id) => _ids.contains(id);

  void toggle(String id) {
    if (!_ids.remove(id)) _ids.add(id);
    notifyListeners();
  }

  void selectAll(Iterable<String> ids) {
    _ids.addAll(ids);
    notifyListeners();
  }

  void clear() {
    if (_ids.isEmpty) return;
    _ids.clear();
    notifyListeners();
  }

  /// Drops ids that no longer exist (e.g. deleted elsewhere).
  void retainOnly(Iterable<String> existing) {
    final keep = existing.toSet();
    final before = _ids.length;
    _ids.retainWhere(keep.contains);
    if (_ids.length != before) notifyListeners();
  }
}

/// Sliver grid or list of documents with tap-to-open, long-press to select.
class DocumentCollectionSliver extends ConsumerWidget {
  const DocumentCollectionSliver({
    required this.documents,
    required this.selection,
    super.key,
  });

  final List<ScanDocument> documents;
  final SelectionController selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(libraryViewProvider.select((s) => s.layout));

    void onTap(ScanDocument doc) {
      if (selection.isActive) {
        selection.toggle(doc.id);
      } else {
        context.push(Routes.document(doc.id));
      }
    }

    return ListenableBuilder(
      listenable: selection,
      builder: (context, _) {
        if (layout == LibraryLayout.list) {
          return SliverList.builder(
            itemCount: documents.length,
            itemBuilder: (context, i) {
              final doc = documents[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: DocumentListTile(
                  document: doc,
                  selected: selection.contains(doc.id),
                  onTap: () => onTap(doc),
                  onLongPress: () => selection.toggle(doc.id),
                  onMore: selection.isActive
                      ? null
                      : () => showDocumentActions(context, ref, doc),
                ),
              );
            },
          );
        }
        return SliverPadding(
          padding: AppSpacing.screenPadding,
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: 0.72,
            ),
            itemCount: documents.length,
            itemBuilder: (context, i) {
              final doc = documents[i];
              return DocumentCard(
                document: doc,
                selected: selection.contains(doc.id),
                onTap: () => onTap(doc),
                onLongPress: () => selection.isActive
                    ? selection.toggle(doc.id)
                    : showDocumentActions(context, ref, doc),
              );
            },
          ),
        );
      },
    );
  }
}

/// App bar shown while documents are selected, with bulk actions.
class SelectionAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const SelectionAppBar({
    required this.selection,
    required this.documents,
    super.key,
  });

  final SelectionController selection;

  /// Every document on screen, in display order.
  final List<ScanDocument> documents;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allIds = [for (final doc in documents) doc.id];
    // Selected ids in the order the documents are shown on screen.
    final ids = [
      for (final id in allIds)
        if (selection.contains(id)) id,
    ];
    final selected = documents.where((d) => selection.contains(d.id));
    final allFavorites =
        selected.isNotEmpty && selected.every((d) => d.isFavorite);

    return AppBar(
      leading: IconButton(
        tooltip: 'Cancel selection',
        icon: const Icon(Icons.close_rounded),
        onPressed: selection.clear,
      ),
      title: Text('${selection.count} selected'),
      actions: [
        IconButton(
          tooltip: 'Select all',
          icon: const Icon(Icons.select_all_rounded),
          onPressed: () => selection.selectAll(allIds),
        ),
        Builder(
          builder: (buttonContext) => IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: ids.isEmpty
                ? null
                : () async {
                    final shared = await shareDocumentsFlow(
                      context,
                      ref,
                      ids,
                      origin: originOf(buttonContext),
                    );
                    if (shared) selection.clear();
                  },
          ),
        ),
        IconButton(
          tooltip: allFavorites ? 'Remove from favorites' : 'Add to favorites',
          icon: Icon(
            allFavorites ? Icons.star_outline_rounded : Icons.star_rounded,
          ),
          onPressed: () =>
              _setFavorites(context, ref, ids, isFavorite: !allFavorites),
        ),
        if (ids.length >= 2)
          IconButton(
            tooltip: 'Merge',
            icon: const Icon(Icons.merge_rounded),
            // Merged in the order the documents are shown on screen.
            onPressed: () => mergeDocumentsFlow(
              context,
              ref,
              ids,
              onMerged: selection.clear,
            ),
          ),
        IconButton(
          tooltip: 'Move to folder',
          icon: const Icon(Icons.drive_file_move_outline),
          onPressed: () async {
            if (await moveDocuments(context, ref, ids)) selection.clear();
          },
        ),
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            if (await deleteDocuments(context, ref, ids)) selection.clear();
          },
        ),
      ],
    );
  }

  Future<void> _setFavorites(
    BuildContext context,
    WidgetRef ref,
    List<String> ids, {
    required bool isFavorite,
  }) async {
    final repo = ref.read(documentRepositoryProvider);
    try {
      for (final id in ids) {
        await repo.setFavorite(id, isFavorite: isFavorite);
      }
    } on Object catch (error) {
      if (context.mounted) showMessage(context, describeError(error));
      return;
    }
    selection.clear();
    if (context.mounted) {
      final count = ids.length;
      final what = count == 1 ? '1 document' : '$count documents';
      showMessage(
        context,
        isFavorite
            ? 'Added $what to favorites'
            : 'Removed $what from favorites',
      );
    }
  }
}

/// Sort and layout controls shown above a collection.
class CollectionToolbar extends ConsumerWidget {
  const CollectionToolbar({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(libraryViewProvider);
    final controller = ref.read(libraryViewProvider.notifier);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count == 1 ? '1 document' : '$count documents',
              style: theme.textTheme.labelMedium,
            ),
          ),
          PopupMenuButton<DocumentSort>(
            tooltip: 'Sort',
            initialValue: view.sort,
            onSelected: controller.setSort,
            itemBuilder: (context) => [
              for (final sort in DocumentSort.values)
                CheckedPopupMenuItem(
                  value: sort,
                  checked: sort == view.sort,
                  child: Text(sortLabel(sort)),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.md,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sort_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    sortLabel(view.sort),
                    style: theme.textTheme.labelMedium,
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: view.layout == LibraryLayout.grid
                ? 'Show as list'
                : 'Show as grid',
            icon: Icon(
              view.layout == LibraryLayout.grid
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded,
            ),
            onPressed: () => controller.setLayout(
              view.layout == LibraryLayout.grid
                  ? LibraryLayout.list
                  : LibraryLayout.grid,
            ),
          ),
        ],
      ),
    );
  }
}
