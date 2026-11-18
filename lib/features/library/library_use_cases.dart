import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/scan_document.dart';
import '../../domain/usecases/duplicate_document.dart';
import '../../shared/providers/core_providers.dart';
import '../../shared/providers/ocr_providers.dart';

/// Copies a document with its page files, edits and recognised text.
final duplicateDocumentProvider = Provider<DuplicateDocumentUseCase>(
  (ref) => DuplicateDocumentUseCase(
    documents: ref.watch(documentRepositoryProvider),
    storage: ref.watch(storageServiceProvider),
    ocr: ref.watch(ocrRepositoryProvider),
  ),
);

/// One document, live. `null` once it has been deleted.
final watchedDocumentProvider = StreamProvider.autoDispose
    .family<ScanDocument?, String>(
      (ref, id) => ref.watch(documentRepositoryProvider).watchDocument(id),
    );
