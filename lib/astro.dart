// Sun, moon and sky positions on the phone, without a server: enough for twilight, the
// moon and an object's altitude over the night to the minute and a fraction of a degree
// (low-precision series after Meeus, "Astronomical Algorithms", ch. 25 and 47, truncated
// to the larger terms). Checked against Skyfield in test/astro_test.dart. Not for
// pointing a telescope – for deciding whether tonight is worth it.

import 'dart:math' as math;

const _deg = math.pi / 180;

double _rev(double x) => x - 360 * (x / 360).floorToDouble();

/// Julian date of an instant.
double julian(DateTime t) => t.toUtc().millisecondsSinceEpoch / 86400000.0 + 2440587.5;

/// Greenwich mean sidereal time in degrees.
double gmst(DateTime t) {
  final d = julian(t) - 2451545.0;
  final c = d / 36525;
  return _rev(280.46061837 + 360.98564736629 * d + 0.000387933 * c * c);
}

double _obliquity(double c) => 23.439291 - 0.0130042 * c;

class Equatorial {
  const Equatorial(this.ra, this.dec, [this.distanceKm]);

  /// Right ascension and declination in degrees (of date for the sun and moon).
  final double ra;
  final double dec;
  final double? distanceKm;
}

Equatorial _fromEcliptic(double lon, double lat, double c, [double? km]) {
  final e = _obliquity(c) * _deg;
  final l = lon * _deg;
  final b = lat * _deg;
  final ra = math.atan2(math.sin(l) * math.cos(e) - math.tan(b) * math.sin(e), math.cos(l));
  final dec = math.asin(math.sin(b) * math.cos(e) + math.cos(b) * math.sin(e) * math.sin(l));
  return Equatorial(_rev(ra / _deg), dec / _deg, km);
}

/// The sun's apparent position (Meeus 25, low precision: about 0.01°).
Equatorial sunPosition(DateTime t) {
  final c = (julian(t) - 2451545.0) / 36525;
  final l0 = _rev(280.46646 + 36000.76983 * c);
  final m = _rev(357.52911 + 35999.05029 * c) * _deg;
  final center =
      (1.914602 - 0.004817 * c) * math.sin(m) +
      (0.019993 - 0.000101 * c) * math.sin(2 * m) +
      0.000289 * math.sin(3 * m);
  final omega = (125.04 - 1934.136 * c) * _deg;
  final lambda = l0 + center - 0.00569 - 0.00478 * math.sin(omega);
  return _fromEcliptic(lambda, 0, c);
}

/// The moon's geocentric position (Meeus 47, the larger terms: about 0.1° and 1 % in
/// distance).
Equatorial moonPosition(DateTime t) {
  final c = (julian(t) - 2451545.0) / 36525;
  final lp = _rev(218.3164477 + 481267.88123421 * c);
  final d = _rev(297.8501921 + 445267.1114034 * c) * _deg;
  final m = _rev(357.5291092 + 35999.0502909 * c) * _deg;
  final mp = _rev(134.9633964 + 477198.8675055 * c) * _deg;
  final f = _rev(93.2720950 + 483202.0175233 * c) * _deg;
  final lon =
      lp +
      6.288774 * math.sin(mp) +
      1.274027 * math.sin(2 * d - mp) +
      0.658314 * math.sin(2 * d) +
      0.213618 * math.sin(2 * mp) -
      0.185116 * math.sin(m) -
      0.114332 * math.sin(2 * f) +
      0.058793 * math.sin(2 * d - 2 * mp) +
      0.057066 * math.sin(2 * d - m - mp) +
      0.053322 * math.sin(2 * d + mp) +
      0.045758 * math.sin(2 * d - m) -
      0.040923 * math.sin(m - mp) -
      0.034720 * math.sin(d) -
      0.030383 * math.sin(m + mp) +
      0.015327 * math.sin(2 * d - 2 * f) -
      0.012528 * math.sin(mp + 2 * f) +
      0.010980 * math.sin(mp - 2 * f) +
      0.010675 * math.sin(4 * d - mp) +
      0.010034 * math.sin(3 * mp) +
      0.008548 * math.sin(4 * d - 2 * mp);
  final lat =
      5.128122 * math.sin(f) +
      0.280602 * math.sin(mp + f) +
      0.277693 * math.sin(mp - f) +
      0.173237 * math.sin(2 * d - f) +
      0.055413 * math.sin(2 * d - mp + f) +
      0.046271 * math.sin(2 * d - mp - f) +
      0.032573 * math.sin(2 * d + f) +
      0.017198 * math.sin(2 * mp + f) +
      0.009266 * math.sin(2 * d + mp - f) +
      0.008822 * math.sin(2 * mp - f);
  final km =
      385000.56 -
      20905.355 * math.cos(mp) -
      3699.111 * math.cos(2 * d - mp) -
      2955.968 * math.cos(2 * d) -
      569.925 * math.cos(2 * mp) +
      48.888 * math.cos(m) -
      3.149 * math.cos(2 * f) +
      246.158 * math.cos(2 * d - 2 * mp) -
      152.138 * math.cos(2 * d - m - mp) -
      170.733 * math.cos(2 * d + mp) -
      204.586 * math.cos(2 * d - m) -
      129.620 * math.cos(m - mp) +
      108.743 * math.cos(d) +
      104.755 * math.cos(m + mp);
  return _fromEcliptic(_rev(lon), lat, c, km);
}

/// Precess J2000 coordinates (catalog) to the equinox of [t] – the sun and moon above
/// are of date; for an object it moves the position by up to 0.35° today.
Equatorial precess(double raJ2000, double decJ2000, DateTime t) {
  final c = (julian(t) - 2451545.0) / 36525;
  final zeta = (2306.2181 * c + 0.30188 * c * c) / 3600 * _deg;
  final z = (2306.2181 * c + 1.09468 * c * c) / 3600 * _deg;
  final theta = (2004.3109 * c - 0.42665 * c * c) / 3600 * _deg;
  final a = raJ2000 * _deg;
  final d = decJ2000 * _deg;
  final aa = math.cos(d) * math.sin(a + zeta);
  final bb = math.cos(theta) * math.cos(d) * math.cos(a + zeta) - math.sin(theta) * math.sin(d);
  final cc = math.sin(theta) * math.cos(d) * math.cos(a + zeta) + math.cos(theta) * math.sin(d);
  return Equatorial(_rev((math.atan2(aa, bb) + z) / _deg), math.asin(cc) / _deg);
}

/// Altitude in degrees of a position at a site (geometric, no refraction).
double altitude(Equatorial p, double latDeg, double lonDeg, DateTime t, {bool topocentricMoon = false}) {
  final h = (gmst(t) + lonDeg - p.ra) * _deg;
  final phi = latDeg * _deg;
  final dec = p.dec * _deg;
  var alt = math.asin(math.sin(phi) * math.sin(dec) + math.cos(phi) * math.cos(dec) * math.cos(h)) / _deg;
  final km = p.distanceKm;
  if (topocentricMoon && km != null) {
    // the moon's parallax: up to a degree lower than from the earth's centre
    alt -= math.asin(6378.14 / km) / _deg * math.cos(alt * _deg);
  }
  return alt;
}

/// Angle between two positions in degrees.
double separation(Equatorial a, Equatorial b) {
  final d1 = a.dec * _deg;
  final d2 = b.dec * _deg;
  final cosSep = math.sin(d1) * math.sin(d2) + math.cos(d1) * math.cos(d2) * math.cos((a.ra - b.ra) * _deg);
  return math.acos(cosSep.clamp(-1.0, 1.0)) / _deg;
}

/// The lit fraction of the moon, 0..1.
double moonIllumination(DateTime t) {
  final s = sunPosition(t);
  final m = moonPosition(t);
  final elongation = separation(s, m) * _deg;
  final phaseAngle = math.atan2(149597870.7 * math.sin(elongation), m.distanceKm! - 149597870.7 * math.cos(elongation));
  return (1 + math.cos(phaseAngle)) / 2;
}

/// Whether the moon is waxing (the sun–moon longitude difference under 180°).
bool moonWaxing(DateTime t) => _rev(moonPosition(t).ra - sunPosition(t).ra) < 180;

/// The night from one local noon to the next: when the sun and moon cross the heights
/// that matter, and the hours of real darkness.
class Night {
  Night._(this.from, this.to, this.lat, this.lon, this.samples);

  /// Steps of five minutes from [from] (the local noon before the night) for 24 hours.
  factory Night.at(DateTime day, double lat, double lon) {
    // local noon by the sun, not by the phone's clock: lon/15 hours from 12:00 UTC
    final noonUtc = DateTime.utc(day.year, day.month, day.day, 12).subtract(Duration(minutes: (lon * 4).round()));
    final samples = <NightSample>[];
    for (var i = 0; i <= 24 * 12; i++) {
      final t = noonUtc.add(Duration(minutes: 5 * i));
      samples.add(
        NightSample(
          t,
          altitude(sunPosition(t), lat, lon, t),
          altitude(moonPosition(t), lat, lon, t, topocentricMoon: true),
        ),
      );
    }
    return Night._(noonUtc, noonUtc.add(const Duration(hours: 24)), lat, lon, samples);
  }

  final DateTime from;
  final DateTime to;
  final double lat;
  final double lon;
  final List<NightSample> samples;

  /// When the sun goes below [height] in the evening and comes back in the morning; null
  /// for a night it never gets that low (or never comes back, near the poles).
  (DateTime?, DateTime?) sunBelow(double height) => _crossings((s) => s.sun - height);

  /// Sunset/sunrise (upper limb with refraction: −0.833°).
  (DateTime?, DateTime?) get sun => sunBelow(-0.833);
  (DateTime?, DateTime?) get civil => sunBelow(-6);
  (DateTime?, DateTime?) get nautical => sunBelow(-12);
  (DateTime?, DateTime?) get astronomical => sunBelow(-18);

  /// Moonrise and moonset within these 24 hours (either may be missing). The moon's
  /// altitude here is topocentric, so the horizon is the sun's −0.833° (refraction and
  /// the upper limb), not Meeus' geocentric +0.125°.
  (DateTime?, DateTime?) get moonRiseSet {
    DateTime? rise;
    DateTime? set;
    for (var i = 1; i < samples.length; i++) {
      final a = samples[i - 1].moon + 0.833;
      final b = samples[i].moon + 0.833;
      if (a < 0 && b >= 0) rise ??= _interpolate(samples[i - 1].time, samples[i].time, a, b);
      if (a >= 0 && b < 0) set ??= _interpolate(samples[i - 1].time, samples[i].time, a, b);
    }
    return (rise, set);
  }

  /// Minutes that are astronomically dark, and of those the ones without the moon up.
  Duration get darkness => Duration(minutes: 5 * samples.where((s) => s.sun < -18).length);
  Duration get moonlessDarkness => Duration(minutes: 5 * samples.where((s) => s.sun < -18 && s.moon < 0).length);

  /// The longest stretch of dark sky without the moon, if any.
  (DateTime, DateTime)? get bestWindow {
    (DateTime, DateTime)? best;
    DateTime? start;
    for (final s in samples) {
      final good = s.sun < -18 && s.moon < 0;
      if (good) {
        start ??= s.time;
        final current = (start, s.time);
        if (best == null || current.$2.difference(current.$1) > best.$2.difference(best.$1)) best = current;
      } else {
        start = null;
      }
    }
    return best;
  }

  (DateTime?, DateTime?) _crossings(double Function(NightSample) value) {
    DateTime? down;
    DateTime? up;
    for (var i = 1; i < samples.length; i++) {
      final a = value(samples[i - 1]);
      final b = value(samples[i]);
      if (a >= 0 && b < 0) down ??= _interpolate(samples[i - 1].time, samples[i].time, a, b);
      if (a < 0 && b >= 0 && down != null) up ??= _interpolate(samples[i - 1].time, samples[i].time, a, b);
    }
    return (down, up);
  }

  static DateTime _interpolate(DateTime t0, DateTime t1, double a, double b) {
    final f = a / (a - b);
    return t0.add(Duration(milliseconds: (t1.difference(t0).inMilliseconds * f).round()));
  }
}

class NightSample {
  const NightSample(this.time, this.sun, this.moon);

  final DateTime time;
  final double sun;
  final double moon;
}

/// An object over one night: its altitude every five minutes, and what that means.
class ObjectNight {
  // Precessed once for the middle of the night: over a night an object moves a few
  // thousandths of a degree, and a catalogue of five hundred stays quick to rank.
  ObjectNight(this.night, double raJ2000, double decJ2000, {this.minAltitude = 30})
    : altitudes = _altitudes(night, precess(raJ2000, decJ2000, night.samples[night.samples.length ~/ 2].time)),
      _position = (raJ2000, decJ2000);

  static List<double> _altitudes(Night night, Equatorial p) => [
    for (final s in night.samples) altitude(p, night.lat, night.lon, s.time),
  ];

  final Night night;
  final List<double> altitudes;

  /// The height above which the object counts as usable (degrees).
  final double minAltitude;
  final (double, double) _position;

  /// Highest altitude while it is astronomically dark, and when.
  (double, DateTime)? get bestInDarkness {
    (double, DateTime)? best;
    for (var i = 0; i < altitudes.length; i++) {
      if (night.samples[i].sun >= -18) continue;
      if (best == null || altitudes[i] > best.$1) best = (altitudes[i], night.samples[i].time);
    }
    return best;
  }

  /// Dark hours above [minAltitude]; and of those, without the moon up.
  Duration get usable => _count((i) => night.samples[i].sun < -18 && altitudes[i] >= minAltitude);
  Duration get usableMoonless =>
      _count((i) => night.samples[i].sun < -18 && altitudes[i] >= minAltitude && night.samples[i].moon < 0);

  /// The moon's distance from the object at the middle of the night, in degrees.
  double get moonDistance {
    final mid = night.samples[night.samples.length ~/ 2].time;
    return separation(precess(_position.$1, _position.$2, mid), moonPosition(mid));
  }

  Duration _count(bool Function(int) good) =>
      Duration(minutes: 5 * [for (var i = 0; i < altitudes.length; i++) i].where(good).length);
}
