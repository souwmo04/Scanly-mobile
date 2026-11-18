# Releasing Scanly

Scanly is distributed **for free**. The primary channel is **GitHub Releases** (signed
APKs). Google Play and F-Droid are optional future channels. Nothing in this process
costs money: GitHub Actions is free for this use, and no store account is needed.

## Versioning

Semantic versioning in `pubspec.yaml`:

```yaml
version: 1.2.0+10   # versionName + versionCode
```

* `1.2.0`: shown to users; bump MAJOR for breaking changes, MINOR for features, PATCH
  for fixes. The git tag is `v1.2.0`.
* `+10`: Android `versionCode`. It must **increase with every release**, or Android
  refuses the update. Never reuse or lower it.
* The About screen shows the version from `lib/features/settings/info_screens.dart`;
  keep it in sync.

## Signing (one-time setup)

Every official APK must be signed with the **same key forever**. Updates only install
over an existing app if the key matches. If the key is lost, users would have to
uninstall (losing their documents) to move to a new one.

### Create the key

```bash
keytool -genkeypair -v -keystore signing/scanly-release.jks -storetype PKCS12 \
  -alias scanly -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=Scanly, O=Scanly"
```

The project's key already exists locally in `signing/` (git-ignored). Its public
certificate fingerprint is published in [INSTALL.md](INSTALL.md).

### Keep it safe

* `signing/` and `android/key.properties` are in `.gitignore`. **Never commit them.**
* Back up `signing/scanly-release.jks` and the password to at least two offline places
  (for example a USB drive and a password manager).

### Local signed builds

`android/key.properties` (git-ignored):

```properties
storePassword=…
keyPassword=…
keyAlias=scanly
storeFile=E:/project/scanly-mobile/signing/scanly-release.jks
```

`android/app/build.gradle.kts` reads it. Without it, local release builds fall back to
the debug key so that testing still works. Passing `-PrequireReleaseSigning=true` turns
the fallback off (the release workflow always passes it).

## Release checklist

1. `main` is green in CI (analyze + tests), and `TASKS.md` is up to date.
2. Bump `version:` in `pubspec.yaml` (name and code) and the About screen version.
3. Add a `## [x.y.z] - date` section to `CHANGELOG.md` (the workflow uses it as the
   release notes) and `fastlane/metadata/android/en-US/changelogs/<versionCode>.txt`.
4. Test a release build on a physical phone, in airplane mode: scan, edit, OCR
   (English and Bangla), PDF, share, search, and updating over the previous version.
5. Commit, then tag and push:
   ```bash
   git tag -a v1.2.0 -m "Scanly 1.2.0"
   git push origin v1.2.0
   ```
6. GitHub Actions (`.github/workflows/release.yml`) builds the signed APKs (arm64-v8a,
   armeabi-v7a, x86_64, universal) and an App Bundle, writes `SHA256SUMS.txt`, and
   publishes the GitHub Release.

### GitHub Actions secrets (one-time)

The release workflow needs the key as repository secrets (**Settings → Secrets and
variables → Actions → New repository secret**). Encrypted secrets are only readable by
workflows; they are never shown in logs or to forks.

| Secret | Value |
| --- | --- |
| `SCANLY_KEYSTORE_BASE64` | Output of `base64 -w0 signing/scanly-release.jks` (PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("signing\scanly-release.jks"))`) |
| `SCANLY_KEYSTORE_PASSWORD` | Keystore password (from `android/key.properties`) |
| `SCANLY_KEY_ALIAS` | `scanly` |
| `SCANLY_KEY_PASSWORD` | Key password (same as the keystore password) |

Without these secrets the workflow stops with an error rather than publishing
debug-signed files.

### Manual release (without Actions)

```bash
flutter build apk --release --split-per-abi -PrequireReleaseSigning=true -Pforce-version-code-ignoring-abi=true
flutter build apk --release -PrequireReleaseSigning=true -Pforce-version-code-ignoring-abi=true
flutter build appbundle --release -PrequireReleaseSigning=true
```

Then on GitHub: **Releases → Draft a new release**, choose the tag, paste the changelog
section plus `docs/INSTALL_SNIPPET.md`, and attach the APKs, the `.aab` and
`SHA256SUMS.txt`.

`force-version-code-ignoring-abi` gives every APK the same `versionCode`, so any variant
can update any other.

### Verify before publishing

```bash
aapt dump permissions build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
apksigner verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Expected: only `android.permission.CAMERA` (plus an internal AndroidX receiver
permission), and the certificate fingerprint from [INSTALL.md](INSTALL.md).

## Free update process

Users update by downloading the new APK from GitHub Releases and installing it over the
old one. Data is kept because the application id `com.scanly.app` never changes, the
signing key never changes, and `versionCode` always increases. Scanly has no internet
permission, so it never checks for updates itself. Users who want notifications can
"Watch → Custom → Releases" on GitHub, or use the free
[Obtainium](https://github.com/ImranR98/Obtainium) app with the repository URL.

## Optional: Google Play (future)

Upload the `.aab` from a release. Use Play App Signing with the same upload key. The
Data safety answers are "No data collected" and "No data shared". This needs a one-time
paid Google developer registration, which is why it is not the primary channel.

## Optional: F-Droid

See [FDROID.md](FDROID.md) for what is ready and what still blocks inclusion.

## iOS (requires macOS)

iOS builds need a Mac with Xcode 16+, which this project's Windows setup doesn't have.
Free distribution to iPhones is limited: Apple requires a paid developer membership for
TestFlight and the App Store. A free Apple ID can install a personal build on your own
iPhone from Xcode, valid for 7 days.

```bash
flutter build ios --release
open ios/Runner.xcworkspace   # set your Team, then Product → Run on a connected iPhone
```

Bundle id `com.scanly.app`, deployment target 15.5. Camera and photo usage strings are
already in `Info.plist`. On a real iPhone, verify the live edge detection orientation,
Tesseract Bangla OCR, and the iPad share popover.
