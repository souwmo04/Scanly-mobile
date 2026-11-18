import 'package:material_ui/material_ui.dart';

/// Raw color palette for Scanly's navy, white and neutral identity.
///
/// Widgets should read colors from `Theme.of(context).colorScheme` rather
/// than from this class directly, so light and dark themes stay consistent.
abstract final class AppColors {
  // Navy scale (brand).
  static const navy950 = Color(0xFF0A1428);
  static const navy900 = Color(0xFF0E1A33);
  static const navy800 = Color(0xFF162544);
  static const navy700 = Color(0xFF1F3260);
  static const navy600 = Color(0xFF2B4580);
  static const navy500 = Color(0xFF3A5A9B);
  static const navy300 = Color(0xFF8EA5D6);
  static const navy200 = Color(0xFFB9C8E8);
  static const navy100 = Color(0xFFE3E9F5);
  static const navy50 = Color(0xFFF2F5FB);

  // Neutrals (light).
  static const white = Color(0xFFFFFFFF);
  static const neutral25 = Color(0xFFFAFAFB);
  static const neutral50 = Color(0xFFF4F5F7);
  static const neutral100 = Color(0xFFECEEF2);
  static const neutral200 = Color(0xFFE1E4EA);
  static const neutral400 = Color(0xFFA0A7B5);
  static const neutral500 = Color(0xFF8A93A3);
  static const neutral600 = Color(0xFF5B6475);
  static const neutral900 = Color(0xFF111827);

  // Neutrals (dark).
  static const ink950 = Color(0xFF0B1120);
  static const ink900 = Color(0xFF111A2C);
  static const ink850 = Color(0xFF162036);
  static const ink800 = Color(0xFF1B2540);
  static const ink700 = Color(0xFF263252);
  static const ink500 = Color(0xFF5C6886);
  static const ink300 = Color(0xFFA6AFC2);
  static const ink100 = Color(0xFFF3F5F9);

  // Semantic accents.
  static const amber = Color(0xFFF2B53A);
  static const red = Color(0xFFD64545);
  static const redDark = Color(0xFFFF8A80);
  static const green = Color(0xFF2E9E6B);

  /// Colors users can assign to folders. Stored by index in the database.
  static const folderPalette = <Color>[
    Color(0xFF3A5A9B),
    Color(0xFF2E9E6B),
    Color(0xFFE08A2E),
    Color(0xFFD64545),
    Color(0xFF8B5CF6),
    Color(0xFF0EA5A4),
    Color(0xFFDB2777),
    Color(0xFF64748B),
  ];

  static Color folderColor(int index) =>
      folderPalette[index.abs() % folderPalette.length];
}
