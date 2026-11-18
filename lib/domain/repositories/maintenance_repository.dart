/// Storage housekeeping that spans the database and the filesystem.
abstract interface class MaintenanceRepository {
  /// Bytes used by all stored documents and temporary files.
  Future<int> storageUsage();

  /// Removes leftovers from interrupted operations. Safe to call on start.
  Future<void> recoverInterruptedWork();

  /// Permanently deletes every document, folder, OCR result and file.
  Future<void> clearAllData();
}
