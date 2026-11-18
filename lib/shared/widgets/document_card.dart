import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/scan_document.dart';

/// First-page preview, or a neutral placeholder if no thumbnail exists yet.
class DocumentThumbnail extends StatelessWidget {
  const DocumentThumbnail({
    required this.document,
    this.borderRadius = AppRadius.mdAll,
    super.key,
  });

  final ScanDocument document;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = document.thumbnailPath;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainer,
      child: Center(
        child: Icon(
          Icons.description_outlined,
          color: scheme.outline,
          size: 28,
        ),
      ),
    );

    return ClipRRect(
      borderRadius: borderRadius,
      child: path == null
          ? placeholder
          : Image.file(
              File(path),
              fit: BoxFit.cover,
              // Decode at display size; never load a full-resolution page.
              cacheWidth: 360,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}

/// Grid card for a document.
class DocumentCard extends StatelessWidget {
  const DocumentCard({
    required this.document,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
    super.key,
  });

  final ScanDocument document;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      selected: selected,
      label: '${document.title}, ${pluralPages(document.pageCount)}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(
            color: selected ? scheme.secondary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.sm,
                        AppSpacing.sm,
                        AppSpacing.sm,
                        0,
                      ),
                      child: DocumentThumbnail(document: document),
                    ),
                    if (document.isFavorite)
                      const Positioned(
                        top: AppSpacing.md,
                        right: AppSpacing.md,
                        child: _FavoriteBadge(),
                      ),
                    if (selected)
                      Positioned(
                        top: AppSpacing.md,
                        left: AppSpacing.md,
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: scheme.secondary,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '${pluralPages(document.pageCount)} · '
                      '${formatRelativeDate(document.updatedAt)}',
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// List row for a document.
class DocumentListTile extends StatelessWidget {
  const DocumentListTile({
    required this.document,
    required this.onTap,
    this.onLongPress,
    this.onMore,
    this.selected = false,
    super.key,
  });

  final ScanDocument document;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMore;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListTile(
      selected: selected,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.5),
      onTap: onTap,
      onLongPress: onLongPress,
      leading: SizedBox(
        width: 44,
        height: 56,
        child: selected
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.secondary,
                  borderRadius: AppRadius.smAll,
                ),
                child: Icon(Icons.check_rounded, color: scheme.onSecondary),
              )
            : DocumentThumbnail(
                document: document,
                borderRadius: AppRadius.smAll,
              ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              document.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          if (document.isFavorite) ...[
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.star_rounded, size: 16, color: AppColors.amber),
          ],
        ],
      ),
      subtitle: Text(
        '${pluralPages(document.pageCount)} · '
        '${formatBytes(document.fileSize)} · '
        '${formatRelativeDate(document.updatedAt)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: onMore == null
          ? null
          : IconButton(
              tooltip: 'More options',
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: onMore,
            ),
    );
  }
}

class _FavoriteBadge extends StatelessWidget {
  const _FavoriteBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.star_rounded, size: 16, color: AppColors.amber),
    );
  }
}
