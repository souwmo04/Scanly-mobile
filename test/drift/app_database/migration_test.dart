// Verifies every schema migration against the snapshots in drift_schemas/.
// Regenerate snapshots with `dart run drift_dev make-migrations` after
// changing tables.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanly/data/database/app_database.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('schema upgrades', () {
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      for (final toVersion in versions.skip(i + 1)) {
        test('from $fromVersion to $toVersion', () async {
          final schema = await verifier.schemaAt(fromVersion);
          final db = AppDatabase.forExecutor(schema.newConnection());
          await verifier.migrateAndValidate(db, toVersion);
          await db.close();
        });
      }
    }
  });

  test('v1 → v2 keeps existing documents and pages', () async {
    const createdAt = 1767225600; // 2026-01-01, seconds since epoch
    const folder = v1.FoldersData(
      id: 'f1',
      name: 'Bills',
      color: 2,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    const document = v1.DocumentsData(
      id: 'd1',
      folderId: 'f1',
      title: 'Electricity',
      pageCount: 1,
      thumbnailPath: '/thumbs/p1.jpg',
      fileSize: 1234,
      isFavorite: 1,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    const page = v1.PagesData(
      id: 'p1',
      documentId: 'd1',
      pageOrder: 0,
      originalPath: '/original/p1.jpg',
      width: 1200,
      height: 1600,
      rotation: 90,
      filterType: 'grayscale',
      createdAt: createdAt,
    );

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.forExecutor,
      createItems: (batch, oldDb) {
        batch
          ..insert(oldDb.folders, folder)
          ..insert(oldDb.documents, document)
          ..insert(oldDb.pages, page);
      },
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.folders).get(), hasLength(1));
        final doc = await newDb.select(newDb.documents).getSingle();
        expect(
          (doc.title, doc.fileSize, doc.isFavorite),
          ('Electricity', 1234, 1),
        );
        final migrated = await newDb.select(newDb.pages).getSingle();
        expect(migrated.originalPath, '/original/p1.jpg');
        expect(migrated.rotation, 90);
        expect(migrated.filterType, 'grayscale');
        expect(migrated.cropCorners, isNull);
      },
    );
  });

  test('v2 → v3 adds neutral adjustments and keeps crop corners', () async {
    const createdAt = 1767225600;
    await verifier.testWithDataIntegrity(
      oldVersion: 2,
      newVersion: 3,
      createOld: v2.DatabaseAtV2.new,
      createNew: v3.DatabaseAtV3.new,
      openTestedDatabase: AppDatabase.forExecutor,
      createItems: (batch, oldDb) {
        batch
          ..insert(
            oldDb.documents,
            const v2.DocumentsData(
              id: 'd1',
              title: 'Receipt',
              pageCount: 1,
              fileSize: 10,
              isFavorite: 0,
              createdAt: createdAt,
              updatedAt: createdAt,
            ),
          )
          ..insert(
            oldDb.pages,
            const v2.PagesData(
              id: 'p1',
              documentId: 'd1',
              pageOrder: 0,
              originalPath: '/o.jpg',
              width: 10,
              height: 10,
              rotation: 0,
              filterType: 'original',
              createdAt: createdAt,
              cropCorners: '[0.1,0.1,0.9,0.1,0.9,0.9,0.1,0.9]',
            ),
          );
      },
      validateItems: (newDb) async {
        final page = await newDb.select(newDb.pages).getSingle();
        expect(page.cropCorners, '[0.1,0.1,0.9,0.1,0.9,0.9,0.1,0.9]');
        expect((page.brightness, page.contrast, page.sharpness), (0, 0, 0));
      },
    );
  });

  test('v3 → v4 keeps OCR text and adds empty lines', () async {
    const createdAt = 1767225600;
    await verifier.testWithDataIntegrity(
      oldVersion: 3,
      newVersion: 4,
      createOld: v3.DatabaseAtV3.new,
      createNew: v4.DatabaseAtV4.new,
      openTestedDatabase: AppDatabase.forExecutor,
      createItems: (batch, oldDb) {
        batch
          ..insert(
            oldDb.documents,
            const v3.DocumentsData(
              id: 'd1',
              title: 'Letter',
              pageCount: 1,
              fileSize: 1,
              isFavorite: 0,
              createdAt: createdAt,
              updatedAt: createdAt,
            ),
          )
          ..insert(
            oldDb.pages,
            const v3.PagesData(
              id: 'p1',
              documentId: 'd1',
              pageOrder: 0,
              originalPath: '/o.jpg',
              width: 1,
              height: 1,
              rotation: 0,
              filterType: 'original',
              createdAt: createdAt,
              brightness: 0,
              contrast: 0,
              sharpness: 0,
            ),
          )
          ..insert(
            oldDb.pageOcr,
            const v3.PageOcrData(
              id: 'o1',
              pageId: 'p1',
              extractedText: 'বাংলা text',
              engine: 'tesseract',
              status: 'done',
              updatedAt: createdAt,
            ),
          );
      },
      validateItems: (newDb) async {
        final ocr = await newDb.select(newDb.pageOcr).getSingle();
        expect(ocr.extractedText, 'বাংলা text');
        expect(ocr.lines, isNull);
        expect(ocr.errorMessage, isNull);
      },
    );
  });
}
