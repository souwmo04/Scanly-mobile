import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/errors/app_exception.dart';
import '../../core/services/storage_service.dart';
import '../entities/ocr_result.dart';
import '../entities/page_edits.dart';
import '../entities/scan_page.dart';
import '../repositories/document_repository.dart';
import '../repositories/ocr_repository.dart';

/// Makes an independent copy of a document.
///
/// Every page file (original, processed and thumbnail) is copied under new
/// ids into a new document called "<title> (copy)" in the same folder. Each
/// page keeps its edits (crop, rotation, filter, adjustments) and its
/// recognised text, which is stored again through the OCR repository so the
/// copy is searchable straight away.
///
/// If anything fails, the copied files and any half-created document are
/// removed and the error is rethrown. The source document is never changed.
class DuplicateDocumentUseCase {
  const DuplicateDocumentUseCase({
    required this._documents,
    required this._storage,
    required this._ocr,
  });

  final DocumentRepository _documents;
  final StorageService _storage;
  final OcrRepository _ocr;

  static const _maxTitleLength = 200;
  static const _suffix = ' (copy)';

  /// Duplicates [documentId] and returns the new document's id.
  Future<String> call(String documentId) async {
    final source = await _documents.getDocument(documentId);
    if (source == null) {
      throw const NotFoundException('Document not found.');
    }
    final pages = await _documents.getPages(documentId);
    if (pages.isEmpty) {
      throw const ValidationException('This document has no pages to copy.');
    }

    final newId = _storage.newId();
    var created = false;
    try {
      final copies = <NewPage>[];
      for (final page in pages) {
        copies.add(await _copyPageFiles(page, newId));
      }
      await _documents.createDocument(
        id: newId,
        title: copyTitle(source.title),
        pages: copies,
        folderId: source.folderId,
      );
      created = true;

      for (var i = 0; i < pages.length; i++) {
        await _copyEdits(pages[i], copies[i]);
        await _copyText(pages[i].id, copies[i].id);
      }
      return newId;
    } on Object {
      await _cleanUp(newId, documentCreated: created);
      rethrow;
    }
  }

  /// "<title> (copy)", shortened so it fits the title length limit.
  static String copyTitle(String title) {
    const room = _maxTitleLength - _suffix.length;
    final base = title.length > room ? title.substring(0, room).trim() : title;
    return '$base$_suffix';
  }

  Future<NewPage> _copyPageFiles(ScanPage source, String documentId) async {
    final pageId = _storage.newId();

    Future<String?> copy(String? from, DocumentFileKind kind) async {
      if (from == null) return null;
      final file = File(from);
      if (!file.existsSync()) {
        // Processed images and thumbnails can be re-rendered; the original
        // cannot, so a missing original fails the copy.
        if (kind == DocumentFileKind.original) {
          throw const StorageException('A page image is missing.');
        }
        return null;
      }
      final extension = p.extension(from).isEmpty ? '.jpg' : p.extension(from);
      final target = _storage.pagePath(
        documentId,
        pageId,
        kind,
        extension: extension,
      );
      await _storage.importFile(file, target);
      return target;
    }

    final original = await copy(source.originalPath, DocumentFileKind.original);
    final processed = await copy(
      source.processedPath,
      DocumentFileKind.processed,
    );
    final thumbnail = await copy(
      source.thumbnailPath,
      DocumentFileKind.thumbnail,
    );
    return NewPage(
      id: pageId,
      originalPath: original!,
      processedPath: processed,
      thumbnailPath: thumbnail,
      width: source.width,
      height: source.height,
      cropCorners: source.cropCorners,
    );
  }

  /// createDocument stores the crop; rotation, filter and adjustments are
  /// written with updatePage.
  Future<void> _copyEdits(ScanPage source, NewPage copy) async {
    final edits = PageEdits.fromPage(source);
    final hasOtherEdits =
        edits.rotation != 0 ||
        edits.filter != PageFilter.original ||
        edits.brightness != 0 ||
        edits.contrast != 0 ||
        edits.sharpness != 0;
    if (!hasOtherEdits) return;
    await _documents.updatePage(
      copy.id,
      PageUpdate(
        processedPath: copy.processedPath,
        thumbnailPath:
            copy.thumbnailPath ?? copy.processedPath ?? copy.originalPath,
        width: copy.width,
        height: copy.height,
        edits: edits,
      ),
    );
  }

  /// Copies finished OCR results. Pages still waiting or failed are left
  /// without text, so they can be recognised again later.
  Future<void> _copyText(String sourcePageId, String copyPageId) async {
    final ocr = await _ocr.getForPage(sourcePageId);
    if (ocr == null || ocr.status != OcrStatus.done) return;
    await _ocr.saveResult(
      copyPageId,
      OcrResult(
        text: ocr.text,
        lines: ocr.lines,
        languageCode: ocr.languageCode ?? 'eng',
        engine: ocr.engine ?? OcrEngineId.mlKit,
      ),
    );
  }

  Future<void> _cleanUp(
    String documentId, {
    required bool documentCreated,
  }) async {
    if (documentCreated) {
      try {
        // Removes rows, OCR, search entries and files.
        await _documents.deleteDocuments([documentId]);
      } on Object {
        // Fall through to the file cleanup below.
      }
    }
    try {
      await _storage.deleteDocumentFiles(documentId);
    } on Object {
      // Leftovers are only unreferenced files; the original error matters.
    }
  }
}
