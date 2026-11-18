import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/drift_ocr_repository.dart';
import '../../data/services/ocr/device_ocr_engine.dart';
import '../../data/services/ocr/mlkit_latin_recognizer.dart';
import '../../data/services/ocr/tesseract_plugin_runner.dart';
import '../../domain/repositories/ocr_repository.dart';
import '../../domain/services/ocr_engine.dart';
import 'core_providers.dart';
import 'scanner_providers.dart';

/// On-device text recognition (ML Kit + Tesseract).
final ocrEngineProvider = Provider<OcrEngine>(
  (ref) => DeviceOcrEngine(
    latin: const MlKitLatinRecognizer(),
    tesseract: const TesseractPluginRunner(),
    readSize: ref.watch(imageServiceProvider).readSize,
  ),
);

/// OCR results storage and search indexing.
final ocrRepositoryProvider = Provider<OcrRepository>(
  (ref) => DriftOcrRepository(ref.watch(appDatabaseProvider)),
);
