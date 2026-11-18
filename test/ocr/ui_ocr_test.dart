import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scanly/core/routing/routes.dart';
import 'package:scanly/domain/entities/app_settings.dart';
import 'package:scanly/domain/entities/ocr_result.dart';
import 'package:scanly/shared/providers/ocr_providers.dart';

import 'pipeline_fakes.dart';
import 'ui_helpers.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late OcrTestApp app;

  setUp(() async {
    app = OcrTestApp();
    await app.setUp();
  });

  tearDown(() => app.tearDown());

  OcrResult result(String text, {String code = 'eng'}) => OcrResult(
    text: text,
    lines: [OcrLine(text)],
    languageCode: code,
    engine: OcrEngineId.tesseract,
  );

  Future<OcrStatus?> statusOf(String pageId) async =>
      (await app.container.read(ocrRepositoryProvider).getForPage(pageId))
          ?.status;

  group('document screen status', () {
    testWidgets('shows progress while recognizing, then done', (tester) async {
      final pages = await insertDocument(app.db, 'doc');
      await app.pump(tester, location: Routes.document('doc'));
      expect(find.textContaining('Recognizing'), findsNothing);
      expect(find.text('Text recognized'), findsNothing);

      app.engine.gate = Completer<void>();
      await app.queue.enqueuePages(pages);
      await tester.pumpAndSettle();
      expect(find.text('Recognizing text… 0/3'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);

      app.engine.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Text recognized'), findsOneWidget);
      expect(app.engine.maxConcurrent, 1);
    });

    testWidgets('failure offers retry that recognizes the failed page', (
      tester,
    ) async {
      final pages = await insertDocument(app.db, 'doc');
      app.engine.failures.add(imagePathOf(pages[2]));
      await app.pump(tester, location: Routes.document('doc'));
      await app.queue.enqueuePages(pages);
      await tester.pumpAndSettle();
      expect(find.text('Text recognition failed on 1 page'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Text recognized'), findsOneWidget);
      expect(app.engine.calls.last.$1, imagePathOf(pages[2]));
    });

    testWidgets('Recognize text runs every page in the chosen language', (
      tester,
    ) async {
      final pages = await insertDocument(app.db, 'doc', pages: 2);
      await app.pump(tester, location: Routes.document('doc'));

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recognize text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('বাংলা (Bangla)'));
      await tester.pumpAndSettle();

      expect(app.engine.calls.map((c) => c.$1), pages.map(imagePathOf));
      expect(app.engine.calls.map((c) => c.$2).toSet(), {OcrLanguage.bangla});
      expect(find.text('Text recognized'), findsOneWidget);
    });
  });

  group('OCR text screen', () {
    testWidgets('shows selectable text and copies it', (tester) async {
      final pages = await insertDocument(app.db, 'doc', pages: 2);
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await app.pump(tester);
      await app.container
          .read(ocrRepositoryProvider)
          .saveResult(pages[1], result('Monthly rent\nশুভ নববর্ষ'));
      unawaitedPush(app, Routes.pageText('doc', pages[1]));
      await tester.pumpAndSettle();

      expect(find.text('Page 2 text'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.text('Monthly rent\nশুভ নববর্ষ'), findsOneWidget);
      expect(find.text('Recognized as English'), findsOneWidget);

      await tester.tap(find.byTooltip('Copy all'));
      await tester.pumpAndSettle();
      expect(copied, ['Monthly rent\nশুভ নববর্ষ']);
      expect(find.text('Text copied'), findsOneWidget);
    });

    testWidgets('re-runs the page in another language', (tester) async {
      final pages = await insertDocument(app.db, 'doc', pages: 1);
      app.engine.texts[imagePathOf(pages[0])] = 'আমার সোনার বাংলা';
      await app.pump(tester);
      await app.container
          .read(ocrRepositoryProvider)
          .saveResult(pages[0], result('garbled'));
      unawaitedPush(app, Routes.pageText('doc', pages[0]));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Recognize again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bangla + English'));
      await tester.pumpAndSettle();

      expect(app.engine.calls.single.$2, OcrLanguage.mixed);
      expect(find.text('আমার সোনার বাংলা'), findsOneWidget);
      expect(find.text('Recognized as Bangla + English'), findsOneWidget);
    });

    testWidgets('failed page shows the error and retries', (tester) async {
      final pages = await insertDocument(app.db, 'doc', pages: 1);
      await app.pump(tester);
      await app.container
          .read(ocrRepositoryProvider)
          .markFailed(pages[0], 'The OCR model could not be loaded.');
      unawaitedPush(app, Routes.pageText('doc', pages[0]));
      await tester.pumpAndSettle();

      expect(find.text('Text recognition failed'), findsOneWidget);
      expect(find.text('The OCR model could not be loaded.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(await statusOf(pages[0]), OcrStatus.done);
      expect(find.text('text of ${imagePathOf(pages[0])}'), findsOneWidget);
    });

    testWidgets('empty, pending and unrecognized states', (tester) async {
      final pages = await insertDocument(app.db, 'doc', pages: 2);
      await app.pump(tester);
      unawaitedPush(app, Routes.pageText('doc', pages[0]));
      await tester.pumpAndSettle();
      expect(find.text('Text not recognized yet'), findsOneWidget);

      await app.container.read(ocrRepositoryProvider).markPending([pages[0]]);
      await tester.pumpAndSettle();
      expect(find.text('Text recognition paused'), findsOneWidget);

      await app.container
          .read(ocrRepositoryProvider)
          .saveResult(pages[0], result('   '));
      await tester.pumpAndSettle();
      expect(find.text('No text found on this page'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byIcon(Icons.copy_rounded),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
    });
  });

  group('in-document search', () {
    Future<void> seedText(List<String> pages) async {
      final repo = app.container.read(ocrRepositoryProvider);
      await repo.saveResult(pages[0], result('Cover letter'));
      await repo.saveResult(pages[1], result('Terms and conditions'));
      await repo.saveResult(pages[2], result('Total INVOICE amount'));
    }

    testWidgets('document screen jumps to the matching page', (tester) async {
      final pages = await insertDocument(app.db, 'doc');
      await app.pump(tester, location: Routes.document('doc'));
      await seedText(pages);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search text'));
      await tester.pumpAndSettle();
      expect(find.text('Search this document'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'nothing-like-this');
      await tester.pumpAndSettle();
      expect(find.text('No matches'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'invoice');
      await tester.pumpAndSettle();
      expect(find.text('Page 3'), findsOneWidget);

      await tester.tap(find.text('Page 3'));
      await tester.pumpAndSettle();
      expect(find.text('Page 3 of 3'), findsOneWidget);
    });

    testWidgets('without text it offers to recognize the document', (
      tester,
    ) async {
      await insertDocument(app.db, 'doc', pages: 2);
      await app.pump(tester, location: Routes.documentSearch('doc'));
      expect(find.text('No recognized text'), findsOneWidget);

      await tester.tap(find.text('Recognize text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(app.engine.calls, hasLength(2));
      expect(find.text('Search this document'), findsOneWidget);
    });

    testWidgets('PDF viewer jumps to the matching page', (tester) async {
      final pages = await insertDocument(app.db, 'doc');
      await app.pump(tester, location: Routes.pdf('doc'));
      await seedText(pages);
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 3'), findsOneWidget);

      await tester.tap(find.byTooltip('Search text'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'terms');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Page 2'));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 3'), findsOneWidget);
    });
  });

  group('triggers', () {
    testWidgets('a saved scan is recognized when auto OCR is on', (
      tester,
    ) async {
      await app.pump(tester, scans: ['/a.jpg', '/b.jpg']);
      unawaitedPush(app, Routes.scan);
      await tester.pumpAndSettle();

      expect(app.engine.calls.map((c) => c.$1), [
        imagePathOf('scan1-p0'),
        imagePathOf('scan1-p1'),
      ]);
      expect(await statusOf('scan1-p1'), OcrStatus.done);
      expect(find.text('Text recognized'), findsOneWidget);
    });

    testWidgets('appended pages are recognized, existing ones are not', (
      tester,
    ) async {
      await insertDocument(app.db, 'doc', pages: 2);
      await app.pump(tester, scans: ['/c.jpg']);
      unawaitedPush(app, Routes.scanAppend('doc'));
      await tester.pumpAndSettle();
      expect(app.engine.calls.map((c) => c.$1), [imagePathOf('doc-p2')]);
    });

    testWidgets('a retaken page is recognized again', (tester) async {
      await insertDocument(app.db, 'doc', pages: 2);
      await app.pump(tester, scans: ['/r.jpg']);
      unawaitedPush(app, Routes.scanRetake('doc-p1'));
      await tester.pumpAndSettle();
      expect(app.engine.calls.map((c) => c.$1), [imagePathOf('doc-p1')]);
    });

    testWidgets('nothing is recognized when auto OCR is off', (tester) async {
      await app.prefs.setBool('settings.auto_ocr', false);
      await app.pump(tester, scans: ['/a.jpg']);
      unawaitedPush(app, Routes.scan);
      await tester.pumpAndSettle();

      expect(find.text('Page 1 of 1'), findsOneWidget);
      expect(app.engine.calls, isEmpty);
      expect(await statusOf('scan1-p0'), isNull);
    });
  });
}

void unawaitedPush(OcrTestApp app, String location) {
  // A pushed route only completes when it is closed.
  app.router.push<Object?>(location).ignore();
}
