enum AppThemeMode { system, light, dark }

/// Capture resolution preference.
enum ScanQuality { standard, high, maximum }

/// Which scanner opens when the user taps Scan.
enum ScannerEngine {
  /// Google's ML Kit Document Scanner on Android when available, otherwise
  /// the built-in camera.
  automatic,

  /// Always use Scanly's built-in camera.
  builtInCamera,
}

/// Page size used when generating PDFs.
enum PdfPageSize { a4, a5, letter, legal, original }

enum PdfOrientation { portrait, landscape, auto }

enum OcrLanguage { english, bangla, mixed }

/// JPEG compression applied to processed pages and PDFs.
enum ImageCompression { low, balanced, high }

/// User preferences. All values have safe defaults.
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.scanQuality = ScanQuality.high,
    this.scannerEngine = ScannerEngine.automatic,
    this.pdfPageSize = PdfPageSize.a4,
    this.pdfOrientation = PdfOrientation.auto,
    this.ocrLanguage = OcrLanguage.mixed,
    this.autoOcr = true,
    this.compression = ImageCompression.balanced,
  });

  final AppThemeMode themeMode;
  final ScanQuality scanQuality;
  final ScannerEngine scannerEngine;
  final PdfPageSize pdfPageSize;
  final PdfOrientation pdfOrientation;
  final OcrLanguage ocrLanguage;

  /// Run OCR automatically after saving a scan.
  final bool autoOcr;
  final ImageCompression compression;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    ScanQuality? scanQuality,
    ScannerEngine? scannerEngine,
    PdfPageSize? pdfPageSize,
    PdfOrientation? pdfOrientation,
    OcrLanguage? ocrLanguage,
    bool? autoOcr,
    ImageCompression? compression,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      scanQuality: scanQuality ?? this.scanQuality,
      scannerEngine: scannerEngine ?? this.scannerEngine,
      pdfPageSize: pdfPageSize ?? this.pdfPageSize,
      pdfOrientation: pdfOrientation ?? this.pdfOrientation,
      ocrLanguage: ocrLanguage ?? this.ocrLanguage,
      autoOcr: autoOcr ?? this.autoOcr,
      compression: compression ?? this.compression,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeMode == themeMode &&
      other.scanQuality == scanQuality &&
      other.scannerEngine == scannerEngine &&
      other.pdfPageSize == pdfPageSize &&
      other.pdfOrientation == pdfOrientation &&
      other.ocrLanguage == ocrLanguage &&
      other.autoOcr == autoOcr &&
      other.compression == compression;

  @override
  int get hashCode => Object.hash(
    themeMode,
    scanQuality,
    scannerEngine,
    pdfPageSize,
    pdfOrientation,
    ocrLanguage,
    autoOcr,
    compression,
  );
}

/// JPEG quality used when saving processed pages.
extension ImageCompressionQuality on ImageCompression {
  int get jpegQuality => switch (this) {
    ImageCompression.low => 92,
    ImageCompression.balanced => 85,
    ImageCompression.high => 72,
  };
}
