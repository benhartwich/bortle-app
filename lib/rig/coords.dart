// Coordinates for the slew form, as the cockpit's mount-coords.ts reads and writes them.
//
// Two rules that cost real nights if they are blurred:
//   1. The mount reports JNow, targets are J2000. Nothing here converts between the two;
//      every caller labels the frame.
//   2. A single number is degrees, a sexagesimal pair or triple of a right ascension is
//      hours. The form always shows the parsed degrees back, so the user sees which of
//      the two was understood before anything moves.

/// One sexagesimal or decimal value. [hours] scales an h/m/s triple by 15.
double? parseAngle(String text, {required bool hours}) {
  final raw = text.trim();
  if (raw.isEmpty) return null;
  final negative = raw.startsWith('-') || raw.startsWith('−');
  final parts = raw
      .replaceFirst(RegExp(r'^[+\-−]'), '')
      .replaceAll(RegExp('[hdms°\'"’′″:]', caseSensitive: false), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty || parts.length > 3) return null;
  final numbers = [for (final p in parts) double.tryParse(p.replaceAll(',', '.'))];
  if (numbers.any((n) => n == null || !n.isFinite || n < 0)) return null;
  final a = numbers[0]!, b = numbers.length > 1 ? numbers[1]! : 0.0, c = numbers.length > 2 ? numbers[2]! : 0.0;
  // a lone number is degrees in both frames
  final value = parts.length == 1 ? a : (a + b / 60 + c / 3600) * (hours ? 15 : 1);
  return negative ? -value : value;
}

/// A right ascension in degrees, read from [text] and inside 0..360; null otherwise.
double? parseRa(String text) {
  final v = parseAngle(text, hours: true);
  return v != null && v >= 0 && v < 360 ? v : null;
}

/// A declination in degrees, read from [text] and inside −90..90; null otherwise.
double? parseDec(String text) {
  final v = parseAngle(text, hours: false);
  return v != null && v >= -90 && v <= 90 ? v : null;
}

/// Right ascension in degrees → "20h 59m 17.1s".
String formatRa(double deg) {
  var hours = (deg / 15) % 24;
  if (hours < 0) hours += 24;
  final h = hours.floor();
  final minutes = (hours - h) * 60;
  final m = minutes.floor();
  final s = (minutes - m) * 60;
  return '${h}h ${m.toString().padLeft(2, '0')}m ${s.toStringAsFixed(1).padLeft(4, '0')}s';
}

/// Declination in degrees → "+44° 31′ 44″".
String formatDec(double deg) {
  final sign = deg < 0 ? '−' : '+';
  final abs = deg.abs();
  final d = abs.floor();
  final minutes = (abs - d) * 60;
  final m = minutes.floor();
  final s = ((minutes - m) * 60).round();
  return '$sign$d° ${m.toString().padLeft(2, '0')}′ ${s.toString().padLeft(2, '0')}″';
}
