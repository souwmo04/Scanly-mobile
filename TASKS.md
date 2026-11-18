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

## Milestone 5: PDF ✅ (built with two parallel agents, reviewed and integrated)

- [x] PDF generation (`pdf` 3.13): A4, A5, Letter, Legal, original size (150 dpi); portrait, landscape or auto per page
- [x] Compression: pages downscaled to ~200 dpi on the page and re-encoded at Low/Balanced/High quality, one page at a time
- [x] Cached `document.pdf` per document with a fingerprint sidecar; regenerated only when pages, edits or options change
- [x] Viewer: lazily rasterized pages (`printing` → Android PdfRenderer / iOS PDFKit), Page x of n, previous/next, go to page, pinch zoom, file size. **Deviation:** `pdfrx` was dropped because its PDFium hook needs a host C compiler (same reason as OpenCV). Text search inside documents arrives with OCR in Milestone 6
- [x] Export options sheet (size, orientation, compression, prefilled from Settings), then the share sheet (save to Files/Drive, email…)
- [x] Share (`share_plus` 13, with an iPad popover anchor) and print (`printing` 5.15)
- [x] Merge selected documents (in display order, into the first document's folder) and split a document at chosen pages; sources are kept and copies keep their edits
- [x] Rename and delete remain in the document viewer menu
- [x] Tests: engine (19), UI (14). 184 total passing; release APK 62.3 MB, CAMERA permission only
- [!] Check the PDF viewer, share sheet and print dialog on a physical phone

## Milestone 6: OCR ✅ (built with three parallel agents, reviewed and integrated)

- [x] English with ML Kit Text Recognition (bundled Latin model, works offline, line boxes); falls back to Tesseract `eng`
- [x] Bangla with Tesseract `ben` (tessdata_fast, Apache-2.0, bundled; license shown in About)
- [x] Mixed with a single Tesseract `ben+eng` pass, so no text is duplicated. **Note:** the Tesseract plugin returns no confidence scores, so confidence-based merging isn't possible. Users can re-run a page in another language and pick the better result
- [x] Text clean-up that keeps ZWJ/ZWNJ and the danda (।)
- [x] Background OCR queue: one page at a time, progress, retry failed pages, stop/resume, resume after restart, auto-run after scan/import (Settings → auto OCR), re-run after edit or rotate
- [x] OCR stored per page (schema v4: lines with boxes, errors) and indexed in FTS5; global search and in-document search (Bengali-safe matching)
- [x] Page text screen: selectable text, copy all, re-run in another language
- [x] Searchable PDF: invisible text layer (render mode 3), Helvetica for Latin, subset-embedded Noto Sans Bengali with ToUnicode; boxes from ML Kit, even line distribution for Tesseract; cached PDFs refresh when OCR changes
- [x] OCR benchmark: `integration_test/ocr_benchmark_test.dart` + docs/OCR_BENCHMARK.md (CER/WER, timing)
- [x] Release shrinking rules for ML Kit and Tesseract (R8 failed without them)
- [x] 278 tests passing; release APK builds (universal 115 MB; per-ABI or AAB is much smaller), CAMERA permission only
- [!] Run the OCR benchmark and real Bangla/English scans on a physical Android phone and an iPhone

## Milestone 7: Library ✅ (built with two parallel agents, reviewed and integrated)

- [x] Folders: create, rename, color, delete (M1); sort by name, recent activity or size (saved); "Add documents" picker with search
- [x] Favorites, including a smart bulk toggle (removes when all selected are favorites)
- [x] Grid/list view and document sorting (M1)
- [x] Multi-select: favorite, move, merge, delete, and share several documents as PDFs in one share sheet (progress, cancel, partial-failure report)
- [x] Duplicate a document, keeping page edits and recognized text
- [x] Live document info sheet (folder, pages, size, dates, OCR status, stored on device)
- [x] Search: results grouped by document with thumbnail, highlighted title and every matching page (Page n + snippet, "+N more"); tap a page to open it there
- [x] Search filters (All / Documents / Text / Folders) applied in SQL with counts; recent searches (last 8, remove, clear); results capped at 50 with a note
- [x] Bengali Unicode tokenization in FTS5 tested (M1, plus Bengali grouped-search tests)
- [x] Fixed: folder card counts could overflow at large text sizes
- [x] 332 tests passing; release APK builds, CAMERA permission only
- [x] Shared action sheet scrolls when it has many entries (short phones, large text)

## Milestone 8: Release

- [ ] Performance pass (thumbnails, lazy loading, memory)
- [ ] Interruption recovery and temp cleanup on startup
- [ ] Privacy review (no network calls, no analytics)
- [ ] Integration tests
- [ ] Release APK and signed AAB
- [!] iOS release configuration and TestFlight (needs macOS)
