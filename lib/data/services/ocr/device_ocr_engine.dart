import 'dart:io';

import 'package:flutter/services.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/services/image_service.dart';
import '../../../domain/entities/app_settings.dart';
import '../../../domain/entities/ocr_result.dart';
import '../../../domain/services/ocr_engine.dart';
import 'ocr_adapters.dart';
import 'ocr_text_cleanup.dart';

/// Reads the displayed (EXIF-rotated) pixel size of an image.
typedef ImageSizeReader = Future<ImageSize> Function(String imagePath);

/// [OcrEngine] that runs entirely on the device.
///
/// * English: ML Kit Latin; if ML Kit throws (missing plugin, model or
///   native error) the page is retried with Tesseract `eng`. An empty ML Kit
///   result is accepted as is (a blank page should not cost a second pass).
/// * Bangla: Tesseract `ben`.
/// * Mixed: Tesseract `ben+eng` in one pass, so nothing is duplicated.
///
/// Every engine output goes through [cleanOcrText]. ML Kit lines carry
/// boxes normalised 0–1; Tesseract lines have no boxes (the plugin returns
/// plain text only).
class DeviceOcrEngine implements OcrEngine {
  DeviceOcrEngine({
    required this._latin,
    required this._tesseract,
    required this._readSize,
    bool Function(String path)? fileExists,
  }) : _fileExists = fileExists ?? ((path) => File(path).existsSync());

  final LatinTextRecognizer _latin;
  final TesseractRunner _tesseract;
  final ImageSizeReader _readSize;
  final bool Function(String path) _fileExists;

  @override
  Future<OcrResult> recognize(String imagePath, OcrLanguage language) async {
    if (!_fileExists(imagePath)) {
      throw const NotFoundException(
        'The page image is missing, so its text cannot be recognised.',
      );
    }
    try {
      return switch (language) {
        OcrLanguage.english => await _english(imagePath),
        OcrLanguage.bangla || OcrLanguage.mixed => await _runTesseract(
          imagePath,
          languageCodeOf(language),
        ),
      };
    } on Object catch (e) {
      throw mapOcrError(e);
    }
  }

  Future<OcrResult> _english(String imagePath) async {
    final List<List<PixelLine>> blocks;
    try {
      blocks = await _latin.recognizeBlocks(imagePath);
    } on Object {
      return _runTesseract(imagePath, languageCodeOf(OcrLanguage.english));
    }
    return _fromMlKit(imagePath, blocks);
  }

  Future<OcrResult> _fromMlKit(
    String imagePath,
    List<List<PixelLine>> blocks,
  ) async {
    final hasText = blocks.any((b) => b.isNotEmpty);
    ImageSize? size;
    if (hasText) {
      try {
        size = await _readSize(imagePath);
      } on Object {
        size = null; // Keep the text; only the boxes are lost.
      }
    }
    final lines = <OcrLine>[];
    final paragraphs = <String>[];
    for (final block in blocks) {
      final blockLines = <String>[];
      for (final pixel in block) {
        final text = cleanOcrLine(pixel.text);
        if (text.isEmpty) continue;
        blockLines.add(text);
        lines.add(
          OcrLine(
            text,
            size == null
                ? null
                : normalisePixelBox(
                    left: pixel.left,
                    top: pixel.top,
                    right: pixel.right,
                    bottom: pixel.bottom,
                    width: size.width,
                    height: size.height,
                  ),
          ),
        );
      }
      if (blockLines.isNotEmpty) paragraphs.add(blockLines.join('\n'));
    }
    return OcrResult(
      text: paragraphs.join('\n\n'),
      lines: lines,
      languageCode: languageCodeOf(OcrLanguage.english),
      engine: OcrEngineId.mlKit,
    );
  }

  Future<OcrResult> _runTesseract(String imagePath, String code) async {
    final raw = await _tesseract.extractText(imagePath, code);
    final text = cleanOcrText(raw);
    return OcrResult(
      text: text,
      lines: [
        for (final line in text.split('\n'))
          if (line.isNotEmpty) OcrLine(line),
      ],
      languageCode: code,
      engine: OcrEngineId.tesseract,
    );
  }
}

/// Maps any engine error to an [AppException] with a user-facing message.
///
/// A missing image is a [NotFoundException]; every other failure is an
/// [OcrException]. Existing [AppException]s pass through unchanged.
AppException mapOcrError(Object error) {
  if (error is AppException) return error;
  if (error is MissingPluginException || error is UnsupportedError) {
    return OcrException(
      'Text recognition is not available on this device.',
      error,
    );
  }
  if (error is PlatformException) {
    switch (error.code) {
      case 'BUSY':
      case 'OCR_TIMEOUT':
        return OcrException(
          'Text recognition is busy. Try again in a moment.',
          error,
        );
      case 'INIT_ERROR':
      case 'OCR_INIT_FAILED':
      case 'MISSING_TESSDATA':
        return OcrException(
          'Text recognition data could not be loaded. '
          'Restart Scanly and try again.',
          error,
        );
    }
  }
  if (error is ArgumentError) {
    return NotFoundException(
      'The page image is missing, so its text cannot be recognised.',
      error,
    );
  }
  return OcrException('Text recognition failed. Try again.', error);
}
