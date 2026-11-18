# Scanly Architecture

## Layers

```
presentation (features/*)  →  domain (entities, repository interfaces, use cases)
                                   ↑
                    data (Drift database, file storage, repository implementations)
                                   ↑
          platform services (scanner, OpenCV, ML Kit, Tesseract, PDF, share/print)
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
| Android | ML Kit Document Scanner (Play services UI, returns JPEGs and a PDF) | Custom camera + OpenCV pipeline |
| iOS | Custom camera + OpenCV pipeline | Manual capture + manual crop |

Both feed the same `ScannedPage` model, so editing, OCR, PDF, and the library don't care
which scanner was used.

### OpenCV pipeline

downscale (~640 px long edge) → grayscale → Gaussian blur → Canny → contours →
approxPolyDP → 4-point candidates → validation (convex, angles 45–135°, area ≥ 20% of the
frame, plausible aspect ratio) → temporal stability (corners move < 2% over N frames) →
full-resolution capture → `warpPerspective` in a background isolate.

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
| ML Kit Document Scanner is Android-only and needs Play services | Abstraction plus a custom OpenCV fallback |
| `opencv_dart` adds a large native binary (~20–40 MB per ABI) | Split APKs per ABI; AAB handles this on Play |
| Tesseract Flutter plugins are thinly maintained | Pin a version, wrap it behind `OcrEngine`, keep the option of a platform-channel replacement |
| Bengali shaping in PDF text layers | Embed Noto Sans Bengali; the visible layer is the image, the invisible text is only for search |
| iOS can't be built or tested from Windows | Keep all logic in shared Dart; document the steps that need a Mac |
