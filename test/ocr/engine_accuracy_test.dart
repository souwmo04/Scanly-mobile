import 'package:flutter_test/flutter_test.dart';
import 'package:scanly/data/services/ocr/ocr_accuracy.dart';

void main() {
  group('levenshtein', () {
    test('classic pairs', () {
      expect(levenshtein('kitten'.split(''), 'sitting'.split('')), 3);
      expect(levenshtein('flaw'.split(''), 'lawn'.split('')), 2);
      expect(levenshtein(<String>[], ['a', 'b']), 2);
      expect(levenshtein(['a'], <String>[]), 1);
      expect(levenshtein(['x', 'y'], ['x', 'y']), 0);
    });
  });

  group('characterErrorRate', () {
    test('identical text is 0', () {
      expect(characterErrorRate('Hello world', 'Hello world'), 0);
    });

    test('kitten → sitting is 3/6', () {
      expect(characterErrorRate('kitten', 'sitting'), closeTo(0.5, 1e-9));
    });

    test('whitespace differences are ignored', () {
      expect(characterErrorRate('a b\nc', '  a   b c \n'), 0);
    });

    test('counts Bengali code points (runes)', () {
      // খাই (খ া ই, 3 runes) vs খাঈ: one substitution.
      expect(characterErrorRate('খাই', 'খাঈ'), closeTo(1 / 3, 1e-9));
      // Missing dari: 1 deletion over 4 runes of "খাই।".
      expect(characterErrorRate('খাই।', 'খাই'), closeTo(0.25, 1e-9));
    });

    test('empty reference', () {
      expect(characterErrorRate('', ''), 0);
      expect(characterErrorRate('  ', 'x'), 1);
    });

    test('can exceed 1 with many insertions', () {
      expect(characterErrorRate('a', 'abc'), 2);
    });
  });

  group('wordErrorRate', () {
    test('one substituted word out of four', () {
      expect(
        wordErrorRate('the quick brown fox', 'the quick brawn fox'),
        closeTo(0.25, 1e-9),
      );
    });

    test('deletion and insertion', () {
      expect(wordErrorRate('a b c', 'a c'), closeTo(1 / 3, 1e-9));
      expect(wordErrorRate('a b', 'a x b'), closeTo(0.5, 1e-9));
    });

    test('Bengali words, whitespace-normalised', () {
      expect(wordErrorRate('আমি ভাত খাই।', 'আমি\nভাত   খাই।'), 0);
      expect(
        wordErrorRate('আমি ভাত খাই।', 'আমি ভাত খাই'),
        closeTo(1 / 3, 1e-9),
      );
    });

    test('empty reference', () {
      expect(wordErrorRate('', ' '), 0);
      expect(wordErrorRate('', 'word'), 1);
    });
  });
}
