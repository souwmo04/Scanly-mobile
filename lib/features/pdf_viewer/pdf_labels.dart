import '../../domain/entities/app_settings.dart';

/// User-facing names for PDF settings.
String pdfPageSizeLabel(PdfPageSize size) => switch (size) {
  PdfPageSize.a4 => 'A4',
  PdfPageSize.a5 => 'A5',
  PdfPageSize.letter => 'Letter',
  PdfPageSize.legal => 'Legal',
  PdfPageSize.original => 'Original size',
};

String pdfOrientationLabel(PdfOrientation orientation) => switch (orientation) {
  PdfOrientation.auto => 'Auto',
  PdfOrientation.portrait => 'Portrait',
  PdfOrientation.landscape => 'Landscape',
};

String compressionLabel(ImageCompression compression) => switch (compression) {
  ImageCompression.low => 'Low',
  ImageCompression.balanced => 'Balanced',
  ImageCompression.high => 'High',
};

/// Short explanation of a compression level.
String compressionHint(ImageCompression compression) => switch (compression) {
  ImageCompression.low => 'Best quality, larger file',
  ImageCompression.balanced => 'Good quality, moderate size',
  ImageCompression.high => 'Smallest file, lower quality',
};

/// "Creating PDF…" or "Creating PDF… page 3 of 8", where [done] pages of
/// [total] are already written.
String pdfProgressLabel(int done, int total) {
  if (total <= 0) return 'Creating PDF…';
  if (done >= total) return 'Finishing PDF…';
  return 'Creating PDF… page ${done + 1} of $total';
}
