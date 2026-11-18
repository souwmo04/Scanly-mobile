import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/pdf_builder.dart';
import '../../data/services/pdf_document_service.dart';
import '../../domain/services/pdf_service.dart';
import 'core_providers.dart';
import 'ocr_providers.dart';
import 'scanner_providers.dart';

/// PDF creation (with a searchable OCR text layer), merge and split.
final documentPdfServiceProvider = Provider<DocumentPdfService>(
  (ref) => PdfDocumentService(
    documents: ref.watch(documentRepositoryProvider),
    storage: ref.watch(storageServiceProvider),
    settings: ref.watch(settingsRepositoryProvider),
    ocr: ref.watch(ocrRepositoryProvider),
    builder: PdfBuilder(
      images: ref.watch(imageServiceProvider),
      bengaliFont: PdfBuilder.bundledBengaliFont,
    ),
  ),
);
