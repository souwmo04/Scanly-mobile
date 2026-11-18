# Scanly — Task Tracker

Work through these one at a time, top to bottom. Each task is checked off only after it
builds, passes `flutter analyze`, has its tests passing, and is committed and pushed.

Legend: `[x]` done · `[ ]` to do · `[~]` in progress · `[!]` needs macOS / a physical device

---

## Milestone 0: Environment and repository

- [x] Inspect the repository (empty at start)
- [x] Check the toolchain: Git 2.53, Java 26, Android SDK (platform 36.1, build-tools 36/37)
- [ ] Install the Flutter stable SDK (not installed yet; it comes with Dart)
- [ ] Run `flutter doctor` and accept the Android licenses
- [ ] Make sure Gradle uses JDK 17/21 (Java 26 is too new for the Android Gradle Plugin)
- [x] Initialize Git and connect the `origin` remote (github.com/souwmo04/Scanly-mobile)
- [x] Write TASKS.md, README, CONTRIBUTING, CHANGELOG, LICENSE, PRIVACY, ARCHITECTURE
- [ ] Set the GitHub repository description

## Milestone 1: Foundation

- [ ] `flutter create --org com.scanly --platforms android,ios scanly`
- [ ] Set Android minSdk 23 (needed by ML Kit / Tesseract) and the iOS deployment target to 15.5
- [ ] Turn on strict lints (`flutter_lints` plus stricter analysis options)
- [ ] Add pinned dependencies (each one checked for version, platforms, and maintenance)
- [ ] Set up the folder structure from ARCHITECTURE.md
- [ ] Design tokens: colors (navy/neutral), typography, spacing, radii, shadows
- [ ] Light, dark, and system themes
- [ ] Reusable widgets: buttons, cards, search bar, empty/loading/error states, dialogs, sheets
- [ ] GoRouter shell with a 5-tab bottom navigation bar and a prominent Scan action
- [ ] Riverpod bootstrap (`ProviderScope`, app-level providers)
- [ ] Drift database: folders, documents, pages, and page_ocr tables, plus indexes
- [ ] Turn on foreign keys and add a migration strategy
- [ ] FTS5 virtual table for search
- [ ] StorageService: per-document UUID folders, safe delete, size calculation, temp cleanup
- [ ] Settings persistence (theme, scan quality, PDF format, OCR language)
- [ ] Home, Files, Search, and Settings screens wired to real (empty) data
- [ ] Unit tests: database CRUD, cascade delete, storage service
- [ ] Widget tests: navigation shell, empty states
- [ ] Build a debug APK

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
