import 'dart:io';

import '../../core/errors/app_exception.dart';
import '../../core/services/image_service.dart';
import '../../core/services/page_cropper.dart';
import '../../core/services/storage_service.dart';
import '../../core/vision/quad.dart';
import '../repositories/document_repository.dart';

/// Reports progress as pages are imported: `done` of `total`.
typedef ImportProgress = void Function(int done, int total);

/// One image to turn into a page.
class PageSource {
  const PageSource(this.path, {this.autoCrop = false});

  final String path;

  /// Detect the document edges and save a flattened copy as the processed
  /// page. Use for camera captures and photos; not for pages that Google's
  /// scanner already cropped.
  final bool autoCrop;
}

/// Turns captured or picked images into a saved document.
///
/// For each image, in order:
/// 1. copy it into the document's `original/` folder (never modified later),
/// 2. if [PageSource.autoCrop], detect the document and save a
///    perspective-corrected copy in `processed/` (kept uncropped if no
///    document is found, so the user can crop by hand later),
/// 3. read the displayed size and write a small JPEG thumbnail.
///
/// Pages are processed one at a time so only one full image is in memory.
/// If anything fails, every file written so far is deleted and nothing is
/// added to the database.
class ImportPagesUseCase {
  const ImportPagesUseCase({
    required this._documents,
    required this._storage,
    required this._images,
    this._cropper = const PageCropper(),
  });

  final DocumentRepository _documents;
  final StorageService _storage;
  final ImageService _images;
  final PageCropper _cropper;

  /// Imports [sources] as a new document and returns its id.
  ///
  /// When [deleteSources] is true the source files are removed after a
  /// successful import (use it for temporary scanner/camera captures, never
  /// for files the user owns).
  Future<String> call(
    List<PageSource> sources, {
    required String title,
    String? folderId,
    bool deleteSources = false,
    int jpegQuality = 88,
    ImportProgress? onProgress,
  }) async {
    _checkSources(sources);

    final documentId = _storage.newId();
    final pages = <NewPage>[];
    onProgress?.call(0, sources.length);

    try {
      for (final source in sources) {
        pages.add(
          await _importPage(documentId, source, jpegQuality: jpegQuality),
        );
        onProgress?.call(pages.length, sources.length);
      }

      await _documents.createDocument(
        id: documentId,
        title: title,
        pages: pages,
        folderId: folderId,
      );
    } on Object {
      await _storage.deleteDocumentFiles(documentId);
      rethrow;
    }

    if (deleteSources) _deleteSources(sources);
    return documentId;
  }

  /// Adds [sources] to the end of an existing document.
  Future<void> appendTo(
    String documentId,
    List<PageSource> sources, {
    bool deleteSources = false,
    int jpegQuality = 88,
    ImportProgress? onProgress,
  }) async {
    _checkSources(sources);
    final pages = <NewPage>[];
    onProgress?.call(0, sources.length);
    try {
      for (final source in sources) {
        pages.add(
          await _importPage(documentId, source, jpegQuality: jpegQuality),
        );
        onProgress?.call(pages.length, sources.length);
      }
      await _documents.addPages(documentId, pages);
    } on Object {
      // Remove only the files written by this import.
      await _deletePageFiles(pages);
      rethrow;
    }
    if (deleteSources) _deleteSources(sources);
  }

  /// Replaces the image of [pageId] with a new capture (retake).
  Future<void> replacePage(
    String pageId,
    PageSource source, {
    bool deleteSource = false,
    int jpegQuality = 88,
  }) async {
    _checkSources([source]);
    final existing = await _documents.getPage(pageId);
    if (existing == null) {
      throw const NotFoundException('Page not found.');
    }
    final page = await _importPage(
      existing.documentId,
      source,
      jpegQuality: jpegQuality,
    );
    final ScanPageFiles old;
    try {
      final replaced = await _documents.replacePage(pageId, page);
      old = ScanPageFiles(
        replaced.originalPath,
        replaced.processedPath,
        replaced.thumbnailPath,
      );
    } on Object {
      await _deletePageFiles([page]);
      rethrow;
    }
    for (final path in old.all) {
      await _storage.deleteFile(path);
    }
    if (deleteSource) _deleteSources([source]);
  }

  void _checkSources(List<PageSource> sources) {
    if (sources.isEmpty) {
      throw const ValidationException('There are no pages to save.');
    }
    for (final source in sources) {
      if (!File(source.path).existsSync()) {
        throw const StorageException(
          'A captured page could not be found. Please scan again.',
        );
      }
    }
  }

  Future<void> _deletePageFiles(List<NewPage> pages) async {
    for (final page in pages) {
      for (final path in [
        page.originalPath,
        page.processedPath,
        page.thumbnailPath,
      ]) {
        if (path != null) await _storage.deleteFile(path);
      }
    }
  }

  void _deleteSources(List<PageSource> sources) {
    for (final source in sources) {
      try {
        final file = File(source.path);
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // Temporary capture already gone; nothing to do.
      }
    }
  }

  Future<NewPage> _importPage(
    String documentId,
    PageSource source, {
    required int jpegQuality,
  }) async {
    final pageId = _storage.newId();
    final originalPath = _storage.pagePath(
      documentId,
      pageId,
      DocumentFileKind.original,
      extension: _extensionOf(source.path),
    );
    final processedFile = _storage.pagePath(
      documentId,
      pageId,
      DocumentFileKind.processed,
    );
    final thumbnailPath = _storage.pagePath(
      documentId,
      pageId,
      DocumentFileKind.thumbnail,
    );

    String? processedPath;
    Quad? corners;
    final ImageSize size;
    try {
      await _storage.importFile(File(source.path), originalPath);
      if (source.autoCrop) {
        corners = await _cropper.detect(originalPath);
        if (corners != null) {
          processedPath = processedFile;
          await _storage.writeBytes(
            processedFile,
            await _cropper.flatten(
              originalPath,
              corners,
              jpegQuality: jpegQuality,
            ),
          );
        }
      }
      final displayPath = processedPath ?? originalPath;
      size = await _images.readSize(displayPath);
      await _storage.writeBytes(
        thumbnailPath,
        await _images.createThumbnail(displayPath),
      );
    } on Object {
      // Don't leave half-imported files behind.
      for (final path in [originalPath, processedFile, thumbnailPath]) {
        await _storage.deleteFile(path);
      }
      rethrow;
    }

    return NewPage(
      id: pageId,
      originalPath: originalPath,
      processedPath: processedPath,
      thumbnailPath: thumbnailPath,
      width: size.width,
      height: size.height,
      cropCorners: corners,
    );
  }

  static const _knownExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.heic'};

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '.jpg';
    final ext = path.substring(dot).toLowerCase();
    if (ext == '.jpeg') return '.jpg';
    return _knownExtensions.contains(ext) ? ext : '.jpg';
  }
}

/// Image files that belong to one page.
class ScanPageFiles {
  const ScanPageFiles(this.original, this.processed, this.thumbnail);

  final String original;
  final String? processed;
  final String? thumbnail;

  List<String> get all => [original, ?processed, ?thumbnail];
}
