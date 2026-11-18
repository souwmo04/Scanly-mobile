import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanly/features/search/recent_searches.dart';
import 'package:scanly/shared/providers/core_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late RecentSearchesStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = RecentSearchesStore(prefs);
  });

  test('starts empty', () {
    expect(store.load(), isEmpty);
  });

  test('keeps the most recent first and persists', () async {
    await store.add('tax');
    await store.add('passport');
    await store.add('receipt');

    expect(store.load(), ['receipt', 'passport', 'tax']);
    expect(RecentSearchesStore(prefs).load(), ['receipt', 'passport', 'tax']);
  });

  test('de-duplicates case-insensitively, moving the entry up', () async {
    await store.add('tax');
    await store.add('passport');
    await store.add('  TAX  ');

    expect(store.load(), ['TAX', 'passport']);
  });

  test('keeps at most 8 searches', () async {
    for (var i = 1; i <= 10; i++) {
      await store.add('query $i');
    }

    final items = store.load();
    expect(items, hasLength(RecentSearchesStore.limit));
    expect(items.first, 'query 10');
    expect(items.last, 'query 3');
  });

  test('ignores blank searches', () async {
    await store.add('   ');
    expect(store.load(), isEmpty);
  });

  test('removes one search and clears all', () async {
    await store.add('a');
    await store.add('b');
    await store.add('c');

    expect(await store.remove('B'), ['c', 'a']);
    expect(store.load(), ['c', 'a']);

    expect(await store.clear(), isEmpty);
    expect(store.load(), isEmpty);
    expect(prefs.getStringList(RecentSearchesStore.storageKey), isNull);
  });

  test('notifier mirrors the store', () async {
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(recentSearchesProvider.notifier);

    await notifier.add('one');
    await notifier.add('two');
    expect(container.read(recentSearchesProvider), ['two', 'one']);

    await notifier.remove('one');
    expect(container.read(recentSearchesProvider), ['two']);
    expect(store.load(), ['two']);

    await notifier.clear();
    expect(container.read(recentSearchesProvider), isEmpty);
  });
}
