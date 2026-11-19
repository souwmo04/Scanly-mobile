import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/services/storage_service.dart';
import 'features/ocr/ocr_queue.dart';
import 'shared/providers/core_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerBundledLicenses();

  final supportDir = await getApplicationSupportDirectory();
  final storage = StorageService(Directory(p.join(supportDir.path, 'scanly')));
  await storage.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      storageServiceProvider.overrideWithValue(storage),
    ],
  );

  runApp(
    UncontrolledProviderScope(container: container, child: const ScanlyApp()),
  );

  // Background work starts only once the first frame is on screen, so it
  // never competes with the first build for the database or the disk:
  // 1. clean up after interrupted work (temp files, orphaned folders),
  // 2. continue text recognition that was interrupted when the app closed.
  //    Pages run one at a time; failures are recorded per page.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_afterFirstFrame(container));
  });
}

Future<void> _afterFirstFrame(ProviderContainer container) async {
  try {
    await container
        .read(maintenanceRepositoryProvider)
        .recoverInterruptedWork();
  } on Object catch (error) {
    debugPrint('Startup cleanup failed: $error');
  }
  await container.read(ocrQueueProvider.notifier).resumeUnfinished();
}

/// Adds licences of bundled data (OCR models, font) to the licence page.
void _registerBundledLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['tessdata_fast (Tesseract OCR models)'],
      await rootBundle.loadString('assets/licenses/tessdata_fast_LICENSE.txt'),
    );
    yield LicenseEntryWithLineBreaks([
      'Noto Sans Bengali',
    ], await rootBundle.loadString('assets/licenses/NotoSansBengali_OFL.txt'));
  });
}
