/// A user-created folder that groups documents.
class Folder {
  const Folder({
    required this.id,
    required this.name,
    required this.colorIndex,
    required this.createdAt,
    required this.updatedAt,
    this.documentCount = 0,
  });

  final String id;
  final String name;

  /// Index into `AppColors.folderPalette`.
  final int colorIndex;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Number of documents in the folder (computed by queries, not stored).
  final int documentCount;

  @override
  bool operator ==(Object other) =>
      other is Folder &&
      other.id == id &&
      other.name == name &&
      other.colorIndex == colorIndex &&
      other.updatedAt == updatedAt &&
      other.documentCount == documentCount;

  @override
  int get hashCode =>
      Object.hash(id, name, colorIndex, updatedAt, documentCount);
}
