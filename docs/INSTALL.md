# Installing Scanly on Android

Scanly is free and is distributed as APK files on
[GitHub Releases](https://github.com/souwmo04/Scanly-mobile/releases). No Play Store,
account or payment is needed.

## 1. Pick the right file

Open the latest release and download **one** APK:

| File | For |
| --- | --- |
| `Scanly-x.y.z-arm64-v8a.apk` | Almost all phones from the last ~8 years (**recommended**) |
| `Scanly-x.y.z-armeabi-v7a.apk` | Older 32-bit phones |
| `Scanly-x.y.z-x86_64.apk` | Emulators and some Chromebooks |
| `Scanly-x.y.z-universal.apk` | Works everywhere, but about twice the download size |

Not sure? Take `arm64-v8a`. If Android says the app isn't compatible, use `universal`.
The `.aab` file is for app stores, not for installing.

## 2. Allow the install

Android only installs apps from outside the Play Store if you allow it once:

1. Open the downloaded APK (from the browser's downloads or the Files app).
2. Android asks to allow installs from that app (for example Chrome or Files): tap
   **Settings**, turn on **Allow from this source**, and go back.
3. Tap **Install**.

Google Play Protect may show "App not scanned" or "Unknown developer", because Scanly
isn't published on the Play Store. Choose **Install anyway**. If you want to check that
the file is genuine first, see section 4.

Requirements: Android 7.0 (API 24) or newer, about 250 MB free space.

## 3. Updating

Download the newer APK from GitHub Releases and install it the same way. It installs
**over** the existing app, and all documents, folders and settings are kept.

Updates work because every official release uses the same application id
(`com.scanly.app`) and the same signing key, and each release has a higher version number.
You can switch between the APK types above when updating.

You can't update a build you compiled yourself, or a debug build, with an official
release (or the other way round). Android blocks installs signed with a different key.
Back up anything important (share the PDFs) and uninstall first.

## 4. Checking the download (optional)

Each release includes `SHA256SUMS.txt`. On a computer:

```bash
sha256sum -c SHA256SUMS.txt --ignore-missing
```

The official signing certificate fingerprint (SHA-256) is:

```
89:DB:A6:10:69:BD:F6:2F:D3:03:4B:0D:20:11:E7:11:78:7F:9D:DD:36:4E:92:E3:55:76:22:82:E1:DB:F8:AE
```

To check an APK's signature with the Android build tools:

```bash
apksigner verify --print-certs Scanly-x.y.z-arm64-v8a.apk
```

Apps such as *AppVerifier* can also compare the fingerprint on the phone.

## Privacy

Scanly needs only the camera permission. It has no internet permission, no account, no
ads and no tracking. Everything stays on your phone. See [PRIVACY.md](PRIVACY.md).
