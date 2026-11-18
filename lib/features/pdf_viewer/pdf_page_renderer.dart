import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

/// One rasterized PDF page, ready to paint.
class RenderedPdfPage {
  const RenderedPdfPage({
    required this.image,
    required this.width,
    required this.height,
  });

  final ImageProvider image;

  /// Bitmap size in pixels.
  final int width;
  final int height;

  double get aspectRatio => height == 0 ? 1 : width / height;
}

/// An opened PDF file whose pages can be rendered one at a time.
abstract interface class OpenedPdf {
  /// Size of the file in bytes.
  int get sizeBytes;

  /// Renders the zero-based page [index] at roughly [targetWidth] pixels wide.
  Future<RenderedPdfPage> renderPage(int index, {required int targetWidth});

  /// Releases the file bytes and cached images.
  void dispose();
}

/// Turns PDF pages into images for on-screen preview.
abstract interface class PdfPageRenderer {
  /// Whether this platform can rasterize PDF pages.
  Future<bool> isAvailable();

  /// Loads the PDF at [path].
  Future<OpenedPdf> open(String path);
}

/// Renders pages with the platform's own PDF engine through
/// `Printing.raster` (PdfRenderer on Android, PDFKit on iOS).
class PrintingPdfPageRenderer implements PdfPageRenderer {
  const PrintingPdfPageRenderer();

  @override
  Future<bool> isAvailable() async {
    try {
      return (await Printing.info()).canRaster;
    } on Object {
      return false;
    }
  }

  @override
  Future<OpenedPdf> open(String path) async {
    final bytes = await File(path).readAsBytes();
    return _PrintingOpenedPdf(bytes);
  }
}

class _PrintingOpenedPdf implements OpenedPdf {
  _PrintingOpenedPdf(this._bytes);

  Uint8List _bytes;
  final _images = <ImageProvider>[];

  /// Page width in PDF points (1/72 inch), learned from the first rendered
  /// page. Starts at A4 width.
  double _pageWidthPoints = 595;

  @override
  int get sizeBytes => _bytes.length;

  @override
  Future<RenderedPdfPage> renderPage(
    int index, {
    required int targetWidth,
  }) async {
    final dpi = (targetWidth / _pageWidthPoints * 72).clamp(36.0, 300.0);
    final raster = await Printing.raster(
      _bytes,
      pages: [index],
      dpi: dpi,
    ).first;
    _pageWidthPoints = raster.width / dpi * 72;
    final image = PdfRasterImage(raster);
    _images.add(image);
    if (_images.length > 12) unawaited(_images.removeAt(0).evict());
    return RenderedPdfPage(
      image: image,
      width: raster.width,
      height: raster.height,
    );
  }

  @override
  void dispose() {
    for (final image in _images) {
      unawaited(image.evict());
    }
    _images.clear();
    _bytes = Uint8List(0);
  }
}

/// Page rasterizer used by the PDF viewer. Overridden in tests.
final pdfPageRendererProvider = Provider<PdfPageRenderer>(
  (ref) => const PrintingPdfPageRenderer(),
);
