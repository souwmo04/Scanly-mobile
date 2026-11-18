import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_adapters.dart';

/// [LatinTextRecognizer] backed by Google ML Kit (on-device, Latin script).
///
/// On Android the plugin depends on `com.google.mlkit:text-recognition`, the
/// bundled model: it ships inside the APK and never downloads anything.
/// A new recognizer is created per image and always closed, so no native
/// resources outlive a call.
class MlKitLatinRecognizer implements LatinTextRecognizer {
  const MlKitLatinRecognizer();

  @override
  Future<List<List<PixelLine>>> recognizeBlocks(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      return [
        for (final block in recognized.blocks)
          [
            for (final line in block.lines)
              PixelLine(
                line.text,
                line.boundingBox.left,
                line.boundingBox.top,
                line.boundingBox.right,
                line.boundingBox.bottom,
              ),
          ],
      ];
    } finally {
      try {
        await recognizer.close();
      } on Object {
        // Closing a recognizer that failed to start must not hide the
        // original error (or turn a success into a failure).
      }
    }
  }
}
