import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/routing/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/repositories/drift_search_repository.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/repositories/search_repository.dart';
import '../../shared/providers/core_providers.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/state_views.dart';
import 'recent_searches.dart';
import 'search_result_widgets.dart';

/// A grouped search: the normalised query and the active filter.
typedef SearchRequest = ({String query, SearchFilter filter});

/// Most documents shown for one search.
const kSearchDocumentLimit = 50;

final groupedSearchProvider = FutureProvider.autoDispose
    .family<GroupedSearchResults, SearchRequest>(
      (ref, request) => ref
          .watch(searchRepositoryProvider)
          .searchGrouped(
            request.query,
            filter: request.filter,
            documentLimit: kSearchDocumentLimit,
          ),
    );

/// Match counts for the filter chips; independent of the selected filter.
final searchCountsProvider = FutureProvider.autoDispose
    .family<SearchCounts, String>(
      (ref, query) => ref.watch(searchRepositoryProvider).countMatches(query),
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
  SearchFilter _filter = SearchFilter.all;

  /// Last loaded results, shown dimmed while the next ones load so the list
  /// doesn't flash on every keystroke.
  GroupedSearchResults? _lastResults;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _setQuery(value);
    });
  }

  void _setQuery(String value) {
    final query = DriftSearchRepository.normalizeQuery(value);
    if (query == _query) return;
    setState(() {
      _query = query;
      if (query.isEmpty) _lastResults = null;
    });
  }

  Future<void> _onSubmitted(String value) async {
    _debounce?.cancel();
    _setQuery(value);
    final query = _query;
    if (query.isEmpty) return;
    final counts = await ref.read(searchRepositoryProvider).countMatches(query);
    if (!mounted || counts.forFilter(_filter) == 0) return;
    await ref.read(recentSearchesProvider.notifier).add(query);
  }

  void _runRecent(String query) {
    _debounce?.cancel();
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _setQuery(query);
  }

  void _openDocument(String documentId, {int? page}) {
    unawaited(ref.read(recentSearchesProvider.notifier).add(_query));
    unawaited(context.push(Routes.document(documentId, page: page)));
  }

  void _openFolder(String folderId) {
    unawaited(ref.read(recentSearchesProvider.notifier).add(_query));
    unawaited(context.push(Routes.folder(folderId)));
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
              AppSpacing.sm,
            ),
            child: _SearchField(
              controller: _controller,
              onChanged: _onChanged,
              onSubmitted: _onSubmitted,
              onClear: () {
                _debounce?.cancel();
                _setQuery('');
              },
            ),
          ),
          if (_query.isNotEmpty)
            _FilterBar(
              query: _query,
              selected: _filter,
              onSelected: (filter) => setState(() => _filter = filter),
            ),
          Expanded(
            child: _query.isEmpty
                ? _RecentSearches(onRun: _runRecent)
                : _buildResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final request = (query: _query, filter: _filter);
    final async = ref.watch(groupedSearchProvider(request));
    if (async.hasValue) _lastResults = async.requireValue;

    if (async.hasError && !async.isLoading) {
      return ErrorState(
        error: async.error!,
        onRetry: () => ref.invalidate(groupedSearchProvider(request)),
      );
    }
    final shown = async.hasValue ? async.requireValue : _lastResults;
    if (shown == null) return const LoadingState();

    return Stack(
      children: [
        _ResultsList(
          results: shown,
          onOpenDocument: _openDocument,
          onOpenFolder: _openFolder,
          onShowAll: () => setState(() => _filter = SearchFilter.all),
        ),
        if (async.isLoading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}

/// Search input with submit support and a length limit.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      inputFormatters: [
        LengthLimitingTextInputFormatter(SearchRepository.maxQueryLength),
      ],
      decoration: InputDecoration(
        hintText: 'Titles, folders or text inside scans',
        prefixIcon: Icon(Icons.search_rounded, color: scheme.onSurfaceVariant),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    controller.clear();
                    onClear();
                  },
                ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 14,
        ),
      ),
    );
  }
}

/// All · Documents · Text · Folders, each with its number of matches.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({
    required this.query,
    required this.selected,
    required this.onSelected,
  });

  final String query;
  final SearchFilter selected;
  final ValueChanged<SearchFilter> onSelected;

  static String labelFor(SearchFilter filter) => switch (filter) {
    SearchFilter.all => 'All',
    SearchFilter.documents => 'Documents',
    SearchFilter.text => 'Text',
    SearchFilter.folders => 'Folders',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final counts = ref.watch(searchCountsProvider(query)).value;

    return SizedBox(
      height: AppSpacing.minTouchTarget,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
        ),
        children: [
          for (final filter in SearchFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Center(
                child: ChoiceChip(
                  key: ValueKey('search-filter-${filter.name}'),
                  selected: filter == selected,
                  showCheckmark: false,
                  onSelected: (_) => onSelected(filter),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(labelFor(filter)),
                      if (counts != null) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '${counts.forFilter(filter)}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.results,
    required this.onOpenDocument,
    required this.onOpenFolder,
    required this.onShowAll,
  });

  final GroupedSearchResults results;
  final void Function(String documentId, {int? page}) onOpenDocument;
  final ValueChanged<String> onOpenFolder;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      final filtered = results.filter != SearchFilter.all;
      final what = switch (results.filter) {
        SearchFilter.all => 'Nothing',
        SearchFilter.documents => 'No document title',
        SearchFilter.text => 'No text inside your scans',
        SearchFilter.folders => 'No folder',
      };
      return ListView(
        children: [
          EmptyState(
            icon: Icons.search_off_rounded,
            title: 'No results',
            message: '$what matches "${results.query}".',
            actionLabel: filtered ? 'Show all results' : null,
            onAction: filtered ? onShowAll : null,
          ),
        ],
      );
    }

    final theme = Theme.of(context);
    final query = results.query;
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.huge),
      children: [
        if (results.folders.isNotEmpty) ...[
          const SectionHeader(title: 'Folders'),
          for (final folder in results.folders)
            FolderResultTile(
              key: ValueKey('folder-${folder.id}'),
              folder: folder,
              query: query,
              onTap: () => onOpenFolder(folder.id),
            ),
        ],
        if (results.documents.isNotEmpty) ...[
          SectionHeader(
            title: results.documents.length == 1
                ? '1 document'
                : '${results.documents.length}'
                      '${results.isCapped ? '+' : ''} documents',
          ),
          for (final hit in results.documents)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenGutter,
                0,
                AppSpacing.screenGutter,
                AppSpacing.md,
              ),
              child: DocumentResultCard(
                key: ValueKey('doc-${hit.document.id}'),
                hit: hit,
                onOpen: ({page}) => onOpenDocument(hit.document.id, page: page),
              ),
            ),
        ],
        if (results.isCapped)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenGutter,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Showing the ${results.documents.length} most relevant '
                    'documents. Add more words to narrow the search.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Recent searches, shown while the field is empty.
class _RecentSearches extends ConsumerWidget {
  const _RecentSearches({required this.onRun});

  final ValueChanged<String> onRun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentSearchesProvider);
    final notifier = ref.read(recentSearchesProvider.notifier);

    if (recents.isEmpty) {
      return const EmptyState(
        icon: Icons.manage_search_rounded,
        title: 'Search everything',
        message:
            'Find documents by name, folder, or words inside scanned pages. '
            'Works in English and বাংলা, fully offline.',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.huge),
      children: [
        SectionHeader(
          title: 'Recent searches',
          actionLabel: 'Clear',
          onAction: () => unawaited(notifier.clear()),
        ),
        for (final query in recents)
          Dismissible(
            key: ValueKey('recent-$query'),
            onDismissed: (_) => unawaited(notifier.remove(query)),
            background: ColoredBox(
              color: Theme.of(context).colorScheme.errorContainer,
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.only(
                left: AppSpacing.screenGutter,
                right: AppSpacing.xs,
              ),
              leading: const Icon(Icons.history_rounded),
              title: Text(query, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => onRun(query),
              trailing: IconButton(
                tooltip: 'Remove "$query"',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => unawaited(notifier.remove(query)),
              ),
            ),
          ),
      ],
    );
  }
}
