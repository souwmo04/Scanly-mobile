import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:scanly/app.dart';
import 'package:scanly/core/services/storage_service.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/shared/providers/core_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory sandbox;
  late StorageService storage;
  late SharedPreferences prefs;
  late AppDatabase db;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scanly_widget_test');
    storage = StorageService(Directory(p.join(sandbox.path, 'scanly')));
    await storage.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forExecutor(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close().timeout(const Duration(seconds: 5));
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  /// Unmounts the app so Drift stream subscriptions are cancelled before the
  /// database closes (otherwise pending timers fail or hang the test).
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> pumpApp(WidgetTester tester) async {
    // Registered first so it also runs when an expectation fails.
    addTearDown(() => unmount(tester));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          storageServiceProvider.overrideWithValue(storage),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const ScanlyApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('home shows brand, scan card and empty state', (tester) async {
    await pumpApp(tester);

    expect(find.text('Scanly'), findsOneWidget);
    expect(find.text('Scan a document'), findsOneWidget);
    expect(find.text('No documents yet'), findsOneWidget);
    for (final label in ['Home', 'Files', 'Search', 'Settings']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('bottom navigation switches tabs', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(find.text('All documents'), findsOneWidget);

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.text('Search everything'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Scan quality'), findsOneWidget);
  });

  testWidgets('scan button opens the full-screen scanner', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.bySemanticsLabel('Scan a document').first);
    await tester.pumpAndSettle();
    expect(find.text('Scanner not available in this build'), findsOneWidget);

    await tester.tap(find.byTooltip('Close scanner'));
    await tester.pumpAndSettle();
    expect(find.text('No documents yet'), findsOneWidget);
  });

  testWidgets('dark theme setting applies and persists', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('Scan quality'));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(prefs.getString('settings.theme_mode'), 'dark');
  });

  testWidgets('creating a folder shows it in Files', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Receipts');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Receipts'), findsOneWidget);
    expect(find.text('0 documents'), findsOneWidget);
  });

  testWidgets('search finds a saved document by title', (tester) async {
    await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            id: 'doc1',
            title: 'Electricity bill',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        );
    await db.indexDocumentTitle('doc1', 'Electricity bill');

    await pumpApp(tester);
    expect(find.text('Electricity bill'), findsOneWidget);

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'elec');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Document title'), findsOneWidget);
  });
}
