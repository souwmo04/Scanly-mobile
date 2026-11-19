import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/errors/app_exception.dart';
import '../../core/services/storage_service.dart';
import '../../domain/repositories/maintenance_repository.dart';
import '../database/app_database.dart';

class LocalMaintenanceRepository implements MaintenanceRepository {
  /// [cacheDirectory] returns the app's private cache folder, or null when
  /// there is none. Plugins leave copies of user content there (photos
  /// picked by image_picker, files handed to the share sheet by share_plus),
  /// so [clearAllData] empties it.
  LocalMaintenanceRepository(this._db, this._storage, {this._cacheDirectory});

  final AppDatabase _db;
  final StorageService _storage;
  final Future<Directory?> Function()? _cacheDirectory;

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
    // Reclaim the space freed by deleted rows. VACUUM rewrites the database
    // file, so deleted text does not linger in free pages.
    await _db.customStatement('VACUUM');
    await _clearCache();
  }

  /// Deletes everything inside the cache folder. Best effort: an entry that
  /// is in use is left for the system to remove later.
  Future<void> _clearCache() async {
    final Directory? dir;
    try {
      dir = await _cacheDirectory?.call();
    } on Object {
      return;
    }
    if (dir == null || !dir.existsSync()) return;
    // Never delete Scanly's own storage root, even if it lived in the cache.
    final root = p.normalize(p.absolute(_storage.root.path));
    final entries = await dir.list(followLinks: false).toList();
    for (final entity in entries) {
      final path = p.normalize(p.absolute(entity.path));
      if (path == root || p.isWithin(path, root)) continue;
      try {
        await entity.delete(recursive: true);
      } on FileSystemException {
        // In use or already gone.
      }
    }
  }
}
