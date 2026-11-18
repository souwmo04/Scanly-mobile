import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';

/// Scanly's mark: a navy tile with four scan-frame corners around a page.
/// Drawn in code so it stays crisp at any size and needs no asset.
class AppLogo extends StatelessWidget {
  const AppLogo({this.size = 36, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Scanly',
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: const _LogoPainter(),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final tile = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(s * 0.28),
    );
    canvas.drawRRect(tile, Paint()..color = AppColors.navy800);

    // Page.
    final page = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.34, s * 0.30, s * 0.32, s * 0.40),
      Radius.circular(s * 0.04),
    );
    canvas.drawRRect(page, Paint()..color = AppColors.white);

    // Scan line.
    canvas.drawLine(
      Offset(s * 0.27, s * 0.50),
      Offset(s * 0.73, s * 0.50),
      Paint()
        ..color = AppColors.amber
        ..strokeWidth = s * 0.05
        ..strokeCap = StrokeCap.round,
    );

    // Corner brackets.
    final corner = Paint()
      ..color = AppColors.navy200
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.055
      ..strokeCap = StrokeCap.round;
    final inset = s * 0.2;
    final len = s * 0.14;
    final far = s - inset;
    for (final (x, y, dx, dy) in [
      (inset, inset, 1.0, 1.0),
      (far, inset, -1.0, 1.0),
      (inset, far, 1.0, -1.0),
      (far, far, -1.0, -1.0),
    ]) {
      final path = Path()
        ..moveTo(x, y + dy * len)
        ..lineTo(x, y)
        ..lineTo(x + dx * len, y);
      canvas.drawPath(path, corner);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
