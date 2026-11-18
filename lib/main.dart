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

  // Clean up after any interrupted work without delaying first frame.
  unawaited(
    container
        .read(maintenanceRepositoryProvider)
        .recoverInterruptedWork()
        .catchError((Object error) {
          debugPrint('Startup cleanup failed: $error');
        }),
  );

  runApp(
    UncontrolledProviderScope(container: container, child: const ScanlyApp()),
  );

  // Continue text recognition that was interrupted when the app closed,
  // once the first frame is on screen. Pages run one at a time in the
  // background; failures are recorded per page.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(container.read(ocrQueueProvider.notifier).resumeUnfinished());
  });
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
