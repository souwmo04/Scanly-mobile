import '../entities/folder.dart';

abstract interface class FolderRepository {
  /// All folders with their document counts, sorted by name.
  Stream<List<Folder>> watchFolders();

  Future<Folder?> getFolder(String id);

  Future<Folder> createFolder({required String name, required int colorIndex});

  Future<void> updateFolder(String id, {String? name, int? colorIndex});

  /// Deletes the folder. Its documents are kept and moved to the root.
  Future<void> deleteFolder(String id);
}
