import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/routing/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../domain/entities/search_result.dart';
import '../../shared/providers/core_providers.dart';
import '../../shared/widgets/scanly_search_bar.dart';
import '../../shared/widgets/state_views.dart';

final searchResultsProvider = FutureProvider.autoDispose
    .family<List<SearchResult>, String>(
      (ref, query) => ref.watch(searchRepositoryProvider).search(query),
    );

/// Local search over document titles, folder names and OCR text.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.xs,
              AppSpacing.screenGutter,
              AppSpacing.md,
            ),
            child: ScanlySearchBar(
              controller: _controller,
              onChanged: _onChanged,
              onClear: () => setState(() => _query = ''),
              hintText: 'Titles, folders or text inside scans',
            ),
          ),
          Expanded(
            child: _query.isEmpty
                ? const EmptyState(
                    icon: Icons.manage_search_rounded,
                    title: 'Search everything',
                    message:
                        'Find documents by name, folder, or words inside '
                        'scanned pages. Works in English and বাংলা, '
                        'fully offline.',
                  )
                : _Results(query: _query),
          ),
        ],
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(searchResultsProvider(query));
    return AsyncValueView(
      value: results,
      onRetry: () => ref.invalidate(searchResultsProvider(query)),
      data: (items) {
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.search_off_rounded,
            title: 'No results',
            message: 'Nothing matches "$query".',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: AppSpacing.huge),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(
            indent: AppSpacing.screenGutter,
            endIndent: AppSpacing.screenGutter,
          ),
          itemBuilder: (context, i) => _ResultTile(result: items[i]),
        );
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (IconData icon, String subtitle) = switch (result.kind) {
      SearchMatchKind.folder => (Icons.folder_rounded, 'Folder'),
      SearchMatchKind.title => (Icons.description_outlined, 'Document title'),
      SearchMatchKind.pageText => (
        Icons.text_snippet_outlined,
        'Page ${result.pageNumber}',
      ),
    };

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
        vertical: AppSpacing.xs,
      ),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.6),
          borderRadius: AppRadius.mdAll,
        ),
        child: Icon(icon, color: scheme.onPrimaryContainer, size: 20),
      ),
      title: Text(
        result.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle, style: theme.textTheme.labelSmall),
          if (result.kind == SearchMatchKind.pageText) ...[
            const SizedBox(height: AppSpacing.xxs),
            HighlightedSnippet(snippet: result.snippet),
          ],
        ],
      ),
      onTap: () {
        switch (result.kind) {
          case SearchMatchKind.folder:
            context.push(Routes.folder(result.folderId!));
          case SearchMatchKind.title:
            context.push(Routes.document(result.documentId!));
          case SearchMatchKind.pageText:
            context.push(
              Routes.document(result.documentId!, page: result.pageNumber),
            );
        }
      },
    );
  }
}

/// Renders an FTS snippet, emphasising the text between highlight markers.
class HighlightedSnippet extends StatelessWidget {
  const HighlightedSnippet({required this.snippet, super.key});

  final String snippet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodySmall;
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
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
