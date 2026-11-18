import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/services/pdf_service.dart';
import '../errors/app_exception.dart';
import 'image_service.dart';
import 'page_renderer.dart';

/// Where and how large one page image is drawn, in PDF points (1/72 inch).
typedef PdfPageLayout = ({
  PdfPageFormat format,
  double x,
  double y,
  double width,
  double height,
});

/// Builds image-only PDFs from page images, entirely on device.
///
/// * Fixed sizes (A4, A5, Letter, Legal) use the standard paper sizes with a
///   [margin] on every side; the image is fitted inside, keeping its aspect
///   ratio, and centred.
/// * [PdfPageSize.original] sizes each page to its image as if it had been
///   scanned at [originalDpi], with no margin. Pages are capped at
///   [maxPagePoints] (200 inches, the PDF viewer limit) and at least one
///   point on each side. The orientation option does not apply: the page
///   always follows the image.
/// * Orientation `auto` turns a page to landscape when its image is wider
///   than tall.
/// * Every image is decoded by the platform codec (EXIF orientation applied)
///   directly at the size needed for [targetDpi] on the page, so a 4000 px
///   photo is never held at full size, then re-encoded as JPEG at the
///   compression quality in a background isolate. Pages are processed one
///   at a time; only the compressed JPEGs are kept until the PDF is saved.
class PdfBuilder {
  const PdfBuilder({this._images = const ImageService()});

  final ImageService _images;

  /// Resolution assumed for [PdfPageSize.original] pages.
  static const double originalDpi = 150;

  /// Images are downscaled to at most this resolution on the page.
  static const double targetDpi = 200;

  /// Margin around the image on fixed paper sizes: 0.25 inch (6.35 mm).
  static const double margin = 18;

  /// Largest page side PDF viewers accept (200 inches).
  static const double maxPagePoints = 14400;

  /// Longest side, in pixels, an image is ever embedded at.
  static const int maxImageSide = 6000;

  /// Writes a PDF with one page per image in [imagePaths], in order, and
  /// returns its bytes. [onProgress] is called after every page.
  Future<Uint8List> build(
    List<String> imagePaths, {
    required PdfExportOptions options,
    String? title,
    PdfProgress? onProgress,
  }) async {
    if (imagePaths.isEmpty) {
      throw const ValidationException('There are no pages to export.');
    }
    final document = PdfDocument(version: PdfVersion.pdf_1_4);
    // Registers itself as the document's /Info dictionary.
    PdfInfo(document, title: title, creator: 'Scanly', producer: 'Scanly');

    final total = imagePaths.length;
    onProgress?.call(0, total);
    for (var i = 0; i < total; i++) {
      await _addPage(document, imagePaths[i], options);
      onProgress?.call(i + 1, total);
    }
    try {
      return await document.save();
    } on Object catch (e) {
      throw StorageException('The PDF could not be created.', e);
    }
  }

  Future<void> _addPage(
    PdfDocument document,
    String path,
    PdfExportOptions options,
  ) async {
    if (!File(path).existsSync()) {
      throw const StorageException('A page image is missing.');
    }
    final size = await _images.readSize(path);
    final planned = layoutFor(options, size.width, size.height);

    // Pixels needed for [targetDpi] across the longest side of the image box.
    final boxLongest = math.max(planned.width, planned.height);
    final neededSide = (boxLongest / PdfPageFormat.inch * targetDpi).ceil();
    final maxSide = math.max(1, math.min(neededSide, maxImageSide));

    final jpeg = await _encodePage(
      path,
      maxSide: maxSide,
      quality: options.compression.jpegQuality,
    );
    final image = PdfImage.jpeg(
      document,
      image: jpeg.bytes,
      orientation: PdfImageOrientation.topLeft,
    );
    // Place the image by its decoded size, which is exact after EXIF.
    final layout = layoutFor(options, jpeg.width, jpeg.height);
    final page = PdfPage(document, pageFormat: layout.format);
    page.getGraphics().drawImage(
      image,
      layout.x,
      layout.y,
      layout.width,
      layout.height,
    );
  }

  /// Page format and image placement for an image of
  /// [imageWidth]×[imageHeight] pixels.
  static PdfPageLayout layoutFor(
    PdfExportOptions options,
    int imageWidth,
    int imageHeight,
  ) {
    final iw = math.max(1, imageWidth).toDouble();
    final ih = math.max(1, imageHeight).toDouble();

    if (options.pageSize == PdfPageSize.original) {
      var w = iw / originalDpi * PdfPageFormat.inch;
      var h = ih / originalDpi * PdfPageFormat.inch;
      final longest = math.max(w, h);
      if (longest > maxPagePoints) {
        final s = maxPagePoints / longest;
        w *= s;
        h *= s;
      }
      w = math.max(1, w);
      h = math.max(1, h);
      return (format: PdfPageFormat(w, h), x: 0, y: 0, width: w, height: h);
    }

    final paper = switch (options.pageSize) {
      PdfPageSize.a4 => PdfPageFormat.a4,
      PdfPageSize.a5 => PdfPageFormat.a5,
      PdfPageSize.letter => PdfPageFormat.letter,
      PdfPageSize.legal => PdfPageFormat.legal,
      PdfPageSize.original => throw StateError('unreachable'),
    };
    final landscape = switch (options.orientation) {
      PdfOrientation.portrait => false,
      PdfOrientation.landscape => true,
      PdfOrientation.auto => iw > ih,
    };
    final turned = landscape ? paper.landscape : paper.portrait;
    final format = PdfPageFormat(turned.width, turned.height);

    final availW = format.width - 2 * margin;
    final availH = format.height - 2 * margin;
    final scale = math.min(availW / iw, availH / ih);
    final w = iw * scale;
    final h = ih * scale;
    return (
      format: format,
      x: (format.width - w) / 2,
      y: (format.height - h) / 2,
      width: w,
      height: h,
    );
  }

  static Future<({Uint8List bytes, int width, int height})> _encodePage(
    String path, {
    required int maxSide,
    required int quality,
  }) async {
    final ui.Image image = await PageRenderer.decodeImage(
      path,
      maxSide: maxSide,
    );
    try {
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) {
        throw const StorageException('Could not read the page pixels.');
      }
      final width = image.width;
      final height = image.height;
      final pixels = rgba.buffer.asUint8List();
      final bytes = await Isolate.run(
        () => _encodeJpeg(pixels, width, height, quality),
      );
      return (bytes: bytes, width: width, height: height);
    } finally {
      image.dispose();
    }
  }
}

Uint8List _encodeJpeg(Uint8List rgba, int width, int height, int quality) {
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    numChannels: 4,
  );
  return img.encodeJpg(image, quality: quality);
}
