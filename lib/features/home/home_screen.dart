import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/routing/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/scan_document.dart';
import '../../shared/providers/library_providers.dart';
import '../../shared/widgets/app_logo.dart';
import '../../shared/widgets/document_card.dart';
import '../../shared/widgets/folder_card.dart';
import '../../shared/widgets/scanly_search_bar.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/state_views.dart';
import '../library/document_actions.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(documentsProvider(documentQuery(limit: 6)));
    final favorites = ref.watch(
      documentsProvider(documentQuery(favoritesOnly: true, limit: 10)),
    );
    final folders = ref.watch(foldersProvider);
    final count = ref.watch(documentCountProvider).value ?? 0;

    final favoriteList = favorites.value ?? const <ScanDocument>[];
    final folderList = folders.value ?? const [];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Header(documentCount: count)),
            SliverToBoxAdapter(
              child: Padding(
                padding: AppSpacing.screenPadding,
                child: ScanlySearchBar(onTap: () => context.go(Routes.search)),
              ),
            ),
            const SliverToBoxAdapter(child: _ScanHeroCard()),
            if (folderList.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Folders',
                  actionLabel: 'See all',
                  onAction: () => context.go(Routes.files),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 124,
                  child: ListView.separated(
                    padding: AppSpacing.screenPadding,
                    scrollDirection: Axis.horizontal,
                    itemCount: folderList.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.md),
                    itemBuilder: (context, i) => SizedBox(
                      width: 150,
                      child: FolderCard(
                        folder: folderList[i],
                        onTap: () =>
                            context.push(Routes.folder(folderList[i].id)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (favoriteList.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: SectionHeader(title: 'Favorites'),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 210,
                  child: ListView.separated(
                    padding: AppSpacing.screenPadding,
                    scrollDirection: Axis.horizontal,
                    itemCount: favoriteList.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.md),
                    itemBuilder: (context, i) => SizedBox(
                      width: 145,
                      child: DocumentCard(
                        document: favoriteList[i],
                        onTap: () =>
                            context.push(Routes.document(favoriteList[i].id)),
                        onLongPress: () =>
                            showDocumentActions(context, ref, favoriteList[i]),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: SectionHeader(
                title: 'Recent',
                actionLabel: count > 6 ? 'See all' : null,
                onAction: () => context.go(Routes.files),
              ),
            ),
            recent.when(
              data: (docs) => docs.isEmpty
                  ? const SliverToBoxAdapter(
                      child: EmptyState(
                        icon: Icons.document_scanner_outlined,
                        title: 'No documents yet',
                        message:
                            'Tap Scan to capture your first document. '
                            'Everything stays on this device.',
                        compact: true,
                      ),
                    )
                  : SliverPadding(
                      padding: AppSpacing.screenPadding,
                      sliver: SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 200,
                              mainAxisSpacing: AppSpacing.md,
                              crossAxisSpacing: AppSpacing.md,
                              childAspectRatio: 0.72,
                            ),
                        itemCount: docs.length,
                        itemBuilder: (context, i) => DocumentCard(
                          document: docs[i],
                          onTap: () =>
                              context.push(Routes.document(docs[i].id)),
                          onLongPress: () =>
                              showDocumentActions(context, ref, docs[i]),
                        ),
                      ),
                    ),
              loading: () => const SliverToBoxAdapter(child: LoadingState()),
              error: (error, _) => SliverToBoxAdapter(
                child: ErrorState(
                  error: error,
                  onRetry: () => ref.invalidate(
                    documentsProvider(documentQuery(limit: 6)),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.huge)),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.documentCount});

  final int documentCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.lg,
        AppSpacing.screenGutter,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppLogo(size: 32),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Scanly',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            greetingFor(DateTime.now()),
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            documentCount == 0
                ? 'Your documents stay private on this device.'
                : '${documentCount == 1 ? '1 document' : '$documentCount '
                            'documents'} stored on this device',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanHeroCard extends StatelessWidget {
  const _ScanHeroCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Solid navy in light mode; a softer navy container in dark mode so the
    // card does not glare against the dark background.
    final isDark = theme.brightness == Brightness.dark;
    final heroColor = isDark ? scheme.primaryContainer : scheme.primary;
    final onHero = isDark ? scheme.onPrimaryContainer : scheme.onPrimary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.xl,
        AppSpacing.screenGutter,
        0,
      ),
      child: Material(
        color: heroColor,
        borderRadius: AppRadius.xlAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(Routes.scan),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scan a document',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: onHero,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Auto edge detection, multi-page, PDF and OCR. '
                        'Free, no watermark.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: onHero.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: onHero.withValues(alpha: 0.14),
                    borderRadius: AppRadius.lgAll,
                  ),
                  child: Icon(
                    Icons.document_scanner_rounded,
                    color: onHero,
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
