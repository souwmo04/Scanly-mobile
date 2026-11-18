# Scanly

A free, offline-first document scanner for Android and iOS, featuring intelligent document
detection, image enhancement, PDF generation, and Bangla-English OCR. No subscriptions, no
watermarks, and no mandatory account.

> **Status:** early development. See [TASKS.md](TASKS.md) for live progress, milestone by milestone.

## Features (planned)

| Area | What it does |
| --- | --- |
| Scanning | Automatic edge detection, perspective correction, auto/manual capture, multi-page |
| Editing | Four-corner crop, rotation, filters, brightness/contrast/sharpness, undo/redo |
| PDF | A4 / A5 / Letter / Legal / original size, compression, merge, split, share, print |
| OCR | English (ML Kit), Bangla and mixed Bangla-English (Tesseract), all on-device |
| Library | Folders, favorites, sorting, multi-select, full-text search over OCR text |
| Privacy | No account, no cloud, no ads, no analytics; everything stays on the device |

## Tech stack

Flutter · Dart · Material 3 · Riverpod · GoRouter · Drift (SQLite + FTS5) · ML Kit ·
OpenCV · Tesseract · `pdf` · `pdfrx`

Details are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Requirements

- Flutter stable (3.x) and Dart 3.x
- Android: Android SDK 36, JDK 17 or 21, a device on Android 6.0 (API 23) or newer
- iOS: **a Mac with Xcode 16+ and CocoaPods**, a device on iOS 15.5 or newer.
  You can't build for iOS from Windows or Linux.

## Getting started

```bash
git clone https://github.com/souwmo04/Scanly-mobile.git
cd Scanly-mobile
flutter pub get
dart run build_runner build
flutter run
```

## Building

**Android test APK**

```bash
flutter build apk --release
```

**Android App Bundle (Play Store)**: create `android/key.properties` (see
[CONTRIBUTING.md](CONTRIBUTING.md#signing)), then run:

```bash
flutter build appbundle --release
```

**iOS** (on macOS only):

```bash
cd ios && pod install && cd ..
flutter build ipa --release
```

Open `ios/Runner.xcworkspace` in Xcode to set your signing team, install on a device, or
upload to TestFlight.

## OCR language models

Tesseract models (`eng.traineddata`, `ben.traineddata`) come from
[tesseract-ocr/tessdata_fast](https://github.com/tesseract-ocr/tessdata_fast) (Apache-2.0)
and live in `assets/tessdata/`. On first launch the app copies them to app-private storage.
English OCR uses Google ML Kit's on-device model, which ships with the app.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `Unsupported class file major version` | Gradle needs JDK 17/21. Run `flutter config --jdk-dir <path>` |
| ML Kit scanner doesn't open | The device needs Google Play services. The app falls back to the built-in camera |
| iOS build fails on `pod install` | Run `pod repo update`, then check that the iOS deployment target is 15.5 |

## License

MIT. See [LICENSE](LICENSE).
