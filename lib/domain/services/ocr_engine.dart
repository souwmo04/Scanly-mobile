import '../entities/app_settings.dart';
import '../entities/ocr_result.dart';

/// Recognises text in a page image, entirely on the device.
///
/// * English: Google ML Kit text recognition (Latin script), falling back to
///   Tesseract `eng` if ML Kit is unavailable.
/// * Bangla: Tesseract `ben`.
/// * Mixed: Tesseract `ben+eng` in a single pass, so no text is duplicated.
abstract interface class OcrEngine {
  /// Throws an `AppException` with a user-facing message on failure.
  Future<OcrResult> recognize(String imagePath, OcrLanguage language);
}
