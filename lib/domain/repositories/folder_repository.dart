import '../entities/folder.dart';

/// Order of [FolderRepository.watchFolders].
enum FolderSort {
  /// Alphabetical, ignoring case.
  nameAZ,

  /// Most recent activity first: the folder's own changes or the latest
  /// change to a document inside it.
  recentlyUpdated,

  /// Folders holding the most documents first (ties by name).
  mostDocuments,
}

abstract interface class FolderRepository {
  /// All folders with their document counts, in [sort] order (by name by
  /// default).
  Stream<List<Folder>> watchFolders({FolderSort sort = FolderSort.nameAZ});

  Future<Folder?> getFolder(String id);

  Future<Folder> createFolder({required String name, required int colorIndex});

  Future<void> updateFolder(String id, {String? name, int? colorIndex});

  /// Deletes the folder. Its documents are kept and moved to the root.
  Future<void> deleteFolder(String id);
}
