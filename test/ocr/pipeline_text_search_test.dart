import 'package:flutter_test/flutter_test.dart';
import 'package:scanly/domain/entities/ocr_result.dart';
import 'package:scanly/domain/entities/scan_page.dart';
import 'package:scanly/features/ocr/ocr_text_search.dart';

void main() {
  ScanPage page(String id, int order) => ScanPage(
    id: id,
    documentId: 'doc',
    pageOrder: order,
    originalPath: '/$id.jpg',
    width: 10,
    height: 10,
    rotation: 0,
    filter: PageFilter.original,
    createdAt: DateTime(2026),
  );

  PageOcr ocr(String id, String text) => PageOcr(
    pageId: id,
    status: OcrStatus.done,
    text: text,
    lines: const [],
    updatedAt: DateTime(2026),
  );

  final pages = [page('a', 0), page('b', 1), page('c', 2)];

  test('finds pages case-insensitively, in page order, with snippet', () {
    final matches = searchPageTexts(pages, {
      'a': ocr('a', 'Nothing here'),
      'b': ocr('b', 'Total INVOICE amount\nsecond invoice'),
      'c': ocr('c', 'invoice'),
    }, 'invoice');
    expect(matches.map((m) => m.pageNumber), [2, 3]);
    final first = matches.first;
    expect(first.count, 2);
    expect(
      first.snippet.substring(first.matchStart, first.matchEnd),
      'INVOICE',
    );
    expect(first.snippet, isNot(contains('\n')));
  });

  test('composed and decomposed Bengali vowel signs match', () {
    // কোন with U+09CB vs কোন with U+09C7 U+09BE.
    const composed = 'আমি কোন বই';
    const decomposed = 'কোন';
    final matches = searchPageTexts(pages, {
      'a': ocr('a', composed),
    }, decomposed);
    expect(matches.single.pageNumber, 1);
    expect(
      searchPageTexts(pages, {'a': ocr('a', 'বাংলা‌ভাষা')}, 'বাংলাভাষা'),
      hasLength(1),
    );
  });

  test('blank query and missing text find nothing', () {
    expect(searchPageTexts(pages, {'a': ocr('a', 'x')}, '   '), isEmpty);
    expect(searchPageTexts(pages, const {}, 'x'), isEmpty);
  });

  test('whitespace runs match a single space', () {
    final matches = searchPageTexts(pages, {
      'a': ocr('a', 'monthly\n  rent'),
    }, 'Monthly rent');
    expect(matches, hasLength(1));
  });
}
