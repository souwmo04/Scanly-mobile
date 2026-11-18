import 'app_settings.dart';

/// Axis-aligned box normalised 0–1 to the page image.
class OcrBox {
  const OcrBox(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  List<double> toList() => [left, top, right, bottom];

  @override
  bool operator ==(Object other) =>
      other is OcrBox &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

/// One recognised line of text, with its position when the engine knows it.
class OcrLine {
  const OcrLine(this.text, [this.box]);

  final String text;
  final OcrBox? box;

  @override
  bool operator ==(Object other) =>
      other is OcrLine && other.text == text && other.box == box;

  @override
  int get hashCode => Object.hash(text, box);
}

/// Output of one OCR run on one page image.
class OcrResult {
  const OcrResult({
    required this.text,
    required this.lines,
    required this.languageCode,
    required this.engine,
  });

  /// Full text with line breaks.
  final String text;

  /// Lines in reading order (empty if the engine reports none).
  final List<OcrLine> lines;

  /// Tesseract-style language code that was used: `eng`, `ben` or `ben+eng`.
  final String languageCode;

  /// Engine id: [OcrEngineId.mlKit] or [OcrEngineId.tesseract].
  final String engine;

  bool get isEmpty => text.trim().isEmpty;
}

abstract final class OcrEngineId {
  static const mlKit = 'mlkit';
  static const tesseract = 'tesseract';
}

/// Tesseract language code for a user-facing [OcrLanguage].
String languageCodeOf(OcrLanguage language) => switch (language) {
  OcrLanguage.english => 'eng',
  OcrLanguage.bangla => 'ben',
  OcrLanguage.mixed => 'ben+eng',
};

enum OcrStatus { pending, processing, done, failed }

/// Stored OCR state of a page.
class PageOcr {
  const PageOcr({
    required this.pageId,
    required this.status,
    required this.text,
    required this.lines,
    required this.updatedAt,
    this.languageCode,
    this.engine,
    this.errorMessage,
  });

  final String pageId;
  final OcrStatus status;
  final String text;
  final List<OcrLine> lines;
  final String? languageCode;
  final String? engine;
  final String? errorMessage;
  final DateTime updatedAt;
}
