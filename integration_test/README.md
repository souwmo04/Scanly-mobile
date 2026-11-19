# Device tests

These tests drive the real app with the real platform services (image codec, GPU renderer,
PDF renderer, ML Kit / Tesseract OCR). They need an Android phone/emulator or an iOS
device/simulator; they cannot run on the host. `flutter test` without arguments only runs
`test/`, so they never slow down or break the host suite.

| File | What it covers |
| --- | --- |
| `app_flow_test.dart` | Home empty state → import a two-page document through `ImportPagesUseCase` from JPEGs rendered with `dart:ui` → open it → edit page 1 (rotate right, Black & white) and save → generate the PDF in the viewer → recognise text in English → find the document via search → reorder pages in the organizer → delete it. |
| `ocr_benchmark_test.dart` | OCR accuracy smoke benchmark (English, Bangla, mixed). See `docs/OCR_BENCHMARK.md`. |

## Running

```sh
flutter devices                                   # find the device id
flutter test integration_test -d <device>         # all device tests
flutter test integration_test/app_flow_test.dart -d <device>
```

On Windows, run `source tools/env.sh` first (Git Bash) so the project's Flutter SDK is used.

Notes:

* The app flow runs against a fresh temporary storage folder, an in-memory database and
  in-memory preferences. The library already on the device is never read or changed, and the
  device's cache folder is not touched.
* English OCR uses ML Kit, which on Android needs Google Play services; on a device without
  them the engine falls back to Tesseract.
* Waits are explicit (`pumpUntil`) with generous timeouts (PDF 90 s, OCR 2 min) because
  spinners keep animating while real work runs. A slow emulator may need more.
* Debug builds keep the `INTERNET` permission for the Flutter tool; release builds don't.
