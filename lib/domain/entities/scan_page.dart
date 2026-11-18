/// Image filter applied to a page. Stored by [name] in the database.
enum PageFilter { original, grayscale, blackWhite, enhanced, colorDocument }

/// One page of a [ScanDocument].
class ScanPage {
  const ScanPage({
    required this.id,
    required this.documentId,
    required this.pageOrder,
    required this.originalPath,
    required this.width,
    required this.height,
    required this.rotation,
    required this.filter,
    required this.createdAt,
    this.processedPath,
    this.thumbnailPath,
  });

  final String id;
  final String documentId;

  /// Zero-based position within the document.
  final int pageOrder;

  /// Untouched capture. Never overwritten.
  final String originalPath;

  /// Cropped and filtered result, or `null` if not processed yet.
  final String? processedPath;
  final String? thumbnailPath;
  final int width;
  final int height;

  /// Clockwise rotation in degrees: 0, 90, 180 or 270.
  final int rotation;
  final PageFilter filter;
  final DateTime createdAt;

  /// The best image to display: processed if available, otherwise original.
  String get displayPath => processedPath ?? originalPath;
}
