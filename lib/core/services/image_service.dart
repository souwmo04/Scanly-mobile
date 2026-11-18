import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

import '../errors/app_exception.dart';

/// Pixel size of an image as it is displayed (EXIF rotation applied).
typedef ImageSize = ({int width, int height});

/// Lightweight image helpers that never hold a full-resolution page in
/// Dart memory.
///
/// Decoding uses the platform codec through `dart:ui` (fast, native, and
/// able to downscale while decoding). Only small images are encoded in Dart,
/// and that work runs in a background isolate.
class ImageService {
  const ImageService();

  /// Reads the displayed size of the image at [path].
  ///
  /// For JPEGs only the header and EXIF block are parsed, so this is cheap
  /// even for 50 MP photos. EXIF orientations 5–8 (rotated 90°/270°) swap
  /// width and height.
  Future<ImageSize> readSize(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw StorageException('Image not found: $path');
    }
    final jpegSize = await Isolate.run(() => _readJpegSize(path));
    if (jpegSize != null) return jpegSize;

    // Non-JPEG (PNG, HEIC, WebP…): ask the platform codec for the header.
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = (width: descriptor.width, height: descriptor.height);
      descriptor.dispose();
      return size;
    } on Object catch (e) {
      throw StorageException('This file is not a supported image.', e);
    } finally {
      buffer.dispose();
    }
  }

  /// Creates a JPEG thumbnail whose longest side is at most [maxSide].
  Future<Uint8List> createThumbnail(
    String path, {
    int maxSide = 480,
    int quality = 80,
  }) async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    ui.ImageDescriptor? descriptor;
    ui.Image? image;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      // Constrain only the longest side; the codec keeps the aspect ratio,
      // which stays correct even if EXIF rotation swaps width and height.
      final w = descriptor.width;
      final h = descriptor.height;
      final needsScaling = (w > h ? w : h) > maxSide;
      final codec = await descriptor.instantiateCodec(
        targetWidth: needsScaling && w >= h ? maxSide : null,
        targetHeight: needsScaling && h > w ? maxSide : null,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      image = frame.image;

      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) {
        throw const StorageException('Could not read image pixels.');
      }
      final width = image.width;
      final height = image.height;
      final pixels = rgba.buffer.asUint8List();
      return await Isolate.run(
        () => _encodeJpeg(pixels, width, height, quality),
      );
    } on AppException {
      rethrow;
    } on Object catch (e) {
      throw StorageException('Could not create a preview for this image.', e);
    } finally {
      image?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}

ImageSize? _readJpegSize(String path) {
  final bytes = File(path).readAsBytesSync();
  final decoder = img.JpegDecoder();
  if (!decoder.isValidFile(bytes)) return null;
  final info = decoder.startDecode(bytes);
  if (info == null) return null;
  final orientation = img.decodeJpgExif(bytes)?.imageIfd.orientation ?? 1;
  final rotated = orientation >= 5 && orientation <= 8;
  return rotated
      ? (width: info.height, height: info.width)
      : (width: info.width, height: info.height);
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
