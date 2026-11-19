import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/core_providers.dart';
import '../search/recent_searches.dart';

/// Deletes all user data on the device ("Clear all data"):
///
/// * every database row: documents, pages, folders, OCR results and the
///   full-text search index (then `VACUUM`),
/// * every stored file: originals, processed pages, thumbnails, PDFs and
///   their `.meta` sidecars, temporary files,
/// * the app cache folder (plugin copies of picked or shared files),
/// * recent searches, which are kept in shared preferences.
///
/// App settings (theme, scan quality, sort order…) are preferences, not
/// user content, and are kept.
final clearAllDataProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    await ref.read(maintenanceRepositoryProvider).clearAllData();
    await ref.read(recentSearchesProvider.notifier).clear();
  },
);
