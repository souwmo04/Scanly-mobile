import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/image_service.dart';
import '../../data/datasources/image_picker_gallery.dart';
import '../../data/datasources/mlkit_document_scanner.dart';
import '../../domain/entities/scan_page.dart';
import '../../domain/services/document_scanner.dart';
import '../../domain/usecases/edit_page.dart';
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

/// Lists the device cameras. Injected so tests can simulate devices with or
/// without cameras.
final availableCamerasProvider =
    Provider<Future<List<CameraDescription>> Function()>(
      (ref) => availableCameras,
    );

final editPageProvider = Provider<EditPageUseCase>(
  (ref) => EditPageUseCase(
    documents: ref.watch(documentRepositoryProvider),
    storage: ref.watch(storageServiceProvider),
    images: ref.watch(imageServiceProvider),
  ),
);

/// Pages of a document, updated live (organizer, editor).
final pagesProvider = StreamProvider.autoDispose.family<List<ScanPage>, String>(
  (ref, documentId) =>
      ref.watch(documentRepositoryProvider).watchPages(documentId),
);

/// Displayed size of an image file (EXIF rotation applied).
final imageSizeProvider = FutureProvider.autoDispose.family<ImageSize, String>(
  (ref, path) => ref.watch(imageServiceProvider).readSize(path),
);
