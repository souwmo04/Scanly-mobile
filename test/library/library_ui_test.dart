import 'dart:async';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scanly/app.dart';
import 'package:scanly/core/routing/app_router.dart';
import 'package:scanly/core/routing/routes.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/data/repositories/drift_ocr_repository.dart';
import 'package:scanly/domain/entities/ocr_result.dart';
import 'package:scanly/domain/usecases/duplicate_document.dart';
import 'package:scanly/features/library/document_info_sheet.dart';
import 'package:scanly/features/library/library_use_cases.dart';
import 'package:scanly/features/pdf_viewer/pdf_page_renderer.dart';
import 'package:scanly/shared/providers/core_providers.dart';
import 'package:scanly/shared/providers/pdf_providers.dart';
import 'package:scanly/shared/providers/share_providers.dart';
import 'package:scanly/shared/widgets/document_card.dart';

import '../pdf/ui_test_helpers.dart';

/// Records duplicate requests without touching files (real file IO never
/// completes inside widget tests' fake async zone).
class _FakeDuplicate implements DuplicateDocumentUseCase {
  final calls = <String>[];

  @override
  Future<String> call(String documentId) async {
    calls.add(documentId);
    return '$documentId-copy';
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late PdfTestApp app;
  late _FakeDuplicate duplicate;

  setUp(() async {
    app = PdfTestApp();
    await app.setUp(prefsValues: {'library.layout': 'list'});
    duplicate = _FakeDuplicate();
  });

  tearDown(() => app.tearDown());

  /// Like [PdfTestApp.pump], plus a fake duplicate use case.
  Future<void> pump(WidgetTester tester, {String? location}) async {
    // Tall enough for the folders row, toolbar and every document tile.
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The test font's wide glyphs wrap FolderCard's "N documents" line
    // (shared widget, no maxLines) and overflow its fixed-height row; a
    // slightly smaller text scale keeps it on one line as on real fonts.
    tester.platformDispatcher.textScaleFactorTestValue = 0.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final router = createRouter();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(app.prefs),
          storageServiceProvider.overrideWithValue(app.storage),
          appDatabaseProvider.overrideWithValue(app.db),
          documentPdfServiceProvider.overrideWithValue(app.pdf),
          shareServiceProvider.overrideWithValue(app.share),
          pdfPageRendererProvider.overrideWithValue(app.renderer),
          duplicateDocumentProvider.overrideWithValue(duplicate),
          routerProvider.overrideWithValue(router),
        ],
        child: const ScanlyApp(),
      ),
    );
    await tester.pumpAndSettle();
    if (location != null) {
      unawaited(router.push(location));
      await tester.pumpAndSettle();
    }
  }

  Future<void> openFiles(WidgetTester tester) async {
    await pump(tester);
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
  }

  Finder tile(String title) => find.ancestor(
    of: find.text(title),
    matching: find.byType(DocumentListTile),
  );

  /// Three documents shown newest first: Alpha, Beta, Gamma.
  Future<void> insertThree() async {
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
  }

  Future<void> selectAll(WidgetTester tester) async {
    await tester.longPress(tile('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select all'));
    await tester.pumpAndSettle();
  }

  Future<void> setFavorite(String id, {required bool value}) =>
      (app.db.update(app.db.documents)..where((d) => d.id.equals(id))).write(
        DocumentsCompanion(isFavorite: Value(value)),
      );

  group('bulk share', () {
    testWidgets('shares every selected PDF in one sheet', (tester) async {
      await insertThree();
      await openFiles(tester);
      await selectAll(tester);
      expect(find.text('3 selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();

      expect(app.pdf.ensureCalls.map((c) => c.documentId), ['a', 'b', 'c']);
      expect(app.share.shared, hasLength(1));
      expect(app.share.shared.single.$1, [
        app.pdf.pathFor('a'),
        app.pdf.pathFor('b'),
        app.pdf.pathFor('c'),
      ]);
      expect(app.share.shared.single.$2, '3 documents');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('3 selected'), findsNothing);
    });

    testWidgets('shows progress per document', (tester) async {
      await insertThree();
      app.pdf.gate = Completer<void>();
      await openFiles(tester);
      await selectAll(tester);

      await tester.tap(find.byTooltip('Share'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Preparing PDF 1 of 3…'), findsOneWidget);
      expect(find.text('Alpha'), findsWidgets);

      app.pdf.gate!.complete();
      await tester.pumpAndSettle();
      expect(app.share.shared, hasLength(1));
    });

    testWidgets('reports a failed document and shares the rest', (
      tester,
    ) async {
      await insertThree();
      app.pdf.failuresLeft = 1;
      await openFiles(tester);
      await selectAll(tester);

      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();

      expect(app.share.shared.single.$1, [
        app.pdf.pathFor('b'),
        app.pdf.pathFor('c'),
      ]);
      expect(find.text('Shared 2 of 3 documents'), findsOneWidget);
      final failure = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text.toPlainText() == 'Alpha: Not enough space for the PDF.',
        ),
      );
      expect(failure, findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('shares nothing when every PDF fails', (tester) async {
      await insertThree();
      app.pdf.failuresLeft = 3;
      await openFiles(tester);
      await selectAll(tester);

      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();

      expect(app.share.shared, isEmpty);
      expect(find.text('Could not create the PDFs'), findsOneWidget);
      expect(find.text('Nothing was shared.'), findsOneWidget);
      // The selection stays so the user can retry.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);
    });

    testWidgets('cancel stops before sharing', (tester) async {
      await insertThree();
      app.pdf.gate = Completer<void>();
      await openFiles(tester);
      await selectAll(tester);

      await tester.tap(find.byTooltip('Share'));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      app.pdf.gate!.complete();
      await tester.pumpAndSettle();

      expect(app.pdf.ensureCalls, hasLength(1));
      expect(app.share.shared, isEmpty);
      expect(find.text('Sharing cancelled'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('smart favorite toggle', () {
    testWidgets('offers removal only when every selected item is a favorite', (
      tester,
    ) async {
      await insertThree();
      await setFavorite('a', value: true);
      await setFavorite('b', value: true);
      await openFiles(tester);

      await tester.longPress(tile('Alpha'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove from favorites'), findsOneWidget);

      await tester.tap(tile('Gamma'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add to favorites'), findsOneWidget);
      expect(find.byTooltip('Remove from favorites'), findsNothing);

      await tester.tap(tile('Gamma'));
      await tester.tap(tile('Beta'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove from favorites'));
      await tester.pumpAndSettle();

      final rows = await app.db.select(app.db.documents).get();
      expect(
        {for (final r in rows) r.id: r.isFavorite},
        {'a': false, 'b': false, 'c': false},
      );
      expect(find.text('Removed 2 documents from favorites'), findsOneWidget);
    });

    testWidgets('adds a mixed selection to favorites', (tester) async {
      await insertThree();
      await setFavorite('a', value: true);
      await openFiles(tester);
      await selectAll(tester);

      await tester.tap(find.byTooltip('Add to favorites'));
      await tester.pumpAndSettle();

      final rows = await app.db.select(app.db.documents).get();
      expect(rows.every((r) => r.isFavorite), isTrue);
    });
  });

  group('document info', () {
    Future<void> insertDetailed() async {
      await app.db
          .into(app.db.folders)
          .insert(
            FoldersCompanion.insert(
              id: 'f',
              name: 'Household',
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          );
      await app.insertDocument('doc', title: 'Lease', pages: 4);
      await (app.db.update(
        app.db.documents,
      )..where((d) => d.id.equals('doc'))).write(
        DocumentsCompanion(
          folderId: const Value('f'),
          fileSize: const Value(2048),
          createdAt: Value(DateTime(2026, 3, 4, 9, 30)),
          updatedAt: Value(DateTime(2026, 5, 6, 17, 45)),
        ),
      );
      final ocr = DriftOcrRepository(app.db);
      for (var i = 0; i < 3; i++) {
        await ocr.saveResult(
          'doc-p$i',
          const OcrResult(
            text: 'text',
            lines: [],
            languageCode: 'eng',
            engine: OcrEngineId.mlKit,
          ),
        );
      }
    }

    void expectInfo() {
      final sheet = find.byType(DocumentInfoSheet);
      Finder inSheet(String text) =>
          find.descendant(of: sheet, matching: find.text(text));
      expect(inSheet('Lease'), findsOneWidget);
      expect(inSheet('Household'), findsOneWidget);
      expect(inSheet('4 pages'), findsOneWidget);
      expect(inSheet('2.0 KB'), findsOneWidget);
      expect(
        inSheet(formatInfoDate(DateTime(2026, 3, 4, 9, 30))),
        findsOneWidget,
      );
      expect(
        inSheet(formatInfoDate(DateTime(2026, 5, 6, 17, 45))),
        findsOneWidget,
      );
      expect(inSheet('Text recognized on 3 of 4 pages'), findsOneWidget);
      expect(inSheet('On this device'), findsOneWidget);
    }

    testWidgets('opens from the document action sheet', (tester) async {
      await insertDetailed();
      await openFiles(tester);

      await tester.tap(
        find.descendant(
          of: tile('Lease'),
          matching: find.byTooltip('More options'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Info'));
      await tester.pumpAndSettle();

      expectInfo();
    });

    testWidgets('opens from the document screen menu', (tester) async {
      await insertDetailed();
      await pump(tester, location: Routes.document('doc'));

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Info'));
      await tester.pumpAndSettle();

      expectInfo();
    });

    testWidgets('shows All files for documents outside folders', (
      tester,
    ) async {
      await app.insertDocument('doc', title: 'Note', pages: 1);
      await pump(tester, location: Routes.document('doc'));

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Info'));
      await tester.pumpAndSettle();

      final sheet = find.byType(DocumentInfoSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('All files')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Not recognized yet')),
        findsOneWidget,
      );
    });
  });

  testWidgets('duplicate from the action sheet', (tester) async {
    await app.insertDocument('doc', title: 'Lease', pages: 1);
    await openFiles(tester);

    await tester.tap(
      find.descendant(
        of: tile('Lease'),
        matching: find.byTooltip('More options'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();

    expect(duplicate.calls, ['doc']);
    expect(find.text('Created "Lease (copy)"'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  group('add documents to a folder', () {
    Future<void> insertFolder() async {
      await app.db
          .into(app.db.folders)
          .insert(
            FoldersCompanion.insert(
              id: 'f',
              name: 'Household',
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          );
    }

    Future<Map<String, String?>> folderOf() async {
      final rows = await app.db.select(app.db.documents).get();
      return {for (final r in rows) r.title: r.folderId};
    }

    testWidgets('picks documents outside the folder and moves them in', (
      tester,
    ) async {
      await insertFolder();
      await insertThree();
      await app.insertDocument('in', title: 'Already here', pages: 1);
      await (app.db.update(app.db.documents)..where((d) => d.id.equals('in')))
          .write(const DocumentsCompanion(folderId: Value('f')));
      await pump(tester, location: Routes.folder('f'));

      await tester.tap(find.byTooltip('Add documents'));
      await tester.pumpAndSettle();

      final sheet = find.byType(BottomSheet);
      Finder option(String title) => find.descendant(
        of: sheet,
        matching: find.widgetWithText(CheckboxListTile, title),
      );
      expect(option('Alpha'), findsOneWidget);
      expect(option('Beta'), findsOneWidget);
      expect(option('Gamma'), findsOneWidget);
      expect(option('Already here'), findsNothing);
      expect(find.text('Select documents'), findsOneWidget);

      // Search as you type, case-insensitive.
      await tester.enterText(
        find.descendant(of: sheet, matching: find.byType(TextField)),
        'GAM',
      );
      await tester.pumpAndSettle();
      expect(option('Alpha'), findsNothing);
      await tester.tap(option('Gamma'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(of: sheet, matching: find.byType(TextField)),
        'zzz',
      );
      await tester.pumpAndSettle();
      expect(find.text('No matches'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      await tester.tap(option('Alpha'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add 2 documents'));
      await tester.pumpAndSettle();

      expect(await folderOf(), {
        'Alpha': 'f',
        'Beta': null,
        'Gamma': 'f',
        'Already here': 'f',
      });
      expect(find.text('Added 2 documents to Household'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      // The folder now lists the moved documents.
      expect(tile('Alpha'), findsOneWidget);
      expect(tile('Gamma'), findsOneWidget);
    });

    testWidgets('dismissing the picker moves nothing', (tester) async {
      await insertFolder();
      await insertThree();
      await pump(tester, location: Routes.folder('f'));

      // The empty folder offers the same action.
      await tester.tap(find.widgetWithText(FilledButton, 'Add documents'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.widgetWithText(CheckboxListTile, 'Beta'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect((await folderOf()).values.every((f) => f == null), isTrue);
    });
  });
}
