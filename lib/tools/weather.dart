// The night's weather for the tools without an account, from bortle.eu's public
// /api/public/weather: cloud layers, humidity, dew point and wind (Open-Meteo), seeing
// and transparency (7Timer!). Only the place, rounded to 0.1°, is sent.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../l10n.dart';

class WeatherHour {
  const WeatherHour({
    required this.time,
    this.cloud,
    this.low,
    this.mid,
    this.high,
    this.humidity,
    this.dewPoint,
    this.temperature,
    this.wind,
    this.gust,
    this.seeing,
    this.transparency,
  });

  factory WeatherHour.fromJson(Map j) {
    double? n(String k) => (j[k] as num?)?.toDouble();
    return WeatherHour(
      time: DateTime.parse('${j['t']}'),
      cloud: n('cloud'),
      low: n('low'),
      mid: n('mid'),
      high: n('high'),
      humidity: n('humidity'),
      dewPoint: n('dew_point'),
      temperature: n('temperature'),
      wind: n('wind'),
      gust: n('gust'),
      seeing: (j['seeing'] as num?)?.toInt(),
      transparency: (j['transparency'] as num?)?.toInt(),
    );
  }

  final DateTime time;

  /// Cloud cover in percent: all, low, mid and high.
  final double? cloud;
  final double? low;
  final double? mid;
  final double? high;
  final double? humidity;
  final double? dewPoint;
  final double? temperature;

  /// km/h
  final double? wind;
  final double? gust;

  /// 7Timer! classes, 1 best … 8 worst.
  final int? seeing;
  final int? transparency;

  /// How close the air is to dew on the optics: degrees between temperature and dew point.
  double? get dewSpread => temperature != null && dewPoint != null ? temperature! - dewPoint! : null;
}

class Forecast {
  const Forecast(this.hours, this.sources);

  final List<WeatherHour> hours;
  final List<String> sources;
}

/// The seeing class in arcseconds, as 7Timer! defines it.
String seeingText(int c) => switch (c) {
  1 => '< 0,5″',
  2 => '0,5–0,75″',
  3 => '0,75–1″',
  4 => '1–1,25″',
  5 => '1,25–1,5″',
  6 => '1,5–2″',
  7 => '2–2,5″',
  _ => '> 2,5″',
}.replaceAll(',', appEnglish ? '.' : ',');

String transparencyText(int c) => switch (c) {
  <= 2 => tr('sehr klar', 'very clear'),
  <= 4 => tr('klar', 'clear'),
  <= 6 => tr('dunstig', 'hazy'),
  _ => tr('trüb', 'poor'),
};

typedef FetchForecast = Future<Forecast> Function(double lat, double lon);

/// The forecast from [base] (bortle.eu unless the person uses their own install).
FetchForecast forecastFrom(String base, [http.Client? client]) => (lat, lon) async {
  final rounded = (lat * 10).round() / 10;
  final roundedLon = (lon * 10).round() / 10;
  final uri = Uri.parse('$base/api/public/weather').replace(queryParameters: {'lat': '$rounded', 'lon': '$roundedLon'});
  final r = await (client ?? http.Client()).get(uri).timeout(const Duration(seconds: 25));
  if (r.statusCode != 200) {
    throw Exception(
      tr('Die Vorhersage antwortet nicht (${r.statusCode}).', 'The forecast does not answer (${r.statusCode}).'),
    );
  }
  final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
  return Forecast(
    [for (final h in (j['hours'] as List? ?? const [])) WeatherHour.fromJson(h as Map)],
    [for (final s in (j['sources'] as List? ?? const [])) '$s'],
  );
};
