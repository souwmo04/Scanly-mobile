import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scanly/core/errors/app_exception.dart';
import 'package:scanly/core/services/storage_service.dart';

void main() {
  late Directory sandbox;
  late StorageService storage;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scanly_storage_test');
    storage = StorageService(Directory(p.join(sandbox.path, 'scanly')));
    await storage.ensureInitialized();
  });

  tearDown(() async {
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  test('creates documents and tmp folders', () {
    expect(storage.documentsDir.existsSync(), isTrue);
    expect(storage.tempDir.existsSync(), isTrue);
  });

  test('builds page paths under the document folder', () {
    final path = storage.pagePath('doc1', 'page1', DocumentFileKind.original);
    expect(
      path,
      p.join(storage.documentsDir.path, 'doc1', 'original', 'page1.jpg'),
    );
    expect(
      storage.pagePath('doc1', 'page1', DocumentFileKind.thumbnail),
      endsWith(p.join('thumbs', 'page1.jpg')),
    );
  });

  test('writeBytes writes atomically and leaves no temp files', () async {
    final target = storage.pagePath('doc1', 'p1', DocumentFileKind.processed);
    final file = await storage.writeBytes(target, [1, 2, 3]);

    expect(file.path, target);
    expect(await file.readAsBytes(), [1, 2, 3]);
    expect(storage.tempDir.listSync(), isEmpty);
  });

  test('writeBytes replaces an existing file', () async {
    final target = storage.pagePath('doc1', 'p1', DocumentFileKind.processed);
    await storage.writeBytes(target, [1]);
    await storage.writeBytes(target, [9, 9]);
    expect(await File(target).readAsBytes(), [9, 9]);
  });

  test('importFile copies without touching the source', () async {
    final source = File(p.join(sandbox.path, 'external.jpg'));
    await source.writeAsBytes([5, 6, 7]);
    final target = storage.pagePath('doc1', 'p1', DocumentFileKind.original);

    await storage.importFile(source, target);

    expect(source.existsSync(), isTrue);
    expect(await File(target).readAsBytes(), [5, 6, 7]);
  });

  test('refuses to write or delete outside app storage', () async {
    final outside = p.join(sandbox.path, 'outside.txt');
    expect(
      () => storage.writeBytes(outside, [1]),
      throwsA(isA<StorageException>()),
    );
    expect(() => storage.deleteFile(outside), throwsA(isA<StorageException>()));
  });

  test('rejects path traversal in identifiers', () {
    expect(
      () => storage.documentDir('../escape'),
      throwsA(isA<ValidationException>()),
    );
    expect(
      () => storage.pagePath('doc', '../../x', DocumentFileKind.original),
      throwsA(isA<ValidationException>()),
    );
  });

  test('deleteDocumentFiles removes the folder and ignores missing', () async {
    await storage.writeBytes(
      storage.pagePath('doc1', 'p1', DocumentFileKind.original),
      [1],
    );
    await storage.deleteDocumentFiles('doc1');
    expect(storage.documentDir('doc1').existsSync(), isFalse);

    await storage.deleteDocumentFiles('never-existed');
  });

  test('sizeOf sums all files', () async {
    await storage.writeBytes(
      storage.pagePath('a', 'p1', DocumentFileKind.original),
      List.filled(100, 0),
    );
    await storage.writeBytes(storage.pdfPath('a'), List.filled(50, 0));
    expect(await storage.sizeOf(), 150);
    expect(await storage.sizeOf(storage.documentDir('a')), 150);
  });

  test('cleanTemp removes leftovers from interrupted work', () async {
    await File(storage.tempPath(extension: '.jpg')).writeAsBytes([1]);
    await storage.cleanTemp();
    expect(storage.tempDir.existsSync(), isTrue);
    expect(storage.tempDir.listSync(), isEmpty);
  });

  test('clearAll deletes every document', () async {
    await storage.writeBytes(
      storage.pagePath('a', 'p1', DocumentFileKind.original),
      [1],
    );
    await storage.clearAll();
    expect(storage.documentsDir.listSync(), isEmpty);
    expect(await storage.sizeOf(), 0);
  });

  test('newId returns unique identifiers', () {
    final ids = List.generate(100, (_) => storage.newId()).toSet();
    expect(ids, hasLength(100));
  });
}
