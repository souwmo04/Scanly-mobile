# OCR benchmark

Scanly's text recognition runs on the device only, so its accuracy depends on
the platform engines, the bundled trained data and the phone. The benchmark is
an integration test that runs the real `DeviceOcrEngine` on a real device or
emulator.

## Run it

Connect a phone (or start an emulator), then from the project root:

```sh
flutter devices                      # find the device id
flutter test integration_test/ocr_benchmark_test.dart -d <device>
```

You need a real Android or iOS target. ML Kit and Tesseract are platform
plugins, so this test cannot run in host `flutter test`. The first run is slower
because the Tesseract plugin copies `assets/tessdata/*.traineddata` into app
storage.

## What it measures

The test draws three printed pages with `dart:ui` (`TextPainter` on a white
1240×1754 canvas, about A4 at 150 dpi, 34 px text):

| Page    | Language setting | Engine path                         | Font                            | File |
|---------|------------------|-------------------------------------|---------------------------------|------|
| english | English          | ML Kit Latin (Tesseract `eng` if ML Kit fails) | platform default               | PNG  |
| bangla  | Bangla           | Tesseract `ben`                     | `assets/fonts/NotoSansBengali-Regular.ttf` (loaded with `FontLoader`) | PNG  |
| mixed   | Mixed            | Tesseract `ben+eng`, single pass    | default, falls back to Noto Sans Bengali | JPEG |

For each page it reports:

- **CER** (character error rate): the Levenshtein distance over Unicode code
  points (runes), divided by the length of the reference text. Bengali vowel
  signs, hasanta, ZWJ and ZWNJ are separate code points, so each wrong one
  counts as one error. CER can go above 100% when the engine inserts a lot of
  extra text.
- **WER** (word error rate): the Levenshtein distance over space-separated
  words, divided by the number of reference words.
- **Time**: wall-clock milliseconds for `recognize`. This includes plugin
  start-up and, on the first run, copying the trained data.
- **Engine**: which engine produced the result (`mlkit` or `tesseract`). If
  the English page shows `tesseract`, ML Kit failed and the fallback ran.

Both metrics normalise whitespace first (every whitespace run becomes one
space), so line-wrapping differences do not count as errors. The text has also
been through Scanly's clean-up step (`cleanOcrText`), the same as in the app.
The code is in `lib/data/services/ocr/ocr_accuracy.dart`.

The test prints a Markdown table and each recognised text to the console, and
also stores the numbers in `binding.reportData`.

### Thresholds

The test fails if CER ≥ 15% (English) or ≥ 35% (Bangla, Mixed). These are
**smoke thresholds**. Clean synthetic pages are much easier than real scans, so
the limits only catch a broken engine, missing trained data or wrong routing.
They do not catch small accuracy regressions. Track the actual numbers in the
table below over time instead.

## Adding real scanned samples

Synthetic pages have no blur, shadows, skew or paper texture. To measure
real-world accuracy:

1. Put scans (the processed page JPEG Scanly stores, not the raw photo) in a
   folder such as `integration_test/samples/`, plus a UTF-8 `.txt` file with the
   same name holding the exact ground truth. For example, `receipt_01.jpg` goes
   with `receipt_01.txt`. Type the ground truth by hand. Do not copy it from OCR
   output.
2. Declare the folder under `flutter: assets:` in `pubspec.yaml` so the files
   get onto the device. Load each one with `rootBundle.load`, write it to the
   temp directory, and pass that path to `DeviceOcrEngine.recognize`.
3. Add a `BenchCase` (or a loop over the samples) with the right
   `OcrLanguage`, and compute CER/WER exactly as the synthetic cases do.
4. Only use documents you are allowed to keep in the repository. Remove
   personal data (names, phone numbers, account numbers) before you commit
   samples.

A useful sample set covers printed English, printed Bangla (several fonts,
including older SutonnyMJ-style prints), mixed receipts and forms, low light,
and slightly skewed pages.

## Results

Not yet run on a device. Fill in one row per device and run, and keep old rows
so trends stay visible.

| Date | Device / OS | Build | Page | Engine | CER | WER | Time (ms) | Notes |
|------|-------------|-------|------|--------|-----|-----|-----------|-------|
|      |             |       | english |     |     |     |           |       |
|      |             |       | bangla  |     |     |     |           |       |
|      |             |       | mixed   |     |     |     |           |       |

## Engine notes

- **ML Kit** (English): the Android plugin depends on
  `com.google.mlkit:text-recognition`, which bundles the Latin model in the
  APK. It never downloads anything and works offline from the first launch.
- **Tesseract** (Bangla, Mixed, English fallback): uses tessdata_fast `eng` and
  `ben` from `assets/tessdata/`. The plugin returns plain text only, with no
  confidence scores or boxes, so Tesseract lines carry no positions. On Android
  (`tesseract_ocr` 0.6.0) the plugin ignores custom options and always uses
  automatic page segmentation. iOS applies the requested
  `preserve_interword_spaces=1` and automatic page segmentation (PSM 3).
