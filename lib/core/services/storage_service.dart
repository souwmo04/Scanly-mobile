import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../errors/app_exception.dart';

/// Sub-folders inside each document folder.
enum DocumentFileKind {
  original('original'),
  processed('processed'),
  thumbnail('thumbs');

  const DocumentFileKind(this.folderName);
  final String folderName;
}

/// Manages Scanly's app-private files.
///
/// Layout:
/// ```
/// <root>/documents/<documentId>/original/<pageId>.jpg
/// <root>/documents/<documentId>/processed/<pageId>.jpg
/// <root>/documents/<documentId>/thumbs/<pageId>.jpg
/// <root>/documents/<documentId>/document.pdf
/// <root>/tmp/
/// ```
///
/// All writes go to `tmp/` first and are then renamed into place, so an
/// interrupted write never leaves a half-written file in a document folder.
class StorageService {
  StorageService(this.root, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  /// App-private root directory, e.g. `<support dir>/scanly`.
  final Directory root;
  final Uuid _uuid;

  Directory get documentsDir => Directory(p.join(root.path, 'documents'));
  Directory get tempDir => Directory(p.join(root.path, 'tmp'));

  /// Generates a new random identifier for documents, pages and folders.
  String newId() => _uuid.v4();

  /// Creates the root folders. Safe to call repeatedly.
  Future<void> ensureInitialized() async {
    try {
      await documentsDir.create(recursive: true);
      await tempDir.create(recursive: true);
    } on FileSystemException catch (e) {
      throw StorageException('Could not prepare app storage.', e);
    }
  }

  Directory documentDir(String documentId) {
    _validateId(documentId);
    return Directory(p.join(documentsDir.path, documentId));
  }

  /// Path where a page image of [kind] should be stored.
  String pagePath(
    String documentId,
    String pageId,
    DocumentFileKind kind, {
    String extension = '.jpg',
  }) {
    _validateId(pageId);
    return p.join(
      documentDir(documentId).path,
      kind.folderName,
      '$pageId$extension',
    );
  }

  String pdfPath(String documentId) =>
      p.join(documentDir(documentId).path, 'document.pdf');

  /// Returns a unique path inside the temp folder.
  String tempPath({String extension = ''}) =>
      p.join(tempDir.path, '${newId()}$extension');

  /// Writes [bytes] to [targetPath] atomically (temp file, then rename).
  Future<File> writeBytes(String targetPath, List<int> bytes) async {
    _ensureInsideRoot(targetPath);
    final temp = File(tempPath(extension: p.extension(targetPath)));
    try {
      await temp.parent.create(recursive: true);
      await temp.writeAsBytes(bytes, flush: true);
      return await _moveInto(temp, targetPath);
    } on FileSystemException catch (e) {
      await _deleteQuietly(temp);
      throw StorageException('Could not save the file.', e);
    }
  }

  /// Copies [source] (which may be outside app storage, e.g. a scanner
  /// cache) to [targetPath] atomically. The source is left untouched.
  Future<File> importFile(File source, String targetPath) async {
    _ensureInsideRoot(targetPath);
    final temp = File(tempPath(extension: p.extension(targetPath)));
    try {
      await temp.parent.create(recursive: true);
      await source.copy(temp.path);
      return await _moveInto(temp, targetPath);
    } on FileSystemException catch (e) {
      await _deleteQuietly(temp);
      throw StorageException('Could not import the file.', e);
    }
  }

  /// Deletes a document's entire folder. Missing folders are ignored.
  Future<void> deleteDocumentFiles(String documentId) async {
    final dir = documentDir(documentId);
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on FileSystemException catch (e) {
      throw StorageException('Could not delete document files.', e);
    }
  }

  /// Deletes one file if it exists and lives inside app storage.
  Future<void> deleteFile(String path) async {
    _ensureInsideRoot(path);
    await _deleteQuietly(File(path));
  }

  /// Total size in bytes of a directory tree (defaults to all app storage).
  Future<int> sizeOf([Directory? directory]) async {
    final dir = directory ?? root;
    if (!dir.existsSync()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } on FileSystemException {
          // The file vanished while we were counting; skip it.
        }
      }
    }
    return total;
  }

  /// Removes leftovers from interrupted operations. Call on app start.
  Future<void> cleanTemp() async {
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      await tempDir.create(recursive: true);
    } on FileSystemException catch (e) {
      throw StorageException('Could not clean temporary files.', e);
    }
  }

  /// Deletes every stored document file. Used by "Clear all data".
  Future<void> clearAll() async {
    try {
      if (documentsDir.existsSync()) {
        await documentsDir.delete(recursive: true);
      }
      await cleanTemp();
      await documentsDir.create(recursive: true);
    } on FileSystemException catch (e) {
      throw StorageException('Could not clear stored files.', e);
    }
  }

  Future<File> _moveInto(File temp, String targetPath) async {
    await Directory(p.dirname(targetPath)).create(recursive: true);
    final target = File(targetPath);
    if (target.existsSync()) await target.delete();
    return temp.rename(targetPath);
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Best effort; temp cleanup on next start will catch leftovers.
    }
  }

  void _ensureInsideRoot(String path) {
    final normalizedRoot = p.normalize(p.absolute(root.path));
    final normalizedPath = p.normalize(p.absolute(path));
    if (!p.isWithin(normalizedRoot, normalizedPath)) {
      throw const StorageException('Refusing to touch a file outside app storage.');
    }
  }

  static final _idPattern = RegExp(r'^[A-Za-z0-9_-]+$');

  void _validateId(String id) {
    if (!_idPattern.hasMatch(id)) {
      throw ValidationException('Invalid identifier: $id');
    }
  }
}
