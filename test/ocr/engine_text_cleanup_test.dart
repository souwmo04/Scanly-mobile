import 'package:flutter_test/flutter_test.dart';
import 'package:scanly/data/services/ocr/ocr_text_cleanup.dart';

const zwj = '\u200D';
const zwnj = '\u200C';

void main() {
  group('cleanOcrText', () {
    test('normalises CRLF, CR and Unicode line separators', () {
      expect(
        cleanOcrText('one\r\ntwo\rthree\u2028four'),
        'one\ntwo\nthree\nfour',
      );
    });

    test('trims lines and collapses runs of spaces and tabs', () {
      expect(cleanOcrText('   Hello    \t world   '), 'Hello world');
      expect(cleanOcrText('a\u00A0\u00A0b\u2009c'), 'a b c');
    });

    test('removes stray zero-width characters and controls', () {
      expect(
        cleanOcrText('\uFEFFIn\u200Bvoice\u2060 no\u00AD.\u0007 1'),
        'Invoice no. 1',
      );
    });

    test('keeps ZWJ and ZWNJ inside Bengali words', () {
      // Ra + ZWJ + hasanta + ya (ra-phala form), and ka + hasanta + ZWNJ + ssa.
      const rab = 'র$zwj্যাব';
      const ksa = 'ক্$zwnjষ';
      final cleaned = cleanOcrText('  $rab   $ksa  ');
      expect(cleaned, '$rab $ksa');
      expect(cleaned.contains(zwj), isTrue);
      expect(cleaned.contains(zwnj), isTrue);
    });

    test('keeps Bengali digits and the dari', () {
      expect(cleanOcrText('আমি ভাত খাই।'), 'আমি ভাত খাই।');
      expect(cleanOcrText('মূল্য: ১২৩৪ টাকা।'), 'মূল্য: ১২৩৪ টাকা।');
      expect(cleanOcrText('১২৩'), '১২৩');
    });

    test('drops lines made only of noise symbols', () {
      expect(cleanOcrText('Title\n— _ ~ |\n...\nBody'), 'Title\nBody');
      expect(cleanOcrText('*** \n---'), '');
    });

    test('keeps one paragraph break and drops edge blank lines', () {
      expect(cleanOcrText('\n\nfirst\n\n\n\nsecond\n\n'), 'first\n\nsecond');
    });

    test('a noise line inside a paragraph does not split it', () {
      expect(cleanOcrText('first\n|\nsecond'), 'first\nsecond');
    });
  });

  group('cleanOcrLine / cleanOcrLines', () {
    test('noise and blank lines become empty', () {
      expect(cleanOcrLine('  '), '');
      expect(cleanOcrLine('•'), '');
      expect(cleanOcrLine(' a  b '), 'a b');
    });

    test('cleanOcrLines returns only non-empty lines', () {
      expect(cleanOcrLines('a\n\n  \n—\nb  c'), ['a', 'b c']);
    });
  });
}
