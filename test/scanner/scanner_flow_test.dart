import 'dart:io';

import 'package:camera/camera.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:scanly/app.dart';
import 'package:scanly/core/errors/app_exception.dart';
import 'package:scanly/core/services/storage_service.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/domain/services/document_scanner.dart';
import 'package:scanly/domain/usecases/import_pages.dart';
import 'package:scanly/shared/providers/core_providers.dart';
import 'package:scanly/shared/providers/scanner_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeScanner implements DocumentScanner {
  FakeScanner(this.result, {this.isSupported = true});

  final ScanResult result;
  int calls = 0;

  @override
  final bool isSupported;

  @override
  Future<ScanResult> scan({
    required int pageLimit,
    required bool allowGalleryImport,
  }) async {
    calls++;
    return result;
  }
}

class FakePicker implements GalleryPicker {
  FakePicker(this.paths);

  final List<String> paths;

  @override
  Future<List<String>> pickImages() async => paths;
}

/// Records calls and inserts a document row directly, so the UI flow can be
/// tested without real image decoding (covered in import_pages_test.dart).
class FakeImport implements ImportPagesUseCase {
  FakeImport(this.db, {this.fail = false});

  final AppDatabase db;
  final bool fail;
  final List<List<String>> calls = [];

  @override
  Future<String> call(
    List<String> sourcePaths, {
    required String title,
    String? folderId,
    bool deleteSources = false,
    ImportProgress? onProgress,
  }) async {
    calls.add(sourcePaths);
    if (fail) throw const StorageException('Disk full.');
    onProgress?.call(sourcePaths.length, sourcePaths.length);
    final id = 'doc${calls.length}';
    await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            id: id,
            title: title,
            pageCount: Value(sourcePaths.length),
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        );
    return id;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory sandbox;
  late StorageService storage;
  late SharedPreferences prefs;
  late AppDatabase db;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scanly_flow_test');
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

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    required DocumentScanner scanner,
    required ImportPagesUseCase importer,
    GalleryPicker? picker,
    Future<List<CameraDescription>> Function()? cameras,
  }) async {
    addTearDown(() => unmount(tester));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          storageServiceProvider.overrideWithValue(storage),
          appDatabaseProvider.overrideWithValue(db),
          documentScannerProvider.overrideWithValue(scanner),
          importPagesProvider.overrideWithValue(importer),
          galleryPickerProvider.overrideWithValue(
            picker ?? FakePicker(const []),
          ),
          availableCamerasProvider.overrideWithValue(
            cameras ?? () async => <CameraDescription>[],
          ),
        ],
        child: const ScanlyApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openScanner(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Scan a document').first);
    await tester.pumpAndSettle();
  }

  testWidgets('completed ML Kit scan is saved and opened', (tester) async {
    final importer = FakeImport(db);
    final scanner = FakeScanner(
      const ScanResult.completed(['/a.jpg', '/b.jpg']),
    );
    await pumpApp(tester, scanner: scanner, importer: importer);

    await openScanner(tester);

    expect(scanner.calls, 1);
    expect(importer.calls.single, ['/a.jpg', '/b.jpg']);
    // Document screen replaced the scanner.
    expect(find.textContaining('Scan '), findsWidgets);
    expect(find.textContaining('2 pages'), findsOneWidget);
  });

  testWidgets('cancelled scan returns to where it started', (tester) async {
    final importer = FakeImport(db);
    await pumpApp(
      tester,
      scanner: FakeScanner(const ScanResult.cancelled()),
      importer: importer,
    );

    await openScanner(tester);

    expect(importer.calls, isEmpty);
    expect(find.text('No documents yet'), findsOneWidget);
    expect(find.text('Scan cancelled'), findsOneWidget);

    // The snackbar offers the built-in camera (e.g. when Google's scanner
    // module failed to download).
    await tester.tap(find.text('Use camera'));
    await tester.pumpAndSettle();
    expect(find.text('No camera found'), findsOneWidget);
  });

  testWidgets('built-in camera setting skips Google scanner', (tester) async {
    await prefs.setString('settings.scanner_engine', 'builtInCamera');
    final scanner = FakeScanner(const ScanResult.cancelled());
    await pumpApp(tester, scanner: scanner, importer: FakeImport(db));

    await openScanner(tester);

    expect(scanner.calls, 0);
    expect(find.byTooltip('Close scanner'), findsOneWidget);
  });

  testWidgets('unavailable ML Kit falls back to the built-in camera', (
    tester,
  ) async {
    await pumpApp(
      tester,
      scanner: FakeScanner(const ScanResult.unavailable('no play services')),
      importer: FakeImport(db),
    );

    await openScanner(tester);

    expect(find.textContaining('Using the built-in camera'), findsOneWidget);
    // No camera plugin in tests, so the camera shows its recovery options.
    expect(find.text('Import photos'), findsOneWidget);
  });

  testWidgets('unsupported platform goes straight to the camera', (
    tester,
  ) async {
    final scanner = FakeScanner(
      const ScanResult.cancelled(),
      isSupported: false,
    );
    await pumpApp(tester, scanner: scanner, importer: FakeImport(db));

    await openScanner(tester);

    expect(scanner.calls, 0);
    expect(find.byTooltip('Close scanner'), findsOneWidget);
  });

  testWidgets('camera permission denial explains how to recover', (
    tester,
  ) async {
    await pumpApp(
      tester,
      scanner: FakeScanner(const ScanResult.cancelled(), isSupported: false),
      importer: FakeImport(db),
      cameras: () async =>
          throw CameraException('CameraAccessDenied', 'User denied access'),
    );

    await openScanner(tester);

    expect(find.text('Camera access is off'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Import photos'), findsOneWidget);
  });

  testWidgets('camera screen can import photos and save them', (tester) async {
    final importer = FakeImport(db);
    await pumpApp(
      tester,
      scanner: FakeScanner(const ScanResult.cancelled(), isSupported: false),
      importer: importer,
      picker: FakePicker(['/g1.jpg', '/g2.jpg']),
    );
    await openScanner(tester);

    await tester.tap(find.text('Import photos'));
    await tester.pumpAndSettle();
    expect(find.text('2 pages'), findsOneWidget);

    await tester.tap(find.text('Done (2)'));
    await tester.pumpAndSettle();

    expect(importer.calls.single, ['/g1.jpg', '/g2.jpg']);
    expect(find.textContaining('2 pages'), findsOneWidget);
  });

  testWidgets('save failure offers retry and discard', (tester) async {
    await pumpApp(
      tester,
      scanner: FakeScanner(const ScanResult.completed(['/a.jpg'])),
      importer: FakeImport(db, fail: true),
    );

    await openScanner(tester);

    expect(find.text('The scan could not be saved'), findsOneWidget);
    expect(find.text('Disk full.'), findsOneWidget);

    await tester.tap(find.text('Discard scan'));
    await tester.pumpAndSettle();
    expect(find.text('No documents yet'), findsOneWidget);
  });

  testWidgets('home import saves picked photos and opens them', (tester) async {
    final importer = FakeImport(db);
    await pumpApp(
      tester,
      scanner: FakeScanner(const ScanResult.cancelled()),
      importer: importer,
      picker: FakePicker(['/p1.jpg', '/p2.jpg', '/p3.jpg']),
    );

    await tester.tap(find.text('Import from photos'));
    await tester.pumpAndSettle();

    expect(importer.calls.single, hasLength(3));
    expect(find.textContaining('3 pages'), findsOneWidget);
  });

  testWidgets('cancelling the photo picker does nothing', (tester) async {
    final importer = FakeImport(db);
    await pumpApp(
      tester,
      scanner: FakeScanner(const ScanResult.cancelled()),
      importer: importer,
    );

    await tester.tap(find.text('Import from photos'));
    await tester.pumpAndSettle();

    expect(importer.calls, isEmpty);
    expect(find.text('No documents yet'), findsOneWidget);
  });
}
