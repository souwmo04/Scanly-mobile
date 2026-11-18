import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanly/core/errors/app_exception.dart';
import 'package:scanly/core/services/image_service.dart';
import 'package:scanly/data/services/ocr/device_ocr_engine.dart';
import 'package:scanly/data/services/ocr/ocr_adapters.dart';
import 'package:scanly/data/services/ocr/tesseract_plugin_runner.dart';
import 'package:scanly/domain/entities/app_settings.dart';
import 'package:scanly/domain/entities/ocr_result.dart';

class FakeLatin implements LatinTextRecognizer {
  FakeLatin({this.blocks = const [], this.error});

  final List<List<PixelLine>> blocks;
  final Object? error;
  final calls = <String>[];

  @override
  Future<List<List<PixelLine>>> recognizeBlocks(String imagePath) async {
    calls.add(imagePath);
    if (error != null) throw error!;
    return blocks;
  }
}

class FakeTesseract implements TesseractRunner {
  FakeTesseract({this.text = '', this.error});

  final String text;
  final Object? error;
  final languages = <String>[];

  @override
  Future<String> extractText(String imagePath, String languageCode) async {
    languages.add(languageCode);
    if (error != null) throw error!;
    return text;
  }
}

const path = '/pages/p1.jpg';

DeviceOcrEngine engine({
  FakeLatin? latin,
  FakeTesseract? tesseract,
  ImageSize size = (width: 1000, height: 2000),
  Object? sizeError,
  bool exists = true,
}) => DeviceOcrEngine(
  latin: latin ?? FakeLatin(),
  tesseract: tesseract ?? FakeTesseract(),
  readSize: (_) async {
    if (sizeError != null) throw sizeError;
    return size;
  },
  fileExists: (_) => exists,
);

void main() {
  group('routing', () {
    test('English uses ML Kit with normalised boxes', () async {
      final latin = FakeLatin(
        blocks: [
          [
            const PixelLine('Hello   world', 100, 200, 600, 260),
            const PixelLine('Second line', 100, 300, 500, 360),
          ],
          [const PixelLine('New block', 0, 1000, 1000, 1100)],
        ],
      );
      final tesseract = FakeTesseract(text: 'unused');
      final result = await engine(
        latin: latin,
        tesseract: tesseract,
      ).recognize(path, OcrLanguage.english);

      expect(latin.calls, [path]);
      expect(tesseract.languages, isEmpty);
      expect(result.engine, OcrEngineId.mlKit);
      expect(result.languageCode, 'eng');
      expect(result.text, 'Hello world\nSecond line\n\nNew block');
      expect(result.lines, [
        const OcrLine('Hello world', OcrBox(0.1, 0.1, 0.6, 0.13)),
        const OcrLine('Second line', OcrBox(0.1, 0.15, 0.5, 0.18)),
        const OcrLine('New block', OcrBox(0, 0.5, 1, 0.55)),
      ]);
    });

    test('Bangla uses Tesseract ben, without boxes', () async {
      final latin = FakeLatin();
      final tesseract = FakeTesseract(text: 'আমি  ভাত খাই।\n\n\nভালো \n');
      final result = await engine(
        latin: latin,
        tesseract: tesseract,
      ).recognize(path, OcrLanguage.bangla);

      expect(latin.calls, isEmpty);
      expect(tesseract.languages, ['ben']);
      expect(result.engine, OcrEngineId.tesseract);
      expect(result.languageCode, 'ben');
      expect(result.text, 'আমি ভাত খাই।\n\nভালো');
      expect(result.lines, const [OcrLine('আমি ভাত খাই।'), OcrLine('ভালো')]);
    });

    test('Mixed uses a single Tesseract ben+eng pass', () async {
      final latin = FakeLatin();
      final tesseract = FakeTesseract(text: 'Invoice চালান\nTotal ১২৩');
      final result = await engine(
        latin: latin,
        tesseract: tesseract,
      ).recognize(path, OcrLanguage.mixed);

      expect(latin.calls, isEmpty);
      expect(tesseract.languages, ['ben+eng']);
      expect(result.languageCode, 'ben+eng');
      expect(result.text, 'Invoice চালান\nTotal ১২৩');
      expect(result.lines, hasLength(2));
    });

    test('Tesseract runner asks for preserved spaces and auto PSM', () {
      expect(TesseractPluginRunner.options, {
        'preserve_interword_spaces': '1',
        'tessedit_pageseg_mode': '3',
      });
    });
  });

  group('fallback', () {
    test('English falls back to Tesseract eng when ML Kit throws', () async {
      final latin = FakeLatin(error: PlatformException(code: 'error'));
      final tesseract = FakeTesseract(text: 'Fallback text');
      final result = await engine(
        latin: latin,
        tesseract: tesseract,
      ).recognize(path, OcrLanguage.english);

      expect(latin.calls, [path]);
      expect(tesseract.languages, ['eng']);
      expect(result.engine, OcrEngineId.tesseract);
      expect(result.languageCode, 'eng');
      expect(result.text, 'Fallback text');
    });

    test('falls back when the ML Kit plugin is missing', () async {
      final tesseract = FakeTesseract(text: 'ok');
      final result = await engine(
        latin: FakeLatin(error: MissingPluginException()),
        tesseract: tesseract,
      ).recognize(path, OcrLanguage.english);
      expect(result.engine, OcrEngineId.tesseract);
    });

    test('an empty ML Kit result is accepted without a second pass', () async {
      final tesseract = FakeTesseract(text: 'x');
      final result = await engine(tesseract: tesseract)
          .recognize(path, OcrLanguage.english);
      expect(result.isEmpty, isTrue);
      expect(result.lines, isEmpty);
      expect(tesseract.languages, isEmpty);
    });

    test(
      'keeps ML Kit text without boxes if the size cannot be read',
      () async {
        final result = await engine(
          latin: FakeLatin(
            blocks: [
              [const PixelLine('Text', 1, 2, 3, 4)],
            ],
          ),
          sizeError: const StorageException('bad'),
        ).recognize(path, OcrLanguage.english);
        expect(result.lines, const [OcrLine('Text')]);
      },
    );

    test('ML Kit noise lines are dropped', () async {
      final result = await engine(
        latin: FakeLatin(
          blocks: [
            [
              const PixelLine('—', 0, 0, 10, 10),
              const PixelLine('Real', 0, 20, 10, 30),
            ],
            [const PixelLine('|||', 0, 40, 10, 50)],
          ],
        ),
      ).recognize(path, OcrLanguage.english);
      expect(result.text, 'Real');
      expect(result.lines.map((l) => l.text), ['Real']);
    });
  });

  group('normalisePixelBox', () {
    OcrBox? box(
      double l,
      double t,
      double r,
      double b, {
      num w = 100,
      num h = 200,
    }) => normalisePixelBox(
      left: l,
      top: t,
      right: r,
      bottom: b,
      width: w,
      height: h,
    );

    test('divides by image size', () {
      expect(box(10, 20, 50, 100), const OcrBox(0.1, 0.1, 0.5, 0.5));
    });

    test('clamps to 0–1', () {
      expect(box(-10, -5, 150, 400), const OcrBox(0, 0, 1, 1));
      expect(box(90, 190, 120, 210), const OcrBox(0.9, 0.95, 1, 1));
    });

    test('swaps reversed coordinates', () {
      expect(box(50, 100, 10, 20), const OcrBox(0.1, 0.1, 0.5, 0.5));
    });

    test('returns null for invalid sizes or boxes outside the image', () {
      expect(box(1, 1, 2, 2, w: 0), isNull);
      expect(box(1, 1, 2, 2, h: -1), isNull);
      expect(box(200, 10, 300, 20), isNull);
      expect(box(double.nan, 1, 2, 2), isNull);
      expect(box(5, 5, 5, 10), isNull);
    });
  });

  group('errors', () {
    test('missing image → NotFoundException', () async {
      await expectLater(
        engine(exists: false).recognize(path, OcrLanguage.bangla),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('Tesseract failure → user-facing AppException', () async {
      final future = engine(
        tesseract: FakeTesseract(error: StateError('native crash')),
      ).recognize(path, OcrLanguage.bangla);
      await expectLater(
        future,
        throwsA(
          isA<OcrException>()
              .having(
                (e) => e.message,
                'message',
                'Text recognition failed. Try again.',
              )
              .having((e) => e.cause, 'cause', isA<StateError>()),
        ),
      );
    });

    test('English fails when both ML Kit and Tesseract fail', () async {
      await expectLater(
        engine(
          latin: FakeLatin(error: Exception('mlkit')),
          tesseract: FakeTesseract(error: Exception('tess')),
        ).recognize(path, OcrLanguage.english),
        throwsA(isA<OcrException>()),
      );
    });

    test('mapOcrError messages', () {
      expect(
        mapOcrError(PlatformException(code: 'BUSY')).message,
        'Text recognition is busy. Try again in a moment.',
      );
      expect(
        mapOcrError(PlatformException(code: 'OCR_TIMEOUT')).message,
        'Text recognition is busy. Try again in a moment.',
      );
      expect(
        mapOcrError(PlatformException(code: 'INIT_ERROR')).message,
        startsWith('Text recognition data could not be loaded'),
      );
      expect(
        mapOcrError(MissingPluginException()).message,
        'Text recognition is not available on this device.',
      );
      expect(
        mapOcrError(ArgumentError('Image file does not exist')),
        isA<NotFoundException>(),
      );
      expect(
        mapOcrError(Exception('x')).message,
        'Text recognition failed. Try again.',
      );
      const original = ValidationException('kept');
      expect(identical(mapOcrError(original), original), isTrue);
    });
  });
}
