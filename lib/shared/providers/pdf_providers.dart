import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/pdf_service.dart';

/// PDF creation, merge and split.
// The PDF engine implementation replaces this body (Milestone 5 in progress).
final documentPdfServiceProvider = Provider<DocumentPdfService>(
  (ref) => throw UnimplementedError('PdfDocumentService not wired yet'),
);
