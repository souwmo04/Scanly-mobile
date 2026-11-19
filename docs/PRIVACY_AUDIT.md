# Privacy audit

_Release hardening pass, November 2026 (version 0.7.0). Scope: all Dart code under `lib/`,
`pubspec.yaml` / `pubspec.lock`, the plugins' native dependencies, and the Android/iOS
configuration (read-only)._

Scanly is distributed for free through GitHub Releases. It must stay free: no ads, no
subscriptions, no watermarks, no paid APIs.

## Summary

| Question | Answer |
| --- | --- |
| Does Scanly's own code use the network? | **No.** No `http`, `HttpClient`, `Socket`, `WebSocket`, `Uri.parse('http…')`, `launchUrl`, `NetworkImage` or remote font loading anywhere in `lib/`. |
| Analytics, crash reporting, ads, Firebase? | **None.** No analytics/crash/ad/attribution SDK and no Firebase package in `pubspec.lock`. |
| Paid APIs or cloud services? | **None.** OCR, edge detection, image processing and PDF creation run on the device. No API keys exist in the project. |
| Can a release build reach the network? | **No (Android).** The release manifest removes `INTERNET` and `ACCESS_NETWORK_STATE`. Debug/profile manifests add `INTERNET` back for the Flutter tool only. |
| Where is user data stored? | App-private storage only (application support directory + app cache). Never public storage. |
| When do files leave the app? | Only when the user shares, prints or exports through the system share sheet / print dialog. |
| Does "Clear all data" delete everything? | **Yes, after this pass** (see below; verified by `test/unit/clear_all_data_test.dart`). |

## 1. Network use in Dart code

Search run over `lib/` (and `integration_test/`):

```
package:http | HttpClient | Socket | WebSocket | Uri.parse( | http:// | https://
launchUrl | url_launcher | firebase | analytics | crashlytics | sentry
NetworkImage | networkImage | PdfGoogleFonts
```

Result: no matches in code. The only hit is the privacy screen's sentence
"no advertising SDK and no analytics".

## 2. Dependencies

Direct dependencies (`pubspec.yaml`): `material_ui`, `cupertino_icons`, `flutter_riverpod`,
`go_router`, `drift`, `drift_flutter`, `shared_preferences`, `path_provider`, `path`, `uuid`,
`intl`, `google_mlkit_document_scanner`, `image_picker`, `camera`, `image`, `pdf`,
`printing`, `share_plus`, `google_mlkit_text_recognition`, `tesseract_ocr`.

Transitive packages that *contain* network code, and why it is never reached:

| Package | Pulled in by | Network code | Used by Scanly? |
| --- | --- | --- | --- |
| `http` | `printing` | `networkImage()`, `PdfGoogleFonts` download fonts | No. Scanly embeds its own fonts (Helvetica built in, Noto Sans Bengali bundled as an asset). |
| `url_launcher_linux/windows/web` | `share_plus` (desktop/web fallbacks) | Opens URLs on desktop | No. Not compiled into Android/iOS builds. |
| `web_socket_channel`, `shelf`, `http_multi_server`, `webdriver`, `sync_http` | dev tooling (`build_runner`, `flutter_driver`, `integration_test`) | Dev servers | No. `dev_dependencies` only, not in the app. |

### Plugins with native network stacks

| Plugin | Native library | What it may do on the network | Why release builds can't |
| --- | --- | --- | --- |
| `google_mlkit_text_recognition` | `com.google.mlkit:text-recognition:16.0.1` (bundled Latin model) + `vision-common` | ML Kit pulls in Google `datatransport` (Firebase transport) to upload anonymous usage/performance logs | The release manifest removes `INTERNET`, so the app process cannot open sockets. The model is bundled, nothing is downloaded. |
| `google_mlkit_document_scanner` | `play-services-mlkit-document-scanner:16.0.0` | The scanner UI and its model run **inside Google Play services**, which downloads the scanner module on first use | Runs in the Play services process under Google's terms, not in Scanly's process; Scanly only receives the cropped JPEGs. The built-in camera (Settings → Scanner) avoids it entirely. |
| `tesseract_ocr` | Tesseract4Android / SwiftyTesseract | None | Trained data is bundled (`assets/tessdata/`) and copied to app storage. |
| `camera`, `image_picker`, `share_plus`, `printing`, `path_provider`, `shared_preferences`, `drift_flutter` (`sqlite3_flutter_libs`) | AndroidX CameraX, system photo picker, system share sheet, system print/PdfRenderer, SQLite | None | — |

`android/app/src/main/AndroidManifest.xml` (read-only for this audit) removes `INTERNET`,
`ACCESS_NETWORK_STATE`, `RECORD_AUDIO` and legacy storage permissions; only `CAMERA` stays.
iOS has no network permission model; there is no network code to call.

### Proprietary components (relevant for F-Droid)

F-Droid requires every dependency to be free software. These are not:

| Component | Licence | Used for | Free alternative already in the app |
| --- | --- | --- | --- |
| Google ML Kit Text Recognition (`com.google.mlkit:text-recognition`, `vision-common`) and its transitive `datatransport` / Firebase components | Proprietary (Google ML Kit terms) | English OCR with line boxes | Tesseract `eng` (already the fallback) |
| Google ML Kit Document Scanner (`play-services-mlkit-document-scanner`) | Proprietary, requires **Google Play services** | Android scanner UI | Built-in camera + Scanly's pure-Dart vision pipeline |
| Google Play services (runtime) | Proprietary | Hosts the document scanner | Not needed with the built-in camera |

Everything else is open source (BSD/MIT/Apache-2.0, Tesseract Apache-2.0, tessdata_fast
Apache-2.0, Noto Sans Bengali SIL OFL 1.1). An F-Droid flavour would need to drop the two
`google_mlkit_*` plugins (e.g. a build flavour with `DeviceOcrEngine` routed to Tesseract only
and the scanner fixed to the built-in camera); both are already behind the `OcrEngine` and
`DocumentScanner` interfaces.

## 3. Where data lives

| Data | Location |
| --- | --- |
| Page originals, processed pages, thumbnails, PDFs and `.meta` sidecars | `<application support>/scanly/documents/<id>/` (Android: `/data/data/<app>/files/…`; iOS: `Library/Application Support/…`) |
| Temporary writes | `<application support>/scanly/tmp/` (emptied on every start) |
| Database (documents, pages, folders, OCR text, FTS5 search index) | `<application support>/scanly.sqlite` |
| Settings, library layout/sort, **recent searches** | Shared preferences (app-private) |
| Tesseract trained data | `<application documents>/tessdata/` (copied from the app bundle) |
| Plugin copies: picked photos (`image_picker`), shared files (`share_plus`), camera captures | App cache (Android `cacheDir`, iOS `Library/Caches`) |

No code writes to public storage (`getExternalStorage*`, Downloads, the photo library).
Camera captures are deleted after they are imported (`scanner_screen.dart`,
`camera_capture_view.dart`).

## 4. Sharing

Files leave Scanly only through user actions: Share PDF / bulk share (system share sheet via
`share_plus`), Print (system print dialog via `printing`), Copy text (clipboard). There is no
background export, sync or upload.

## 5. "Clear all data"

Checked: `LocalMaintenanceRepository.clearAllData` deleted all database rows (including
`search_index`), all document folders and `tmp/`, then ran `VACUUM`. Two gaps were found
and fixed:

1. **Recent searches survived** (shared preferences key `search.recent`). Now cleared.
2. **Plugin copies in the app cache survived**: photos copied by `image_picker` when
   importing from the gallery and PDFs copied into `cache/share_plus/` when sharing. The
   cache folder is now emptied (Android/iOS only; never on desktop hosts, where the temp
   folder is shared; Scanly's own storage root is always skipped).

Implementation: `lib/features/settings/clear_all_data.dart` (`clearAllDataProvider`),
`lib/data/repositories/local_maintenance_repository.dart` (`_clearCache`),
`lib/shared/providers/core_providers.dart` (`cacheDirectoryProvider`). The settings screen
also drops decoded thumbnails from Flutter's in-memory image cache. App settings (theme, scan
quality, sort order) are preferences, not user content, and are kept.

`test/unit/clear_all_data_test.dart` imports a real two-page document into a folder, runs OCR
bookkeeping, generates a PDF + sidecar, adds a temp file, cache copies and a recent search,
then asserts after clearing: 0 rows in `documents`, `pages`, `page_ocr`, `folders`,
`search_index`; no files under `documents/` and `tmp/`; empty cache folder; no recent
searches; settings kept; storage still usable.

The SQLite database uses the default rollback journal (no WAL), so `VACUUM` rewrites the
file and deleted text does not remain in free pages.

## 6. Findings for the lead (outside this pass's file scope)

1. **Android Auto Backup is on.** `android:allowBackup` is not set in the manifest, so it
   defaults to `true`: Android may copy `files/` (all documents, the database with OCR text)
   and shared preferences into the user's Google Drive backup and device-to-device
   transfers. This happens in the system backup service, so removing `INTERNET` does not
   stop it. Recommended: `android:allowBackup="false"` (and, for Android 12+,
   `android:dataExtractionRules` excluding everything, or `android:fullBackupContent="false"`
   for older versions) in `android/app/src/main/AndroidManifest.xml`.
2. **iOS backups.** `Library/Application Support` is included in iCloud/Finder backups by
   default. If documents should never leave the device, mark the `scanly/` folder and the
   database with `NSURLIsExcludedFromBackupKey` (needs a small platform channel or a
   plugin; no new package was added here).
3. **Gallery import copies.** On Android, `image_picker` leaves a copy of every imported
   photo in `cacheDir/<uuid>/` until the OS trims the cache or the user clears all data.
   Optional improvement: delete those copies after a successful import (they are always
   plugin copies, never the user's original photo).
4. `docs/PRIVACY.md` now describes backups neutrally; update it if (1)/(2) are changed.
