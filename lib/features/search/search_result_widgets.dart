import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/folder.dart';
import '../../domain/entities/search_result.dart';
import '../../shared/widgets/document_card.dart';

/// Page rows shown on a result card before "+N more pages".
const kCollapsedPageRows = 3;

/// Renders an FTS snippet, emphasising the text between highlight markers.
class HighlightedSnippet extends StatelessWidget {
  const HighlightedSnippet({
    required this.snippet,
    this.style,
    this.maxLines = 2,
    super.key,
  });

  final String snippet;

  /// Base style; defaults to `bodySmall`.
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = style ?? theme.textTheme.bodySmall;
    final highlight = base?.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w700,
      backgroundColor: AppColors.amber.withValues(alpha: 0.28),
    );

    final spans = <TextSpan>[];
    var rest = snippet;
    while (rest.isNotEmpty) {
      final start = rest.indexOf(SearchResult.highlightStart);
      if (start < 0) {
        spans.add(TextSpan(text: rest));
        break;
      }
      final end = rest.indexOf(SearchResult.highlightEnd, start);
      if (end < 0) {
        spans.add(
          TextSpan(text: rest.replaceAll(SearchResult.highlightStart, '')),
        );
        break;
      }
      if (start > 0) spans.add(TextSpan(text: rest.substring(0, start)));
      spans.add(
        TextSpan(text: rest.substring(start + 1, end), style: highlight),
      );
      rest = rest.substring(end + 1);
    }

    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Wraps every case-insensitive occurrence of [query] in [text] with
/// highlight markers (used for folder names, which are matched with LIKE).
String highlightSubstring(String text, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return text;
  final haystack = text.toLowerCase();
  // Lower-casing can change length for a few scripts; only highlight when
  // indexes still line up.
  if (haystack.length != text.length) return text;
  final out = StringBuffer();
  var from = 0;
  while (true) {
    final at = haystack.indexOf(needle, from);
    if (at < 0) break;
    out
      ..write(text.substring(from, at))
      ..write(SearchResult.highlightStart)
      ..write(text.substring(at, at + needle.length))
      ..write(SearchResult.highlightEnd);
    from = at + needle.length;
  }
  out.write(text.substring(from));
  return out.toString();
}

/// A matching folder.
class FolderResultTile extends StatelessWidget {
  const FolderResultTile({
    required this.folder,
    required this.query,
    required this.onTap,
    super.key,
  });

  final Folder folder;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = AppColors.folderColor(folder.colorIndex);
    final count = folder.documentCount;
    final countLabel = count == 1 ? '1 document' : '$count documents';

    return Semantics(
      button: true,
      label: 'Folder ${folder.name}, $countLabel',
      excludeSemantics: true,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
        ),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: AppRadius.mdAll,
          ),
          child: Icon(Icons.folder_rounded, color: color, size: 22),
        ),
        title: HighlightedSnippet(
          snippet: highlightSubstring(folder.name, query),
          style: theme.textTheme.titleSmall,
          maxLines: 1,
        ),
        subtitle: Text(countLabel),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

/// One document with its title match and matching pages.
class DocumentResultCard extends StatefulWidget {
  const DocumentResultCard({
    required this.hit,
    required this.onOpen,
    super.key,
  });

  final DocumentSearchHit hit;

  /// Opens the document, at a one-based page when [page] is given.
  final void Function({int? page}) onOpen;

  @override
  State<DocumentResultCard> createState() => _DocumentResultCardState();
}

class _DocumentResultCardState extends State<DocumentResultCard> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hit = widget.hit;
    final doc = hit.document;

    final pages = _expanded
        ? hit.pages
        : hit.pages.take(kCollapsedPageRows).toList();
    final hiddenPages = hit.pages.length - pages.length;
    final unloadedPages = hit.pageMatchCount - hit.pages.length;

    final meta = [
      hit.folderName ?? 'No folder',
      pluralPages(doc.pageCount),
      formatRelativeDate(doc.updatedAt),
    ].join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgAll,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: 'Open ${doc.title}',
            child: InkWell(
              onTap: () => widget.onOpen(),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 48,
                      height: 64,
                      child: DocumentThumbnail(
                        document: doc,
                        borderRadius: AppRadius.smAll,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          HighlightedSnippet(
                            snippet: hit.highlightedTitle ?? doc.title,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            meta,
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xs,
                            children: [
                              if (hit.titleMatched)
                                const _MatchTag(
                                  icon: Icons.title_rounded,
                                  label: 'Document title',
                                ),
                              if (hit.pageMatchCount > 0)
                                _MatchTag(
                                  icon: Icons.text_snippet_outlined,
                                  label: hit.pageMatchCount == 1
                                      ? 'Text on 1 page'
                                      : 'Text on ${hit.pageMatchCount} pages',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (pages.isNotEmpty) const Divider(height: 1),
          for (final page in pages)
            _PageRow(
              page: page,
              onTap: () => widget.onOpen(page: page.pageNumber),
            ),
          if (hiddenPages > 0)
            _ExpandButton(
              label: hiddenPages == 1
                  ? '+1 more page'
                  : '+$hiddenPages more pages',
              icon: Icons.expand_more_rounded,
              onPressed: () => setState(() => _expanded = true),
            )
          else if (_expanded && hit.pages.length > kCollapsedPageRows) ...[
            if (unloadedPages > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  0,
                ),
                child: Text(
                  'Showing the first ${hit.pages.length} of '
                  '${hit.pageMatchCount} matching pages.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            _ExpandButton(
              label: 'Show fewer pages',
              icon: Icons.expand_less_rounded,
              onPressed: () => setState(() => _expanded = false),
            ),
          ],
        ],
      ),
    );
  }
}

class _MatchTag extends StatelessWidget {
  const _MatchTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.6),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.pill)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onPrimaryContainer),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _PageRow extends StatelessWidget {
  const _PageRow({required this.page, required this.onTap});

  final PageSearchHit page;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: 'Open page ${page.pageNumber}',
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    'Page ${page.pageNumber}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: HighlightedSnippet(snippet: page.snippet)),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandButton extends StatelessWidget {
  const _ExpandButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: TextButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
        ),
      ),
    );
  }
}
