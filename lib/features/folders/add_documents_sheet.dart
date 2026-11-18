import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/folder.dart';
import '../../domain/entities/scan_document.dart';
import '../../domain/repositories/document_repository.dart';
import '../../shared/providers/core_providers.dart';
import '../../shared/providers/library_providers.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/scanly_search_bar.dart';
import '../../shared/widgets/state_views.dart';

/// Lets the user pick documents that are not in [folder] and moves them in.
/// Returns the number of documents moved (0 if cancelled or failed).
Future<int> addDocumentsToFolder(
  BuildContext context,
  WidgetRef ref,
  Folder folder,
) async {
  final ids = await showModalBottomSheet<List<String>>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => AddDocumentsSheet(folder: folder),
  );
  if (ids == null || ids.isEmpty || !context.mounted) return 0;
  try {
    await ref.read(documentRepositoryProvider).moveToFolder(ids, folder.id);
  } on Object catch (error) {
    if (context.mounted) showMessage(context, describeError(error));
    return 0;
  }
  if (context.mounted) {
    final what = ids.length == 1 ? '1 document' : '${ids.length} documents';
    showMessage(context, 'Added $what to ${folder.name}');
  }
  return ids.length;
}

/// Multi-select list of documents outside [folder], with search by title.
/// Pops with the chosen ids.
class AddDocumentsSheet extends ConsumerStatefulWidget {
  const AddDocumentsSheet({required this.folder, super.key});

  final Folder folder;

  @override
  ConsumerState<AddDocumentsSheet> createState() => _AddDocumentsSheetState();
}

class _AddDocumentsSheetState extends ConsumerState<AddDocumentsSheet> {
  final _search = TextEditingController();
  final _selected = <String>{};
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static final _allByName = documentQuery(sort: DocumentSort.titleAZ);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final documents = ref.watch(documentsProvider(_allByName));
    final candidates = [
      for (final doc in documents.value ?? const <ScanDocument>[])
        if (doc.folderId != widget.folder.id) doc,
    ];
    // Drop selections that were moved or deleted meanwhile.
    _selected.retainAll(candidates.map((d) => d.id));
    final needle = _query.trim().toLowerCase();
    final visible = needle.isEmpty
        ? candidates
        : [
            for (final doc in candidates)
              if (doc.title.toLowerCase().contains(needle)) doc,
          ];
    final count = _selected.length;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              0,
              AppSpacing.xxl,
              AppSpacing.md,
            ),
            child: Text(
              'Add to ${widget.folder.name}',
              style: theme.textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: ScanlySearchBar(
              controller: _search,
              hintText: 'Search by title',
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: documents.when(
              loading: () => const LoadingState(),
              error: (error, _) => ErrorState(
                error: error,
                onRetry: () => ref.invalidate(documentsProvider(_allByName)),
              ),
              data: (_) {
                if (candidates.isEmpty) {
                  return const EmptyState(
                    icon: Icons.folder_copy_outlined,
                    title: 'Nothing to add',
                    message:
                        'Every document is already in this folder, or you '
                        'have no documents yet.',
                    compact: true,
                  );
                }
                if (visible.isEmpty) {
                  return EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No matches',
                    message: 'No document title contains "${_query.trim()}".',
                    compact: true,
                  );
                }
                return ListView.builder(
                  controller: scrollController,
                  itemCount: visible.length,
                  itemBuilder: (context, i) {
                    final doc = visible[i];
                    return CheckboxListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _selected.contains(doc.id),
                      title: Text(
                        doc.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${pluralPages(doc.pageCount)} · '
                        '${formatRelativeDate(doc.updatedAt)}',
                      ),
                      onChanged: (checked) => setState(() {
                        if (checked ?? false) {
                          _selected.add(doc.id);
                        } else {
                          _selected.remove(doc.id);
                        }
                      }),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: PrimaryButton(
                expand: true,
                onPressed: count == 0
                    ? null
                    : () => Navigator.of(context).pop([
                        // Keep the on-screen order.
                        for (final doc in candidates)
                          if (_selected.contains(doc.id)) doc.id,
                      ]),
                label: count == 0
                    ? 'Select documents'
                    : count == 1
                    ? 'Add 1 document'
                    : 'Add $count documents',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
