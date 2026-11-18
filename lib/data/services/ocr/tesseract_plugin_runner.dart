import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'package:tesseract_ocr/tesseract_ocr.dart';

import 'ocr_adapters.dart';

/// [TesseractRunner] backed by the `tesseract_ocr` plugin
/// (Tesseract4Android on Android, SwiftyTesseract on iOS).
///
/// Trained data (`eng`, `ben` from tessdata_fast) is bundled under
/// `assets/tessdata/` and copied to app storage by the plugin on first use.
class TesseractPluginRunner implements TesseractRunner {
  const TesseractPluginRunner();

  /// Options passed to Tesseract. iOS applies them; the Android plugin
  /// (0.6.0) ignores `options` and always uses automatic page segmentation,
  /// which is the same mode requested here.
  static const options = <String, String>{
    TesseractConfig.preserveInterwordSpaces: '1',
    TesseractConfig.pageSegMode: PageSegmentationMode.auto,
  };

  @override
  Future<String> extractText(String imagePath, String languageCode) {
    return TesseractOcr.extractText(
      imagePath,
      config: OCRConfig(
        language: languageCode,
        // Explicit: the plugin's default engine is Apple Vision on iOS,
        // which has no Bengali.
        engine: OCREngine.tesseract,
        options: options,
      ),
    );
  }
}
