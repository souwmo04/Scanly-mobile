import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_spacing.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/services/pdf_service.dart';
import '../../shared/widgets/buttons.dart';
import 'pdf_labels.dart';

/// Lets the user choose page size, orientation and compression for an export.
/// Resolves to the chosen options, or `null` if dismissed.
Future<PdfExportOptions?> showPdfExportSheet(
  BuildContext context, {
  required PdfExportOptions initial,
}) {
  return showModalBottomSheet<PdfExportOptions>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => PdfExportSheet(initial: initial),
  );
}

class PdfExportSheet extends StatefulWidget {
  const PdfExportSheet({required this.initial, super.key});

  final PdfExportOptions initial;

  @override
  State<PdfExportSheet> createState() => _PdfExportSheetState();
}

class _PdfExportSheetState extends State<PdfExportSheet> {
  late PdfExportOptions _options = widget.initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl,
          0,
          AppSpacing.xxl,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Export PDF', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Choose how the PDF is laid out, then save or send it.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            _Section(
              title: 'Page size',
              children: [
                for (final size in PdfPageSize.values)
                  ChoiceChip(
                    label: Text(pdfPageSizeLabel(size)),
                    selected: _options.pageSize == size,
                    onSelected: (_) => setState(
                      () => _options = _options.copyWith(pageSize: size),
                    ),
                  ),
              ],
            ),
            _Section(
              title: 'Orientation',
              children: [
                for (final orientation in PdfOrientation.values)
                  ChoiceChip(
                    label: Text(pdfOrientationLabel(orientation)),
                    selected: _options.orientation == orientation,
                    onSelected: (_) => setState(
                      () => _options = _options.copyWith(
                        orientation: orientation,
                      ),
                    ),
                  ),
              ],
            ),
            _Section(
              title: 'Compression',
              subtitle: compressionHint(_options.compression),
              children: [
                for (final compression in ImageCompression.values)
                  ChoiceChip(
                    label: Text(compressionLabel(compression)),
                    selected: _options.compression == compression,
                    onSelected: (_) => setState(
                      () => _options = _options.copyWith(
                        compression: compression,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),
            PrimaryButton(
              label: 'Export and share',
              icon: Icons.ios_share_rounded,
              expand: true,
              onPressed: () => Navigator.of(context).pop(_options),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.subtitle});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          if (subtitle != null)
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: children,
          ),
        ],
      ),
    );
  }
}
