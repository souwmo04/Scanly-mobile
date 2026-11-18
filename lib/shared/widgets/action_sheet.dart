import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_spacing.dart';

/// One row in an [showActionSheet] menu.
class SheetAction<T> {
  const SheetAction({
    required this.value,
    required this.label,
    required this.icon,
    this.destructive = false,
  });

  final T value;
  final String label;
  final IconData icon;
  final bool destructive;
}

/// Bottom sheet with a list of actions. Resolves to the chosen value, or
/// `null` if dismissed.
///
/// The sheet sizes itself to its content and scrolls when that is taller
/// than the screen allows (many entries, short phones or large text sizes).
Future<T?> showActionSheet<T>(
  BuildContext context, {
  required List<SheetAction<T>> actions,
  String? title,
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
              if (title != null)
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
