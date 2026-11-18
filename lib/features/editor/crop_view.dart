import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';
import '../../core/vision/quad.dart';

/// Maps a point normalised to the original image into the frame shown after
/// rotating the image clockwise by [quarterTurns].
Pt toDisplay(Pt p, int quarterTurns) => switch (quarterTurns % 4) {
  1 => Pt(1 - p.y, p.x),
  2 => Pt(1 - p.x, 1 - p.y),
  3 => Pt(p.y, 1 - p.x),
  _ => p,
};

/// Inverse of [toDisplay].
Pt fromDisplay(Pt p, int quarterTurns) => switch (quarterTurns % 4) {
  1 => Pt(p.y, 1 - p.x),
  2 => Pt(1 - p.x, 1 - p.y),
  3 => Pt(1 - p.y, p.x),
  _ => p,
};

/// Shows the original image with four draggable crop corners.
///
/// Corners are kept in the original image's normalised coordinates; the
/// image (and handles) are shown rotated by [rotation] so users crop the
/// page the way it will look.
class CropView extends StatefulWidget {
  const CropView({
    required this.imagePath,
    required this.imageWidth,
    required this.imageHeight,
    required this.corners,
    required this.rotation,
    required this.onDragStart,
    required this.onChanged,
    super.key,
  });

  final String imagePath;

  /// Displayed (EXIF-corrected) size of the original image.
  final int imageWidth;
  final int imageHeight;
  final Quad corners;
  final int rotation;
  final VoidCallback onDragStart;
  final ValueChanged<Quad> onChanged;

  @override
  State<CropView> createState() => _CropViewState();
}

class _CropViewState extends State<CropView> {
  /// Index of the corner being dragged (0 = top-left, clockwise).
  int? _active;
  Offset? _touch;

  static const _handleRadius = 14.0;
  static const _hitRadius = 36.0;

  int get _turns => (widget.rotation ~/ 90) % 4;

  @override
  Widget build(BuildContext context) {
    final quarter = _turns;
    final shownW = quarter.isOdd ? widget.imageHeight : widget.imageWidth;
    final shownH = quarter.isOdd ? widget.imageWidth : widget.imageHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        const pad = 28.0; // room for handles at the image edge
        final maxW = math.max(1.0, constraints.maxWidth - pad * 2);
        final maxH = math.max(1.0, constraints.maxHeight - pad * 2);
        final scale = math.min(maxW / shownW, maxH / shownH);
        final w = shownW * scale;
        final h = shownH * scale;
        final origin = Offset(
          (constraints.maxWidth - w) / 2,
          (constraints.maxHeight - h) / 2,
        );
        final rect = origin & Size(w, h);
        final displayPts = [
          for (final p in widget.corners.points) toDisplay(p, quarter),
        ];
        final offsets = [
          for (final p in displayPts)
            Offset(rect.left + p.x * w, rect.top + p.y * h),
        ];
        final valid = widget.corners.isConvex;
        final dpr = MediaQuery.devicePixelRatioOf(context);

        void updateFrom(Offset local) {
          final i = _active;
          if (i == null) return;
          final dx = ((local.dx - rect.left) / w).clamp(0.0, 1.0);
          final dy = ((local.dy - rect.top) / h).clamp(0.0, 1.0);
          final original = fromDisplay(Pt(dx, dy), quarter);
          final pts = List.of(widget.corners.points)..[i] = original;
          widget.onChanged(Quad(pts[0], pts[1], pts[2], pts[3]));
          setState(() => _touch = local);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            final local = details.localPosition;
            var best = -1;
            var bestDist = _hitRadius;
            for (var i = 0; i < 4; i++) {
              final d = (offsets[i] - local).distance;
              if (d < bestDist) {
                bestDist = d;
                best = i;
              }
            }
            if (best < 0) return;
            widget.onDragStart();
            setState(() {
              _active = best;
              _touch = local;
            });
          },
          onPanUpdate: (details) => updateFrom(details.localPosition),
          onPanEnd: (_) => setState(() {
            _active = null;
            _touch = null;
          }),
          onPanCancel: () => setState(() {
            _active = null;
            _touch = null;
          }),
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: rect,
                child: RotatedBox(
                  quarterTurns: quarter,
                  child: Image.file(
                    File(widget.imagePath),
                    fit: BoxFit.fill,
                    cacheWidth: (math.max(w, h) * dpr).round(),
                    gaplessPlayback: true,
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _CropPainter(
                    corners: offsets,
                    imageRect: rect,
                    active: _active,
                    valid: valid,
                    handleRadius: _handleRadius,
                  ),
                ),
              ),
              if (_touch case final touch?)
                Positioned(
                  left: touch.dx - 55,
                  top: math.max(0, touch.dy - 150),
                  child: RawMagnifier(
                    size: const Size(110, 110),
                    magnificationScale: 2,
                    // Magnify the point under the finger, not under the lens.
                    focalPointOffset: Offset(
                      0,
                      touch.dy - math.max(0, touch.dy - 150) - 55,
                    ),
                    decoration: MagnifierDecoration(
                      shape: CircleBorder(
                        side: BorderSide(
                          color: valid ? AppColors.amber : AppColors.red,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
                ),
              for (var i = 0; i < 4; i++)
                Positioned(
                  left: offsets[i].dx - 24,
                  top: offsets[i].dy - 24,
                  child: Semantics(
                    label: const [
                      'Top-left corner',
                      'Top-right corner',
                      'Bottom-right corner',
                      'Bottom-left corner',
                    ][(i + quarter) % 4],
                    child: const SizedBox(width: 48, height: 48),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.corners,
    required this.imageRect,
    required this.active,
    required this.valid,
    required this.handleRadius,
  });

  final List<Offset> corners;
  final Rect imageRect;
  final int? active;
  final bool valid;
  final double handleRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Path()..addPolygon(corners, true);
    // Dim everything outside the crop.
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(imageRect)
      ..addPath(outline, Offset.zero);
    canvas.drawPath(
      shade,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    final color = valid ? AppColors.amber : AppColors.red;
    canvas.drawPath(
      outline,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    for (var i = 0; i < corners.length; i++) {
      final isActive = i == active;
      canvas
        ..drawCircle(
          corners[i],
          isActive ? handleRadius + 4 : handleRadius,
          Paint()..color = Colors.white,
        )
        ..drawCircle(
          corners[i],
          isActive ? handleRadius + 4 : handleRadius,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.corners != corners ||
      old.active != active ||
      old.valid != valid ||
      old.imageRect != imageRect;
}
