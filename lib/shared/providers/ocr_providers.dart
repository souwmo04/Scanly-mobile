import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/ocr_repository.dart';
import '../../domain/services/ocr_engine.dart';

// Milestone 6 in progress: the engine and storage implementations replace
// these bodies.

/// On-device text recognition (ML Kit + Tesseract).
final ocrEngineProvider = Provider<OcrEngine>(
  (ref) => throw UnimplementedError('OCR engine not wired yet'),
);

/// OCR results storage and search indexing.
final ocrRepositoryProvider = Provider<OcrRepository>(
  (ref) => throw UnimplementedError('OCR repository not wired yet'),
);
