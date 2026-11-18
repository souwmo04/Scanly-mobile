import 'dart:io';
import 'dart:ui' show Rect;

import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/services/pdf_service.dart';

/// [ShareService] backed by the platform share sheet (share_plus) and the
/// system print dialog (printing).
class SystemShareService implements ShareService {
  const SystemShareService();

  @override
  Future<void> shareFiles(
    List<String> paths, {
    String? subject,
    Rect? origin,
  }) async {
    if (paths.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [for (final path in paths) XFile(path, mimeType: _mime(path))],
        subject: subject,
        title: subject,
        sharePositionOrigin: origin,
      ),
    );
  }

  @override
  Future<void> printPdf(String path, {required String jobName}) async {
    final bytes = await File(path).readAsBytes();
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: jobName);
  }

  static String? _mime(String path) =>
      switch (p.extension(path).toLowerCase()) {
        '.pdf' => 'application/pdf',
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.png' => 'image/png',
        '.txt' => 'text/plain',
        _ => null,
      };
}
