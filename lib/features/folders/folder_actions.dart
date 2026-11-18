import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/entities/folder.dart';
import '../../shared/providers/core_providers.dart';
import '../../shared/widgets/action_sheet.dart';
import '../../shared/widgets/dialogs.dart';
import 'folder_editor_dialog.dart';

enum _FolderAction { edit, delete }

/// Folder menu (edit name/color, delete). Returns `true` if the folder was
/// deleted, so a folder screen can close itself.
Future<bool> showFolderActions(
  BuildContext context,
  WidgetRef ref,
  Folder folder,
) async {
  final action = await showActionSheet<_FolderAction>(
    context,
    title: folder.name,
    actions: const [
      SheetAction(
        value: _FolderAction.edit,
        label: 'Rename or change color',
        icon: Icons.edit_outlined,
      ),
      SheetAction(
        value: _FolderAction.delete,
        label: 'Delete folder',
        icon: Icons.delete_outline_rounded,
        destructive: true,
      ),
    ],
  );
  if (action == null || !context.mounted) return false;

  final repo = ref.read(folderRepositoryProvider);
  try {
    switch (action) {
      case _FolderAction.edit:
        final draft = await showFolderEditor(
          context,
          title: 'Edit folder',
          confirmLabel: 'Save',
          initialName: folder.name,
          initialColor: folder.colorIndex,
        );
        if (draft == null) return false;
        await repo.updateFolder(
          folder.id,
          name: draft.name,
          colorIndex: draft.colorIndex,
        );
        return false;
      case _FolderAction.delete:
        final confirmed = await showConfirmDialog(
          context,
          title: 'Delete "${folder.name}"?',
          message:
              'The folder is removed. Its documents are kept and moved to '
              'All files.',
          confirmLabel: 'Delete folder',
          destructive: true,
        );
        if (!confirmed) return false;
        await repo.deleteFolder(folder.id);
        return true;
    }
  } on Object catch (error) {
    if (context.mounted) showMessage(context, describeError(error));
    return false;
  }
}
