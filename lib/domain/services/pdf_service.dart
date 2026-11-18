import 'dart:ui' show Rect;

import '../entities/app_settings.dart';

/// How a document is laid out when written as a PDF.
class PdfExportOptions {
  const PdfExportOptions({
    this.pageSize = PdfPageSize.a4,
    this.orientation = PdfOrientation.auto,
    this.compression = ImageCompression.balanced,
  });

  /// The user's defaults from Settings.
  factory PdfExportOptions.fromSettings(AppSettings settings) =>
      PdfExportOptions(
        pageSize: settings.pdfPageSize,
        orientation: settings.pdfOrientation,
        compression: settings.compression,
      );

  final PdfPageSize pageSize;
  final PdfOrientation orientation;
  final ImageCompression compression;

  PdfExportOptions copyWith({
    PdfPageSize? pageSize,
    PdfOrientation? orientation,
    ImageCompression? compression,
  }) => PdfExportOptions(
    pageSize: pageSize ?? this.pageSize,
    orientation: orientation ?? this.orientation,
    compression: compression ?? this.compression,
  );

  @override
  bool operator ==(Object other) =>
      other is PdfExportOptions &&
      other.pageSize == pageSize &&
      other.orientation == orientation &&
      other.compression == compression;

  @override
  int get hashCode => Object.hash(pageSize, orientation, compression);
}

/// Reports progress while pages are written: `done` of `total`.
typedef PdfProgress = void Function(int done, int total);

/// Creates, merges and splits document PDFs. Everything runs on device.
abstract interface class DocumentPdfService {
  /// Returns the path of an up-to-date PDF of the document, written with
  /// [options] (defaults: the user's settings). Reuses the cached file when
  /// the document has not changed since it was written, unless [force].
  /// The PDF lives in the document's private folder.
  Future<String> ensurePdf(
    String documentId, {
    PdfExportOptions? options,
    bool force = false,
    PdfProgress? onProgress,
  });

  /// Merges documents, in the given order, into a new document and returns
  /// its id. The source documents are kept.
  Future<String> mergeDocuments(
    List<String> documentIds, {
    required String title,
  });

  /// Splits a document into new documents. [partStarts] are the zero-based
  /// indexes of the first page of every part after the first, ascending
  /// (e.g. `[3, 5]` on 8 pages gives pages 1–3, 4–5 and 6–8). Returns the new
  /// document ids in order. The source document is kept.
  Future<List<String>> splitDocument(String documentId, List<int> partStarts);
}

/// System share sheet and print dialog.
abstract interface class ShareService {
  /// Opens the share sheet for [paths] (e.g. save to Files, send by email).
  /// [origin] is the on-screen area (global coordinates) the share started
  /// from; iPad needs it to anchor the share popover.
  Future<void> shareFiles(List<String> paths, {String? subject, Rect? origin});

  /// Opens the system print dialog for the PDF at [path].
  Future<void> printPdf(String path, {required String jobName});
}
