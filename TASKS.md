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
- [x] The Scan route showed an honest "not available yet" screen until Milestone 2 replaced it

## Milestone 2: Android scanner ✅ (needs a check on a physical phone)

- [x] `DocumentScanner` / `GalleryPicker` abstractions in the domain layer
- [x] ML Kit Document Scanner (`google_mlkit_document_scanner` 0.7.2): full mode, up to 100 pages per session, gallery import inside the scanner
- [x] Gallery import from Home ("Import from photos") and from the camera screen, via the system photo picker (no storage permission)
- [x] Import pipeline: byte-identical originals, EXIF-aware sizes, 480 px thumbnails decoded natively, one page at a time, full rollback on failure
- [x] Built-in camera: preview, flash (off/auto/on), camera switch, manual capture, page counter, undo last page, discard confirmation
- [x] Falls back to the built-in camera when ML Kit is unavailable; after a cancelled Google scan the snackbar offers "Use camera"
- [x] Settings → Scanner: Google scanner or built-in camera (Android)
- [x] Permission handling: clear messages for denied, restricted, missing or busy cameras, each with a way forward
- [x] Release APK permissions: CAMERA only. Plugin-added microphone, storage and network (Google telemetry) permissions removed
- [x] Tests: import pipeline (12), scanner flows with fakes (11); 64 total passing
- [x] Debug and release APKs build
- [!] On the emulator, Play services couldn't install Google's scanner module ("Something went wrong"). Scanly handled the cancel correctly. Test a full ML Kit scan and the built-in camera on a physical Android phone

## Milestone 3: Edge detection and auto-capture (iOS + Android built-in camera) ✅

- [x] Camera preview using `camera` (done in M2), streaming YUV420 (Android) / BGRA (iOS)
- [x] Vision pipeline in pure Dart: downscale, grayscale, Gaussian blur, adaptive Canny, dilation, contours, convex hull, quad. **Deviation:** `opencv_dart` was evaluated and dropped because it needs a native C++ toolchain on every build machine and adds 20–40 MB per ABI. The reasons are in docs/ARCHITECTURE.md
- [x] Quad validation: convexity, corner angles, area ratio, aspect ratio, side length, edge-support confidence
- [x] Temporal stability (6 steady frames, < 2 % movement) and auto-capture with a 1.5 s cooldown; Auto/Manual toggle
- [x] Live outline overlay that fills in as the document steadies; hints ("Looking for a document…", "Hold steady…")
- [x] Manual capture, flash, camera switch, page counter (M2)
- [x] Full-resolution perspective correction on the GPU (Flutter renderer + homography); JPEG encoding in an isolate
- [x] Auto-crop for camera captures and gallery photos; the uncropped original is kept when no page is found
- [x] Crop corners stored per page (schema v2) with a verified Drift migration
- [x] Tests: vision (23), cropper incl. EXIF (6), live frames (4), auto-crop import (3), migration (2). 102 total passing
- [x] Release APK builds (60.5 MB, only +0.3 MB); permissions still CAMERA only
- [!] Test live detection and auto-capture on a physical Android phone (the emulator was in use by another app)
- [!] Test on a physical iPhone (needs macOS and Xcode); confirm stream orientation matches `sensorOrientation`

## Milestone 4: Editor ✅

- [x] Four-corner crop handles with a magnifier; red outline and blocked save when corners cross
- [x] Crop shown in the page's rotation; Auto detect, Full page, Reset all
- [x] Rotate left/right (editor) and quick rotate (organizer)
- [x] Retake a page (camera or Google scanner, 1 page); keeps its position, resets edits and stale OCR text
- [x] Filters: original, grayscale, black & white (Bradley adaptive threshold, shadow-tolerant), enhanced, color document
- [x] Brightness, contrast and sharpness sliders (one undo step per drag)
- [x] Undo/redo history; the original image is never touched, every save re-renders from it
- [x] Debounced live preview rendered with the same pipeline as the saved page
- [x] Page organizer: grid, long-press drag to reorder, add pages (scan and append), delete (not the last page), rotate, edit, retake
- [x] Search hit page numbers follow reorders and deletions
- [x] Edit settings stored per page (schema v3: brightness, contrast, sharpness) with a verified migration
- [x] Fixed: a failed page import could leave its copied original behind (found by tests)
- [x] Tests: filters and history (20), renderer (6), edit/append/retake use cases (7), page operations (9), editor and organizer UI (8). 150 total passing
- [x] Release APK builds (61.5 MB), CAMERA permission only
- [!] Check crop handles, magnifier and drag-to-reorder by hand on a physical phone

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
