// Generates Scanly's launcher icons and launch-screen marks.
//
// Run from the project root:
//
//   dart run tool/generate_app_icons.dart
//
// The mark is the same one `lib/shared/widgets/app_logo.dart` paints in
// code: a navy tile, a white page, an amber scan line and light-navy corner
// brackets. Shapes are described as signed distance fields and rasterised
// with 4x4 supersampling per output pixel (premultiplied, then averaged
// down), so every size is drawn fresh rather than resized from a master.
//
// Outputs (all committed):
//   assets/branding/                 masters for stores and docs
//   fastlane/metadata/android/en-US/images/icon.png   F-Droid listing icon
//   android/app/src/main/res/mipmap-*      legacy + adaptive launcher icons
//   android/app/src/main/res/drawable-*    launch_mark.png (pre-Android 12)
//   ios/Runner/Assets.xcassets/AppIcon.appiconset   every size in Contents.json
//   ios/Runner/Assets.xcassets/LaunchImage.imageset @1x/@2x/@3x
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

// Brand colors, mirrored from lib/core/theme/app_colors.dart.
const _navy800 = _Rgb(0x16, 0x25, 0x44);
const _navy200 = _Rgb(0xB9, 0xC8, 0xE8);
const _white = _Rgb(0xFF, 0xFF, 0xFF);
const _amber = _Rgb(0xF2, 0xB5, 0x3A);

/// Supersampling factor per axis.
const _ss = 4;

/// Adaptive icons: the mark's size relative to the 108dp canvas. Its farthest
/// point (a bracket corner) sits 0.463 * scale from the centre, so 0.65 keeps
/// it at ~32.5dp, inside the 33dp-radius safe zone every launcher mask keeps.
const _adaptiveScale = 0.65;

/// Legacy square icons leave a 2dp margin on the 48dp grid.
const _legacyPad = 2 / 48;

/// The mark inside the legacy round icon is shrunk so bracket corners clear
/// the circle edge.
const _roundMarkScale = 0.86;

const _densities = <String, double>{
  'mdpi': 1,
  'hdpi': 1.5,
  'xhdpi': 2,
  'xxhdpi': 3,
  'xxxhdpi': 4,
};

Future<void> main() async {
  final root = Directory.current.path;
  if (!File('$root/pubspec.yaml').existsSync()) {
    stderr.writeln('Run this from the project root.');
    exitCode = 64;
    return;
  }
  var count = 0;

  void write(String path, img.Image image) {
    final file = File('$root/$path')..parent.createSync(recursive: true);
    file.writeAsBytesSync(img.encodePng(image, level: 9));
    count++;
    stdout.writeln(
      '  $path  ${image.width}x${image.height}'
      '${image.numChannels == 3 ? '  (opaque RGB)' : ''}',
    );
  }

  stdout.writeln('Branding masters');
  write('assets/branding/icon_1024.png', _render(1024, _fullBleed()));
  write(
    'assets/branding/icon_foreground_1024.png',
    _render(1024, _foreground(), opaque: false),
  );
  write(
    'assets/branding/icon_monochrome_1024.png',
    _render(1024, _monochrome(), opaque: false),
  );
  // Google Play wants a 512x512 full-bleed icon; it applies its own mask.
  write('assets/branding/play_store_icon_512.png', _render(512, _fullBleed()));
  // F-Droid / fastlane metadata icon.
  write(
    'fastlane/metadata/android/en-US/images/icon.png',
    _render(512, _fullBleed()),
  );

  stdout.writeln('Android');
  const res = 'android/app/src/main/res';
  for (final MapEntry(key: name, value: m) in _densities.entries) {
    write(
      '$res/mipmap-$name/ic_launcher.png',
      _render((48 * m).round(), _legacySquare(), opaque: false),
    );
    write(
      '$res/mipmap-$name/ic_launcher_round.png',
      _render((48 * m).round(), _legacyRound(), opaque: false),
    );
    write(
      '$res/mipmap-$name/ic_launcher_foreground.png',
      _render((108 * m).round(), _foreground(), opaque: false),
    );
    write(
      '$res/mipmap-$name/ic_launcher_monochrome.png',
      _render((108 * m).round(), _monochrome(), opaque: false),
    );
    write(
      '$res/drawable-$name/launch_mark.png',
      _render((160 * m).round(), _launchMark(), opaque: false),
    );
  }

  stdout.writeln('iOS');
  const appIcon = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  final contents =
      jsonDecode(File('$root/$appIcon/Contents.json').readAsStringSync())
          as Map<String, dynamic>;
  final written = <String>{};
  for (final entry in contents['images'] as List<dynamic>) {
    final image = entry as Map<String, dynamic>;
    final filename = image['filename'] as String?;
    if (filename == null || !written.add(filename)) continue;
    final points = double.parse((image['size'] as String).split('x').first);
    final scale = double.parse((image['scale'] as String).replaceAll('x', ''));
    // Apple rejects icons with an alpha channel, so all are opaque RGB.
    write('$appIcon/$filename', _render((points * scale).round(), _fullBleed()));
  }
  const launch = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
  for (final (suffix, scale) in [('', 1), ('@2x', 2), ('@3x', 3)]) {
    write(
      '$launch/LaunchImage$suffix.png',
      _render(120 * scale, _launchMark(), opaque: false),
    );
  }

  stdout.writeln('Wrote $count images.');
}

// ---------------------------------------------------------------------------
// Variants. Coordinates are in unit space: (0, 0) top-left, (1, 1) bottom-right.

/// Full-bleed navy square with the mark: iOS (the OS applies the mask), the
/// store icons and the opaque master.
List<_Layer> _fullBleed() => [
  _Layer((x, y) => -1, _navy800),
  ..._mark(),
];

/// Pre-Android 8 square icon: the rounded navy tile, as in AppLogo.
List<_Layer> _legacySquare() {
  const side = 1 - 2 * _legacyPad;
  return [
    _Layer(_rrect(_legacyPad, _legacyPad, side, side, 0.28 * side), _navy800),
    ..._place(_mark(), _legacyPad, _legacyPad, side),
  ];
}

/// Pre-Android 8 round icon.
List<_Layer> _legacyRound() {
  const radius = 0.5 - _legacyPad;
  const markSide = 2 * radius * _roundMarkScale;
  const offset = (1 - markSide) / 2;
  return [
    _Layer(_circle(0.5, 0.5, radius), _navy800),
    ..._place(_mark(), offset, offset, markSide),
  ];
}

/// Adaptive-icon foreground: the mark on transparency; the navy tile comes
/// from the `ic_launcher_background` color.
List<_Layer> _foreground() {
  const offset = (1 - _adaptiveScale) / 2;
  return _place(_mark(), offset, offset, _adaptiveScale);
}

/// Android 13 themed-icon layer: a single colour, so the scan line is cut
/// out of the page with a small gap to stay readable.
List<_Layer> _monochrome() {
  const offset = (1 - _adaptiveScale) / 2;
  return _place(
    [
      _Layer(_brackets(), _white),
      _Layer(_page(), _white),
      _Layer(_capsule(0.27, 0.5, 0.73, 0.5, 0.025 + 0.03), null),
      _Layer(_scanLine(), _white),
    ],
    offset,
    offset,
    _adaptiveScale,
  );
}

/// Launch screens: the mark alone, drawn on a navy window background.
List<_Layer> _launchMark() => _mark();

/// The mark itself, minus the tile, at AppLogo's proportions.
List<_Layer> _mark() => [
  _Layer(_page(), _white),
  _Layer(_scanLine(), _amber),
  _Layer(_brackets(), _navy200),
];

_Sdf _page() => _rrect(0.34, 0.30, 0.32, 0.40, 0.04);

_Sdf _scanLine() => _capsule(0.27, 0.5, 0.73, 0.5, 0.05 / 2);

/// Four corner brackets: stroke width 0.055 with round caps and a miter
/// join (Flutter's default), i.e. two capsules plus a square at the corner.
_Sdf _brackets() {
  const inset = 0.2;
  const len = 0.14;
  const half = 0.055 / 2;
  const far = 1 - inset;
  final parts = <_Sdf>[];
  for (final (x, y, dx, dy) in [
    (inset, inset, 1.0, 1.0),
    (far, inset, -1.0, 1.0),
    (inset, far, 1.0, -1.0),
    (far, far, -1.0, -1.0),
  ]) {
    parts
      ..add(_capsule(x, y, x, y + dy * len, half))
      ..add(_capsule(x, y, x + dx * len, y, half))
      ..add(_rrect(x - half, y - half, 2 * half, 2 * half, 0));
  }
  return (px, py) {
    var d = double.infinity;
    for (final part in parts) {
      d = math.min(d, part(px, py));
    }
    return d;
  };
}

/// Maps layers drawn in unit space into the square at ([left], [top]) with
/// side [side].
List<_Layer> _place(List<_Layer> layers, double left, double top, double side) {
  return [
    for (final layer in layers)
      _Layer(
        (x, y) => layer.sdf((x - left) / side, (y - top) / side) * side,
        layer.color,
      ),
  ];
}

// ---------------------------------------------------------------------------
// Signed distance fields (negative inside).

typedef _Sdf = double Function(double x, double y);

_Sdf _rrect(double left, double top, double w, double h, double r) {
  final cx = left + w / 2;
  final cy = top + h / 2;
  final hx = w / 2 - r;
  final hy = h / 2 - r;
  return (x, y) {
    final qx = (x - cx).abs() - hx;
    final qy = (y - cy).abs() - hy;
    final ox = math.max(qx, 0.0);
    final oy = math.max(qy, 0.0);
    return math.sqrt(ox * ox + oy * oy) + math.min(math.max(qx, qy), 0.0) - r;
  };
}

_Sdf _circle(double cx, double cy, double r) => (x, y) {
  final dx = x - cx;
  final dy = y - cy;
  return math.sqrt(dx * dx + dy * dy) - r;
};

_Sdf _capsule(double ax, double ay, double bx, double by, double r) {
  final bax = bx - ax;
  final bay = by - ay;
  final lenSq = bax * bax + bay * bay;
  return (x, y) {
    final pax = x - ax;
    final pay = y - ay;
    final t = lenSq == 0
        ? 0.0
        : ((pax * bax + pay * bay) / lenSq).clamp(0.0, 1.0);
    final dx = pax - bax * t;
    final dy = pay - bay * t;
    return math.sqrt(dx * dx + dy * dy) - r;
  };
}

// ---------------------------------------------------------------------------
// Rasteriser.

class _Rgb {
  const _Rgb(this.r, this.g, this.b);
  final int r;
  final int g;
  final int b;
}

/// A filled shape. A null [color] erases what is below it.
class _Layer {
  const _Layer(this.sdf, this.color);
  final _Sdf sdf;
  final _Rgb? color;
}

/// Draws [layers] into a [size] x [size] image. Each pixel averages
/// [_ss] x [_ss] premultiplied subsamples, each with analytic coverage over a
/// one-subsample-wide edge. Opaque images are written as 3-channel RGB.
img.Image _render(int size, List<_Layer> layers, {bool opaque = true}) {
  final image = img.Image(
    width: size,
    height: size,
    numChannels: opaque ? 3 : 4,
  );
  final sub = 1 / (size * _ss);
  for (var py = 0; py < size; py++) {
    for (var px = 0; px < size; px++) {
      var sr = 0.0, sg = 0.0, sb = 0.0, sa = 0.0;
      for (var j = 0; j < _ss; j++) {
        final y = (py * _ss + j + 0.5) * sub;
        for (var i = 0; i < _ss; i++) {
          final x = (px * _ss + i + 0.5) * sub;
          var r = 0.0, g = 0.0, b = 0.0, a = 0.0;
          for (final layer in layers) {
            final cov = (0.5 - layer.sdf(x, y) / sub).clamp(0.0, 1.0);
            if (cov == 0) continue;
            final keep = 1 - cov;
            final c = layer.color;
            if (c == null) {
              r *= keep;
              g *= keep;
              b *= keep;
              a *= keep;
            } else {
              r = c.r * cov + r * keep;
              g = c.g * cov + g * keep;
              b = c.b * cov + b * keep;
              a = cov + a * keep;
            }
          }
          sr += r;
          sg += g;
          sb += b;
          sa += a;
        }
      }
      const n = _ss * _ss;
      final alpha = sa / n;
      if (opaque) {
        image.setPixelRgb(px, py, (sr / n).round(), (sg / n).round(),
            (sb / n).round(),);
      } else if (alpha == 0) {
        image.setPixelRgba(px, py, 0, 0, 0, 0);
      } else {
        // Un-premultiply.
        image.setPixelRgba(
          px,
          py,
          (sr / sa).round().clamp(0, 255),
          (sg / sa).round().clamp(0, 255),
          (sb / sa).round().clamp(0, 255),
          (alpha * 255).round(),
        );
      }
    }
  }
  return image;
}
