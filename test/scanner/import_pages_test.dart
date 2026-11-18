import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:scanly/core/errors/app_exception.dart';
import 'package:scanly/core/services/image_service.dart';
import 'package:scanly/core/services/storage_service.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/data/repositories/drift_document_repository.dart';
import 'package:scanly/domain/usecases/import_pages.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory sandbox;
  late StorageService storage;
  late AppDatabase db;
  late DriftDocumentRepository documents;
  late ImportPagesUseCase importPages;
  const images = ImageService();

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scanly_import_test');
    storage = StorageService(Directory(p.join(sandbox.path, 'scanly')));
    await storage.ensureInitialized();
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    documents = DriftDocumentRepository(db, storage);
    importPages = ImportPagesUseCase(
      documents: documents,
      storage: storage,
      images: images,
    );
  });

  tearDown(() async {
    await db.close();
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  /// Writes a solid-color JPEG "capture" outside app storage.
  String makeJpeg(
    String name, {
    int width = 1200,
    int height = 1600,
    int? exifOrientation,
  }) {
    final image = img.Image(width: width, height: height)
      ..clear(img.ColorRgb8(240, 240, 235));
    if (exifOrientation != null) {
      image.exif.imageIfd.orientation = exifOrientation;
    }
    final path = p.join(sandbox.path, name);
    File(path).writeAsBytesSync(img.encodeJpg(image, quality: 85));
    return path;
  }

  group('ImageService', () {
    test('reads JPEG size from the header', () async {
      final path = makeJpeg('a.jpg', width: 1000, height: 1414);
      expect(await images.readSize(path), (width: 1000, height: 1414));
    });

    test('swaps size for EXIF-rotated JPEGs', () async {
      final path = makeJpeg(
        'r.jpg',
        width: 1600,
        height: 1200,
        exifOrientation: 6,
      );
      expect(await images.readSize(path), (width: 1200, height: 1600));
    });

    test('reads PNG size through the platform codec', () async {
      final png = img.encodePng(img.Image(width: 300, height: 200));
      final path = p.join(sandbox.path, 'x.png');
      File(path).writeAsBytesSync(png);
      expect(await images.readSize(path), (width: 300, height: 200));
    });

    test('creates a downscaled JPEG thumbnail', () async {
      final path = makeJpeg('big.jpg', width: 2000, height: 3000);
      final bytes = await images.createThumbnail(path, maxSide: 480);
      final thumb = img.decodeJpg(bytes)!;
      expect(thumb.height, 480);
      expect(thumb.width, 320);
    });

    test('does not upscale small images', () async {
      final path = makeJpeg('small.jpg', width: 200, height: 100);
      final thumb = img.decodeJpg(await images.createThumbnail(path))!;
      expect((thumb.width, thumb.height), (200, 100));
    });

    test('rejects missing and corrupt files', () async {
      expect(
        () => images.readSize(p.join(sandbox.path, 'missing.jpg')),
        throwsA(isA<StorageException>()),
      );
      final junk = p.join(sandbox.path, 'junk.jpg');
      File(junk).writeAsStringSync('not an image');
      expect(() => images.readSize(junk), throwsA(isA<StorageException>()));
    });
  });

  group('ImportPagesUseCase', () {
    test('imports pages in order with sizes and thumbnails', () async {
      final sources = [
        makeJpeg('1.jpg', width: 1000, height: 1400),
        makeJpeg('2.jpg', width: 1400, height: 1000),
        makeJpeg('3.jpg'),
      ];
      final progress = <(int, int)>[];

      final id = await importPages(
        sources,
        title: 'Lease agreement',
        onProgress: (done, total) => progress.add((done, total)),
      );

      final doc = await documents.getDocument(id);
      expect(doc!.title, 'Lease agreement');
      expect(doc.pageCount, 3);
      expect(doc.fileSize, greaterThan(0));
      expect(doc.thumbnailPath, isNotNull);

      final pages = await documents.getPages(id);
      expect(pages.map((pg) => (pg.width, pg.height)), [
        (1000, 1400),
        (1400, 1000),
        (1200, 1600),
      ]);
      for (final page in pages) {
        expect(File(page.originalPath).existsSync(), isTrue);
        expect(File(page.thumbnailPath!).existsSync(), isTrue);
        expect(
          p.isWithin(storage.documentDir(id).path, page.originalPath),
          isTrue,
        );
      }
      expect(progress, [(0, 3), (1, 3), (2, 3), (3, 3)]);

      // Sources are kept unless deleteSources is set.
      expect(sources.every((s) => File(s).existsSync()), isTrue);
    });

    test('originals are byte-identical copies', () async {
      final source = makeJpeg('orig.jpg');
      final id = await importPages([source], title: 'Copy');
      final page = (await documents.getPages(id)).single;
      expect(
        File(page.originalPath).readAsBytesSync(),
        File(source).readAsBytesSync(),
      );
    });

    test('deleteSources removes temporary captures', () async {
      final source = makeJpeg('temp.jpg');
      await importPages([source], title: 'Temp', deleteSources: true);
      expect(File(source).existsSync(), isFalse);
    });

    test('rolls back files when a page fails', () async {
      final good = makeJpeg('good.jpg');
      final bad = p.join(sandbox.path, 'bad.jpg');
      File(bad).writeAsStringSync('corrupt');

      await expectLater(
        importPages([good, bad], title: 'Broken'),
        throwsA(isA<StorageException>()),
      );

      expect(await db.select(db.documents).get(), isEmpty);
      expect(storage.documentsDir.listSync(), isEmpty);
      expect(File(good).existsSync(), isTrue);
    });

    test('rejects empty input and missing files', () async {
      await expectLater(
        importPages([], title: 'Empty'),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        importPages([p.join(sandbox.path, 'nope.jpg')], title: 'Missing'),
        throwsA(isA<StorageException>()),
      );
    });

    test('keeps PNG extension for PNG imports', () async {
      final path = p.join(sandbox.path, 'shot.PNG');
      File(path)
          .writeAsBytesSync(img.encodePng(img.Image(width: 50, height: 80)));
      final id = await importPages([path], title: 'Screenshot');
      final page = (await documents.getPages(id)).single;
      expect(page.originalPath, endsWith('.png'));
      expect((page.width, page.height), (50, 80));
    });
  });
}
