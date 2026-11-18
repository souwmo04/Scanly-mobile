import 'package:flutter_riverpod/flutter_riverpod.dart';
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

final maintenanceRepositoryProvider = Provider<MaintenanceRepository>(
  (ref) => LocalMaintenanceRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(storageServiceProvider),
  ),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => PrefsSettingsRepository(ref.watch(sharedPreferencesProvider)),
);
