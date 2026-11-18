# Scanly Architecture

## Layers

```
presentation (features/*)  →  domain (entities, repository interfaces, use cases)
                                   ↑
                    data (Drift database, file storage, repository implementations)
                                   ↑
          platform services (ML Kit scanner, vision pipeline, Tesseract, PDF, share/print)
```

- **Presentation**: widgets and Riverpod providers. No direct I/O.
- **Domain**: plain Dart entities (`Document`, `Page`, `Folder`, `OcrResult`), abstract
  repositories, and the `DocumentScanner` / `OcrEngine` / `PdfBuilder` interfaces.
- **Data**: Drift tables plus DAOs, `StorageService` (filesystem), and repository implementations.
- **Services**: platform-specific implementations behind the domain interfaces.

## Folder layout

```
lib/
  main.dart, app.dart
  core/       constants, errors, theme, routing, utils, services
  domain/     entities, repositories, usecases
  data/       database, datasources, repositories, models
  features/   home, library, folders, scanner, editor, filters,
              pdf_viewer, ocr, search, settings
  shared/     widgets, models, providers
assets/       fonts, icons, images, tessdata
test/         unit, widget, integration, scanner, ocr, pdf
```

## Scanning

| Platform | First choice | Fallback |
| --- | --- | --- |
| Android | ML Kit Document Scanner (Play services UI, returns cropped JPEGs) | Built-in camera + Scanly vision pipeline |
| iOS | Built-in camera + Scanly vision pipeline | Manual capture (manual crop in the editor) |

Both feed the same `PageSource` → `ImportPagesUseCase` path, so editing, OCR, PDF and the
library don't care which scanner was used. Users can also choose the built-in camera on
Android in Settings.

### Vision pipeline (`lib/core/vision/`)

The edge-detection pipeline follows the classic OpenCV approach, implemented in pure Dart:

1. **Frame**: the camera stream (YUV420 on Android, BGRA on iOS) is subsampled to about
   480 px inside the camera callback. Full-resolution frames are never processed.
2. **Rotate** to upright by `sensorOrientation`, then **downscale** to 320 px (area average).
3. **Gaussian blur** (5×5, separable integer kernel).
4. **Canny**: Sobel gradients, non-maximum suppression, hysteresis. Thresholds adapt to
   each frame (percentile of gradient magnitudes), which matters for white-on-white scenes.
5. **Dilate** (3×3) to close gaps in the outline.
6. **Contours**: 8-connected edge components → convex hull → Douglas–Peucker with growing
   tolerance until 4 corners remain.
7. **Validate**: convex; corner angles 45–135°; area 12–98.5 % of the frame; aspect ratio
   ≤ 4.5; no very short sides; **edge support** ≥ 55 % (share of the outline backed by real
   edges). The best candidate is chosen by area × support.
8. **Stability**: auto-capture fires after 6 consecutive detections whose corners move
   less than 2 % of the frame diagonal, then waits 1.5 s before the next one.
9. **Still photo**: after capture, detection runs again on a 720 px copy of the real photo
   (EXIF rotation applied by the platform codec). The page is then flattened at full
   resolution by drawing it through the solved homography with Flutter's renderer (GPU on
   devices) and JPEG-encoded in a background isolate. Corners are stored on the page
   (`pages.crop_corners`) for the editor.

Each step runs in a background isolate. A 1280×720 frame is analysed in well under
250 ms even in debug mode; the live loop is throttled to one frame per 150 ms.

#### Why not OpenCV?

The original plan used `opencv_dart`. Its build hook compiles a native wrapper with
CMake for every target, including the host machine for `flutter test`. That needs a recent
CMake plus a C++ toolchain (Visual Studio on Windows, Xcode on macOS), and adds about
20–40 MB of native code per ABI. For the handful of operations a scanner needs on a
320 px frame, pure Dart is fast enough, behaves identically on Android and iOS, is fully
unit-tested on any machine, and keeps the app small. The perspective warp, the only
full-resolution step, uses the GPU through Flutter's own renderer. If heavier vision work
is needed later (e.g. shadow removal), OpenCV can be added behind the same interfaces.

## Editing

Every page keeps its untouched original. Edits are stored as settings on the page row
(`crop_corners`, `rotation`, `filter_type`, `brightness`, `contrast`, `sharpness`) and the
processed image is always re-rendered from the original by `PageRenderer`:

```
original ─▶ decode (EXIF applied, ≤ 4096 px) ─▶ homography crop + quarter-turn rotation
         (one GPU draw) ─▶ filter preset ─▶ brightness/contrast ─▶ unsharp mask ─▶ JPEG
```

* The editor preview uses the same renderer at 1200 px, so preview and result match.
* Filters (`lib/core/vision/image_filters.dart`): grayscale (BT.601), black & white
  (Bradley–Roth adaptive threshold over an integral image, which handles shadows), enhanced
  (auto levels + paper whitening + mild sharpen), color document (auto levels + saturation
  + whitening).
* Each save writes the page under a new file name (`<pageId>-<timestamp>.jpg`) so image
  caches never show a stale version, then deletes the previous version.
* Undo/redo is an in-memory `EditHistory<PageEdits>`; a slider or corner drag is one step.
* Page operations (append, retake, delete, reorder) run in one transaction and refresh
  the document's page count, cover, size and search-result page numbers.

## PDF

* **Builder** (`lib/core/services/pdf_builder.dart`): one PDF page per scanned page.
  Fixed sizes use `PdfPageFormat` (A4, A5, Letter, Legal) with an 18 pt margin;
  `original` sizes the page to the image at 150 dpi. `auto` orientation turns a page to
  landscape when its image is wider than tall. Each image is decoded by the platform codec
  straight to the pixel size needed for ~200 dpi in its box on the page, then JPEG-encoded in
  an isolate at the chosen compression. Pages are processed one at a time.
* **Service** (`lib/data/services/pdf_document_service.dart`): `ensurePdf` writes
  `document.pdf` atomically next to a `document.pdf.meta` sidecar holding the options and a
  fingerprint of every page (id, path, size, modification time). The cached PDF is reused
  only while that fingerprint matches. Merge and split copy page files (original,
  processed, thumbnail) into new documents and carry over each page's edit settings.
* **Viewer**: pages are rasterized one at a time with `Printing.raster`, which uses the
  operating system's own PDF renderer. Only the visible page and its neighbours are kept.
* **Why not pdfrx?** `pdfrx` 3 renders with PDFium through a native-assets hook that
  compiles a C shim on the host machine, so every `flutter test` would need a C compiler
  (Visual Studio on Windows). The platform renderers already on every phone are enough for
  viewing scanned pages, and they keep the app smaller.

## Storage

```
<app documents>/scanly/documents/<document-uuid>/
  original/<page-uuid>.jpg     never modified
  processed/<page-uuid>.jpg    cropped + filtered result
  thumbs/<page-uuid>.jpg
  document.pdf
<app documents>/scanly/tmp/    cleared on startup
```

Files are first written to `tmp/`, then renamed into place, so an interrupted write never
leaves a half-written file in a document folder.

## Database (Drift / SQLite)

`folders`, `documents`, `pages`, `page_ocr`, plus the `search_index` FTS5 virtual table
(`unicode61` tokenizer, which keeps Bengali code points together). Foreign keys use
`ON DELETE CASCADE`. Document deletion runs in a transaction, and the files are removed
after the commit succeeds.

## OCR

- `english` → ML Kit Text Recognition (Latin script)
- `bangla` → Tesseract `ben`
- `mixed` → Tesseract `eng+ben`, compared against ML Kit line by line and merged by
  confidence so text isn't duplicated

## Native integration risks

| Risk | Mitigation |
| --- | --- |
| ML Kit Document Scanner is Android-only and needs Play services | Abstraction, a built-in camera fallback, a "Use camera" action after a cancelled scan, and a Settings choice |
| Google's scanner module may fail to download on first use (seen on an emulator) | Same fallbacks as above |
| ML Kit pulls in Google telemetry (`datatransport`) | Release manifest removes INTERNET and ACCESS_NETWORK_STATE |
| Camera stream orientation on iOS is assumed to match `sensorOrientation` | Covered by Android tests; needs checking on a physical iPhone |
| Tesseract Flutter plugins are thinly maintained | Pin a version, wrap it behind `OcrEngine`, keep the option of a platform-channel replacement |
| Bengali shaping in PDF text layers | Embed Noto Sans Bengali; the visible layer is the image, the invisible text is only for search |
| iOS can't be built or tested from Windows | Keep all logic in shared Dart; document the steps that need a Mac |
