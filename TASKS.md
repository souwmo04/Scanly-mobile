# Scanly — Task Tracker

Work through these one at a time, top to bottom. Each task is checked off only after it
builds, passes `flutter analyze`, has its tests passing, and is committed and pushed.

Legend: `[x]` done · `[ ]` to do · `[~]` in progress · `[!]` needs macOS / a physical device

---

## Milestone 0: Environment and repository

- [x] Inspect the repository (empty at start)
- [x] Check the toolchain: Git 2.53, Java 26, Android SDK (platform 36.1, build-tools 36/37)
- [x] Install Flutter 3.50.0 / Dart 3.14.0 into `tools/flutter` (project-local, not on C:)
- [x] Install a project-local Android SDK, NDK 28.2 and JDK 21 under `tools/`; `flutter doctor` passes for Android
- [x] Accept the Android SDK licenses
- [x] Initialize Git and connect the `origin` remote (github.com/souwmo04/Scanly-mobile)
- [x] Write TASKS.md, README, CONTRIBUTING, CHANGELOG, LICENSE, PRIVACY, ARCHITECTURE
- [ ] Set the GitHub repository description (do this on GitHub; the `gh` CLI isn't installed)

## Milestone 1: Foundation ✅

- [x] `flutter create` for Android and iOS (`com.scanly.app`)
- [x] Android minSdk 24 (Flutter default, covers ML Kit / Tesseract); iOS deployment target 15.5
- [x] Release signing reads `android/key.properties`; release builds have no INTERNET permission
- [x] Turn on strict lints (strict-casts/inference/raw-types plus extra rules)
- [x] Dependencies resolved by pub for Flutter 3.50: Riverpod 3.5, GoRouter 18.1, Drift 2.35
- [x] Feature-first folder structure (core / domain / data / features / shared)
- [x] Design tokens: navy/neutral palette, typography, spacing, radii
- [x] Light, dark, and system themes, switchable in Settings and persisted
- [x] Reusable widgets: buttons, document/folder cards, search bar, empty/loading/error states, dialogs, action sheet, logo
- [x] GoRouter shell with a 5-slot bottom navigation bar and a prominent Scan action
- [x] Riverpod bootstrap with injected storage and preferences
- [x] Drift database: folders, documents, pages, page_ocr, with indexes and foreign keys (CASCADE / SET NULL)
- [x] Migration strategy and a check on every open that foreign keys are on
- [x] FTS5 search index whose tokenizer keeps Bengali vowel signs inside words (tested)
- [x] StorageService: per-document UUID folders, atomic writes, path safety, size calculation, temp cleanup
- [x] Startup recovery: clear temp files and remove orphaned document folders
- [x] Settings persistence (theme, scan quality, compression, PDF size and orientation, OCR language, auto-OCR)
- [x] Home, Files (folders, favorites, sort, grid/list, multi-select), Folder, Search, Settings, Privacy, About, Document viewer
- [x] Clear all data and storage usage
- [x] Unit tests: storage (12), database/search (17), settings (3), formatters (4)
- [x] Widget tests: navigation, scanner route, dark theme, folder creation, search (6)
- [x] Build a debug APK; tested on the Android emulator (Pixel 10 Pro, Android 37) in light and dark mode
- [x] The Scan route shows an honest "not available yet" screen until Milestone 2

## Milestone 2: Android scanner

- [ ] Add a `DocumentScanner` abstraction (domain layer)
- [ ] ML Kit Document Scanner implementation (`google_mlkit_document_scanner`)
- [ ] Multi-page capture plus gallery import
- [ ] Turn scanner output into Page entities and save the files
- [ ] Fall back to the custom camera if ML Kit is unavailable
- [ ] Permission handling and denial UX
- [!] Test on a physical Android phone

## Milestone 3: iOS scanner (shared OpenCV pipeline)

- [ ] Camera preview using `camera`
- [ ] OpenCV pipeline: downscale, grayscale, blur, Canny, contours, quad
- [ ] Quad validation: convexity, angles, area ratio, aspect ratio
- [ ] Temporal stability check and auto-capture
- [ ] Manual capture, flash, camera switch, page counter
- [ ] Perspective warp at full resolution in an isolate
- [ ] Unit tests on synthetic images (tilted document, white on white)
- [!] Test on a physical iPhone (needs macOS and Xcode)

## Milestone 4: Editor

- [ ] Four-corner crop handles with a magnifier
- [ ] Rotate, reset crop, retake
- [ ] Filters: original, grayscale, black and white, enhanced, color document
- [ ] Brightness, contrast, and sharpness controls
- [ ] Undo/redo stack (the original image is never touched)
- [ ] Page organizer: grid, drag-to-reorder, add, delete, rotate, edit

## Milestone 5: PDF

- [ ] PDF generation (`pdf`): A4, A5, Letter, Legal, original size; portrait/landscape
- [ ] Image compression levels
- [ ] Viewer (`pdfrx`): page navigation, zoom, text search
- [ ] Share (`share_plus`) and print (`printing`)
- [ ] Merge and split
- [ ] Rename and delete from the viewer

## Milestone 6: OCR

- [ ] English with ML Kit Text Recognition
- [ ] Bangla with Tesseract `ben.traineddata` (check the Apache-2.0 license)
- [ ] Mixed `eng+ben`, confidence-based merge without duplicate text
- [ ] OCR progress, retry, and cancel
- [ ] Store OCR text per page and index it in FTS5
- [ ] Searchable PDF with an invisible text layer and an embedded Bengali font
- [ ] OCR benchmark set (printed English, Bangla, mixed)

## Milestone 7: Library

- [ ] Folders: create, rename, color, delete
- [ ] Favorites
- [ ] Grid/list view, sorting
- [ ] Multi-select and bulk move/delete/share
- [ ] Search results with title, page number, snippet; tap opens the right page
- [ ] Test Bengali Unicode tokenization in FTS5

## Milestone 8: Release

- [ ] Performance pass (thumbnails, lazy loading, memory)
- [ ] Interruption recovery and temp cleanup on startup
- [ ] Privacy review (no network calls, no analytics)
- [ ] Integration tests
- [ ] Release APK and signed AAB
- [!] iOS release configuration and TestFlight (needs macOS)
