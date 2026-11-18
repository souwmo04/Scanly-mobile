import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../domain/entities/folder.dart';
import '../../domain/entities/scan_document.dart';
import '../../domain/repositories/folder_repository.dart';
import '../../shared/providers/core_providers.dart';
import '../../shared/providers/library_providers.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/folder_card.dart';
import '../../shared/widgets/state_views.dart';
import '../folders/folder_actions.dart';
import '../folders/folder_editor_dialog.dart';
import '../folders/folder_sort.dart';
import 'document_collection.dart';
import 'library_controller.dart';

enum _LibraryFilter { all, favorites }

/// The Files tab: folders plus all documents, with sorting, layout toggle,
/// favorites filter and multi-select bulk actions.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _selection = SelectionController();
  _LibraryFilter _filter = _LibraryFilter.all;

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  Future<void> _createFolder() async {
    final draft = await showFolderEditor(context);
    if (draft == null || !mounted) return;
    try {
      await ref
          .read(folderRepositoryProvider)
          .createFolder(name: draft.name, colorIndex: draft.colorIndex);
    } on Object catch (error) {
      if (mounted) showMessage(context, describeError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sort = ref.watch(libraryViewProvider.select((s) => s.sort));
    final query = documentQuery(
      sort: sort,
      favoritesOnly: _filter == _LibraryFilter.favorites,
    );
    final documents = ref.watch(documentsProvider(query));
    final folders = ref.watch(sortedFoldersProvider);

    final docList = documents.value ?? const <ScanDocument>[];
    // Drop selected ids that were deleted elsewhere. Done in a listener, not
    // during build, because it notifies the selection's listeners.
    ref.listen(documentsProvider(query), (_, next) {
      final docs = next.value;
      if (docs != null) _selection.retainOnly(docs.map((d) => d.id));
    });

    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) => PopScope(
        canPop: !_selection.isActive,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _selection.clear();
        },
        child: Scaffold(
          appBar: _selection.isActive
              ? SelectionAppBar(selection: _selection, documents: docList)
              : AppBar(
                  title: const Text('Files'),
                  actions: [
                    IconButton(
                      tooltip: 'New folder',
                      icon: const Icon(Icons.create_new_folder_outlined),
                      onPressed: _createFolder,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                ),
          body: RefreshIndicator(
            onRefresh: () async {
              ref
                ..invalidate(documentsProvider(query))
                ..invalidate(sortedFoldersProvider);
            },
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _FoldersSection(
                    folders: folders,
                    onCreate: _createFolder,
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenGutter,
                      AppSpacing.lg,
                      AppSpacing.screenGutter,
                      0,
                    ),
                    child: SegmentedButton<_LibraryFilter>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: _LibraryFilter.all,
                          label: Text('All documents'),
                        ),
                        ButtonSegment(
                          value: _LibraryFilter.favorites,
                          label: Text('Favorites'),
                          icon: Icon(Icons.star_rounded, size: 18),
                        ),
                      ],
                      selected: {_filter},
                      onSelectionChanged: (value) {
                        _selection.clear();
                        setState(() => _filter = value.first);
                      },
                    ),
                  ),
                ),
                ...documents.when(
                  data: (docs) => [
                    SliverToBoxAdapter(
                      child: CollectionToolbar(count: docs.length),
                    ),
                    if (docs.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _filter == _LibraryFilter.favorites
                            ? const EmptyState(
                                icon: Icons.star_outline_rounded,
                                title: 'No favorites yet',
                                message:
                                    'Long-press a document and choose '
                                    '"Add to favorites" to pin it here.',
                                compact: true,
                              )
                            : EmptyState(
                                icon: Icons.description_outlined,
                                title: 'No documents yet',
                                message:
                                    'Scanned documents are saved here, on '
                                    'your device.',
                                actionLabel: 'Scan a document',
                                onAction: () => context.push(Routes.scan),
                                compact: true,
                              ),
                      )
                    else
                      DocumentCollectionSliver(
                        documents: docs,
                        selection: _selection,
                      ),
                  ],
                  loading: () => const [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: LoadingState(),
                    ),
                  ],
                  error: (error, _) => [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: ErrorState(
                        error: error,
                        onRetry: () => ref.invalidate(documentsProvider(query)),
                      ),
                    ),
                  ],
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.huge),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FoldersSection extends ConsumerWidget {
  const _FoldersSection({required this.folders, required this.onCreate});

  final AsyncValue<List<Folder>> folders;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FoldersHeader(onCreate: onCreate),
        SizedBox(
          height: 124,
          child: folders.when(
            loading: () => const Center(
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
            error: (error, _) => Padding(
              padding: AppSpacing.screenPadding,
              child: _FoldersError(
                onRetry: () => ref.invalidate(sortedFoldersProvider),
              ),
            ),
            data: (list) => list.isEmpty
                ? Padding(
                    padding: AppSpacing.screenPadding,
                    child: _NewFolderTile(onTap: onCreate),
                  )
                : ListView.separated(
                    padding: AppSpacing.screenPadding,
                    scrollDirection: Axis.horizontal,
                    itemCount: list.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.md),
                    itemBuilder: (context, i) => SizedBox(
                      width: 150,
                      child: FolderCard(
                        folder: list[i],
                        onTap: () => context.push(Routes.folder(list[i].id)),
                        onLongPress: () =>
                            showFolderActions(context, ref, list[i]),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// "Folders" title with the folder sort menu and a "New" button.
class _FoldersHeader extends ConsumerWidget {
  const _FoldersHeader({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sort = ref.watch(folderSortProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.xxl,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text('Folders', style: theme.textTheme.titleMedium),
            ),
          ),
          PopupMenuButton<FolderSort>(
            tooltip: 'Sort folders',
            initialValue: sort,
            onSelected: ref.read(folderSortProvider.notifier).setSort,
            itemBuilder: (context) => [
              for (final option in FolderSort.values)
                CheckedPopupMenuItem(
                  value: option,
                  checked: option == sort,
                  child: Text(folderSortLabel(option)),
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
                    folderSortLabel(sort),
                    style: theme.textTheme.labelMedium,
                  ),
                ],
              ),
            ),
          ),
          TextButton(onPressed: onCreate, child: const Text('New')),
        ],
      ),
    );
  }
}

class _FoldersError extends StatelessWidget {
  const _FoldersError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.error_outline_rounded, color: theme.colorScheme.error),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'Folders could not be loaded.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

class _NewFolderTile extends StatelessWidget {
  const _NewFolderTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 150,
        child: Material(
          color: scheme.surfaceContainer,
          borderRadius: AppRadius.lgAll,
          child: InkWell(
            borderRadius: AppRadius.lgAll,
            onTap: onTap,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.create_new_folder_outlined,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text('Create a folder', style: theme.textTheme.labelMedium),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
