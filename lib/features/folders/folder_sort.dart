import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/folder.dart';
import '../../domain/repositories/folder_repository.dart';
import '../../shared/providers/core_providers.dart';

/// Order of the folders row on the Files tab. Persisted like the document
/// sort so it survives restarts.
class FolderSortController extends Notifier<FolderSort> {
  static const _key = 'library.folderSort';

  @override
  FolderSort build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return FolderSort.values.asNameMap()[prefs.getString(_key)] ??
        FolderSort.nameAZ;
  }

  Future<void> setSort(FolderSort sort) async {
    state = sort;
    await ref.read(sharedPreferencesProvider).setString(_key, sort.name);
  }
}

final folderSortProvider = NotifierProvider<FolderSortController, FolderSort>(
  FolderSortController.new,
);

/// All folders in the user's chosen order, with document counts.
final sortedFoldersProvider = StreamProvider.autoDispose<List<Folder>>(
  (ref) => ref
      .watch(folderRepositoryProvider)
      .watchFolders(sort: ref.watch(folderSortProvider)),
);

String folderSortLabel(FolderSort sort) => switch (sort) {
  FolderSort.nameAZ => 'Name (A–Z)',
  FolderSort.recentlyUpdated => 'Recently updated',
  FolderSort.mostDocuments => 'Most documents',
};
