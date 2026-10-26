/// Formatting helpers for the Russian UI.
library;

String formatSpeed(int bytesPerSec) => '${formatBytes(bytesPerSec)}/с';

String formatBytes(int bytes) {
  const units = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final s = i == 0 || v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '${s.replaceAll('.', ',')} ${units[i]}';
}

String formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

/// "только что", "5 мин назад", "3 ч назад", "12.10.2026".
String formatAgo(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final d = n.difference(t);
  if (d.inMinutes < 1) return 'только что';
  if (d.inHours < 1) return '${d.inMinutes} мин назад';
  if (d.inDays < 1) return '${d.inHours} ч назад';
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)}.${t.year}';
}

/// Flag emoji for an ISO alpha-2 code ("DE" -> 🇩🇪).
String flagEmoji(String code) =>
    String.fromCharCodes(code.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 65));
