import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_spacing.dart';
import '../../domain/entities/folder.dart';
import '../../domain/entities/scan_document.dart';
import '../../shared/providers/library_providers.dart';
import '../../shared/widgets/state_views.dart';
import '../library/document_collection.dart';
import '../library/library_controller.dart';
import 'add_documents_sheet.dart';
import 'folder_actions.dart';

/// Documents inside one folder.
class FolderScreen extends ConsumerStatefulWidget {
  const FolderScreen({required this.folderId, super.key});

  final String folderId;

  @override
  ConsumerState<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends ConsumerState<FolderScreen> {
  final _selection = SelectionController();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch the folder list so renames and deletions show immediately.
    final folders = ref.watch(foldersProvider);
    final sort = ref.watch(libraryViewProvider.select((s) => s.sort));
    final query = documentQuery(sort: sort, folderId: widget.folderId);
    final documents = ref.watch(documentsProvider(query));
    // Drop selected ids that were deleted elsewhere (in a listener, not
    // during build, because it notifies the selection's listeners).
    ref.listen(documentsProvider(query), (_, next) {
      final docs = next.value;
      if (docs != null) _selection.retainOnly(docs.map((d) => d.id));
    });

    final Folder? folder = folders.value
        ?.where((f) => f.id == widget.folderId)
        .firstOrNull;
    final docList = documents.value ?? const <ScanDocument>[];

    if (folders.hasValue && folder == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.folder_off_outlined,
          title: 'Folder not found',
          message: 'It may have been deleted.',
        ),
      );
    }

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
                  title: Text(folder?.name ?? ''),
                  actions: [
                    if (folder != null)
                      IconButton(
                        tooltip: 'Add documents',
                        icon: const Icon(Icons.playlist_add_rounded),
                        onPressed: () =>
                            addDocumentsToFolder(context, ref, folder),
                      ),
                    if (folder != null)
                      IconButton(
                        tooltip: 'Folder options',
                        icon: const Icon(Icons.more_vert_rounded),
                        onPressed: () async {
                          final deleted = await showFolderActions(
                            context,
                            ref,
                            folder,
                          );
                          if (deleted && context.mounted) context.pop();
                        },
                      ),
                  ],
                ),
          body: CustomScrollView(
            slivers: [
              ...documents.when(
                data: (docs) => [
                  SliverToBoxAdapter(
                    child: CollectionToolbar(count: docs.length),
                  ),
                  if (docs.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        icon: Icons.folder_open_rounded,
                        title: 'This folder is empty',
                        message:
                            'Add documents you already have, or use "Move to '
                            'folder" on any document.',
                        actionLabel: folder == null ? null : 'Add documents',
                        onAction: folder == null
                            ? null
                            : () => addDocumentsToFolder(context, ref, folder),
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
    );
  }
}
