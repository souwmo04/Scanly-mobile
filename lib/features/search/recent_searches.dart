import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repositories/drift_search_repository.dart';
import '../../shared/providers/core_providers.dart';

/// Recently run searches, kept in shared preferences.
///
/// Most recent first, at most [limit] entries, without duplicates (compared
/// case-insensitively; the newest spelling wins).
class RecentSearchesStore {
  RecentSearchesStore(this._prefs);

  static const storageKey = 'search.recent';
  static const limit = 8;

  final SharedPreferences _prefs;

  List<String> load() {
    final stored = _prefs.getStringList(storageKey) ?? const <String>[];
    return _dedupe(stored).take(limit).toList();
  }

  /// Moves [query] to the top. Blank queries are ignored.
  Future<List<String>> add(String query) async {
    final text = DriftSearchRepository.normalizeQuery(query);
    if (text.isEmpty) return load();
    return _save(_dedupe([text, ...load()]));
  }

  Future<List<String>> remove(String query) async {
    final key = query.toLowerCase();
    return _save([
      for (final q in load())
        if (q.toLowerCase() != key) q,
    ]);
  }

  Future<List<String>> clear() async {
    await _prefs.remove(storageKey);
    return const [];
  }

  Future<List<String>> _save(List<String> items) async {
    final kept = items.take(limit).toList();
    await _prefs.setStringList(storageKey, kept);
    return kept;
  }

  static List<String> _dedupe(Iterable<String> items) {
    final seen = <String>{};
    return [
      for (final q in items)
        if (q.trim().isNotEmpty && seen.add(q.toLowerCase())) q,
    ];
  }
}

final recentSearchesStoreProvider = Provider<RecentSearchesStore>(
  (ref) => RecentSearchesStore(ref.watch(sharedPreferencesProvider)),
);

/// The recent searches list, updated as searches are saved or removed.
final recentSearchesProvider =
    NotifierProvider<RecentSearchesNotifier, List<String>>(
      RecentSearchesNotifier.new,
    );

class RecentSearchesNotifier extends Notifier<List<String>> {
  RecentSearchesStore get _store => ref.read(recentSearchesStoreProvider);

  @override
  List<String> build() => ref.watch(recentSearchesStoreProvider).load();

  Future<void> add(String query) async => state = await _store.add(query);

  /// Updates the list immediately (a dismissed row must leave the tree in
  /// the same frame), then persists.
  Future<void> remove(String query) async {
    final key = query.toLowerCase();
    state = [
      for (final q in state)
        if (q.toLowerCase() != key) q,
    ];
    await _store.remove(query);
  }

  Future<void> clear() async {
    state = const [];
    await _store.clear();
  }
}
