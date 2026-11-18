import 'dart:io';

import '../../core/errors/app_exception.dart';
import '../../core/services/image_service.dart';
import '../../core/services/storage_service.dart';
import '../repositories/document_repository.dart';

/// Reports progress as pages are imported: `done` of `total`.
typedef ImportProgress = void Function(int done, int total);

/// Turns captured or picked images into a saved document.
///
/// For each image, in order:
/// 1. copy it into the document's `original/` folder (never modified later),
/// 2. read its displayed size,
/// 3. write a small JPEG thumbnail.
///
/// Pages are processed one at a time so only one image is ever decoded.
/// If anything fails, every file written so far is deleted and nothing is
/// added to the database.
class ImportPagesUseCase {
  const ImportPagesUseCase({
    required this._documents,
    required this._storage,
    required this._images,
  });

  final DocumentRepository _documents;
  final StorageService _storage;
  final ImageService _images;

  /// Imports [sourcePaths] as a new document and returns its id.
  ///
  /// When [deleteSources] is true the source files are removed after a
  /// successful import (use it for temporary scanner/camera captures, never
  /// for files the user owns).
  Future<String> call(
    List<String> sourcePaths, {
    required String title,
    String? folderId,
    bool deleteSources = false,
    ImportProgress? onProgress,
  }) async {
    if (sourcePaths.isEmpty) {
      throw const ValidationException('There are no pages to save.');
    }
    for (final path in sourcePaths) {
      if (!File(path).existsSync()) {
        throw const StorageException(
          'A captured page could not be found. Please scan again.',
        );
      }
    }

    final documentId = _storage.newId();
    final pages = <NewPage>[];
    onProgress?.call(0, sourcePaths.length);

    try {
      for (final source in sourcePaths) {
        final pageId = _storage.newId();
        final extension = _extensionOf(source);
        final originalPath = _storage.pagePath(
          documentId,
          pageId,
          DocumentFileKind.original,
          extension: extension,
        );
        await _storage.importFile(File(source), originalPath);

        final size = await _images.readSize(originalPath);
        final thumbnailPath = _storage.pagePath(
          documentId,
          pageId,
          DocumentFileKind.thumbnail,
        );
        await _storage.writeBytes(
          thumbnailPath,
          await _images.createThumbnail(originalPath),
        );

        pages.add(
          NewPage(
            id: pageId,
            originalPath: originalPath,
            thumbnailPath: thumbnailPath,
            width: size.width,
            height: size.height,
          ),
        );
        onProgress?.call(pages.length, sourcePaths.length);
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

    if (deleteSources) {
      for (final source in sourcePaths) {
        try {
          await File(source).delete();
        } on FileSystemException {
          // Temporary capture already gone; nothing to do.
        }
      }
    }
    return documentId;
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
