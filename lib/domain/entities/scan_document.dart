/// A scanned document made of one or more pages.
///
/// Named `ScanDocument` to avoid clashing with Flutter and Drift types.
class ScanDocument {
  const ScanDocument({
    required this.id,
    required this.title,
    required this.pageCount,
    required this.fileSize,
    required this.isFavorite,
    required this.createdAt,
    required this.updatedAt,
    this.folderId,
    this.pdfPath,
    this.thumbnailPath,
  });

  final String id;
  final String? folderId;
  final String title;
  final int pageCount;

  /// Absolute path of the generated PDF, or `null` until one is generated.
  final String? pdfPath;

  /// Absolute path of the first-page thumbnail, if any.
  final String? thumbnailPath;

  /// Total bytes on disk for this document's files.
  final int fileSize;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  ScanDocument copyWith({
    String? title,
    bool? isFavorite,
    int? pageCount,
    int? fileSize,
    DateTime? updatedAt,
  }) {
    return ScanDocument(
      id: id,
      folderId: folderId,
      title: title ?? this.title,
      pageCount: pageCount ?? this.pageCount,
      pdfPath: pdfPath,
      thumbnailPath: thumbnailPath,
      fileSize: fileSize ?? this.fileSize,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScanDocument &&
      other.id == id &&
      other.folderId == folderId &&
      other.title == title &&
      other.pageCount == pageCount &&
      other.pdfPath == pdfPath &&
      other.thumbnailPath == thumbnailPath &&
      other.fileSize == fileSize &&
      other.isFavorite == isFavorite &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    folderId,
    title,
    pageCount,
    pdfPath,
    thumbnailPath,
    fileSize,
    isFavorite,
    updatedAt,
  );
}
