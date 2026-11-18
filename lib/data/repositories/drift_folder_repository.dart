import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../core/services/storage_service.dart';
import '../../domain/entities/folder.dart';
import '../../domain/repositories/folder_repository.dart';
import '../database/app_database.dart';

class DriftFolderRepository implements FolderRepository {
  DriftFolderRepository(this._db, this._storage, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final StorageService _storage;
  final DateTime Function() _clock;

  @override
  Stream<List<Folder>> watchFolders() {
    final docCount = _db.documents.id.count();
    final query =
        _db.select(_db.folders).join([
            leftOuterJoin(
              _db.documents,
              _db.documents.folderId.equalsExp(_db.folders.id),
              useColumns: false,
            ),
          ])
          ..addColumns([docCount])
          ..groupBy([_db.folders.id])
          ..orderBy([
            OrderingTerm.asc(_db.folders.name.collate(Collate.noCase)),
          ]);

    return query.watch().map(
      (rows) => rows
          .map(
            (row) =>
                _toEntity(row.readTable(_db.folders), row.read(docCount) ?? 0),
          )
          .toList(),
    );
  }

  @override
  Future<Folder?> getFolder(String id) async {
    final row = await (_db.select(
      _db.folders,
    )..where((f) => f.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toEntity(row, 0);
  }

  @override
  Future<Folder> createFolder({
    required String name,
    required int colorIndex,
  }) async {
    final cleanName = _validateName(name);
    final now = _clock();
    final id = _storage.newId();
    await _db
        .into(_db.folders)
        .insert(
          FoldersCompanion.insert(
            id: id,
            name: cleanName,
            color: Value(colorIndex),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return Folder(
      id: id,
      name: cleanName,
      colorIndex: colorIndex,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<void> updateFolder(String id, {String? name, int? colorIndex}) async {
    final updated =
        await (_db.update(_db.folders)..where((f) => f.id.equals(id))).write(
          FoldersCompanion(
            name: name == null
                ? const Value.absent()
                : Value(_validateName(name)),
            color: colorIndex == null
                ? const Value.absent()
                : Value(colorIndex),
            updatedAt: Value(_clock()),
          ),
        );
    if (updated == 0) throw const NotFoundException('Folder not found.');
  }

  @override
  Future<void> deleteFolder(String id) async {
    // documents.folder_id has ON DELETE SET NULL, so documents move to root.
    await (_db.delete(_db.folders)..where((f) => f.id.equals(id))).go();
  }

  String _validateName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Please enter a folder name.');
    }
    if (trimmed.length > 120) {
      throw const ValidationException(
        'Folder names can be at most 120 characters.',
      );
    }
    return trimmed;
  }

  Folder _toEntity(FolderRow row, int count) => Folder(
    id: row.id,
    name: row.name,
    colorIndex: row.color,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    documentCount: count,
  );
}
