import 'dart:typed_data';

import '../../core/services/image_service.dart';
import '../../core/services/page_cropper.dart';
import '../../core/services/page_renderer.dart';
import '../../core/services/storage_service.dart';
import '../../core/vision/image_filters.dart';
import '../../core/vision/quad.dart';
import '../entities/page_edits.dart';
import '../entities/scan_page.dart';
import '../repositories/document_repository.dart';

/// Applies editor changes to a page.
///
/// The original capture is never modified: every save re-renders the
/// processed image from it, so edits never stack up quality loss and can be
/// reverted at any time.
class EditPageUseCase {
  const EditPageUseCase({
    required this._documents,
    required this._storage,
    required this._images,
    this._renderer = const PageRenderer(),
    this._cropper = const PageCropper(),
  });

  final DocumentRepository _documents;
  final StorageService _storage;
  final ImageService _images;
  final PageRenderer _renderer;
  final PageCropper _cropper;

  /// Small, fast render for the editor preview.
  Future<Uint8List> preview(
    ScanPage page,
    PageEdits edits, {
    int maxSide = 1200,
  }) => _render(page, edits, maxSide: maxSide, jpegQuality: 80);

  /// Finds the document outline in the original image again.
  Future<Quad?> detectCorners(ScanPage page) =>
      _cropper.detect(page.originalPath);

  /// Renders the page at full resolution and stores the result.
  Future<void> save(
    ScanPage page,
    PageEdits edits, {
    int jpegQuality = 88,
  }) async {
    // A fresh file name on every save, so image caches can't show a stale
    // version of the page.
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final version = '${page.id}-$stamp';
    String? processedPath;
    var displayPath = page.originalPath;

    if (!edits.isIdentity) {
      processedPath = _storage.pagePath(
        page.documentId,
        version,
        DocumentFileKind.processed,
      );
      await _storage.writeBytes(
        processedPath,
        await _render(page, edits, maxSide: 4096, jpegQuality: jpegQuality),
      );
      displayPath = processedPath;
    }

    final thumbnailPath = _storage.pagePath(
      page.documentId,
      version,
      DocumentFileKind.thumbnail,
    );
    try {
      await _storage.writeBytes(
        thumbnailPath,
        await _images.createThumbnail(displayPath),
      );
      final size = await _images.readSize(displayPath);
      await _documents.updatePage(
        page.id,
        PageUpdate(
          processedPath: processedPath,
          thumbnailPath: thumbnailPath,
          width: size.width,
          height: size.height,
          edits: edits,
        ),
      );
    } on Object {
      // Leave the page exactly as it was.
      if (processedPath != null) await _storage.deleteFile(processedPath);
      await _storage.deleteFile(thumbnailPath);
      rethrow;
    }

    // The previous versions are no longer referenced.
    for (final old in [page.processedPath, page.thumbnailPath]) {
      if (old != null && old != page.originalPath) {
        await _storage.deleteFile(old);
      }
    }
  }

  /// Rotates the page a quarter turn and saves it.
  Future<void> rotate(ScanPage page, {bool clockwise = true}) =>
      save(page, PageEdits.fromPage(page).rotated(clockwise: clockwise));

  Future<Uint8List> _render(
    ScanPage page,
    PageEdits edits, {
    required int maxSide,
    required int jpegQuality,
  }) => _renderer.render(
    page.originalPath,
    corners: edits.corners,
    rotation: edits.rotation,
    filter: filterKindOf(edits.filter),
    brightness: edits.brightness,
    contrast: edits.contrast,
    sharpness: edits.sharpness,
    maxSide: maxSide,
    jpegQuality: jpegQuality,
  );
}

/// Maps the domain filter to the pixel-level preset.
FilterKind filterKindOf(PageFilter filter) => switch (filter) {
  PageFilter.original => FilterKind.original,
  PageFilter.grayscale => FilterKind.grayscale,
  PageFilter.blackWhite => FilterKind.blackWhite,
  PageFilter.enhanced => FilterKind.enhanced,
  PageFilter.colorDocument => FilterKind.colorDocument,
};
