// On-device OCR smoke benchmark. Run on a phone or emulator:
//
//   flutter test integration_test/ocr_benchmark_test.dart -d <device>
//
// See docs/OCR_BENCHMARK.md. The thresholds below are smoke thresholds for
// clean, synthetic, printed pages: they catch a broken engine, missing
// trained data or wrong routing, not small accuracy regressions.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:scanly/core/services/image_service.dart';
import 'package:scanly/data/services/ocr/device_ocr_engine.dart';
import 'package:scanly/data/services/ocr/mlkit_latin_recognizer.dart';
import 'package:scanly/data/services/ocr/ocr_accuracy.dart';
import 'package:scanly/data/services/ocr/tesseract_plugin_runner.dart';
import 'package:scanly/domain/entities/app_settings.dart';

const bengaliFont = 'NotoSansBengali';

const englishText =
    'Scanly turns paper into clean digital documents. Place the page on a '
    'flat surface with good light, hold the phone steady, and the scanner '
    'finds the edges for you. Every page is stored on this device only. '
    'Invoice number 4821 was paid on 12 March 2024 for a total of 375 taka.';

const banglaText =
    'আমাদের গ্রামের পাশে একটি ছোট নদী আছে। বর্ষাকালে নদীর পানি অনেক বেড়ে '
    'যায় এবং চারদিকে সবুজ ধানক্ষেত দেখা যায়। শিশুরা বিকেলে মাঠে খেলা করে '
    'আর কৃষকেরা সন্ধ্যায় বাড়ি ফেরে। এই বছর ১২৫ মণ ধান হয়েছে।';

const mixedText =
    'রসিদ নম্বর ৪৫৬ - Receipt number 456. গ্রাহকের নাম: Rahim Uddin. '
    'মোট মূল্য ১,২৫০ টাকা (Total 1,250 Taka). পরিশোধের তারিখ ১০ জানুয়ারি '
    'Payment date 10 January. ধন্যবাদ, Thank you for shopping with us.';

class BenchCase {
  const BenchCase(
    this.name,
    this.language,
    this.reference,
    this.style,
    this.maxCer, {
    this.jpeg = false,
  });

  final String name;
  final OcrLanguage language;
  final String reference;
  final TextStyle style;
  final double maxCer;
  final bool jpeg;
}

class BenchResult {
  BenchResult(this.c, this.engine, this.cer, this.wer, this.ms, this.text);

  final BenchCase c;
  final String engine;
  final double cer;
  final double wer;
  final int ms;
  final String text;
}

Future<void> loadBengaliFont() async {
  final loader = FontLoader(bengaliFont)
    ..addFont(rootBundle.load('assets/fonts/NotoSansBengali-Regular.ttf'));
  await loader.load();
}

/// Renders [text] as black-on-white printed page (A4 at ~150 dpi) and saves
/// it as PNG or JPEG.
Future<String> renderPage(
  String dir,
  String name,
  String text,
  TextStyle style, {
  required bool jpeg,
}) async {
  const width = 1240;
  const height = 1754;
  const margin = 110.0;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(
      const Rect.fromLTWH(0, 0, width + 0.0, height + 0.0),
      Paint()..color = const Color(0xFFFFFFFF),
    );
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width - margin * 2);
  painter.paint(canvas, const Offset(margin, margin));
  painter.dispose();

  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  try {
    if (jpeg) {
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final decoded = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgba!.buffer,
        numChannels: 4,
      );
      final path = p.join(dir, '$name.jpg');
      await File(path).writeAsBytes(img.encodeJpg(decoded, quality: 90));
      return path;
    }
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final path = p.join(dir, '$name.png');
    await File(path).writeAsBytes(Uint8List.view(png!.buffer));
    return path;
  } finally {
    image.dispose();
  }
}

String pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OCR benchmark: English, Bangla, Mixed', (tester) async {
    await loadBengaliFont();
    final tmp = await getTemporaryDirectory();
    final dir = await Directory(p.join(tmp.path, 'ocr_benchmark'))
        .create(recursive: true);

    const base = TextStyle(color: Color(0xFF000000), fontSize: 34, height: 1.5);
    final cases = [
      const BenchCase('english', OcrLanguage.english, englishText, base, 0.15),
      BenchCase(
        'bangla',
        OcrLanguage.bangla,
        banglaText,
        base.copyWith(fontFamily: bengaliFont),
        0.35,
      ),
      BenchCase(
        'mixed',
        OcrLanguage.mixed,
        mixedText,
        base.copyWith(fontFamilyFallback: const [bengaliFont]),
        0.35,
        jpeg: true,
      ),
    ];

    final engine = DeviceOcrEngine(
      latin: const MlKitLatinRecognizer(),
      tesseract: const TesseractPluginRunner(),
      readSize: const ImageService().readSize,
    );

    final results = <BenchResult>[];
    for (final c in cases) {
      final path = await renderPage(
        dir.path,
        c.name,
        c.reference,
        c.style,
        jpeg: c.jpeg,
      );
      final watch = Stopwatch()..start();
      final result = await engine.recognize(path, c.language);
      watch.stop();
      results.add(
        BenchResult(
          c,
          result.engine,
          characterErrorRate(c.reference, result.text),
          wordErrorRate(c.reference, result.text),
          watch.elapsedMilliseconds,
          result.text,
        ),
      );
    }

    final table = StringBuffer()
      ..writeln('| Page | Language | Engine | CER | WER | Time (ms) |')
      ..writeln('|------|----------|--------|-----|-----|-----------|');
    for (final r in results) {
      table.writeln(
        '| ${r.c.name} | ${r.c.language.name} | ${r.engine} | '
        '${pct(r.cer)} | ${pct(r.wer)} | ${r.ms} |',
      );
    }
    debugPrint('\nOCR benchmark (${Platform.operatingSystem})\n$table');
    for (final r in results) {
      debugPrint('--- ${r.c.name} recognised text ---\n${r.text}\n');
    }
    binding.reportData = {
      for (final r in results)
        r.c.name: {'engine': r.engine, 'cer': r.cer, 'wer': r.wer, 'ms': r.ms},
    };

    for (final r in results) {
      expect(
        r.cer,
        lessThan(r.c.maxCer),
        reason: '${r.c.name}: CER ${pct(r.cer)} >= smoke limit',
      );
    }
  });
}
