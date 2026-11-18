import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scanly/core/theme/app_theme.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/features/search/recent_searches.dart';
import 'package:scanly/features/search/search_screen.dart';
import 'package:scanly/shared/providers/core_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'search_test_data.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late SearchSeed seed;
  late SharedPreferences prefs;

  Future<void> setUpPrefs([List<String>? recents]) async {
    SharedPreferences.setMockInitialValues({
      RecentSearchesStore.storageKey: ?recents,
    });
    prefs = await SharedPreferences.getInstance();
  }

  setUp(() async {
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    seed = SearchSeed(db);
    await setUpPrefs();
  });

  tearDown(() => db.close().timeout(const Duration(seconds: 5)));

  /// Pumps the search screen in a small router whose document and folder
  /// routes just print where they were opened.
  Future<void> pumpSearch(WidgetTester tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SearchScreen()),
        GoRoute(
          path: '/document/:id',
          builder: (_, state) => Scaffold(
            body: Text(
              'document ${state.pathParameters['id']} '
              'page ${state.uri.queryParameters['page'] ?? '-'}',
            ),
          ),
        ),
        GoRoute(
          path: '/files/folder/:id',
          builder: (_, state) =>
              Scaffold(body: Text('folder ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      router.dispose();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> typeQuery(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  Finder chip(String name) => find.byKey(ValueKey('search-filter-$name'));
  Finder card(String id) => find.byKey(ValueKey('doc-$id'));

  testWidgets('groups page matches under one card and expands +N more', (
    tester,
  ) async {
    await seed.folder('f1', 'Bills');
    await seed.document(
      'd1',
      'Electricity statement',
      folderId: 'f1',
      pageTexts: {for (var n = 1; n <= 5; n++) n: 'invoice line $n'},
    );
    await seed.document('d2', 'Invoice archive');

    await pumpSearch(tester);
    await typeQuery(tester, 'invoice');

    expect(card('d1'), findsOneWidget);
    expect(card('d2'), findsOneWidget);
    expect(find.text('Electricity statement'), findsOneWidget);
    expect(find.textContaining('Bills ·'), findsOneWidget);
    expect(find.text('Text on 5 pages'), findsOneWidget);
    expect(find.text('Document title'), findsOneWidget);

    final inCard = find.descendant(of: card('d1'), matching: find.byType(Text));
    String texts() => tester
        .widgetList<Text>(inCard)
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .join('|');
    expect(texts(), contains('Page 3'));
    expect(texts(), isNot(contains('Page 4')));
    expect(find.text('+2 more pages'), findsOneWidget);

    await tester.tap(find.text('+2 more pages'));
    await tester.pumpAndSettle();

    expect(texts(), contains('Page 4'));
    expect(texts(), contains('Page 5'));
    expect(find.text('Show fewer pages'), findsOneWidget);
  });

  testWidgets('filter chips show counts and change the results', (
    tester,
  ) async {
    await seed.folder('f1', 'Receipts');
    await seed.document('t', 'Receipt from cafe');
    await seed.document('p', 'Scan 12', pageTexts: {1: 'Receipt total 450'});

    await pumpSearch(tester);
    await typeQuery(tester, 'receipt');

    String countOf(String name) => tester
        .widgetList<Text>(
          find.descendant(of: chip(name), matching: find.byType(Text)),
        )
        .last
        .data!;
    expect(countOf('all'), '3');
    expect(countOf('documents'), '1');
    expect(countOf('text'), '1');
    expect(countOf('folders'), '1');

    expect(find.byKey(const ValueKey('folder-f1')), findsOneWidget);
    expect(card('t'), findsOneWidget);
    expect(card('p'), findsOneWidget);

    await tester.tap(chip('documents'));
    await tester.pumpAndSettle();
    expect(card('t'), findsOneWidget);
    expect(card('p'), findsNothing);
    expect(find.byKey(const ValueKey('folder-f1')), findsNothing);

    await tester.tap(chip('text'));
    await tester.pumpAndSettle();
    expect(card('t'), findsNothing);
    expect(card('p'), findsOneWidget);
    expect(find.text('Page 1'), findsOneWidget);

    await tester.tap(chip('folders'));
    await tester.pumpAndSettle();
    expect(card('t'), findsNothing);
    expect(card('p'), findsNothing);
    expect(find.byKey(const ValueKey('folder-f1')), findsOneWidget);
  });

  testWidgets('an empty filter offers to show all results', (tester) async {
    await seed.document('t', 'Warranty card');

    await pumpSearch(tester);
    await typeQuery(tester, 'warranty');
    await tester.tap(chip('text'));
    await tester.pumpAndSettle();

    expect(find.text('No results'), findsOneWidget);
    await tester.tap(find.text('Show all results'));
    await tester.pumpAndSettle();
    expect(card('t'), findsOneWidget);
  });

  testWidgets('tapping a page row opens that page and saves the search', (
    tester,
  ) async {
    await seed.document(
      'd1',
      'Lease',
      pageTexts: {2: 'deposit amount', 4: 'deposit refund rules'},
    );

    await pumpSearch(tester);
    await typeQuery(tester, 'deposit');
    await tester.tap(find.text('Page 4'));
    await tester.pumpAndSettle();

    expect(find.text('document d1 page 4'), findsOneWidget);
    expect(RecentSearchesStore(prefs).load(), ['deposit']);
  });

  testWidgets('tapping the card opens the document', (tester) async {
    await seed.document('d1', 'Lease agreement');

    await pumpSearch(tester);
    await typeQuery(tester, 'lease');
    await tester.tap(find.text('Lease agreement'));
    await tester.pumpAndSettle();

    expect(find.text('document d1 page -'), findsOneWidget);
  });

  testWidgets('tapping a folder opens it', (tester) async {
    await seed.folder('f1', 'Medical');

    await pumpSearch(tester);
    await typeQuery(tester, 'medi');
    await tester.tap(find.byKey(const ValueKey('folder-f1')));
    await tester.pumpAndSettle();

    expect(find.text('folder f1'), findsOneWidget);
  });

  testWidgets('submitting saves searches that have results only', (
    tester,
  ) async {
    await seed.document('d1', 'Passport');

    await pumpSearch(tester);
    await tester.enterText(find.byType(TextField), 'nothing here');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(RecentSearchesStore(prefs).load(), isEmpty);

    await tester.enterText(find.byType(TextField), 'passport');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(RecentSearchesStore(prefs).load(), ['passport']);
  });

  testWidgets('recent searches appear, re-run and can be removed', (
    tester,
  ) async {
    await setUpPrefs(['tax', 'passport', 'receipt']);
    await seed.document('d1', 'Passport scan');

    await pumpSearch(tester);
    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('tax'), findsOneWidget);
    expect(find.text('passport'), findsOneWidget);

    // Re-run.
    await tester.tap(find.text('passport'));
    await tester.pumpAndSettle();
    expect(card('d1'), findsOneWidget);
    expect(find.text('Recent searches'), findsNothing);

    // Back to recents when the field is cleared.
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Recent searches'), findsOneWidget);

    // Remove with the close button.
    await tester.tap(find.byTooltip('Remove "tax"'));
    await tester.pumpAndSettle();
    expect(find.text('tax'), findsNothing);

    // Remove with a swipe.
    await tester.drag(find.text('receipt'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('receipt'), findsNothing);
    expect(RecentSearchesStore(prefs).load(), ['passport']);
  });

  testWidgets('Clear removes every recent search', (tester) async {
    await setUpPrefs(['tax', 'passport']);

    await pumpSearch(tester);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(find.text('Recent searches'), findsNothing);
    expect(find.text('Search everything'), findsOneWidget);
    expect(RecentSearchesStore(prefs).load(), isEmpty);
  });

  testWidgets('shows a note when results are capped', (tester) async {
    for (var i = 0; i < kSearchDocumentLimit + 2; i++) {
      await seed.document('d$i', 'Form $i');
    }

    await pumpSearch(tester);
    await typeQuery(tester, 'form');

    expect(find.text('$kSearchDocumentLimit+ documents'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('most relevant documents'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('Add more words'), findsOneWidget);
  });
}
