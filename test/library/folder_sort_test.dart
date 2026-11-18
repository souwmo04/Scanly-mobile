import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanly/core/services/storage_service.dart';
import 'package:scanly/data/database/app_database.dart';
import 'package:scanly/domain/repositories/folder_repository.dart';
import 'package:scanly/features/folders/folder_sort.dart';
import 'package:scanly/shared/providers/core_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory sandbox;
  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scanly_folder_sort');
    db = AppDatabase.forExecutor(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    Future<void> folder(String id, String name, DateTime updated) => db
        .into(db.folders)
        .insert(
          FoldersCompanion.insert(
            id: id,
            name: name,
            createdAt: DateTime(2026),
            updatedAt: updated,
          ),
        );
    Future<void> doc(String id, String folderId, DateTime updated) => db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            id: id,
            folderId: Value(folderId),
            title: id,
            createdAt: DateTime(2026),
            updatedAt: updated,
          ),
        );

    // Bills: renamed recently, one document.
    // archive: old folder, but holds the most recently edited document.
    // Contracts: old, three documents.
    await folder('bills', 'Bills', DateTime(2026, 5));
    await folder('archive', 'archive', DateTime(2026, 1));
    await folder('contracts', 'Contracts', DateTime(2026, 2));
    await doc('b1', 'bills', DateTime(2026, 3));
    await doc('a1', 'archive', DateTime(2026, 9));
    await doc('c1', 'contracts', DateTime(2026, 2));
    await doc('c2', 'contracts', DateTime(2026, 2));
    await doc('c3', 'contracts', DateTime(2026, 2));
  });

  tearDown(() async {
    await db.close();
    if (sandbox.existsSync()) await sandbox.delete(recursive: true);
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        storageServiceProvider.overrideWithValue(StorageService(sandbox)),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<List<String>> names(ProviderContainer c) async {
    final sub = c.listen(sortedFoldersProvider, (_, _) {});
    addTearDown(sub.close);
    final folders = await c.read(sortedFoldersProvider.future);
    return [for (final f in folders) f.name];
  }

  test('defaults to name order, ignoring case', () async {
    final c = container();
    expect(c.read(folderSortProvider), FolderSort.nameAZ);
    expect(await names(c), ['archive', 'Bills', 'Contracts']);
  });

  test('recently updated counts document changes inside the folder', () async {
    final c = container();
    await c
        .read(folderSortProvider.notifier)
        .setSort(FolderSort.recentlyUpdated);
    expect(await names(c), ['archive', 'Bills', 'Contracts']);

    // A newer document in Contracts moves it to the front.
    await (db.update(db.documents)..where((d) => d.id.equals('c1'))).write(
      DocumentsCompanion(updatedAt: Value(DateTime(2026, 10))),
    );
    // The stream re-emits asynchronously; wait for the new order.
    var latest = await names(c);
    for (var i = 0; i < 100 && latest.first != 'Contracts'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      latest = await names(c);
    }
    expect(latest, ['Contracts', 'archive', 'Bills']);
  });

  test('most documents first, ties by name', () async {
    final c = container();
    await c.read(folderSortProvider.notifier).setSort(FolderSort.mostDocuments);
    final sub = c.listen(sortedFoldersProvider, (_, _) {});
    addTearDown(sub.close);
    final folders = await c.read(sortedFoldersProvider.future);
    expect(
      [for (final f in folders) (f.name, f.documentCount)],
      [('Contracts', 3), ('archive', 1), ('Bills', 1)],
    );
  });

  test('the choice is persisted and restored', () async {
    final first = container();
    await first
        .read(folderSortProvider.notifier)
        .setSort(FolderSort.mostDocuments);
    expect(prefs.getString('library.folderSort'), 'mostDocuments');

    final second = container();
    expect(second.read(folderSortProvider), FolderSort.mostDocuments);
    expect(await names(second), ['Contracts', 'archive', 'Bills']);
  });

  test('unknown stored values fall back to name order', () async {
    await prefs.setString('library.folderSort', 'bogus');
    expect(container().read(folderSortProvider), FolderSort.nameAZ);
  });
}
