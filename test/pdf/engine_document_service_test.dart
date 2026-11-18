import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:scanly/core/errors/app_exception.dart';
import 'package:scanly/core/services/pdf_builder.dart';
import 'package:scanly/core/services/storage_service.dart';
import 'package:scanly/core/vision/quad.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/data/repositories/drift_document_repository.dart';
import 'package:scanly/data/services/pdf_document_service.dart';
import 'package:scanly/domain/entities/app_settings.dart';
import 'package:scanly/domain/entities/page_edits.dart';
import 'package:scanly/domain/entities/scan_page.dart';
import 'package:scanly/domain/repositories/document_repository.dart';
import 'package:scanly/domain/repositories/settings_repository.dart';
import 'package:scanly/domain/services/pdf_service.dart';

import 'searchable_helpers.dart';

class _FakeSettings implements SettingsRepository {
  AppSettings value = const AppSettings();

  @override
  AppSettings load() => value;

  @override
  Future<void> save(AppSettings settings) async => value = settings;
}

class _CountingBuilder extends PdfBuilder {
  int calls = 0;

  @override
  Future<Uint8List> build(
    List<String> imagePaths, {
    required PdfExportOptions options,
    String? title,
    PdfProgress? onProgress,
    List<PdfPageText?> pageTexts = const [],
  }) {
    calls++;
    return super.build(
      imagePaths,
      options: options,
      title: title,
      onProgress: onProgress,
      pageTexts: pageTexts,
    );
  }
}

int pdfPageCount(List<int> bytes) =>
    RegExp(r'/Type\s*/Page(?![A-Za-z])')
        .allMatches(latin1.decode(bytes))
        .length;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory sandbox;
  late StorageService storage;
  late AppDatabase db;
  late DriftDocumentRepository documents;
  late _FakeSettings settings;
  late _CountingBuilder builder;
  late PdfDocumentService service;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scanly_pdf_service');
    storage = StorageService(Directory(p.join(sandbox.path, 'scanly')));
    await storage.ensureInitialized();
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    documents = DriftDocumentRepository(db, storage);
    settings = _FakeSettings();
    builder = _CountingBuilder();
    service = PdfDocumentService(
      documents: documents,
      storage: storage,
      settings: settings,
      ocr: FakeOcrRepository(),
      builder: builder,
    );
  });

  tearDown(() async {
    await db.close();
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  /// A JPEG whose grey level identifies it.
  List<int> jpeg(int shade, {int width = 120, int height = 160}) {
    final image = img.Image(width: width, height: height)
      ..clear(img.ColorRgb8(shade, shade, shade));
    return img.encodeJpg(image);
  }

  /// Creates a document with [shades].length pages; each page's original is
  /// a JPEG filled with that shade.
  Future<String> document(
    List<int> shades, {
    String title = 'Doc',
    String? folderId,
  }) async {
    final id = storage.newId();
    final pages = <NewPage>[];
    for (final shade in shades) {
      final pageId = storage.newId();
      final original = storage.pagePath(id, pageId, DocumentFileKind.original);
      final thumb = storage.pagePath(id, pageId, DocumentFileKind.thumbnail);
      await storage.writeBytes(original, jpeg(shade));
      await storage.writeBytes(thumb, jpeg(shade, width: 30, height: 40));
      pages.add(
        NewPage(
          id: pageId,
          originalPath: original,
          thumbnailPath: thumb,
          width: 120,
          height: 160,
        ),
      );
    }
    await documents.createDocument(
      id: id,
      title: title,
      pages: pages,
      folderId: folderId,
    );
    return id;
  }

  /// Grey level of the centre pixel of the image at [path].
  int shadeOf(String path) {
    final image = img.decodeJpg(File(path).readAsBytesSync())!;
    return image.getPixel(image.width ~/ 2, image.height ~/ 2).r.toInt();
  }

  Future<List<int>> shades(String documentId) async => [
    for (final page in await documents.getPages(documentId))
      shadeOf(page.originalPath),
  ];

  bool near(int a, int b) => (a - b).abs() <= 3;

  Matcher shadesNear(List<int> expected) => predicate<List<int>>(
    (actual) =>
        actual.length == expected.length &&
        [for (var i = 0; i < actual.length; i++) near(actual[i], expected[i])]
            .every((ok) => ok),
    'shades close to $expected',
  );

  /// Gives a page a new processed image, as the editor does.
  Future<void> editPage(String documentId, int index) async {
    final page = (await documents.getPages(documentId))[index];
    final processed = storage.pagePath(
      documentId,
      storage.newId(),
      DocumentFileKind.processed,
    );
    await storage.writeBytes(processed, jpeg(30));
    await documents.updatePage(
      page.id,
      PageUpdate(
        processedPath: processed,
        thumbnailPath: page.thumbnailPath!,
        width: 120,
        height: 160,
        edits: PageEdits.initial().rotated(),
      ),
    );
  }

  group('ensurePdf', () {
    test('writes the PDF into the document folder and records it', () async {
      final id = await document([10, 120, 240]);
      final progress = <int>[];
      final path = await service.ensurePdf(
        id,
        onProgress: (done, total) => progress.add(done),
      );
      expect(path, storage.pdfPath(id));
      expect(p.isWithin(storage.documentDir(id).path, path), isTrue);
      expect(pdfPageCount(File(path).readAsBytesSync()), 3);
      expect(progress, [0, 1, 2, 3]);
      expect((await documents.getDocument(id))!.pdfPath, path);
      expect(File(service.metaPath(id)).existsSync(), isTrue);
      expect(
        p.isWithin(storage.documentDir(id).path, service.metaPath(id)),
        isTrue,
      );
    });

    test('reuses the cached PDF until the document changes', () async {
      final id = await document([10, 120]);
      await service.ensurePdf(id);
      await service.ensurePdf(id);
      expect(builder.calls, 1);

      await editPage(id, 1);
      final path = await service.ensurePdf(id);
      expect(builder.calls, 2);
      expect(pdfPageCount(File(path).readAsBytesSync()), 2);

      await service.ensurePdf(id);
      expect(builder.calls, 2);

      await service.ensurePdf(id, force: true);
      expect(builder.calls, 3);
    });

    test('regenerates when the options change', () async {
      final id = await document([10]);
      await service.ensurePdf(id);
      await service.ensurePdf(
        id,
        options: const PdfExportOptions(pageSize: PdfPageSize.letter),
      );
      expect(builder.calls, 2);
      await service.ensurePdf(
        id,
        options: const PdfExportOptions(pageSize: PdfPageSize.letter),
      );
      expect(builder.calls, 2);

      // Defaults come from settings.
      settings.value = const AppSettings(compression: ImageCompression.high);
      await service.ensurePdf(id);
      expect(builder.calls, 3);
    });

    test('regenerates when the PDF or its sidecar is missing', () async {
      final id = await document([10]);
      final path = await service.ensurePdf(id);
      File(path).deleteSync();
      await service.ensurePdf(id);
      expect(builder.calls, 2);
      File(service.metaPath(id)).deleteSync();
      await service.ensurePdf(id);
      expect(builder.calls, 3);
    });

    test('rejects unknown and empty documents', () async {
      await expectLater(
        service.ensurePdf('missing'),
        throwsA(isA<NotFoundException>()),
      );
      final id = storage.newId();
      await documents.createDocument(id: id, title: 'Empty', pages: []);
      await expectLater(
        service.ensurePdf(id),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('mergeDocuments', () {
    test('copies pages in order and keeps the sources', () async {
      final a = await document([10, 60]);
      final b = await document([120, 180, 240]);
      // Give one source page edits that must be carried over.
      await editPage(b, 0);
      final bPages = await documents.getPages(b);

      final merged = await service.mergeDocuments([b, a], title: '  All  ');
      final doc = (await documents.getDocument(merged))!;
      expect(doc.title, 'All');
      expect(doc.pageCount, 5);
      expect(await shades(merged), shadesNear([120, 180, 240, 10, 60]));

      final pages = await documents.getPages(merged);
      expect(pages.map((pg) => pg.id).toSet(), hasLength(5));
      for (final page in pages) {
        expect(
          p.isWithin(storage.documentDir(merged).path, page.originalPath),
          isTrue,
        );
        expect(page.thumbnailPath, isNotNull);
        expect(
          p.isWithin(storage.documentDir(merged).path, page.thumbnailPath!),
          isTrue,
        );
      }
      expect(pages.first.rotation, 90);
      expect(pages.first.processedPath, isNotNull);
      expect(pages.first.processedPath, isNot(bPages.first.processedPath));
      expect(shadeOf(pages.first.processedPath!), closeTo(30, 3));
      expect(pages[1].rotation, 0);

      // Sources are untouched.
      expect(await shades(a), shadesNear([10, 60]));
      expect((await documents.getDocument(b))!.pageCount, 3);

      // Deleting a source does not affect the merged document.
      await documents.deleteDocuments([a, b]);
      for (final page in await documents.getPages(merged)) {
        expect(File(page.displayPath).existsSync(), isTrue);
      }
      final pdf = await service.ensurePdf(merged);
      expect(pdfPageCount(File(pdf).readAsBytesSync()), 5);
    });

    test('preserves the crop of copied pages', () async {
      final a = await document([10]);
      final b = await document([200]);
      final page = (await documents.getPages(a)).single;
      final crop = Quad.fromList([0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9]);
      await documents.updatePage(
        page.id,
        PageUpdate(
          processedPath: null,
          thumbnailPath: page.thumbnailPath!,
          width: 120,
          height: 160,
          edits: PageEdits.initial().copyWith(
            corners: crop,
            filter: PageFilter.grayscale,
            brightness: 0.25,
          ),
        ),
      );
      final merged = await service.mergeDocuments([a, b], title: 'M');
      final copied = (await documents.getPages(merged)).first;
      expect(copied.cropCorners, crop);
      expect(copied.filter, PageFilter.grayscale);
      expect(copied.brightness, 0.25);
    });

    test('validates its input', () async {
      final a = await document([10]);
      final b = await document([20]);
      await expectLater(
        service.mergeDocuments([a], title: 'M'),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        service.mergeDocuments([a, b], title: '   '),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        service.mergeDocuments([a, 'missing'], title: 'M'),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('removes copied files when a copy fails', () async {
      final a = await document([10, 20]);
      final b = await document([30]);
      final before = storage.documentsDir.listSync().length;
      File((await documents.getPages(b)).single.originalPath).deleteSync();

      await expectLater(
        service.mergeDocuments([a, b], title: 'M'),
        throwsA(isA<StorageException>()),
      );
      expect(storage.documentsDir.listSync(), hasLength(before));
      expect(await documents.watchDocumentCount().first, 2);
    });
  });

  group('splitDocument', () {
    test('creates one document per part, in order', () async {
      final id = await document([
        10,
        40,
        70,
        100,
        130,
        160,
        190,
        220,
      ], title: 'Book');
      final parts = await service.splitDocument(id, [3, 5]);
      expect(parts, hasLength(3));

      final titles = [
        for (final part in parts) (await documents.getDocument(part))!.title,
      ];
      expect(titles, ['Book (part 1)', 'Book (part 2)', 'Book (part 3)']);
      expect(await shades(parts[0]), shadesNear([10, 40, 70]));
      expect(await shades(parts[1]), shadesNear([100, 130]));
      expect(await shades(parts[2]), shadesNear([160, 190, 220]));

      // The source is kept, and the parts survive its deletion.
      expect((await documents.getDocument(id))!.pageCount, 8);
      await documents.deleteDocuments([id]);
      expect(await shades(parts[2]), shadesNear([160, 190, 220]));
    });

    test('rejects invalid split points', () async {
      final id = await document([10, 20, 30, 40]);
      for (final starts in [
        <int>[],
        [0],
        [4],
        [2, 2],
        [3, 1],
        [-1],
      ]) {
        await expectLater(
          service.splitDocument(id, starts),
          throwsA(isA<ValidationException>()),
          reason: '$starts',
        );
      }
      final single = await document([10]);
      await expectLater(
        service.splitDocument(single, [1]),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        service.splitDocument('missing', [1]),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('rolls back created parts when a later part fails', () async {
      final id = await document([10, 20, 30, 40]);
      final before = storage.documentsDir.listSync().length;
      final pages = await documents.getPages(id);
      File(pages.last.originalPath).deleteSync();

      await expectLater(
        service.splitDocument(id, [2]),
        throwsA(isA<StorageException>()),
      );
      expect(await documents.watchDocumentCount().first, 1);
      expect(storage.documentsDir.listSync(), hasLength(before));
    });
  });
}
