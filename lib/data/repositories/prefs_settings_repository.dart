import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';

/// Stores [AppSettings] in SharedPreferences, one key per field. Enum
/// values are stored by name so reordering enums never corrupts settings.
class PrefsSettingsRepository implements SettingsRepository {
  PrefsSettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _themeKey = 'settings.theme_mode';
  static const _qualityKey = 'settings.scan_quality';
  static const _pageSizeKey = 'settings.pdf_page_size';
  static const _orientationKey = 'settings.pdf_orientation';
  static const _ocrLanguageKey = 'settings.ocr_language';
  static const _autoOcrKey = 'settings.auto_ocr';
  static const _compressionKey = 'settings.compression';
  static const _engineKey = 'settings.scanner_engine';

  @override
  AppSettings load() {
    const defaults = AppSettings();
    return AppSettings(
      themeMode: _enum(_themeKey, AppThemeMode.values, defaults.themeMode),
      scanQuality: _enum(_qualityKey, ScanQuality.values, defaults.scanQuality),
      scannerEngine: _enum(
        _engineKey,
        ScannerEngine.values,
        defaults.scannerEngine,
      ),
      pdfPageSize: _enum(
        _pageSizeKey,
        PdfPageSize.values,
        defaults.pdfPageSize,
      ),
      pdfOrientation: _enum(
        _orientationKey,
        PdfOrientation.values,
        defaults.pdfOrientation,
      ),
      ocrLanguage: _enum(
        _ocrLanguageKey,
        OcrLanguage.values,
        defaults.ocrLanguage,
      ),
      autoOcr: _prefs.getBool(_autoOcrKey) ?? defaults.autoOcr,
      compression: _enum(
        _compressionKey,
        ImageCompression.values,
        defaults.compression,
      ),
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    await Future.wait([
      _prefs.setString(_themeKey, settings.themeMode.name),
      _prefs.setString(_qualityKey, settings.scanQuality.name),
      _prefs.setString(_pageSizeKey, settings.pdfPageSize.name),
      _prefs.setString(_orientationKey, settings.pdfOrientation.name),
      _prefs.setString(_ocrLanguageKey, settings.ocrLanguage.name),
      _prefs.setBool(_autoOcrKey, settings.autoOcr),
      _prefs.setString(_compressionKey, settings.compression.name),
      _prefs.setString(_engineKey, settings.scannerEngine.name),
    ]);
  }

  T _enum<T extends Enum>(String key, List<T> values, T fallback) {
    final stored = _prefs.getString(key);
    if (stored == null) return fallback;
    return values.asNameMap()[stored] ?? fallback;
  }
}
