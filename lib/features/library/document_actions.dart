import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../domain/entities/folder.dart';
import '../../domain/entities/scan_document.dart';
import '../../domain/usecases/duplicate_document.dart';
import '../../shared/providers/core_providers.dart';
import '../../shared/widgets/action_sheet.dart';
import '../../shared/widgets/dialogs.dart';
import '../pdf_viewer/pdf_actions.dart';
import 'document_info_sheet.dart';
import 'library_use_cases.dart';

enum _DocumentAction { info, rename, favorite, move, duplicate, delete }

/// Shows the per-document menu and performs the chosen action.
Future<void> showDocumentActions(
  BuildContext context,
  WidgetRef ref,
  ScanDocument document,
) async {
  final action = await _showScrollableActionSheet<_DocumentAction>(
    context,
    title: document.title,
    actions: [
      const SheetAction(
        value: _DocumentAction.info,
        label: 'Info',
        icon: Icons.info_outline_rounded,
      ),
      const SheetAction(
        value: _DocumentAction.rename,
        label: 'Rename',
        icon: Icons.drive_file_rename_outline_rounded,
      ),
      SheetAction(
        value: _DocumentAction.favorite,
        label: document.isFavorite
            ? 'Remove from favorites'
            : 'Add to favorites',
        icon: document.isFavorite
            ? Icons.star_outline_rounded
            : Icons.star_rounded,
      ),
      const SheetAction(
        value: _DocumentAction.move,
        label: 'Move to folder',
        icon: Icons.drive_file_move_outline,
      ),
      const SheetAction(
        value: _DocumentAction.duplicate,
        label: 'Duplicate',
        icon: Icons.copy_all_rounded,
      ),
      const SheetAction(
        value: _DocumentAction.delete,
        label: 'Delete',
        icon: Icons.delete_outline_rounded,
        destructive: true,
      ),
    ],
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _DocumentAction.info:
      await showDocumentInfo(context, document.id);
    case _DocumentAction.rename:
      await renameDocument(context, ref, document);
    case _DocumentAction.favorite:
      await _run(
        context,
        () => ref
            .read(documentRepositoryProvider)
            .setFavorite(document.id, isFavorite: !document.isFavorite),
      );
    case _DocumentAction.move:
      await moveDocuments(context, ref, [document.id]);
    case _DocumentAction.duplicate:
      await duplicateDocument(context, ref, document);
    case _DocumentAction.delete:
      await deleteDocuments(context, ref, [document.id]);
  }
}

/// Copies [document] (pages, edits and recognised text) into a new
/// document next to it. Returns the new id, or `null` after showing the
/// error.
Future<String?> duplicateDocument(
  BuildContext context,
  WidgetRef ref,
  ScanDocument document,
) async {
  final duplicate = ref.read(duplicateDocumentProvider);
  try {
    final id = await runWithProgressDialog(
      context,
      label: (_) => 'Duplicating document…',
      task: (_) => duplicate(document.id),
    );
    if (context.mounted) {
      showMessage(
        context,
        'Created "${DuplicateDocumentUseCase.copyTitle(document.title)}"',
      );
    }
    return id;
  } on Object catch (error) {
    if (context.mounted) {
      showMessage(
        context,
        'Could not duplicate the document. ${describeError(error)}',
      );
    }
    return null;
  }
}

Future<bool> renameDocument(
  BuildContext context,
  WidgetRef ref,
  ScanDocument document,
) async {
  final name = await showTextInputDialog(
    context,
    title: 'Rename document',
    confirmLabel: 'Rename',
    initialValue: document.title,
    maxLength: 200,
  );
  if (name == null || name == document.title || !context.mounted) {
    return false;
  }
  return _run(
    context,
    () => ref.read(documentRepositoryProvider).rename(document.id, name),
  );
}

/// Asks for confirmation, then deletes. Returns `true` if deleted.
Future<bool> deleteDocuments(
  BuildContext context,
  WidgetRef ref,
  List<String> ids,
) async {
  final count = ids.length;
  final confirmed = await showConfirmDialog(
    context,
    title: count == 1 ? 'Delete document?' : 'Delete $count documents?',
    message:
        'The pages, extracted text and PDF will be permanently removed '
        'from this device. This cannot be undone.',
    confirmLabel: 'Delete',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return false;
  final ok = await _run(
    context,
    () => ref.read(documentRepositoryProvider).deleteDocuments(ids),
  );
  if (ok && context.mounted) {
    showMessage(
      context,
      count == 1 ? 'Document deleted' : '$count documents deleted',
    );
  }
  return ok;
}

/// Lets the user pick a destination folder, then moves the documents.
Future<bool> moveDocuments(
  BuildContext context,
  WidgetRef ref,
  List<String> ids,
) async {
  final folders = await ref.read(folderRepositoryProvider).watchFolders().first;
  if (!context.mounted) return false;

  final destination = await showModalBottomSheet<_MoveTarget>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => _FolderPicker(folders: folders),
  );
  if (destination == null || !context.mounted) return false;

  final ok = await _run(
    context,
    () => ref
        .read(documentRepositoryProvider)
        .moveToFolder(ids, destination.folderId),
  );
  if (ok && context.mounted) {
    showMessage(
      context,
      destination.folderId == null
          ? 'Moved to All files'
          : 'Moved to ${destination.name}',
    );
  }
  return ok;
}

/// Like [showActionSheet], but scrolls when the menu is taller than the
/// screen allows (the document menu has many entries, and short phones or
/// large text sizes would otherwise overflow).
Future<T?> _showScrollableActionSheet<T>(
  BuildContext context, {
  required List<SheetAction<T>> actions,
  required String title,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                  title,
                  style: theme.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              for (final action in actions)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxl,
                  ),
                  leading: Icon(
                    action.icon,
                    color: action.destructive ? scheme.error : null,
                  ),
                  title: Text(
                    action.label,
                    style: action.destructive
                        ? TextStyle(color: scheme.error)
                        : null,
                  ),
                  onTap: () => Navigator.of(context).pop(action.value),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Runs [action] and reports failures as a snackbar. Returns success.
Future<bool> _run(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } on Object catch (error) {
    if (context.mounted) showMessage(context, describeError(error));
    return false;
  }
}

class _MoveTarget {
  const _MoveTarget(this.folderId, this.name);

  final String? folderId;
  final String name;
}

class _FolderPicker extends StatelessWidget {
  const _FolderPicker({required this.folders});

  final List<Folder> folders;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              0,
              AppSpacing.xxl,
              AppSpacing.md,
            ),
            child: Text('Move to', style: theme.textTheme.titleMedium),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxl,
            ),
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('All files (no folder)'),
            onTap: () =>
                Navigator.of(context).pop(const _MoveTarget(null, 'All files')),
          ),
          for (final folder in folders)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxl,
              ),
              leading: Icon(
                Icons.folder_rounded,
                color: AppColors.folderColor(folder.colorIndex),
              ),
              title: Text(folder.name),
              onTap: () =>
                  Navigator.of(context)
                      .pop(_MoveTarget(folder.id, folder.name)),
            ),
          if (folders.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Text(
                'No folders yet. Create one from the Files tab.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
