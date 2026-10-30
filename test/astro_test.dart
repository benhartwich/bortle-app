// The phone's own sky math against Skyfield with the JPL ephemeris DE421 (the server's
// planner), at three places and seasons. Times within two minutes, altitudes within a
// fraction of a degree – the tools decide whether a night is worth it, they do not point.

import 'package:bortle_app/astro.dart';
import 'package:flutter_test/flutter_test.dart';

void near(DateTime? actual, String expected, {int minutes = 2}) {
  expect(actual, isNotNull);
  final diff = actual!.difference(DateTime.parse(expected)).inSeconds.abs();
  expect(diff, lessThanOrEqualTo(minutes * 60), reason: '$actual vs $expected');
}

void main() {
  test('Hofkirchen, 2 November 2026', () {
    final night = Night.at(DateTime(2026, 11, 2), 48.2, 14.2);
    near(night.sun.$1, '2026-11-02T15:42:57Z');
    near(night.sun.$2, '2026-11-03T05:51:28Z');
    near(night.civil.$1, '2026-11-02T16:15:40Z');
    near(night.nautical.$1, '2026-11-02T16:52:30Z');
    near(night.astronomical.$1, '2026-11-02T17:28:41Z');
    near(night.astronomical.$2, '2026-11-03T04:05:26Z');
    near(night.moonRiseSet.$1, '2026-11-02T23:02:44Z', minutes: 4);

    final t = DateTime.utc(2026, 11, 2, 22);
    expect(moonIllumination(t), closeTo(0.3838, 0.01));
    expect(altitude(sunPosition(t), 48.2, 14.2, t), closeTo(-55.399, 0.1));
    expect(altitude(moonPosition(t), 48.2, 14.2, t, topocentricMoon: true), closeTo(-9.443, 0.4));
    expect(altitude(precess(10.6847, 41.2690, t), 48.2, 14.2, t), closeTo(77.22, 0.1));
  });

  test('Cape Town, 15 June 2026: southern winter, new moon', () {
    final night = Night.at(DateTime(2026, 6, 15), -33.9, 18.4);
    near(night.sun.$1, '2026-06-15T15:44:06Z');
    near(night.astronomical.$1, '2026-06-15T17:13:30Z');
    near(night.astronomical.$2, '2026-06-16T04:20:32Z');
    near(night.moonRiseSet.$2, '2026-06-15T15:55:37Z', minutes: 4);
    expect(moonIllumination(DateTime.utc(2026, 6, 15, 22)), closeTo(0.0112, 0.01));
    final t = DateTime.utc(2026, 6, 15, 22);
    expect(altitude(precess(10.6847, 41.2690, t), -33.9, 18.4, t), closeTo(-41.717, 0.1));
  });

  test('Berlin at midsummer never gets astronomically dark', () {
    final night = Night.at(DateTime(2026, 6, 21), 52.5, 13.4);
    near(night.sun.$1, '2026-06-21T19:33:11Z');
    near(night.nautical.$1, '2026-06-21T21:46:36Z');
    expect(night.astronomical.$1, isNull);
    expect(night.darkness, Duration.zero);
    expect(night.bestWindow, isNull);
    final t = DateTime.utc(2026, 6, 21, 22);
    expect(altitude(sunPosition(t), 52.5, 13.4, t), closeTo(-12.615, 0.1));
    expect(moonIllumination(t), closeTo(0.5016, 0.01));
  });

  test('an object over the night: how long it is usable, and the moon', () {
    final night = Night.at(DateTime(2026, 11, 2), 48.2, 14.2);
    final m31 = ObjectNight(night, 10.6847, 41.2690);
    final best = m31.bestInDarkness!;
    expect(best.$1, greaterThan(80)); // M31 passes almost overhead at 48°
    // dark from 17:29 to 04:05 UTC, and M31 above 30° for all but the last hours
    expect(m31.usable.inHours, inInclusiveRange(8, 11));
    // the moon rises at 23:03, so the moonless part is shorter
    expect(m31.usableMoonless, lessThan(m31.usable));
    expect(night.bestWindow!.$1.difference(DateTime.parse('2026-11-02T17:28:41Z')).inMinutes.abs(), lessThan(6));
  });
}
