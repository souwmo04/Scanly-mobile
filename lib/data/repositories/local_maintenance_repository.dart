import 'package:path/path.dart' as p;

import '../../core/errors/app_exception.dart';
import '../../core/services/storage_service.dart';
import '../../domain/repositories/maintenance_repository.dart';
import '../database/app_database.dart';

class LocalMaintenanceRepository implements MaintenanceRepository {
  LocalMaintenanceRepository(this._db, this._storage);

  final AppDatabase _db;
  final StorageService _storage;

  @override
  Future<int> storageUsage() => _storage.sizeOf();

  @override
  Future<void> recoverInterruptedWork() async {
    await _storage.ensureInitialized();
    await _storage.cleanTemp();

    // Remove document folders that have no database row, e.g. when the app
    // was killed after files were written but before the document was saved.
    final known = (await _db.select(_db.documents).get())
        .map((row) => row.id)
        .toSet();
    final dir = _storage.documentsDir;
    if (!dir.existsSync()) return;

    final orphans = <String>[];
    await for (final entity in dir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (!known.contains(name)) orphans.add(name);
    }
    for (final name in orphans) {
      try {
        await _storage.deleteDocumentFiles(name);
      } on AppException {
        // Not a folder Scanly created (invalid id) or locked; leave it.
      }
    }
  }

  @override
  Future<void> clearAllData() async {
    await _db.deleteEverything();
    await _storage.clearAll();
    // Reclaim the space freed by deleted rows.
    await _db.customStatement('VACUUM');
  }
}
