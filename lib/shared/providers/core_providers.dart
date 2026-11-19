import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/storage_service.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/drift_document_repository.dart';
import '../../data/repositories/drift_folder_repository.dart';
import '../../data/repositories/drift_search_repository.dart';
import '../../data/repositories/local_maintenance_repository.dart';
import '../../data/repositories/prefs_settings_repository.dart';
import '../../domain/repositories/document_repository.dart';
import '../../domain/repositories/folder_repository.dart';
import '../../domain/repositories/maintenance_repository.dart';
import '../../domain/repositories/search_repository.dart';
import '../../domain/repositories/settings_repository.dart';

/// Loaded once in `main()` and injected with `overrideWithValue`.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override in main() before runApp'),
);

/// Resolved once in `main()` (needs the async app-support directory).
final storageServiceProvider = Provider<StorageService>(
  (ref) => throw UnimplementedError('Override in main() before runApp'),
);

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final documentRepositoryProvider = Provider<DocumentRepository>(
  (ref) => DriftDocumentRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(storageServiceProvider),
  ),
);

final folderRepositoryProvider = Provider<FolderRepository>(
  (ref) => DriftFolderRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(storageServiceProvider),
  ),
);

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => DriftSearchRepository(ref.watch(appDatabaseProvider)),
);

/// The app's private cache folder (Android `cacheDir`, iOS `Caches`), or
/// null when the platform has none. Overridden in tests.
final cacheDirectoryProvider = Provider<Future<Directory?> Function()>(
  (ref) => _platformCacheDirectory,
);

Future<Directory?> _platformCacheDirectory() async {
  // Only phones have an app-private cache. On desktop hosts (including
  // `flutter test`) the temporary directory is shared with other programs
  // and must never be emptied.
  if (!Platform.isAndroid && !Platform.isIOS) return null;
  try {
    return await getTemporaryDirectory();
  } on Object {
    return null;
  }
}

final maintenanceRepositoryProvider = Provider<MaintenanceRepository>(
  (ref) => LocalMaintenanceRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(storageServiceProvider),
    cacheDirectory: ref.watch(cacheDirectoryProvider),
  ),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => PrefsSettingsRepository(ref.watch(sharedPreferencesProvider)),
);
