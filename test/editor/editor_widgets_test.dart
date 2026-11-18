import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingTerm, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:scanly/app.dart';
import 'package:scanly/core/routing/app_router.dart';
import 'package:scanly/core/routing/routes.dart';
import 'package:scanly/core/services/storage_service.dart';
import 'package:scanly/core/vision/quad.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/domain/entities/page_edits.dart';
import 'package:scanly/domain/entities/scan_page.dart';
import 'package:scanly/domain/usecases/edit_page.dart';
import 'package:scanly/shared/providers/core_providers.dart';
import 'package:scanly/shared/providers/scanner_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Storage whose async disk scans/deletes return immediately, so repository
/// calls complete inside widget tests' fake async zone.
class TestStorage extends StorageService {
  TestStorage(super.root);

  @override
  Future<int> sizeOf([Directory? directory]) async => 0;

  @override
  Future<void> deleteFile(String path) async {}

  @override
  Future<void> deleteDocumentFiles(String documentId) async {}
}

/// Records saves instead of rendering images.
class FakeEditPage implements EditPageUseCase {
  final saved = <PageEdits>[];
  final rotated = <String>[];

  @override
  Future<Uint8List> preview(
    ScanPage page,
    PageEdits edits, {
    int maxSide = 1200,
  }) async => tinyJpeg;

  @override
  Future<Quad?> detectCorners(ScanPage page) async =>
      Quad.fromList([0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9]);

  @override
  Future<void> save(
    ScanPage page,
    PageEdits edits, {
    int jpegQuality = 88,
  }) async => saved.add(edits);

  @override
  Future<void> rotate(ScanPage page, {bool clockwise = true}) async =>
      rotated.add(page.id);
}

final tinyJpeg = Uint8List.fromList(
  img.encodeJpg(img.Image(width: 4, height: 6)),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory sandbox;
  late TestStorage storage;
  late SharedPreferences prefs;
  late AppDatabase db;
  late FakeEditPage editPage;
  late String imagePath;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scanly_editor_ui');
    storage = TestStorage(Directory(p.join(sandbox.path, 'scanly')));
    await storage.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    editPage = FakeEditPage();
    imagePath = p.join(sandbox.path, 'page.jpg');
    File(imagePath).writeAsBytesSync(tinyJpeg);
  });

  tearDown(() async {
    await db.close().timeout(const Duration(seconds: 5));
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  Future<void> insertDocument(int pages) async {
    await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            id: 'doc',
            title: 'Lease',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        );
    for (var i = 0; i < pages; i++) {
      await db
          .into(db.pages)
          .insert(
            PagesCompanion.insert(
              id: 'p$i',
              documentId: 'doc',
              pageOrder: i,
              originalPath: imagePath,
              width: 400,
              height: 600,
              createdAt: DateTime(2026),
            ),
          );
    }
  }

  Future<void> open(WidgetTester tester, String location) async {
    final router = createRouter();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          storageServiceProvider.overrideWithValue(storage),
          appDatabaseProvider.overrideWithValue(db),
          editPageProvider.overrideWithValue(editPage),
          imageSizeProvider.overrideWith(
            (ref, path) async => (width: 400, height: 600),
          ),
          routerProvider.overrideWithValue(router),
        ],
        child: const ScanlyApp(),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(router.push(location));
    await tester.pumpAndSettle();
  }

  Finder iconButton(String tooltip) => find.ancestor(
    of: find.byTooltip(tooltip),
    matching: find.byType(IconButton),
  );

  group('page editor', () {
    testWidgets('filter change supports undo, redo and save', (tester) async {
      await insertDocument(1);
      await open(tester, Routes.editPage('doc', 'p0'));
      expect(find.text('Edit page'), findsOneWidget);

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Black & white'));
      await tester.pumpAndSettle();

      final undo = find.byTooltip('Undo');
      expect(
        tester.widget<IconButton>(iconButton('Undo')).onPressed,
        isNotNull,
      );
      await tester.tap(undo);
      await tester.pumpAndSettle();
      expect(
        tester.widget<IconButton>(iconButton('Redo')).onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip('Redo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(editPage.saved.single.filter, PageFilter.blackWhite);
      expect(find.text('Edit page'), findsNothing);
    });

    testWidgets('rotate and auto-detect update the crop', (tester) async {
      await insertDocument(1);
      await open(tester, Routes.editPage('doc', 'p0'));

      await tester.tap(find.text('Rotate right'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Auto detect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = editPage.saved.single;
      expect(saved.rotation, 90);
      expect(saved.corners.topLeft, const Pt(0.1, 0.1));
    });

    testWidgets('closing with changes asks before discarding', (tester) async {
      await insertDocument(1);
      await open(tester, Routes.editPage('doc', 'p0'));
      await tester.tap(find.text('Rotate left'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Close editor'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Edit page'), findsOneWidget);

      await tester.tap(find.byTooltip('Close editor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Edit page'), findsNothing);
      expect(editPage.saved, isEmpty);
    });

    testWidgets('adjust sliders change brightness', (tester) async {
      await insertDocument(1);
      await open(tester, Routes.editPage('doc', 'p0'));
      await tester.tap(find.text('Adjust'));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Slider).first, const Offset(80, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(editPage.saved.single.brightness, greaterThan(0));
    });
  });

  group('page organizer', () {
    testWidgets('shows pages and rotates from the page menu', (tester) async {
      await insertDocument(3);
      await open(tester, Routes.pages('doc'));
      expect(find.text('Pages (3)'), findsOneWidget);
      expect(find.bySemanticsLabel('Page 2'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Page 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rotate right'));
      await tester.pumpAndSettle();
      expect(editPage.rotated, ['p1']);
    });

    testWidgets('deletes a page after confirmation', (tester) async {
      await insertDocument(2);
      await open(tester, Routes.pages('doc'));

      await tester.tap(find.bySemanticsLabel('Page 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete page'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Pages (1)'), findsOneWidget);
      final pages = await db.select(db.pages).get();
      expect(pages.single.id, 'p1');
    });

    testWidgets('a single page cannot be deleted', (tester) async {
      await insertDocument(1);
      await open(tester, Routes.pages('doc'));
      await tester.tap(find.bySemanticsLabel('Page 1'));
      await tester.pumpAndSettle();
      expect(find.text('Delete page'), findsNothing);
    });

    testWidgets('dragging a page reorders the document', (tester) async {
      await insertDocument(3);
      await open(tester, Routes.pages('doc'));

      final first = tester.getCenter(find.bySemanticsLabel('Page 1'));
      final third = tester.getCenter(find.bySemanticsLabel('Page 3'));
      final gesture = await tester.startGesture(first);
      await tester.pump(const Duration(milliseconds: 700));
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(Offset.lerp(first, third, i / 10)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final order = await (db.select(
        db.pages,
      )..orderBy([(p) => OrderingTerm.asc(p.pageOrder)])).get();
      expect(order.map((p) => p.id), ['p1', 'p2', 'p0']);
    });
  });
}
