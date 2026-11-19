# Scanly Privacy Policy (Draft)

_Last updated: 19 November 2026_

Scanly is built so your documents never leave your device.

## What we collect

**Nothing.** Scanly has no account system, no analytics, no advertising SDKs, and no
crash-reporting service that sends data to us.

## Where your documents live

Scans, processed images, PDFs, extracted text, and the search index are stored in Scanly's
private app storage on your phone. Your recent searches are kept in Scanly's private settings
on the device. Other apps can't read any of it. When you uninstall Scanly, it's deleted.

On Android, Scanly excludes all of its data from cloud backups (such as Google backup).
It can only be moved directly to a new phone during device-to-device setup. On iPhone,
iCloud or computer backups that you have turned on may include app data;
that is handled by your phone and your backup provider, not by Scanly.

## Processing

Edge detection, image enhancement, PDF generation, and text recognition (OCR) all run
on-device, including the recognition models, which ship inside the app. Scanly never uploads
your document images, recognised text, or searches to any server. Scanly is free: there are
no ads, subscriptions, or paid online services.

## Permissions

| Permission | Why |
| --- | --- |
| Camera | To scan documents. Only used while the scanner screen is open. |
| Photos / files | Only when you choose to import an image or PDF. |

On Android, Google ML Kit's document scanner and text recognizer are provided through Google
Play services and run on the device. Google's own terms govern Play services. The first time
you scan, Play services may download the scanner module itself.

## No network access

Release builds of Scanly for Android declare **no internet permission**. Some Google libraries
add one to upload usage statistics; Scanly removes it, so the app can't send anything off your
phone even by accident. The only permission it asks for is the camera.

## Sharing

Files leave Scanly only when you share or export them yourself, through your phone's share sheet.

## Deleting your data

Settings → **Clear all data** permanently deletes every document, folder, page image, PDF,
recognised text, the search index, recent searches, and temporary copies made while importing
or sharing. Your app settings (theme, scan quality, sort order) are kept.

## Contact

Open an issue at https://github.com/souwmo04/Scanly-mobile/issues.
