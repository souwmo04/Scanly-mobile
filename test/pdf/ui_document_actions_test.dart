import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scanly/core/routing/routes.dart';
import 'package:scanly/shared/widgets/document_card.dart';

import 'ui_test_helpers.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late PdfTestApp app;

  setUp(() async {
    app = PdfTestApp();
    await app.setUp(prefsValues: {'library.layout': 'list'});
  });

  tearDown(() => app.tearDown());

  Future<void> openMenu(WidgetTester tester, String item) async {
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  group('document screen', () {
    testWidgets('PDF button opens the viewer at the current page', (
      tester,
    ) async {
      await app.insertDocument('doc', title: 'Lease', pages: 3);
      await app.pump(tester, location: Routes.document('doc', page: 2));

      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();

      expect(app.pdf.ensureCalls.single.documentId, 'doc');
      expect(find.text('Page 2 of 3'), findsOneWidget);
      expect(find.byTooltip('Export'), findsOneWidget);
    });

    testWidgets('Share PDF and Print create the PDF first', (tester) async {
      await app.insertDocument('doc', title: 'Lease', pages: 2);
      await app.pump(tester, location: Routes.document('doc'));

      await openMenu(tester, 'Share PDF');
      await openMenu(tester, 'Print');

      final path = app.pdf.pathFor('doc');
      expect(app.pdf.ensureCalls, hasLength(2));
      expect(app.share.shared.single.$1, [path]);
      expect(app.share.shared.single.$2, 'Lease');
      expect(app.share.printed.single, (path, 'Lease'));
      // Progress dialog closed again.
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('PDF failure is reported without sharing', (tester) async {
      await app.insertDocument('doc', title: 'Lease', pages: 2);
      app.pdf.failuresLeft = 1;
      await app.pump(tester, location: Routes.document('doc'));

      await openMenu(tester, 'Share PDF');

      expect(app.share.shared, isEmpty);
      expect(find.textContaining('Not enough space'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('split passes the chosen part starts', (tester) async {
      // Tall enough for every page of the split sheet.
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await app.insertDocument('doc', title: 'Lease', pages: 8);
      await app.pump(tester, location: Routes.document('doc'));

      await openMenu(tester, 'Split document');
      expect(find.text('Choose split points'), findsOneWidget);

      for (final after in [3, 5]) {
        await tester.tap(find.byKey(ValueKey('split-after-$after')));
        await tester.pumpAndSettle();
      }
      expect(find.text('Pages 1–3, 4–5, 6–8'), findsOneWidget);

      await tester.tap(find.text('Split into 3 documents'));
      await tester.pumpAndSettle();

      expect(app.pdf.splitCalls.single.$1, 'doc');
      expect(app.pdf.splitCalls.single.$2, [3, 5]);
      expect(find.text('Split into 3 documents'), findsOneWidget);
    });

    testWidgets('single-page documents cannot be split', (tester) async {
      await app.insertDocument('doc', title: 'Lease', pages: 1);
      await app.pump(tester, location: Routes.document('doc'));

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      expect(find.text('Split document'), findsNothing);
      expect(find.text('Share PDF'), findsOneWidget);
    });
  });

  group('merge', () {
    testWidgets('merges selected documents in display order', (tester) async {
      // Newest first in the library: Alpha, Beta, Gamma.
      await app.insertDocument(
        'a',
        title: 'Alpha',
        pages: 1,
        updatedAt: DateTime(2026, 3),
      );
      await app.insertDocument(
        'b',
        title: 'Beta',
        pages: 1,
        updatedAt: DateTime(2026, 2),
      );
      await app.insertDocument(
        'c',
        title: 'Gamma',
        pages: 1,
        updatedAt: DateTime(2026),
      );
      await app.pump(tester);
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      Finder tile(String title) => find.ancestor(
        of: find.text(title),
        matching: find.byType(DocumentListTile),
      );

      await tester.longPress(tile('Beta'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Merge'), findsNothing);

      await tester.tap(tile('Alpha'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Merge'));
      await tester.pumpAndSettle();
      expect(find.text('Merge 2 documents'), findsOneWidget);
      expect(find.text('Alpha (merged)'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Contracts');
      await tester.tap(find.text('Merge'));
      await tester.pumpAndSettle();

      expect(app.pdf.mergeCalls.single.$1, ['a', 'b']);
      expect(app.pdf.mergeCalls.single.$2, 'Contracts');
      // The merged document is open and the selection is gone.
      expect(find.text('Contracts'), findsWidgets);
      expect(find.byType(DocumentListTile), findsNothing);
      expect(find.textContaining('Merged 2 documents'), findsOneWidget);
      expect(find.text('2 selected'), findsNothing);
    });

    testWidgets('cancelling the title dialog merges nothing', (tester) async {
      await app.insertDocument('a', title: 'Alpha', pages: 1);
      await app.insertDocument('b', title: 'Beta', pages: 1);
      await app.pump(tester);
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      Finder tile(String title) => find.ancestor(
        of: find.text(title),
        matching: find.byType(DocumentListTile),
      );
      await tester.longPress(tile('Alpha'));
      await tester.pumpAndSettle();
      await tester.tap(tile('Beta'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Merge'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(app.pdf.mergeCalls, isEmpty);
      expect(find.text('2 selected'), findsOneWidget);
    });
  });
}
