import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scanly/core/routing/routes.dart';
import 'package:scanly/domain/entities/app_settings.dart';
import 'package:scanly/domain/services/pdf_service.dart';

import 'ui_test_helpers.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late PdfTestApp app;

  setUp(() async {
    app = PdfTestApp();
    await app.setUp();
  });

  tearDown(() => app.tearDown());

  group('PDF viewer', () {
    testWidgets('shows progress, then lazily renders pages', (tester) async {
      await app.insertDocument('doc', title: 'Lease', pages: 8);
      app.pdf
        ..progress = (2, 8)
        ..gate = Completer<void>();
      await app.pump(tester, location: Routes.pdf('doc'));

      expect(find.text('Creating PDF… page 3 of 8'), findsOneWidget);
      expect(app.pdf.ensureCalls.single.force, isFalse);
      expect(app.pdf.ensureCalls.single.options, isNull);

      app.pdf.gate!.complete();
      await tester.pumpAndSettle();

      expect(find.text('Page 1 of 8'), findsOneWidget);
      expect(find.textContaining('PDF 2.0 KB'), findsOneWidget);
      expect(app.renderer.opened, [app.pdf.pathFor('doc')]);
      // Only the visible page and its neighbour, never the whole file.
      expect(app.renderer.rendered.toSet(), {0, 1});

      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 8'), findsOneWidget);
      expect(app.renderer.rendered.toSet(), {0, 1, 2});
    });

    testWidgets('opens at the requested page and jumps to a page', (
      tester,
    ) async {
      await app.insertDocument('doc', title: 'Lease', pages: 8);
      await app.pump(tester, location: Routes.pdf('doc', page: 3));
      expect(find.text('Page 3 of 8'), findsOneWidget);

      await tester.tap(find.text('Page 3 of 8'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '7');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.text('Page 7 of 8'), findsOneWidget);
      expect(app.renderer.rendered, containsAll([5, 6, 7]));
      expect(app.renderer.rendered, isNot(contains(0)));
    });

    testWidgets('error state retries', (tester) async {
      await app.insertDocument('doc', title: 'Lease', pages: 2);
      app.pdf.failuresLeft = 1;
      await app.pump(tester, location: Routes.pdf('doc'));

      expect(find.text('Not enough space for the PDF.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(app.pdf.ensureCalls, hasLength(2));
      expect(find.text('Page 1 of 2'), findsOneWidget);
    });

    testWidgets('share and print use the generated file', (tester) async {
      await app.insertDocument('doc', title: 'Lease', pages: 2);
      await app.pump(tester, location: Routes.pdf('doc'));

      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Print'));
      await tester.pumpAndSettle();

      final path = app.pdf.pathFor('doc');
      expect(app.share.shared.single.$1, [path]);
      expect(app.share.shared.single.$2, 'Lease');
      expect(app.share.printed.single, (path, 'Lease'));
    });

    testWidgets('without rasterization, sharing still works', (tester) async {
      app.renderer = FakeRenderer(available: false);
      await app.insertDocument('doc', title: 'Lease', pages: 2);
      await app.pump(tester, location: Routes.pdf('doc'));

      expect(find.text('Preview not available'), findsOneWidget);
      expect(app.renderer.rendered, isEmpty);
      await tester.tap(find.text('Share PDF'));
      await tester.pumpAndSettle();
      expect(app.share.shared.single.$1, [app.pdf.pathFor('doc')]);
    });

    testWidgets('export passes the chosen options and shares', (tester) async {
      await app.insertDocument('doc', title: 'Lease', pages: 2);
      await app.pump(tester, location: Routes.pdf('doc'));

      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();
      expect(find.text('Export PDF'), findsOneWidget);

      await tester.tap(find.text('Legal'));
      await tester.tap(find.text('Landscape'));
      await tester.tap(find.text('High'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export and share'));
      await tester.pumpAndSettle();

      final call = app.pdf.ensureCalls.last;
      expect(call.force, isTrue);
      expect(
        call.options,
        const PdfExportOptions(
          pageSize: PdfPageSize.legal,
          orientation: PdfOrientation.landscape,
          compression: ImageCompression.high,
        ),
      );
      expect(app.share.shared.single.$1, [app.pdf.pathFor('doc')]);
      expect(find.text('Page 1 of 2'), findsOneWidget);
    });

    testWidgets('export sheet is prefilled from settings', (tester) async {
      await app.prefs.setString('settings.pdf_page_size', 'letter');
      await app.prefs.setString('settings.pdf_orientation', 'portrait');
      await app.prefs.setString('settings.compression', 'low');
      await app.insertDocument('doc', title: 'Lease', pages: 1);
      await app.pump(tester, location: Routes.pdf('doc'));

      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export and share'));
      await tester.pumpAndSettle();

      expect(
        app.pdf.ensureCalls.last.options,
        const PdfExportOptions(
          pageSize: PdfPageSize.letter,
          orientation: PdfOrientation.portrait,
          compression: ImageCompression.low,
        ),
      );
    });
  });
}
