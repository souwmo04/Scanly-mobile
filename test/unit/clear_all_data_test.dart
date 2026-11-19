import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:scanly/core/services/storage_service.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/domain/entities/ocr_result.dart';
import 'package:scanly/domain/services/pdf_service.dart';
import 'package:scanly/domain/usecases/import_pages.dart';
import 'package:scanly/features/search/recent_searches.dart';
import 'package:scanly/features/settings/clear_all_data.dart';
import 'package:scanly/shared/providers/core_providers.dart';
import 'package:scanly/shared/providers/ocr_providers.dart';
import 'package:scanly/shared/providers/pdf_providers.dart';
import 'package:scanly/shared/providers/scanner_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Clear all data" must leave nothing of the user's content behind:
/// database rows, the search index, OCR text, page images, PDFs and their
/// sidecars, temporary files, plugin copies in the cache folder, and recent
/// searches.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory sandbox;
  late Directory cache;
  late StorageService storage;
  late AppDatabase db;
  late SharedPreferences prefs;
  late ProviderContainer container;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scanly_clear_all');
    storage = StorageService(
      Directory(p.join(sandbox.path, 'support', 'scanly')),
    );
    await storage.ensureInitialized();
    cache = Directory(p.join(sandbox.path, 'cache'))..createSync();
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({
      'settings.theme_mode': 'dark',
      RecentSearchesStore.storageKey: ['older search'],
    });
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        storageServiceProvider.overrideWithValue(storage),
        appDatabaseProvider.overrideWithValue(db),
        cacheDirectoryProvider.overrideWithValue(() async => cache),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  String makeJpeg(String name) {
    final image = img.Image(width: 600, height: 800)
      ..clear(img.ColorRgb8(240, 240, 235));
    final path = p.join(sandbox.path, name);
    File(path).writeAsBytesSync(img.encodeJpg(image, quality: 85));
    return path;
  }

  Future<int> count(String table) async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM $table')
        .getSingle();
    return row.read<int>('c');
  }

  List<FileSystemEntity> filesUnder(Directory dir) => dir.existsSync()
      ? dir.listSync(recursive: true).whereType<File>().toList()
      : const [];

  test('removes every row, file, cache entry and recent search', () async {
    // A folder with a two-page document, OCR text and a generated PDF.
    final folder = await container
        .read(folderRepositoryProvider)
        .createFolder(name: 'Taxes', colorIndex: 1);
    final documentId = await container.read(importPagesProvider).call([
      PageSource(makeJpeg('a.jpg')),
      PageSource(makeJpeg('b.jpg')),
    ], title: 'Tax return');
    await container.read(documentRepositoryProvider).moveToFolder([
      documentId,
    ], folder.id);
    final pages = await container
        .read(documentRepositoryProvider)
        .getPages(documentId);
    final ocr = container.read(ocrRepositoryProvider);
    await ocr.saveResult(
      pages.first.id,
      const OcrResult(
        text: 'Annual income statement',
        lines: [OcrLine('Annual income statement')],
        languageCode: 'eng',
        engine: 'test',
      ),
    );
    await ocr.markPending([pages.last.id]);
    final pdfPath = await container
        .read(documentPdfServiceProvider)
        .ensurePdf(documentId, options: const PdfExportOptions());
    expect(File(pdfPath).existsSync(), isTrue);
    expect(File('$pdfPath.meta').existsSync(), isTrue);

    // A leftover temp file and plugin copies in the cache folder.
    File(storage.tempPath(extension: '.jpg')).writeAsBytesSync([1, 2, 3]);
    File(p.join(cache.path, 'share_plus', 'Tax return.pdf'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1]);
    File(p.join(cache.path, 'image_picker_123', 'IMG_0001.jpg'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1]);
    await container.read(recentSearchesProvider.notifier).add('income');

    expect(await count('documents'), 1);
    expect(await count('pages'), 2);
    expect(await count('page_ocr'), 2);
    expect(await count('folders'), 1);
    expect(await count('search_index'), 2);
    expect(filesUnder(storage.documentsDir), isNotEmpty);

    await container.read(clearAllDataProvider)();

    expect(await count('documents'), 0);
    expect(await count('pages'), 0);
    expect(await count('page_ocr'), 0);
    expect(await count('folders'), 0);
    expect(await count('search_index'), 0);
    final counts = await container
        .read(searchRepositoryProvider)
        .countMatches('income');
    expect(counts.allDocuments, 0);
    expect(filesUnder(storage.documentsDir), isEmpty);
    expect(filesUnder(storage.tempDir), isEmpty);
    expect(cache.listSync(), isEmpty);
    // Storage stays usable for new scans.
    expect(storage.documentsDir.existsSync(), isTrue);
    expect(storage.tempDir.existsSync(), isTrue);

    expect(container.read(recentSearchesProvider), isEmpty);
    expect(prefs.getStringList(RecentSearchesStore.storageKey), isNull);
    // Settings are preferences, not user content, and are kept.
    expect(prefs.getString('settings.theme_mode'), 'dark');
  });

  test('works when there is no cache folder', () async {
    container.dispose();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        storageServiceProvider.overrideWithValue(storage),
        appDatabaseProvider.overrideWithValue(db),
        cacheDirectoryProvider.overrideWithValue(() async => null),
      ],
    );
    await container.read(clearAllDataProvider)();
    expect(await count('documents'), 0);
    expect(container.read(recentSearchesProvider), isEmpty);
  });

  test('never deletes app storage that lives inside the cache', () async {
    final inner = StorageService(Directory(p.join(cache.path, 'scanly')));
    await inner.ensureInitialized();
    File(p.join(cache.path, 'junk.bin')).writeAsBytesSync([1]);
    container.dispose();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        storageServiceProvider.overrideWithValue(inner),
        appDatabaseProvider.overrideWithValue(db),
        cacheDirectoryProvider.overrideWithValue(() async => cache),
      ],
    );
    await container.read(clearAllDataProvider)();
    expect(File(p.join(cache.path, 'junk.bin')).existsSync(), isFalse);
    expect(inner.documentsDir.existsSync(), isTrue);
  });

  test('the platform cache folder is never used on desktop hosts', () async {
    // On the test host this must be null, so a test can never empty the
    // machine's shared temp directory.
    final fresh = ProviderContainer();
    addTearDown(fresh.dispose);
    expect(await fresh.read(cacheDirectoryProvider)(), isNull);
  });
}
