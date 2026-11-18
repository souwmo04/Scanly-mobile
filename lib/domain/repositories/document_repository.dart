import '../entities/scan_document.dart';
import '../entities/scan_page.dart';

enum DocumentSort { updatedNewest, createdNewest, createdOldest, titleAZ, sizeLargest }

/// Input for one page when creating a document. Files must already exist
/// inside the document's storage folder.
class NewPage {
  const NewPage({
    required this.id,
    required this.originalPath,
    required this.width,
    required this.height,
    this.processedPath,
    this.thumbnailPath,
  });

  final String id;
  final String originalPath;
  final String? processedPath;
  final String? thumbnailPath;
  final int width;
  final int height;
}

abstract interface class DocumentRepository {
  Stream<List<ScanDocument>> watchDocuments({
    DocumentSort sort = DocumentSort.updatedNewest,
    String? folderId,
    bool favoritesOnly = false,
    int? limit,
  });

  Stream<int> watchDocumentCount();

  Future<ScanDocument?> getDocument(String id);

  Future<List<ScanPage>> getPages(String documentId);

  /// Creates a document and its pages in one transaction and indexes the
  /// title for search.
  Future<ScanDocument> createDocument({
    required String id,
    required String title,
    required List<NewPage> pages,
    String? folderId,
  });

  Future<void> rename(String id, String title);

  Future<void> setFavorite(String id, {required bool isFavorite});

  Future<void> moveToFolder(List<String> ids, String? folderId);

  /// Deletes documents, their pages, OCR rows, search index entries and files.
  Future<void> deleteDocuments(List<String> ids);
}
