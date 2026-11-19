# Performance audit

_Release hardening pass, November 2026 (version 0.7.0)._

This records what was checked, what was measured and what changed. Numbers from the host
test runner (Windows, debug JIT, in-memory SQLite) are upper bounds for relative comparison,
not phone timings.

## 1. Image decoding

Rule: no widget decodes a page image at camera resolution. Every `Image.file` /
`Image.memory` of a page or thumbnail passes `cacheWidth` (decode-time downscale), or shows
bytes that were already rendered at preview size.

| Place | Source | Decode size | Verdict |
| --- | --- | --- | --- |
| `lib/shared/widgets/document_card.dart:40` (`DocumentThumbnail`: home, library grid/list, search results, add-to-folder sheet) | 480 px thumbnail | `cacheWidth: 360` (one cache entry shared by every list) | OK |
| `lib/features/editor/page_organizer_screen.dart:276` | thumbnail | `cacheWidth: 360` | OK |
| `lib/features/pdf_viewer/split_document_sheet.dart:180` | thumbnail | `cacheWidth: 64 × dpr` | OK |
| `lib/features/scanner/camera_capture_view.dart:689` (capture strip) | full camera photo | `cacheWidth: 120` | OK |
| `lib/features/pdf_viewer/document_screen.dart:336` (page pager) | processed page | `cacheWidth: screen width × dpr × 2` (zoom headroom; never upscaled) | OK |
| `lib/features/editor/crop_view.dart:142` | original | `cacheWidth: longest box side × dpr` | OK |
| `lib/features/editor/page_editor_screen.dart:392` (`Image.memory`) | preview JPEG rendered by `PageRenderer` at 1200 px | no `cacheWidth` needed: the bytes are already preview-sized and the view zooms up to 5× | OK |
| PDF viewer | `Printing.raster` at screen width (36–300 dpi), at most 5 pages kept, 12 raster images evicted FIFO | — | OK |

All grids and lists of documents/pages are lazy (`SliverGrid.builder`,
`SliverList.builder`, `GridView.builder`, `ListView.builder`). The search results list is a
plain `ListView`, but it is capped at 50 documents (+10 folders) and `ListView` still builds
and lays out children lazily; not worth changing.

## 2. Full-resolution images in Dart memory and isolates

| Step | Where full-size pixels live | Heavy CPU work |
| --- | --- | --- |
| Import (`ImportPagesUseCase`) | File copy only; size read from the JPEG header (`ImageService.readSize`, in an isolate); thumbnail decoded by the platform codec straight at 480 px | JPEG encode of the thumbnail in an isolate |
| Auto-crop / editor save (`PageRenderer`) | Platform decode capped at 4096 px; homography + rotation drawn on the GPU; one RGBA buffer handed to an isolate | Filters + JPEG encode in `Isolate.run` |
| Edge detection (`PageCropper`) | Decoded at 720 px | Isolate |
| PDF (`PdfBuilder`) | Each page decoded by the platform codec at the size needed for 200 dpi in its box, one page at a time; only compressed JPEGs are kept | JPEG encode per page in an isolate; `PdfDocument.save()` itself runs in a background isolate (`pdfCompute`) |
| OCR (`OcrQueue`) | Nothing: ML Kit / Tesseract get the file path and decode natively | Native, one page at a time |
| PDF viewer | PDF bytes (compressed) + up to 5 rasters at screen size | Platform renderer |

Known, accepted costs (no change):

* `Isolate.run` copies the captured RGBA buffer into the worker (a 4096×4096 page is
  64 MB, briefly twice). `TransferableTypedData.fromList` would copy too, so there is no
  cheap win; pages are processed one at a time, so the peak is bounded.
* `PdfDocument.save()` copies the document graph (all page JPEGs) into its worker isolate,
  so peak memory during export is about 2× the PDF size (a 100-page balanced PDF is
  ~30 MB → ~60–90 MB peak).
* `ImageService.readSize` reads the whole JPEG into the worker isolate to parse the header.
  It runs off the UI thread and the files are a few MB.

## 3. Large-library behaviour

`test/unit/large_library_test.dart` seeds an in-memory database with **1,000 documents,
5,000 pages, 5,000 OCR rows (English + Bengali text), 6,000 search-index rows and 20
folders** and asserts every query below completes in under 3 s (generous on purpose: it
catches full scans and N+1 patterns, which take tens of seconds at this size).

Measured on the host (debug JIT, in-memory SQLite):

| Query | Time |
| --- | --- |
| Seeding (batch insert + FTS indexing) | ~800 ms |
| `watchDocuments` first emission, each of the 5 sorts, all 1,000 rows | 2–13 ms |
| `watchDocuments(limit: 6)` (home "Recent") / favourites / one folder | 0–1 ms |
| `watchDocumentCount` | 9 ms |
| `watchFolders` with document counts, each of the 3 sorts | 0–4 ms |
| `searchGrouped('invoice')` (capped at 50 of 100+ matches) | 7 ms |
| `searchGrouped` Bengali word / prefix / two words / no match | 0–13 ms |
| `countMatches` (all four filters) | 2 ms |
| `unfinishedPages`, `pagesNeedingOcr`, `watchForDocument` | 0–3 ms |
| `indexPageText` for one page (delete by `page_id` + insert) | 1 ms |
| `getPages` of one document | 2 ms |

### Indexes

Present (`lib/data/database/tables.dart`): `idx_documents_folder`,
`idx_documents_updated`, `idx_documents_favorite`, `idx_pages_document (document_id,
page_order)`, `idx_page_ocr_page (page_id, unique)`. These cover the library, folder count,
page list and OCR lookups.

Not indexed, measured as harmless at 5,000 pages; listed for the lead in case libraries get
much larger (schema changes need a migration, so nothing was changed here):

* `documents.created_at`, `documents.file_size`, `documents.title COLLATE NOCASE` — the
  "Created", "Size" and "A–Z" library sorts use a temp B-tree sort (2–4 ms at 1,000 rows).
* `page_ocr.status` — `unfinishedPages` scans `page_ocr` once at startup (0 ms at 5,000).
* `search_index` deletes filter on the `UNINDEXED` columns `page_id` / `document_id`, which
  scans the FTS table (1 ms at 6,000 rows). An external-content FTS table or a rowid map
  would make this O(log n) if it ever matters.

## 4. Startup

Before the first frame `main()` only does: `getApplicationSupportDirectory`, create two
folders, `SharedPreferences.getInstance`, register lazy licence loaders. The database is
opened lazily by the first provider read, in drift's background isolate.

**Change** (`lib/main.dart`): startup recovery (`recoverInterruptedWork`: clean `tmp/`,
remove orphaned document folders) used to be started *before* `runApp` (unawaited), so it
competed with the first build for the database connection and the disk. It now runs in a
post-frame callback, followed by OCR resume (`resumeUnfinished`), one after the other.

## 5. Riverpod providers

Every provider that holds documents, pages, OCR results, search results or image sizes is
`autoDispose` (`documentsProvider`, `documentDetailProvider`, `pagesProvider`,
`pageOcrProvider`, `documentOcrProvider`, `watchedDocumentProvider`,
`groupedSearchProvider`, `searchCountsProvider`, `imageSizeProvider`, `folderProvider`,
`foldersProvider`, `sortedFoldersProvider`, `storageUsageProvider`, the editor's
`_pageProvider`). The non-disposing ones hold services, settings, the router, the OCR queue
(app-wide by design) and recent searches (at most 8 strings). Nothing needed changing.

## 6. Other

* "Clear all data" also clears Flutter's decoded-image cache, so thumbnails of deleted pages
  do not stay in memory (`lib/features/settings/settings_screen.dart`).
