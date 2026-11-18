import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/folder.dart';
import '../../domain/entities/scan_document.dart';
import '../../domain/entities/scan_page.dart';
import '../../domain/repositories/document_repository.dart';
import 'core_providers.dart';

/// Parameters for [documentsProvider]. Records compare by value, so equal
/// queries share one subscription.
typedef DocumentQuery = ({
  DocumentSort sort,
  String? folderId,
  bool favoritesOnly,
  int? limit,
});

DocumentQuery documentQuery({
  DocumentSort sort = DocumentSort.updatedNewest,
  String? folderId,
  bool favoritesOnly = false,
  int? limit,
}) => (
  sort: sort,
  folderId: folderId,
  favoritesOnly: favoritesOnly,
  limit: limit,
);

final documentsProvider = StreamProvider.autoDispose
    .family<List<ScanDocument>, DocumentQuery>(
      (ref, query) => ref
          .watch(documentRepositoryProvider)
          .watchDocuments(
            sort: query.sort,
            folderId: query.folderId,
            favoritesOnly: query.favoritesOnly,
            limit: query.limit,
          ),
    );

final documentCountProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(documentRepositoryProvider).watchDocumentCount(),
);

final foldersProvider = StreamProvider.autoDispose<List<Folder>>(
  (ref) => ref.watch(folderRepositoryProvider).watchFolders(),
);

final folderProvider = FutureProvider.autoDispose.family<Folder?, String>(
  (ref, id) => ref.watch(folderRepositoryProvider).getFolder(id),
);

/// A document together with its pages, for the document screen.
typedef DocumentWithPages = ({ScanDocument document, List<ScanPage> pages});

final documentDetailProvider = FutureProvider.autoDispose
    .family<DocumentWithPages?, String>((ref, id) async {
      final repo = ref.watch(documentRepositoryProvider);
      final document = await repo.getDocument(id);
      if (document == null) return null;
      return (document: document, pages: await repo.getPages(id));
    });

final storageUsageProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(maintenanceRepositoryProvider).storageUsage(),
);
