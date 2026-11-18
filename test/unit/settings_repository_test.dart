import 'package:flutter_test/flutter_test.dart';
import 'package:scanly/data/repositories/prefs_settings_repository.dart';
import 'package:scanly/domain/entities/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('returns defaults when nothing is stored', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = PrefsSettingsRepository(await SharedPreferences.getInstance());
    expect(repo.load(), const AppSettings());
  });

  test('round-trips every field', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = PrefsSettingsRepository(await SharedPreferences.getInstance());
    const custom = AppSettings(
      themeMode: AppThemeMode.dark,
      scanQuality: ScanQuality.maximum,
      pdfPageSize: PdfPageSize.legal,
      pdfOrientation: PdfOrientation.landscape,
      ocrLanguage: OcrLanguage.bangla,
      autoOcr: false,
      compression: ImageCompression.high,
    );

    await repo.save(custom);

    expect(repo.load(), custom);
  });

  test('falls back to defaults for unknown stored values', () async {
    SharedPreferences.setMockInitialValues({
      'settings.theme_mode': 'purple',
      'settings.pdf_page_size': 'a3',
    });
    final repo = PrefsSettingsRepository(await SharedPreferences.getInstance());
    final loaded = repo.load();
    expect(loaded.themeMode, AppThemeMode.system);
    expect(loaded.pdfPageSize, PdfPageSize.a4);
  });
}
