import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/app_logo.dart';

/// Explains how Scanly handles data and why it asks for permissions.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.sm,
          AppSpacing.screenGutter,
          AppSpacing.huge,
        ),
        children: const [
          _InfoBlock(
            icon: Icons.phone_android_rounded,
            title: 'Your documents never leave your phone',
            body:
                'Scans, PDFs and recognized text are stored in Scanly\'s '
                'private app storage. Other apps cannot read them, and '
                'nothing is uploaded anywhere.',
          ),
          _InfoBlock(
            icon: Icons.memory_rounded,
            title: 'All processing happens on device',
            body:
                'Edge detection, enhancement, PDF creation and text '
                'recognition (English and Bangla) run locally. Scanly works '
                'in airplane mode.',
          ),
          _InfoBlock(
            icon: Icons.person_off_outlined,
            title: 'No account, ads or tracking',
            body:
                'There is no sign-up, no advertising SDK and no analytics. '
                'Scanly does not collect any personal data.',
          ),
          _InfoBlock(
            icon: Icons.photo_camera_outlined,
            title: 'Camera permission',
            body: 'Used only while the scanner is open, to capture documents.',
          ),
          _InfoBlock(
            icon: Icons.photo_library_outlined,
            title: 'Photos and files',
            body:
                'Accessed only when you choose to import an image or PDF. '
                'Scanly never browses your library on its own.',
          ),
          _InfoBlock(
            icon: Icons.ios_share_rounded,
            title: 'Sharing is always your choice',
            body:
                'Files leave Scanly only when you share or export them with '
                'your phone\'s share sheet.',
          ),
          _InfoBlock(
            icon: Icons.delete_sweep_outlined,
            title: 'Delete everything anytime',
            body:
                'Settings → Clear all data permanently removes every '
                'document. Uninstalling Scanly removes it too.',
          ),
        ],
      ),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const version = '0.6.0';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        children: [
          const SizedBox(height: AppSpacing.xxl),
          const Center(child: AppLogo(size: 72)),
          const SizedBox(height: AppSpacing.lg),
          Center(child: Text('Scanly', style: theme.textTheme.headlineSmall)),
          Center(
            child: Text('Version $version', style: theme.textTheme.bodySmall),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text(
            'A free, offline-first document scanner with Bangla and English '
            'text recognition. No subscriptions, no watermarks, no page '
            'limits and no account.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.code_rounded),
                  title: Text('Source code'),
                  subtitle: Text('github.com/souwmo04/Scanly-mobile'),
                ),
                const Divider(indent: 56),
                const ListTile(
                  leading: Icon(Icons.gavel_rounded),
                  title: Text('License'),
                  subtitle: Text('MIT'),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: const Text('Open-source licenses'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Scanly',
                    applicationVersion: version,
                    applicationIcon: const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: AppLogo(size: 48),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.6),
              borderRadius: AppRadius.mdAll,
            ),
            child: Icon(icon, color: scheme.onPrimaryContainer, size: 20),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
