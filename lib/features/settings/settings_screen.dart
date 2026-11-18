import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/errors/app_exception.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/app_settings.dart';
import '../../shared/providers/core_providers.dart';
import '../../shared/providers/library_providers.dart';
import '../../shared/widgets/dialogs.dart';
import 'settings_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final usage = ref.watch(storageUsageProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.huge),
        children: [
          const _GroupLabel('Appearance'),
          _SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: SegmentedButton<AppThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: AppThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto_rounded),
                    ),
                    ButtonSegment(
                      value: AppThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_rounded),
                    ),
                    ButtonSegment(
                      value: AppThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_rounded),
                    ),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (value) => controller.update(
                    (s) => s.copyWith(themeMode: value.first),
                  ),
                ),
              ),
            ],
          ),
          const _GroupLabel('Scanning'),
          _SettingsCard(
            children: [
              _ChoiceTile<ScanQuality>(
                icon: Icons.high_quality_outlined,
                title: 'Scan quality',
                value: settings.scanQuality,
                options: ScanQuality.values,
                labelOf: _scanQualityLabel,
                onChanged: (v) =>
                    controller.update((s) => s.copyWith(scanQuality: v)),
              ),
              const Divider(indent: 56),
              _ChoiceTile<ImageCompression>(
                icon: Icons.compress_rounded,
                title: 'Image compression',
                value: settings.compression,
                options: ImageCompression.values,
                labelOf: _compressionLabel,
                onChanged: (v) =>
                    controller.update((s) => s.copyWith(compression: v)),
              ),
            ],
          ),
          const _GroupLabel('PDF'),
          _SettingsCard(
            children: [
              _ChoiceTile<PdfPageSize>(
                icon: Icons.description_outlined,
                title: 'Default page size',
                value: settings.pdfPageSize,
                options: PdfPageSize.values,
                labelOf: _pageSizeLabel,
                onChanged: (v) =>
                    controller.update((s) => s.copyWith(pdfPageSize: v)),
              ),
              const Divider(indent: 56),
              _ChoiceTile<PdfOrientation>(
                icon: Icons.screen_rotation_alt_rounded,
                title: 'Orientation',
                value: settings.pdfOrientation,
                options: PdfOrientation.values,
                labelOf: _orientationLabel,
                onChanged: (v) =>
                    controller.update((s) => s.copyWith(pdfOrientation: v)),
              ),
            ],
          ),
          const _GroupLabel('Text recognition (OCR)'),
          _SettingsCard(
            children: [
              _ChoiceTile<OcrLanguage>(
                icon: Icons.translate_rounded,
                title: 'OCR language',
                value: settings.ocrLanguage,
                options: OcrLanguage.values,
                labelOf: _ocrLanguageLabel,
                onChanged: (v) =>
                    controller.update((s) => s.copyWith(ocrLanguage: v)),
              ),
              const Divider(indent: 56),
              SwitchListTile(
                secondary: const Icon(Icons.text_snippet_outlined),
                title: const Text('Recognize text automatically'),
                subtitle: const Text('Run OCR on device after each scan'),
                value: settings.autoOcr,
                onChanged: (v) =>
                    controller.update((s) => s.copyWith(autoOcr: v)),
              ),
            ],
          ),
          const _GroupLabel('Storage & privacy'),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.sd_storage_outlined),
                title: const Text('Storage used'),
                trailing: Text(
                  usage.when(
                    data: formatBytes,
                    loading: () => '…',
                    error: (_, _) => 'Unavailable',
                  ),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const Divider(indent: 56),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Privacy'),
                subtitle: const Text('Everything stays on your device'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.privacy),
              ),
              const Divider(indent: 56),
              ListTile(
                leading: Icon(
                  Icons.delete_forever_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Clear all data',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () => _clearAllData(context, ref),
              ),
            ],
          ),
          const _GroupLabel('About'),
          _SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('About Scanly'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.about),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllData(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Clear all data?',
      message:
          'Every document, folder, page and extracted text will be '
          'permanently deleted from this device. This cannot be undone.',
      confirmLabel: 'Delete everything',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(maintenanceRepositoryProvider).clearAllData();
      ref.invalidate(storageUsageProvider);
      if (context.mounted) showMessage(context, 'All data cleared');
    } on Object catch (error) {
      if (context.mounted) showMessage(context, describeError(error));
    }
  }
}

String _scanQualityLabel(ScanQuality v) => switch (v) {
  ScanQuality.standard => 'Standard (smaller files)',
  ScanQuality.high => 'High (recommended)',
  ScanQuality.maximum => 'Maximum',
};

String _compressionLabel(ImageCompression v) => switch (v) {
  ImageCompression.low => 'Low (best quality)',
  ImageCompression.balanced => 'Balanced',
  ImageCompression.high => 'High (smallest files)',
};

String _pageSizeLabel(PdfPageSize v) => switch (v) {
  PdfPageSize.a4 => 'A4',
  PdfPageSize.a5 => 'A5',
  PdfPageSize.letter => 'US Letter',
  PdfPageSize.legal => 'US Legal',
  PdfPageSize.original => 'Original image size',
};

String _orientationLabel(PdfOrientation v) => switch (v) {
  PdfOrientation.auto => 'Automatic',
  PdfOrientation.portrait => 'Portrait',
  PdfOrientation.landscape => 'Landscape',
};

String _ocrLanguageLabel(OcrLanguage v) => switch (v) {
  OcrLanguage.english => 'English',
  OcrLanguage.bangla => 'বাংলা (Bangla)',
  OcrLanguage.mixed => 'Bangla + English',
};

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter + AppSpacing.xs,
        AppSpacing.xxl,
        AppSpacing.screenGutter,
        AppSpacing.sm,
      ),
      child: Semantics(
        header: true,
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.screenPadding,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }
}

/// List tile that opens a bottom sheet to pick one of [options].
class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(labelOf(value)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () async {
        final picked = await showModalBottomSheet<T>(
          context: context,
          useSafeArea: true,
          builder: (context) => SafeArea(
            top: false,
            child: RadioGroup<T>(
              groupValue: value,
              onChanged: (v) => Navigator.of(context).pop(v),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xxl,
                      0,
                      AppSpacing.xxl,
                      AppSpacing.sm,
                    ),
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  for (final option in options)
                    RadioListTile<T>(
                      value: option,
                      title: Text(labelOf(option)),
                    ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
          ),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}
