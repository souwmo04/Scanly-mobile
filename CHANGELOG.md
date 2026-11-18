# Changelog

All notable changes to Scanly are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
