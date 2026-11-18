import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart'
    as mlkit;

import '../../domain/services/document_scanner.dart';

/// Android scanner backed by Google ML Kit Document Scanner.
///
/// ML Kit shows its own full-screen UI with edge detection, auto-capture,
/// cropping, filters and multi-page support. It runs on device through
/// Google Play services and needs no camera permission in this app.
class MlKitDocumentScanner implements DocumentScanner {
  MlKitDocumentScanner({bool? isAndroid})
    : _isAndroid = isAndroid ?? Platform.isAndroid;

  final bool _isAndroid;

  /// Error messages the plugin returns (see its DocumentScanner.kt).
  static const _cancelledMessage = 'Operation cancelled';

  @override
  bool get isSupported => _isAndroid;

  @override
  Future<ScanResult> scan({
    required int pageLimit,
    required bool allowGalleryImport,
  }) async {
    if (!_isAndroid) {
      return const ScanResult.unavailable('ML Kit scanner is Android-only');
    }

    final scanner = mlkit.DocumentScanner(
      options: mlkit.DocumentScannerOptions(
        documentFormats: const {mlkit.DocumentFormat.jpeg},
        mode: mlkit.ScannerMode.full,
        pageLimit: pageLimit,
        isGalleryImport: allowGalleryImport,
      ),
    );

    try {
      final result = await scanner.scanDocument();
      final images = result.images ?? const <String>[];
      if (images.isEmpty) return const ScanResult.cancelled();
      return ScanResult.completed(images);
    } on PlatformException catch (e) {
      if (e.message == _cancelledMessage) return const ScanResult.cancelled();
      // "Failed to start document scanner": Play services missing, the
      // scanner module couldn't be installed, or the device is unsupported.
      return ScanResult.unavailable(e.message);
    } on MissingPluginException catch (e) {
      return ScanResult.unavailable(e.message);
    } finally {
      try {
        await scanner.close();
      } on Object {
        // Closing is best effort; the native side may already be gone.
      }
    }
  }
}
