# Scanly

A free, offline-first document scanner for Android and iOS, featuring intelligent document
detection, image enhancement, PDF generation, and Bangla-English OCR. No subscriptions, no
watermarks, and no mandatory account.

> **Version 1.0.0.** Free download for Android from
> [GitHub Releases](https://github.com/souwmo04/Scanly-mobile/releases). Install guide:
> [docs/INSTALL.md](docs/INSTALL.md). Progress by milestone: [TASKS.md](TASKS.md).

## Features

| Area | What it does |
| --- | --- |
| Scanning | Automatic edge detection, perspective correction, auto/manual capture, multi-page |
| Editing | Four-corner crop, rotation, filters, brightness/contrast/sharpness, undo/redo |
| PDF | A4 / A5 / Letter / Legal / original size, compression, merge, split, share, print |
| OCR | English (ML Kit), Bangla and mixed Bangla-English (Tesseract), all on-device |
| Library | Folders, favorites, sorting, multi-select, full-text search over OCR text |
| Privacy | Camera permission only, no internet permission, no account, ads or analytics; excluded from cloud backups |
| Free | No subscription, watermark, page limit or paid API, ever |

## Tech stack

Flutter · Dart · Material 3 · Riverpod · GoRouter · Drift (SQLite + FTS5) · ML Kit ·
Pure-Dart edge detection · Tesseract · `pdf` · `printing` · `share_plus`

Details are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Requirements

- Flutter stable (3.x) and Dart 3.x
- Android: Android SDK 36, JDK 17 or 21, a device on Android 6.0 (API 23) or newer
- iOS: **a Mac with Xcode 16+ and CocoaPods**, a device on iOS 15.5 or newer.
  You can't build for iOS from Windows or Linux.

## Download

Get the APK from [GitHub Releases](https://github.com/souwmo04/Scanly-mobile/releases)
(`arm64-v8a` for most phones). Updates install over the previous version and keep your
documents. See [docs/INSTALL.md](docs/INSTALL.md).

Maintainers: [docs/RELEASE.md](docs/RELEASE.md) (signing, versioning, GitHub Actions
releases), [docs/FDROID.md](docs/FDROID.md), [docs/PRIVACY_AUDIT.md](docs/PRIVACY_AUDIT.md),
[docs/PERFORMANCE.md](docs/PERFORMANCE.md).

## Getting started (development)

```bash
git clone https://github.com/souwmo04/Scanly-mobile.git
cd Scanly-mobile
flutter pub get
dart run build_runner build
flutter run
```

### Project-local toolchain (optional)

The SDKs don't have to be installed system-wide. This repo is developed with everything
under a git-ignored `tools/` folder:

| Path | Contents |
| --- | --- |
| `tools/flutter` | Flutter stable (`git clone -b stable https://github.com/flutter/flutter.git`) |
| `tools/jdk21` | Eclipse Temurin JDK 21 |
| `tools/android-sdk` | cmdline-tools, platform-tools, platform 36, build-tools 36, NDK 28.2, CMake |
| `tools/pub-cache`, `tools/gradle-home` | Dart and Gradle caches |

Set `JAVA_HOME`, `ANDROID_HOME`, `PUB_CACHE` and `GRADLE_USER_HOME` to those folders, and put
`tools/flutter/bin` on `PATH`. Then run:

```bash
flutter config --android-sdk tools/android-sdk --jdk-dir tools/jdk21
```

## Building

**Android test APK**

```bash
flutter build apk --release
```

That universal APK (~115 MB) contains the OCR native libraries for every CPU type. For
smaller test installs, build one APK per CPU type and install the `arm64-v8a` one on
modern phones:

```bash
flutter build apk --release --split-per-abi
```

The Play Store App Bundle below is split per device automatically.

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
