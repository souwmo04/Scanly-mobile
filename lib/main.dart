import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/services/storage_service.dart';
import 'shared/providers/core_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
}
