import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Result of [showFolderEditor].
typedef FolderDraft = ({String name, int colorIndex});

/// Dialog for creating or editing a folder's name and color.
Future<FolderDraft?> showFolderEditor(
  BuildContext context, {
  String title = 'New folder',
  String confirmLabel = 'Create',
  String initialName = '',
  int initialColor = 0,
}) {
  return showDialog<FolderDraft>(
    context: context,
    builder: (context) => _FolderEditorDialog(
      title: title,
      confirmLabel: confirmLabel,
      initialName: initialName,
      initialColor: initialColor,
    ),
  );
}

class _FolderEditorDialog extends StatefulWidget {
  const _FolderEditorDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialName,
    required this.initialColor,
  });

  final String title;
  final String confirmLabel;
  final String initialName;
  final int initialColor;

  @override
  State<_FolderEditorDialog> createState() => _FolderEditorDialogState();
}

class _FolderEditorDialogState extends State<_FolderEditorDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  late int _color = widget.initialColor;

  bool get _canSubmit => _controller.text.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context)
        .pop((name: _controller.text.trim(), colorIndex: _color));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 120,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Folder name'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (var i = 0; i < AppColors.folderPalette.length; i++)
                Semantics(
                  button: true,
                  selected: i == _color,
                  label: 'Folder color ${i + 1}',
                  child: InkResponse(
                    onTap: () => setState(() => _color = i),
                    radius: 24,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.folderPalette[i],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: i == _color
                              ? scheme.onSurface
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: i == _color
                          ? const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
