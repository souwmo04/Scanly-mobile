import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_spacing.dart';
import '../../domain/entities/scan_page.dart';
import '../../shared/widgets/buttons.dart';

/// Lets the user tap the gaps between pages to choose where to split.
/// Resolves to the ascending zero-based index of the first page of every
/// part after the first (see `DocumentPdfService.splitDocument`), or `null`
/// if dismissed.
Future<List<int>?> showSplitDocumentSheet(
  BuildContext context, {
  required List<ScanPage> pages,
}) {
  return showModalBottomSheet<List<int>>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => SplitDocumentSheet(pages: pages),
  );
}

class SplitDocumentSheet extends StatefulWidget {
  const SplitDocumentSheet({required this.pages, super.key});

  final List<ScanPage> pages;

  @override
  State<SplitDocumentSheet> createState() => _SplitDocumentSheetState();
}

class _SplitDocumentSheetState extends State<SplitDocumentSheet> {
  /// One-based page numbers after which the document is split.
  final _splitAfter = <int>{};

  void _toggle(int pageNumber) => setState(() {
    if (!_splitAfter.remove(pageNumber)) _splitAfter.add(pageNumber);
  });

  /// Page ranges of the resulting parts, e.g. ["1–3", "4–5"].
  List<String> get _ranges {
    final cuts = [..._splitAfter]..sort();
    final ranges = <String>[];
    var start = 1;
    for (final cut in [...cuts, widget.pages.length]) {
      ranges.add(start == cut ? '$start' : '$start–$cut');
      start = cut + 1;
    }
    return ranges;
  }

  void _submit() {
    // "Split after page N" (one-based) starts the next part at index N.
    Navigator.of(context).pop([..._splitAfter]..sort());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pages = widget.pages;
    final parts = _splitAfter.length + 1;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      builder: (context, scrollController) => SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxl,
                0,
                AppSpacing.xxl,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Split document', style: theme.textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Tap between pages to choose where each new document '
                    'starts. The original stays as it is.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxl,
                  vertical: AppSpacing.md,
                ),
                itemCount: pages.length * 2 - 1,
                itemBuilder: (context, i) {
                  if (i.isEven) {
                    return _PageRow(page: pages[i ~/ 2], number: i ~/ 2 + 1);
                  }
                  final after = i ~/ 2 + 1;
                  return _SplitGap(
                    key: ValueKey('split-after-$after'),
                    afterPage: after,
                    selected: _splitAfter.contains(after),
                    onTap: () => _toggle(after),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxl,
                AppSpacing.md,
                AppSpacing.xxl,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    parts == 1
                        ? 'No split points yet'
                        : 'Pages ${_ranges.join(', ')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  PrimaryButton(
                    label: parts == 1
                        ? 'Choose split points'
                        : 'Split into $parts documents',
                    icon: Icons.content_cut_rounded,
                    expand: true,
                    onPressed: parts == 1 ? null : _submit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageRow extends StatelessWidget {
  const _PageRow({required this.page, required this.number});

  final ScanPage page;
  final int number;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Row(
      children: [
        ClipRRect(
          borderRadius: AppRadius.smAll,
          child: Container(
            width: 48,
            height: 64,
            color: scheme.surfaceContainerHighest,
            child: RotatedBox(
              quarterTurns: page.rotation ~/ 90,
              child: Image.file(
                File(page.displayPath),
                cacheWidth: (64 * dpr).round(),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  Icons.insert_drive_file_outlined,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Text('Page $number', style: theme.textTheme.bodyLarge),
      ],
    );
  }
}

class _SplitGap extends StatelessWidget {
  const _SplitGap({
    required this.afterPage,
    super.key,
    required this.selected,
    required this.onTap,
  });

  final int afterPage;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = selected ? scheme.primary : scheme.outlineVariant;
    return Semantics(
      button: true,
      toggled: selected,
      label: 'Split after page $afterPage',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.smAll,
        child: SizedBox(
          height: AppSpacing.minTouchTarget,
          child: Row(
            children: [
              Icon(
                selected ? Icons.content_cut_rounded : Icons.add_rounded,
                size: 18,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Divider(color: color, thickness: selected ? 2 : 1),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                selected ? 'New document starts here' : 'Split here',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
