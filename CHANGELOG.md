# Changelog

All notable changes to Scanly are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.7.0] - 2026-11-19 (Milestone 7: Library)

### Added
- Search results grouped by document, with every matching page, filters (All, Documents,
  Text, Folders) with counts, and recent searches.
- Share several documents as PDFs at once.
- Duplicate a document, including its edits and recognized text.
- Document info sheet.
- Folder sorting and an "Add documents" picker inside folders.
- Favorite button removes favorites when every selected document already is one.

### Fixed
- Folder cards no longer overflow at large text sizes.

## [0.6.0] - 2026-11-19 (Milestone 6: OCR)

### Added
- On-device text recognition: English (ML Kit), Bangla and Bangla + English (Tesseract).
- Automatic OCR after scanning and importing, with progress, stop/resume, retry and resume
  after restart. Pages are re-read after they are edited or rotated.
- Page text screen with copy and re-run in another language.
- Search inside a document, plus OCR text in global search (Bengali-safe).
- Searchable PDFs with an invisible text layer and an embedded Bengali font.
- On-device OCR benchmark (character and word error rates).

### Changed
- Release builds include shrinking rules for ML Kit and Tesseract.

## [0.5.0] - 2026-11-18 (Milestone 5: PDF)

### Added
- PDF creation in A4, A5, Letter, Legal or original size, portrait/landscape/automatic,
  with three compression levels. PDFs are cached and refreshed only when pages change.
- PDF viewer with page navigation, go to page, pinch zoom and file size.
- Export options sheet, share sheet and system printing.
- Merge several documents into one, and split a document at chosen pages.

## [0.4.0] - 2026-11-18 (Milestone 4: Editor)

### Added
- Page editor: four-corner crop with a magnifier, auto-detect, full page, rotation,
  filters (original, grayscale, black & white, enhanced, color document), brightness,
  contrast and sharpness, with undo/redo and a live preview.
- Page organizer: drag to reorder, add pages by scanning, rotate, retake, edit and delete.
- "Edit page" and "Pages" actions in the document viewer.
- Edit settings are stored per page (database schema v3); originals are never changed.

### Fixed
- A page that failed to import could leave its copied image behind.
- The adjustment sliders no longer overflow the tool panel.

## [0.3.0] - 2026-11-18 (Milestone 3: Edge detection and auto-capture)

### Added
- Live document edge detection in the built-in camera, with an outline overlay.
- Automatic capture once the document holds steady, with an Auto/Manual toggle.
- Automatic perspective correction of camera captures and imported photos. The
  original photo is always kept.
- Crop corners saved per page for later manual adjustment (database schema v2).

### Changed
- The scanning pipeline is implemented in pure Dart instead of OpenCV, with a GPU
  perspective warp. No native build toolchain is needed and app size stays small.

## [0.2.0] - 2026-11-18 (Milestone 2: Android scanner)

### Added
- Scanning with Google ML Kit Document Scanner on Android: automatic edge detection,
  capture, cropping, filters, multi-page (up to 100 pages per session) and gallery import.
- Built-in camera scanner with flash, camera switching, manual capture, page counter,
  undo and photo import. Used on iOS, when Google's scanner is unavailable, or when chosen.
- "Import from photos" on Home: turns picked images into a document.
- Scanner choice in Settings (Google scanner or built-in camera).
- Import pipeline that keeps byte-identical originals, reads EXIF-aware page sizes,
  creates thumbnails off the UI thread and rolls back cleanly on failure.

### Changed
- Release builds request only the camera permission. Plugin-added microphone, storage and
  network permissions (used by Google telemetry) are removed.

## [0.1.0] - 2026-11-18 (Milestone 1: Foundation)

### Added
- Flutter project for Android and iOS (`com.scanly.app`), iOS 15.5+, Android API 24+.
- Navy/neutral design system with light, dark and system themes.
- Bottom navigation with Home, Files, Search, Settings and a prominent Scan action.
- Home screen with greeting, search launcher, scan card, folders, favorites and recents.
- Files screen with folders, favorites filter, sorting, grid/list layouts and
  multi-select (favorite, move, delete).
- Folder creation, renaming, recoloring and deletion (documents are kept).
- Document viewer that shows stored page images with swipe and pinch-to-zoom.
- Local search over titles, folder names and OCR text using SQLite FTS5, with
  Bengali-aware tokenization and highlighted snippets.
- Settings for theme, scan quality, compression, PDF page size/orientation, OCR language
  and auto-OCR; privacy and about screens; storage usage; clear all data.
- Drift database with foreign keys, cascading deletes and indexes.
- App-private file storage with atomic writes, path safety and startup recovery.
- Unit and widget test suites (42 tests).

### Not yet available
- Camera scanning (Milestone 2/3), editing, PDF export, OCR.
