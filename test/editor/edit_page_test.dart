import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:scanly/core/errors/app_exception.dart';
import 'package:scanly/core/services/image_service.dart';
import 'package:scanly/core/services/storage_service.dart';
import 'package:scanly/core/vision/quad.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/data/repositories/drift_document_repository.dart';
import 'package:scanly/domain/entities/page_edits.dart';
import 'package:scanly/domain/entities/scan_page.dart';
import 'package:scanly/domain/usecases/edit_page.dart';
import 'package:scanly/domain/usecases/import_pages.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory sandbox;
  late StorageService storage;
  late AppDatabase db;
  late DriftDocumentRepository documents;
  late ImportPagesUseCase importPages;
  late EditPageUseCase editPage;
  const images = ImageService();

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scanly_edit_test');
    storage = StorageService(Directory(p.join(sandbox.path, 'scanly')));
    await storage.ensureInitialized();
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    documents = DriftDocumentRepository(db, storage);
    importPages = ImportPagesUseCase(
      documents: documents,
      storage: storage,
      images: images,
    );
    editPage = EditPageUseCase(
      documents: documents,
      storage: storage,
      images: images,
    );
  });

  tearDown(() async {
    await db.close();
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  String photo(String name, {int width = 400, int height = 600}) {
    final image = img.Image(width: width, height: height)
      ..clear(img.ColorRgb8(200, 200, 195));
    img.fillRect(
      image,
      x1: 40,
      y1: 40,
      x2: 200,
      y2: 80,
      color: img.ColorRgb8(20, 20, 20),
    );
    final path = p.join(sandbox.path, name);
    File(path).writeAsBytesSync(img.encodeJpg(image));
    return path;
  }

  Future<ScanPage> singlePage() async {
    final id = await importPages([PageSource(photo('a.jpg'))], title: 'Doc');
    return (await documents.getPages(id)).single;
  }

  test('preview renders a small image with the edits applied', () async {
    final page = await singlePage();
    final bytes = await editPage.preview(
      page,
      PageEdits.initial().rotated(),
      maxSide: 300,
    );
    final preview = img.decodeJpg(bytes)!;
    expect(preview.width, greaterThan(preview.height)); // rotated portrait
    expect(preview.width, lessThanOrEqualTo(300));
  });

  test('save writes a new processed image and keeps the original', () async {
    final page = await singlePage();
    final originalBytes = File(page.originalPath).readAsBytesSync();
    final edits = PageEdits.initial().copyWith(
      corners: Quad.fromList([0, 0, 0.5, 0, 0.5, 0.5, 0, 0.5]),
      filter: PageFilter.grayscale,
    );

    await editPage.save(page, edits);

    final saved = (await documents.getPage(page.id))!;
    expect(PageEdits.fromPage(saved), edits);
    expect(saved.processedPath, isNotNull);
    expect(File(saved.processedPath!).existsSync(), isTrue);
    expect((saved.width, saved.height), (200, 300));
    expect(File(saved.originalPath).readAsBytesSync(), originalBytes);
    // The old thumbnail was replaced and removed.
    expect(saved.thumbnailPath, isNot(page.thumbnailPath));
    expect(File(page.thumbnailPath!).existsSync(), isFalse);
  });

  test('saving twice removes the previous processed version', () async {
    final page = await singlePage();
    await editPage.save(page, PageEdits.initial().rotated());
    final first = (await documents.getPage(page.id))!;

    await editPage.save(first, PageEdits.fromPage(first).rotated());
    final second = (await documents.getPage(page.id))!;

    expect(second.rotation, 180);
    expect(second.processedPath, isNot(first.processedPath));
    expect(File(first.processedPath!).existsSync(), isFalse);
  });

  test('resetting all edits shows the original again', () async {
    final page = await singlePage();
    await editPage.save(page, PageEdits.initial().rotated());
    final rotated = (await documents.getPage(page.id))!;

    await editPage.save(rotated, PageEdits.initial());

    final reset = (await documents.getPage(page.id))!;
    expect(reset.processedPath, isNull);
    expect(reset.displayPath, reset.originalPath);
    expect(File(rotated.processedPath!).existsSync(), isFalse);
    expect((reset.width, reset.height), (400, 600));
  });

  test('rotate turns the page a quarter turn', () async {
    final page = await singlePage();
    await editPage.rotate(page, clockwise: false);
    final rotated = (await documents.getPage(page.id))!;
    expect(rotated.rotation, 270);
    expect((rotated.width, rotated.height), (600, 400));
  });

  test('appendTo adds pages and cleans up on failure', () async {
    final id = await importPages([PageSource(photo('a.jpg'))], title: 'Doc');
    await importPages.appendTo(id, [
      PageSource(photo('b.jpg')),
      PageSource(photo('c.jpg')),
    ]);
    expect(await documents.getPages(id), hasLength(3));

    final before = await storage.sizeOf(storage.documentDir(id));
    final bad = p.join(sandbox.path, 'bad.jpg');
    File(bad).writeAsStringSync('nope');
    await expectLater(
      importPages.appendTo(id, [PageSource(photo('d.jpg')), PageSource(bad)]),
      throwsA(isA<StorageException>()),
    );
    expect(await documents.getPages(id), hasLength(3));
    expect(await storage.sizeOf(storage.documentDir(id)), before);
  });

  test('replacePage swaps the image and deletes the old files', () async {
    final page = await singlePage();
    await editPage.save(page, PageEdits.initial().rotated());
    final edited = (await documents.getPage(page.id))!;

    await importPages.replacePage(
      page.id,
      PageSource(photo('retake.jpg', width: 500, height: 700)),
    );

    final retaken = (await documents.getPage(page.id))!;
    expect(retaken.originalPath, isNot(edited.originalPath));
    expect((retaken.width, retaken.height), (500, 700));
    expect(retaken.rotation, 0);
    for (final old in [
      edited.originalPath,
      edited.processedPath!,
      edited.thumbnailPath!,
    ]) {
      expect(File(old).existsSync(), isFalse, reason: old);
    }
  });
}
