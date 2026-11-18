import '../entities/ocr_result.dart';

/// Stores OCR results per page and keeps the search index in sync.
abstract interface class OcrRepository {
  Future<PageOcr?> getForPage(String pageId);

  Stream<PageOcr?> watchForPage(String pageId);

  /// OCR state of every page of a document, keyed by page id. Pages that
  /// were never processed are absent.
  Stream<Map<String, PageOcr>> watchForDocument(String documentId);

  /// Marks pages as waiting for OCR (creates rows when missing).
  Future<void> markPending(List<String> pageIds);

  Future<void> markProcessing(String pageId);

  /// Stores a finished result and indexes its text for search under the
  /// page's current number.
  Future<void> saveResult(String pageId, OcrResult result);

  Future<void> markFailed(String pageId, String message);

  /// Pages of the document whose OCR is missing, pending or failed, in page
  /// order (used to resume interrupted work).
  Future<List<String>> pagesNeedingOcr(String documentId);

  /// Every page in the library that is pending or was left processing
  /// (e.g. the app was closed mid-run), oldest first.
  Future<List<String>> unfinishedPages();
}
