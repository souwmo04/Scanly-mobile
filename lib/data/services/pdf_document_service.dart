import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/errors/app_exception.dart';
import '../../core/services/pdf_builder.dart';
import '../../core/services/storage_service.dart';
import '../../domain/entities/ocr_result.dart';
import '../../domain/entities/page_edits.dart';
import '../../domain/entities/scan_page.dart';
import '../../domain/repositories/document_repository.dart';
import '../../domain/repositories/ocr_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/services/pdf_service.dart';

/// Creates, merges and splits documents' PDFs on device.
///
/// **PDF cache.** The PDF is written to `StorageService.pdfPath` (the
/// document's own folder) and described by a sidecar file next to it,
/// `document.pdf.meta` (JSON). The sidecar records the export options and a
/// fingerprint of the document's state: its `updatedAt` and every page's id,
/// image path, image size and image modification time. The cached PDF is
/// reused only when the PDF exists, is newer than the document's
/// `updatedAt`, and the sidecar matches the current options and fingerprint.
/// The fingerprint catches edits that fall within the same second as the
/// last write, which `updatedAt` alone (stored at one-second precision)
/// would miss. The sidecar also records every page's OCR state (the
/// `updatedAt` and content of finished results), so the PDF is rebuilt with
/// its searchable text layer once OCR finishes or changes. Only
/// [OcrStatus.done] results are drawn. The sidecar is deleted before a new PDF is written and
/// written last, so an interrupted export never leaves a matching sidecar
/// next to a PDF made with other settings.
///
/// **Merge and split** create new documents whose page files are copies of
/// the source pages (original, processed and thumbnail), with new page ids
/// and the source pages' edit settings. Sources are never changed. If
/// anything fails, every copied file and created document is removed again.
class PdfDocumentService implements DocumentPdfService {
  PdfDocumentService({
    required this._documents,
    required this._storage,
    required this._settings,
    required this._ocr,
    this._builder = const PdfBuilder(),
  });

  final DocumentRepository _documents;
  final StorageService _storage;
  final SettingsRepository _settings;
  final OcrRepository _ocr;
  final PdfBuilder _builder;

  /// Version 2 added the OCR state; older sidecars never match.
  static const _cacheVersion = 2;

  /// Path of the cache sidecar for [documentId]'s PDF.
  String metaPath(String documentId) => '${_storage.pdfPath(documentId)}.meta';

  @override
  Future<String> ensurePdf(
    String documentId, {
    PdfExportOptions? options,
    bool force = false,
    PdfProgress? onProgress,
  }) async {
    final document = await _documents.getDocument(documentId);
    if (document == null) {
      throw const NotFoundException('Document not found.');
    }
    final pages = await _documents.getPages(documentId);
    if (pages.isEmpty) {
      throw const ValidationException('This document has no pages.');
    }
    final effective =
        options ?? PdfExportOptions.fromSettings(_settings.load());
    final texts = <PdfPageText?>[];
    final ocrKeys = StringBuffer();
    for (final page in pages) {
      final ocr = await _doneOcr(page.id);
      final text = PdfPageText.fromOcr(ocr);
      texts.add(text);
      ocrKeys
        ..write(page.id)
        ..write('|')
        ..write(text == null ? '-' : _ocrKey(ocr!))
        ..write('\n');
    }
    final pdfPath = _storage.pdfPath(documentId);
    final meta = metaPath(documentId);
    final expected = jsonEncode({
      'v': _cacheVersion,
      'options': _optionsKey(effective),
      'updatedAt': document.updatedAt.microsecondsSinceEpoch,
      'pages': _fingerprint(pages),
      'ocr': _fnv1a(ocrKeys.toString()),
    });

    if (!force && _isCacheValid(pdfPath, meta, expected, document.updatedAt)) {
      if (document.pdfPath != pdfPath) {
        await _documents.setPdfPath(documentId, pdfPath);
      }
      onProgress?.call(pages.length, pages.length);
      return pdfPath;
    }

    await _storage.deleteFile(meta);
    final bytes = await _builder.build(
      [for (final page in pages) page.displayPath],
      options: effective,
      title: document.title,
      onProgress: onProgress,
      pageTexts: texts,
    );
    await _storage.writeBytes(pdfPath, bytes);
    await _storage.writeBytes(meta, utf8.encode(expected));
    await _documents.setPdfPath(documentId, pdfPath);
    return pdfPath;
  }

  /// The page's finished OCR, or null. A failing lookup exports the page
  /// without text rather than failing the export.
  Future<PageOcr?> _doneOcr(String pageId) async {
    try {
      final ocr = await _ocr.getForPage(pageId);
      return ocr != null && ocr.status == OcrStatus.done ? ocr : null;
    } on Object {
      return null;
    }
  }

  /// Identity of a finished OCR result: when it was stored and its content.
  static String _ocrKey(PageOcr ocr) {
    final buffer = StringBuffer()
      ..write(ocr.updatedAt.microsecondsSinceEpoch)
      ..write('|')
      ..write(ocr.text);
    for (final line in ocr.lines) {
      buffer
        ..write('\n')
        ..write(line.text)
        ..write('@')
        ..write(line.box?.toList().join(',') ?? '');
    }
    return _fnv1a(buffer.toString());
  }

  bool _isCacheValid(
    String pdfPath,
    String metaPath,
    String expected,
    DateTime updatedAt,
  ) {
    try {
      final pdf = File(pdfPath);
      final meta = File(metaPath);
      if (!pdf.existsSync() || !meta.existsSync()) return false;
      if (!pdf.lastModifiedSync().isAfter(updatedAt)) return false;
      return meta.readAsStringSync() == expected;
    } on FileSystemException {
      return false;
    }
  }

  static String _optionsKey(PdfExportOptions o) =>
      '${o.pageSize.name}/${o.orientation.name}/${o.compression.name}';

  /// Short hash of every page's identity and image file state.
  static String _fingerprint(List<ScanPage> pages) {
    final buffer = StringBuffer();
    for (final page in pages) {
      final file = File(page.displayPath);
      var length = -1;
      var modified = -1;
      try {
        final stat = file.statSync();
        if (stat.type != FileSystemEntityType.notFound) {
          length = stat.size;
          modified = stat.modified.microsecondsSinceEpoch;
        }
      } on FileSystemException {
        // Treated as missing; the builder reports it if we regenerate.
      }
      buffer
        ..write(page.id)
        ..write('|')
        ..write(page.displayPath)
        ..write('|')
        ..write(length)
        ..write('|')
        ..write(modified)
        ..write('\n');
    }
    return '${pages.length}-${_fnv1a(buffer.toString())}';
  }

  /// 64-bit FNV-1a, written as hex.
  static String _fnv1a(String input) {
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    for (final unit in utf8.encode(input)) {
      hash ^= unit;
      hash *= prime;
    }
    return hash.toUnsigned(64).toRadixString(16);
  }

  @override
  Future<String> mergeDocuments(
    List<String> documentIds, {
    required String title,
  }) async {
    if (documentIds.length < 2) {
      throw const ValidationException(
        'Choose at least two documents to merge.',
      );
    }
    final cleanTitle = _validateTitle(title);
    final pages = <ScanPage>[];
    String? folderId;
    for (var i = 0; i < documentIds.length; i++) {
      final document = await _documents.getDocument(documentIds[i]);
      if (document == null) {
        throw const NotFoundException('A document to merge was not found.');
      }
      if (i == 0) folderId = document.folderId;
      pages.addAll(await _documents.getPages(document.id));
    }
    if (pages.isEmpty) {
      throw const ValidationException('These documents have no pages.');
    }
    return _createCopy(cleanTitle, folderId, pages);
  }

  @override
  Future<List<String>> splitDocument(
    String documentId,
    List<int> partStarts,
  ) async {
    final document = await _documents.getDocument(documentId);
    if (document == null) {
      throw const NotFoundException('Document not found.');
    }
    final pages = await _documents.getPages(documentId);
    if (pages.length < 2) {
      throw const ValidationException(
        'A document needs at least two pages to be split.',
      );
    }
    if (partStarts.isEmpty) {
      throw const ValidationException('Choose where to split the document.');
    }
    var previous = 0;
    for (final start in partStarts) {
      if (start <= previous || start >= pages.length) {
        throw const ValidationException(
          'Split points must be in order and inside the document.',
        );
      }
      previous = start;
    }

    final bounds = [0, ...partStarts, pages.length];
    final created = <String>[];
    try {
      for (var i = 0; i < bounds.length - 1; i++) {
        final part = pages.sublist(bounds[i], bounds[i + 1]);
        created.add(
          await _createCopy(
            _partTitle(document.title, i + 1),
            document.folderId,
            part,
          ),
        );
      }
    } on Object {
      await _deleteQuietly(created);
      rethrow;
    }
    return created;
  }

  /// "<title> (part N)", shortened so it fits the 200-character limit.
  static String _partTitle(String title, int n) {
    final suffix = ' (part $n)';
    final room = 200 - suffix.length;
    final base = title.length > room ? title.substring(0, room).trim() : title;
    return '$base$suffix';
  }

  static String _validateTitle(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Please enter a name.');
    }
    if (trimmed.length > 200) {
      throw const ValidationException('Names can be at most 200 characters.');
    }
    return trimmed;
  }

  /// Creates a document whose pages are copies of [sources], in order.
  Future<String> _createCopy(
    String title,
    String? folderId,
    List<ScanPage> sources,
  ) async {
    final documentId = _storage.newId();
    var created = false;
    try {
      final newPages = <NewPage>[];
      for (final source in sources) {
        newPages.add(await _copyPageFiles(source, documentId));
      }
      await _documents.createDocument(
        id: documentId,
        title: title,
        pages: newPages,
        folderId: folderId,
      );
      created = true;

      for (var i = 0; i < sources.length; i++) {
        final source = sources[i];
        final copy = newPages[i];
        final edits = PageEdits.fromPage(source);
        // createDocument already stores the crop; the rest needs updatePage.
        final hasOtherEdits =
            edits.rotation != 0 ||
            edits.filter != PageFilter.original ||
            edits.brightness != 0 ||
            edits.contrast != 0 ||
            edits.sharpness != 0;
        if (!hasOtherEdits) continue;
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
      return documentId;
    } on Object {
      if (created) {
        await _deleteQuietly([documentId]);
      } else {
        try {
          await _storage.deleteDocumentFiles(documentId);
        } on Object {
          // Leftovers are only unreferenced files; nothing else to do.
        }
      }
      rethrow;
    }
  }

  Future<NewPage> _copyPageFiles(ScanPage source, String documentId) async {
    final pageId = _storage.newId();
    Future<String?> copy(String? from, DocumentFileKind kind) async {
      if (from == null) return null;
      final file = File(from);
      if (!file.existsSync()) {
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

  Future<void> _deleteQuietly(List<String> documentIds) async {
    if (documentIds.isEmpty) return;
    try {
      await _documents.deleteDocuments(documentIds);
    } on Object {
      // Best effort cleanup; the original error is more useful.
    }
    for (final id in documentIds) {
      try {
        await _storage.deleteDocumentFiles(id);
      } on Object {
        // Already gone or not removable; nothing more to do.
      }
    }
  }
}
