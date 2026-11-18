/// Outcome of a scanning session.
enum ScanStatus {
  /// Pages were captured; see [ScanResult.imagePaths].
  completed,

  /// The user closed the scanner without saving.
  cancelled,

  /// This scanner can't run on this device (e.g. no Google Play services).
  /// Callers should fall back to the built-in camera.
  unavailable,
}

class ScanResult {
  const ScanResult.completed(this.imagePaths)
    : status = ScanStatus.completed,
      message = null;

  const ScanResult.cancelled()
    : status = ScanStatus.cancelled,
      imagePaths = const [],
      message = null;

  const ScanResult.unavailable([this.message])
    : status = ScanStatus.unavailable,
      imagePaths = const [];

  final ScanStatus status;

  /// Absolute paths of captured page images, in page order. These are
  /// temporary files owned by the scanner; import them before they are
  /// cleaned up.
  final List<String> imagePaths;

  /// Why the scanner was unavailable, for logs.
  final String? message;
}

/// A platform scanner that captures, crops and returns page images.
///
/// Android uses Google's ML Kit Document Scanner. Other platforms report
/// [isSupported] = false and the app uses its own camera screen instead.
abstract interface class DocumentScanner {
  bool get isSupported;

  Future<ScanResult> scan({
    required int pageLimit,
    required bool allowGalleryImport,
  });
}

/// Picks existing images from the device's photo library.
abstract interface class GalleryPicker {
  /// Returns picked image paths, or an empty list if the user cancelled.
  Future<List<String>> pickImages();
}
