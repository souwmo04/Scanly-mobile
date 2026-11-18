import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_spacing.dart';

/// Rounded search field.
///
/// When [onTap] is set the field is read-only and acts as a button that
/// opens the search screen (used on Home). Otherwise it is editable.
class ScanlySearchBar extends StatelessWidget {
  const ScanlySearchBar({
    this.controller,
    this.onChanged,
    this.onTap,
    this.onClear,
    this.autofocus = false,
    this.hintText = 'Search documents and text',
    super.key,
  });

  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final bool autofocus;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final readOnly = onTap != null;

    return Semantics(
      button: readOnly,
      label: readOnly ? hintText : null,
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        onTap: onTap,
        autofocus: autofocus,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: Icon(
            Icons.search_rounded,
            color: scheme.onSurfaceVariant,
          ),
          suffixIcon: controller == null || readOnly
              ? null
              : ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller!,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            controller!.clear();
                            onChanged?.call('');
                            onClear?.call();
                          },
                        ),
                ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}
