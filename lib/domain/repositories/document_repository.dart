import '../../core/vision/quad.dart';
import '../entities/page_edits.dart';
import '../entities/scan_document.dart';
import '../entities/scan_page.dart';

enum DocumentSort {
  updatedNewest,
  createdNewest,
  createdOldest,
  titleAZ,
  sizeLargest,
}

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
    this.cropCorners,
  });

  final String id;
  final String originalPath;
  final String? processedPath;
  final String? thumbnailPath;
  final int width;
  final int height;
  final Quad? cropCorners;
}

/// New state of an edited page.
class PageUpdate {
  const PageUpdate({
    required this.processedPath,
    required this.thumbnailPath,
    required this.width,
    required this.height,
    required this.edits,
  });

  /// Re-rendered image, or null when the edits are the identity and the
  /// original is shown as-is.
  final String? processedPath;
  final String thumbnailPath;
  final int width;
  final int height;
  final PageEdits edits;
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

  /// Pages of a document in order; emits again whenever they change.
  Stream<List<ScanPage>> watchPages(String documentId);

  Future<ScanPage?> getPage(String pageId);

  /// Saves a re-rendered page: new image paths, size and edit settings.
  /// The caller deletes the previous image files.
  Future<void> updatePage(String pageId, PageUpdate update);

  /// Appends pages to the end of an existing document.
  Future<void> addPages(String documentId, List<NewPage> pages);

  /// Swaps a page's images for a new capture (retake), keeping its position
  /// and resetting its edits. Returns the replaced page so the caller can
  /// delete its old files.
  Future<ScanPage> replacePage(String pageId, NewPage replacement);

  /// Deletes one page and its files. The last page of a document cannot be
  /// deleted; delete the document instead.
  Future<void> deletePage(String pageId);

  /// Stores a new page order. [pageIds] must contain exactly the
  /// document's pages.
  Future<void> reorderPages(String documentId, List<String> pageIds);

  /// Creates a document and its pages in one transaction and indexes the
  /// title for search.
  Future<ScanDocument> createDocument({
    required String id,
    required String title,
    required List<NewPage> pages,
    String? folderId,
  });

  Future<void> rename(String id, String title);

  /// Records the generated PDF (or null to forget it). Does not change the
  /// document's modification time.
  Future<void> setPdfPath(String id, String? pdfPath);

  Future<void> setFavorite(String id, {required bool isFavorite});

  Future<void> moveToFolder(List<String> ids, String? folderId);

  /// Deletes documents, their pages, OCR rows, search index entries and files.
  Future<void> deleteDocuments(List<String> ids);
}
