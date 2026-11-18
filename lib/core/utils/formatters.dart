import 'package:intl/intl.dart';

/// Human-readable size, e.g. `1.4 MB`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// Short relative date: "Just now", "5 min ago", "Today, 14:20",
/// "Yesterday", or a calendar date.
String formatRelativeDate(DateTime date, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final diff = current.difference(date);
  if (diff.inSeconds < 60 && !diff.isNegative) return 'Just now';
  if (diff.inMinutes < 60 && !diff.isNegative) {
    return '${diff.inMinutes} min ago';
  }
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(date.year, date.month, date.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'Today, ${DateFormat.Hm().format(date)}';
  if (days == 1) return 'Yesterday';
  if (date.year == current.year) return DateFormat.MMMd().format(date);
  return DateFormat.yMMMd().format(date);
}

/// "1 page" / "3 pages".
String pluralPages(int count) => count == 1 ? '1 page' : '$count pages';

/// Greeting based on the time of day.
String greetingFor(DateTime time) {
  final hour = time.hour;
  if (hour < 5) return 'Good evening';
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// Default title for a new scan, e.g. "Scan 18 Nov 2026 14.05".
String defaultScanTitle(DateTime time) =>
    'Scan ${DateFormat('d MMM yyyy HH.mm').format(time)}';

/// Default title for imported images, e.g. "Import 18 Nov 2026 14.05".
String defaultImportTitle(DateTime time) =>
    'Import ${DateFormat('d MMM yyyy HH.mm').format(time)}';
