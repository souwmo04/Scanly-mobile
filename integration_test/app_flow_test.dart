// End-to-end flow on a real device or emulator, with the real services
// (platform image codec, PDF builder and renderer, ML Kit text recognition):
//
//   flutter test integration_test/app_flow_test.dart -d <device>
//
// The app runs against a fresh temporary storage folder, an in-memory
// database and in-memory preferences, so the user's own library on the
// device is never touched. See integration_test/README.md.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:scanly/app.dart';
import 'package:scanly/core/routing/app_router.dart';
import 'package:scanly/core/routing/routes.dart';
import 'package:scanly/core/services/storage_service.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/domain/entities/ocr_result.dart';
import 'package:scanly/domain/entities/scan_page.dart';
import 'package:scanly/domain/usecases/import_pages.dart';
import 'package:scanly/features/ocr/ocr_queue.dart';
import 'package:scanly/shared/providers/core_providers.dart';
import 'package:scanly/shared/providers/ocr_providers.dart';
import 'package:scanly/shared/providers/scanner_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const documentTitle = 'Integration flow';

/// Text of the two generated pages. Page 2 is never rotated, so its words
/// are what the search step looks for.
const page1Lines = ['RENTAL AGREEMENT', 'Landlord and tenant', 'Monthly rent'];
const page2Lines = ['ELECTRICITY INVOICE', 'Invoice number 4821', 'Total due'];
const searchWord = 'electricity';

/// Renders black text on a white A4 page (~150 dpi) with Flutter's own
/// renderer and saves it as a JPEG, like a clean scan.
Future<String> renderPageJpeg(
  Directory dir,
  String name,
  List<String> lines,
) async {
  const width = 1240;
  const height = 1754;
  const margin = 120.0;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawRect(
      const ui.Rect.fromLTWH(0, 0, width + 0.0, height + 0.0),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
  var y = margin;
  for (final line in lines) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 64))
      ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF000000)))
      ..addText(line);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: width - 2 * margin));
    canvas.drawParagraph(paragraph, ui.Offset(margin, y));
    y += paragraph.height + 48;
    paragraph.dispose();
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  try {
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final jpeg = img.encodeJpg(
      img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgba!.buffer,
        numChannels: 4,
      ),
      quality: 90,
    );
    final path = p.join(dir.path, '$name.jpg');
    await File(path).writeAsBytes(jpeg, flush: true);
    return path;
  } finally {
    image.dispose();
  }
}

/// Pumps frames until [finder] matches, or fails after [timeout]. Used
/// instead of `pumpAndSettle` where progress indicators keep animating while
/// real work (rendering, PDF, OCR) runs.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
  String? reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out after $timeout waiting for ${reason ?? finder}');
}

/// Pumps frames until [condition] holds, or fails after [timeout].
Future<void> pumpUntilTrue(
  WidgetTester tester,
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  required String reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (await condition()) return;
  }
  fail('Timed out after $timeout waiting for $reason');
}

/// `pumpAndSettle` with a bound, tolerating screens that never settle.
Future<void> settle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
  } on FlutterError {
    // Still animating (e.g. a spinner); the next step waits explicitly.
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory sandbox;
  late StorageService storage;
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scanly_app_flow');
    storage = StorageService(Directory(p.join(sandbox.path, 'scanly')));
    await storage.ensureInitialized();
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        storageServiceProvider.overrideWithValue(storage),
        appDatabaseProvider.overrideWithValue(db),
        // Never empty the device's real cache folder from a test.
        cacheDirectoryProvider.overrideWithValue(() async => null),
        availableCamerasProvider.overrideWithValue(
          () async => <CameraDescription>[],
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  testWidgets('scan to search to delete, with real services', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const ScanlyApp()),
    );
    addTearDown(() async {
      // Unmount first so Drift stream subscriptions end before the
      // database closes.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
    });
    await settle(tester);
    final documents = container.read(documentRepositoryProvider);
    final router = container.read(routerProvider);

    // 1. Home, empty library.
    expect(find.text('No documents yet'), findsOneWidget);

    // 2. Seed a document through the real import use case.
    final captures = Directory(p.join(sandbox.path, 'captures'))..createSync();
    final sources = [
      PageSource(await renderPageJpeg(captures, 'page1', page1Lines)),
      PageSource(await renderPageJpeg(captures, 'page2', page2Lines)),
    ];
    final documentId = await container
        .read(importPagesProvider)
        .call(sources, title: documentTitle);
    var pages = await documents.getPages(documentId);
    expect(pages, hasLength(2));
    for (final page in pages) {
      expect(File(page.originalPath).existsSync(), isTrue);
      expect(File(page.thumbnailPath!).existsSync(), isTrue);
    }

    // 3. Open it from the home screen.
    await pumpUntil(tester, find.text(documentTitle));
    await tester.tap(find.text(documentTitle).first);
    await settle(tester);
    await pumpUntil(tester, find.byTooltip('Edit page'));
    expect(find.textContaining('2 pages'), findsOneWidget);

    // 4. Edit page 1: rotate and apply a filter, then save.
    await tester.tap(find.byTooltip('Edit page'));
    await pumpUntil(tester, find.text('Rotate right'));
    await tester.tap(find.text('Rotate right'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Filters'));
    await settle(tester);
    await tester.tap(find.text('Black & white'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Save'));
    await pumpUntil(
      tester,
      find.byTooltip('Open PDF'),
      timeout: const Duration(seconds: 60),
      reason: 'the editor to save and close',
    );
    final edited = (await documents.getPages(documentId)).first;
    expect(edited.rotation, 90);
    expect(edited.filter, PageFilter.blackWhite);
    expect(edited.processedPath, isNotNull);
    expect(File(edited.processedPath!).existsSync(), isTrue);

    // 5. Generate the PDF through the viewer.
    await tester.tap(find.byTooltip('Open PDF'));
    await pumpUntil(
      tester,
      find.textContaining('of 2'),
      timeout: const Duration(seconds: 90),
      reason: 'the PDF to be generated and shown',
    );
    expect(File(storage.pdfPath(documentId)).existsSync(), isTrue);
    expect(File('${storage.pdfPath(documentId)}.meta').existsSync(), isTrue);
    await tester.pageBack();
    await pumpUntil(tester, find.byTooltip('More options'));

    // 6. Recognise the text in English with the real engine.
    await tester.tap(find.byTooltip('More options'));
    await settle(tester);
    await tester.tap(find.text('Recognize text'));
    await settle(tester);
    await tester.tap(find.text('English'));
    final ocr = container.read(ocrRepositoryProvider);
    await pumpUntilTrue(
      tester,
      () async {
        final statuses = [
          for (final page in pages) (await ocr.getForPage(page.id))?.status,
        ];
        final queue = container.read(ocrQueueProvider);
        return queue.currentPageId == null &&
            queue.queuedPageIds.isEmpty &&
            statuses.every((s) => s == OcrStatus.done || s == OcrStatus.failed);
      },
      timeout: const Duration(minutes: 2),
      reason: 'text recognition of both pages',
    );
    final page2Ocr = await ocr.getForPage(pages[1].id);
    expect(page2Ocr?.status, OcrStatus.done);
    expect(page2Ocr?.text.toLowerCase(), contains(searchWord));

    // ... and find it via search.
    router.go(Routes.search);
    await settle(tester);
    await tester.enterText(find.byType(TextField), searchWord);
    final hit = find.byKey(ValueKey('doc-$documentId'));
    await pumpUntil(tester, hit, reason: 'the search result');
    expect(find.text('No results'), findsNothing);

    // 7. Reorder pages in the organizer.
    await tester.tap(hit);
    await pumpUntil(tester, find.byTooltip('Pages'));
    await tester.tap(find.byTooltip('Pages'));
    await pumpUntil(tester, find.bySemanticsLabel('Page 2'));
    final first = tester.getCenter(find.bySemanticsLabel('Page 1'));
    final second = tester.getCenter(find.bySemanticsLabel('Page 2'));
    final gesture = await tester.startGesture(first);
    await tester.pump(const Duration(milliseconds: 800));
    for (var i = 1; i <= 20; i++) {
      await gesture.moveTo(
        Offset.lerp(first, second + const Offset(24, 0), i / 20)!,
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settle(tester);
    await pumpUntilTrue(
      tester,
      () async {
        final order = await documents.getPages(documentId);
        return order.first.id == pages[1].id;
      },
      timeout: const Duration(seconds: 10),
      reason: 'the new page order to be saved',
    );
    pages = await documents.getPages(documentId);
    expect(pages.map((p) => p.pageOrder), [0, 1]);
    await tester.pageBack();
    await pumpUntil(tester, find.byTooltip('More options'));

    // 8. Delete the document.
    await tester.tap(find.byTooltip('More options'));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(find.text('Delete document?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await pumpUntilTrue(
      tester,
      () async => await documents.getDocument(documentId) == null,
      reason: 'the document to be deleted',
    );
    expect(storage.documentDir(documentId).existsSync(), isFalse);
    final indexRows = await db
        .customSelect('SELECT COUNT(*) AS c FROM search_index')
        .getSingle();
    expect(indexRows.read<int>('c'), 0);

    router.go(Routes.home);
    await pumpUntil(tester, find.text('No documents yet'));
  });
}
