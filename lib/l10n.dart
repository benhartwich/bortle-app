// The app's language, as in the allskyhub app: German on a phone set to German, English
// everywhere else. Each text sits in the code as a pair, German first:
// `tr('Anmelden', 'Sign in')`.

import 'dart:ui';

/// Whether the app speaks English; read once from the phone's languages at start.
/// Tests set it themselves (test/flutter_test_config.dart).
bool appEnglish = !_prefersGerman(PlatformDispatcher.instance.locales);

bool _prefersGerman(List<Locale> locales) {
  for (final l in locales) {
    if (l.languageCode == 'de') return true;
    if (l.languageCode == 'en') return false;
  }
  return false;
}

/// The text in the app's language.
String tr(String de, String en) => appEnglish ? en : de;

/// The language for Flutter's own texts.
Locale get appLocale => Locale(appEnglish ? 'en' : 'de');

/// A decimal number with the language's separator ("1,5" or "1.5").
String decimal(num value, int digits) {
  final text = value.toStringAsFixed(digits);
  return appEnglish ? text : text.replaceAll('.', ',');
}

/// "28.10. 21:07" or "28 Oct 21:07", in local time.
String when(DateTime d) {
  final l = d.toLocal();
  final hm = '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  return appEnglish
      ? '${l.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][l.month - 1]} $hm'
      : '${l.day.toString().padLeft(2, '0')}.${l.month.toString().padLeft(2, '0')}. $hm';
}

/// "12 min", "1 h 40".
String duration(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  final m = d.inMinutes % 60;
  return '${d.inHours} h ${m.toString().padLeft(2, '0')}';
}
