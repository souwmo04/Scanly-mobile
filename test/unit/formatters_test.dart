import 'package:flutter_test/flutter_test.dart';
import 'package:scanly/core/utils/formatters.dart';

void main() {
  test('formatBytes', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1023), '1023 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
    expect(formatBytes(300 * 1024 * 1024), '300 MB');
  });

  test('formatRelativeDate', () {
    final now = DateTime(2026, 11, 18, 15, 30);
    expect(formatRelativeDate(now, now: now), 'Just now');
    expect(
      formatRelativeDate(now.subtract(const Duration(minutes: 5)), now: now),
      '5 min ago',
    );
    expect(
      formatRelativeDate(DateTime(2026, 11, 18, 9, 5), now: now),
      'Today, 09:05',
    );
    expect(
      formatRelativeDate(DateTime(2026, 11, 17, 23), now: now),
      'Yesterday',
    );
    expect(formatRelativeDate(DateTime(2026, 3, 2), now: now), 'Mar 2');
    expect(formatRelativeDate(DateTime(2024, 3, 2), now: now), 'Mar 2, 2024');
  });

  test('pluralPages and greeting', () {
    expect(pluralPages(1), '1 page');
    expect(pluralPages(4), '4 pages');
    expect(greetingFor(DateTime(2026, 1, 1, 8)), 'Good morning');
    expect(greetingFor(DateTime(2026, 1, 1, 13)), 'Good afternoon');
    expect(greetingFor(DateTime(2026, 1, 1, 20)), 'Good evening');
  });

  test('defaultScanTitle', () {
    expect(
      defaultScanTitle(DateTime(2026, 11, 18, 14, 5)),
      'Scan 18 Nov 2026 14.05',
    );
  });
}
