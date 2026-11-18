import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/routing/routes.dart';
import '../../core/theme/app_spacing.dart';

/// Root scaffold with Scanly's bottom navigation.
///
/// Four tabs are shell branches (Home, Files, Search, Settings). The centre
/// Scan action opens the full-screen scanner on top of the shell.
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: ScanlyBottomNav(
        currentIndex: navigationShell.currentIndex,
        onTabSelected: (index) => navigationShell.goBranch(
          index,
          // Tapping the active tab returns to its root.
          initialLocation: index == navigationShell.currentIndex,
        ),
        onScan: () => context.push(Routes.scan),
      ),
    );
  }
}

class _NavDestination {
  const _NavDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _NavDestination('Home', Icons.home_outlined, Icons.home_rounded),
  _NavDestination('Files', Icons.folder_outlined, Icons.folder_rounded),
  _NavDestination('Search', Icons.search_outlined, Icons.search_rounded),
  _NavDestination('Settings', Icons.settings_outlined, Icons.settings_rounded),
];

class ScanlyBottomNav extends StatelessWidget {
  const ScanlyBottomNav({
    required this.currentIndex,
    required this.onTabSelected,
    required this.onScan,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget tab(int index) => Expanded(
      child: _NavItem(
        destination: _destinations[index],
        selected: currentIndex == index,
        onTap: () => onTabSelected(index),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              tab(0),
              tab(1),
              Expanded(child: _ScanButton(onPressed: onScan)),
              tab(2),
              tab(3),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: AppDurations.fast,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? scheme.primaryContainer
                    : scheme.primaryContainer.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Icon(
                selected ? destination.selectedIcon : destination.icon,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              destination.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Semantics(
        button: true,
        label: 'Scan a document',
        excludeSemantics: true,
        child: Material(
          color: scheme.primary,
          shape: const CircleBorder(),
          elevation: 3,
          shadowColor: scheme.shadow.withValues(alpha: 0.35),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 56,
              child: Icon(
                Icons.document_scanner_rounded,
                color: scheme.onPrimary,
                size: 26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
