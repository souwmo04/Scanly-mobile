import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/image_service.dart';
import '../../data/datasources/image_picker_gallery.dart';
import '../../data/datasources/mlkit_document_scanner.dart';
import '../../domain/services/document_scanner.dart';
import '../../domain/usecases/import_pages.dart';
import 'core_providers.dart';

final imageServiceProvider = Provider<ImageService>(
  (ref) => const ImageService(),
);

/// Platform scanner (ML Kit on Android; unsupported elsewhere).
final documentScannerProvider = Provider<DocumentScanner>(
  (ref) => MlKitDocumentScanner(),
);

final galleryPickerProvider = Provider<GalleryPicker>(
  (ref) => ImagePickerGallery(),
);

final importPagesProvider = Provider<ImportPagesUseCase>(
  (ref) => ImportPagesUseCase(
    documents: ref.watch(documentRepositoryProvider),
    storage: ref.watch(storageServiceProvider),
    images: ref.watch(imageServiceProvider),
  ),
);

/// ML Kit's limit per session; Scanly itself imposes no page limit.
const maxPagesPerScan = 100;
