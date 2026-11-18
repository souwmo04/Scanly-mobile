# F-Droid readiness

F-Droid only builds apps from source with free and open-source dependencies. This is the
current status for Scanly.

## Ready

* **License:** MIT ([LICENSE](../LICENSE)); bundled data is Apache-2.0 (Tesseract models)
  and SIL OFL 1.1 (Noto Sans Bengali). Licenses are shown in the app.
* **No anti-features in behaviour:** no ads, no tracking, no analytics, no network
  permission, no account, no paid features.
* **Metadata:** fastlane-style metadata in `fastlane/metadata/android/en-US/` (title,
  descriptions, changelogs per versionCode, icon). F-Droid and IzzyOnDroid both read this
  layout.
* **Stable ids and versions:** application id `com.scanly.app`, semantic versions with
  increasing `versionCode`, and tags `vX.Y.Z`.
* **Builds from source** with the Flutter SDK, with no proprietary build tools.

## Blockers

Three dependencies are proprietary Google libraries, which F-Droid does not allow:

| Dependency | Used for | Free replacement already in Scanly |
| --- | --- | --- |
| `google_mlkit_document_scanner` (Play services) | Google's scanner UI on Android | The built-in camera with Scanly's own edge detection and auto-capture (Settings → Scanner → Built-in camera) |
| `google_mlkit_text_recognition` | English OCR | Tesseract `eng`, the existing fallback |
| Google `datatransport` (pulled in by ML Kit) | Telemetry (already blocked: no INTERNET permission) | Removed together with ML Kit |

Scanly already has free implementations for both features. The remaining work is a
**FOSS build** that leaves the ML Kit packages out:

1. Move the ML Kit adapters behind a build-time switch: a `--dart-define=SCANLY_FOSS=true`
   build that never imports them, with separate `pubspec` dependency sets (for example a
   `scanly_mlkit` package listed only in the non-FOSS build).
2. Make the FOSS build default to the built-in camera and Tesseract for English.
3. Add F-Droid build metadata (`com.scanly.app.yml`) in the
   [fdroiddata](https://gitlab.com/fdroid/fdroiddata) repository, with the Flutter
   srclib, and submit a merge request (free).

Until then, GitHub Releases is the distribution channel.
[Obtainium](https://github.com/ImranR98/Obtainium) can track Scanly's GitHub Releases
for automatic update checks, without F-Droid.
