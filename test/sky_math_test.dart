// The sky map's geometry: the projection, the frame against Skyfield (DE421, apparent
// positions, the server's planner) and the phone's aim from gravity and the field.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:bortle_app/astro.dart';
import 'package:bortle_app/sky/phone_aim.dart';
import 'package:bortle_app/sky/sky_catalog.dart';
import 'package:bortle_app/sky/sky_math.dart';
import 'package:flutter_test/flutter_test.dart';

/// The difference of two azimuths, across north.
double azDiff(double a, double b) => ((a - b + 540) % 360 - 180).abs();

void main() {
  final catalog = SkyCatalog.parse(File('assets/sky.json').readAsStringSync());

  group('projection', () {
    const size = Size(400, 800);

    test('the zenith sits in the centre of a view up', () {
      final view = SkyView(az: 123, alt: 90, fov: 180, size: size);
      expect(view.projectAzAlt(0, 90), offsetMoreOrLessEquals(const Offset(200, 400), epsilon: 1e-9));
    });

    test('a 180° field puts the horizon on the shorter side\'s edge', () {
      final view = SkyView(az: 0, alt: 90, fov: 180, size: size);
      for (final az in [0.0, 90.0, 200.0, 301.0]) {
        final p = view.projectAzAlt(az, 0)!;
        expect((p - view.centre).distance, closeTo(200, 1e-6));
      }
    });

    test('looking south, east is on the left and the zenith above', () {
      final view = SkyView(az: 180, alt: 30, fov: 90, size: size);
      expect(view.projectAzAlt(135, 30)!.dx, lessThan(200));
      expect(view.projectAzAlt(225, 30)!.dx, greaterThan(200));
      expect(view.projectAzAlt(180, 60)!.dy, lessThan(400));
      expect(view.projectAzAlt(180, 30), offsetMoreOrLessEquals(const Offset(200, 400), epsilon: 1e-9));
    });

    test('unproject is the inverse', () {
      final view = SkyView(az: 77, alt: 41, fov: 120, size: size);
      for (final (a, h) in [(77.0, 41.0), (10.0, 5.0), (150.0, 80.0), (300.0, 60.0)]) {
        final (a2, h2) = view.unproject(view.projectAzAlt(a, h)!);
        expect(azDiff(a2, a), lessThan(1e-6));
        expect(h2, closeTo(h, 1e-6));
      }
    });

    test('behind the observer there is no point', () {
      final view = SkyView(az: 0, alt: 0, fov: 90, size: size);
      expect(view.projectAzAlt(180, 0), isNull);
    });

    test('the compass names eight points', () {
      expect(compassPoint(304.8, english: false), 'NW');
      expect(compassPoint(90, english: false), 'O');
      expect(compassPoint(90, english: true), 'E');
      expect(compassPoint(359, english: true), 'N');
      expect(compassPoint(157, english: false), 'SO');
    });
  });

  group('the sky at a site, against Skyfield', () {
    (double, double) star(String name) {
      final i = catalog.find(name)!;
      return (catalog.ra[i].toDouble(), catalog.dec[i].toDouble());
    }

    void check(String name, double lat, double lon, DateTime t, double alt, double az) {
      final (ra, dec) = star(name);
      final (a, h) = SkyFrame.at(lat, lon, t).horizontal(ra, dec);
      expect(h, closeTo(alt, 0.5), reason: '$name altitude');
      expect(azDiff(a, az), lessThan(0.5 / math.cos(alt * math.pi / 180)), reason: '$name azimuth');
    }

    test('Vega and Polaris over Hofkirchen, 2 November 2026, 19:00 UTC', () {
      final t = DateTime.utc(2026, 11, 2, 19);
      check('Vega', 48.2, 14.2, t, 45.446, 281.787);
      check('Polaris', 48.2, 14.2, t, 48.451, 0.858);
    });

    test('Betelgeuse over Cape Town, 10 January 2026, 21:00 UTC', () {
      check('Betelgeuse', -33.9, 18.4, DateTime.utc(2026, 1, 10, 21), 48.378, 8.011);
    });

    test('a position of date placed as JNow agrees with its J2000 original', () {
      final t = DateTime.utc(2026, 11, 2, 19);
      final frame = SkyFrame.at(48.2, 14.2, t);
      final now = precess(314.75, 44.33, t);
      final (a1, h1) = frame.horizontal(314.75, 44.33);
      final (a2, h2) = frame.horizontal(now.ra, now.dec, jNow: true);
      expect(h2, closeTo(h1, 1e-6));
      expect(azDiff(a2, a1), lessThan(1e-6));
      // and agrees with lib/astro.dart's altitude()
      expect(h1, closeTo(altitude(now, 48.2, 14.2, t), 1e-6));
    });
  });

  group('the catalogue', () {
    test('is small, sorted brightest first and has the figures', () {
      expect(File('assets/sky.json').lengthSync(), lessThan(500 * 1024));
      expect(catalog.length, greaterThan(1500));
      for (var i = 1; i < catalog.length; i++) {
        expect(catalog.mag[i], greaterThanOrEqualTo(catalog.mag[i - 1]));
      }
      expect(catalog.names[0], 'Sirius');
      expect(catalog.lines.length, greaterThan(88));
      expect(catalog.constellations.map((c) => c.name), contains('Cygnus'));
    });
  });

  group('the phone\'s aim', () {
    // the field in central Europe: 20 µT north, 44 µT down
    test('upright, the back towards the north', () {
      final aim = aimFrom((0, 9.81, 0), (0, -44, -20))!;
      expect(azDiff(aim.az, 0), lessThan(1e-6));
      expect(aim.alt, closeTo(0, 1e-6));
    });

    test('upright, the back towards the east', () {
      // the phone's −z is east; its +x (the right edge) then points south
      final aim = aimFrom((0, 9.81, 0), (-20, -44, 0))!;
      expect(azDiff(aim.az, 90), lessThan(1e-6));
    });

    test('flat on the table, screen up, the back points down', () {
      expect(aimFrom((0, 0, 9.81), (0, 20, -44))!.alt, closeTo(-90, 1e-6));
    });

    test('tilted back 30°, looking north-west at 30° altitude', () {
      // build the readings from the pose: back = (az 315, alt 30) in east-north-up
      const az = 315 * math.pi / 180, alt = 30 * math.pi / 180;
      final back = (math.cos(alt) * math.sin(az), math.cos(alt) * math.cos(az), math.sin(alt));
      final up = (-math.sin(alt) * math.sin(az), -math.sin(alt) * math.cos(az), math.cos(alt));
      final right = (math.cos(az), -math.sin(az), 0.0);
      double dot((double, double, double) a, (double, double, double) b) => a.$1 * b.$1 + a.$2 * b.$2 + a.$3 * b.$3;
      // world vectors in device axes: x = right, y = up the screen, z = −back
      (double, double, double) device((double, double, double) w) => (dot(w, right), dot(w, up), -dot(w, back));
      final gravity = device((0, 0, 9.81));
      final field = device((0, 20, -44));
      final aim = aimFrom(gravity, field)!;
      expect(azDiff(aim.az, 315), lessThan(1e-6));
      expect(aim.alt, closeTo(30, 1e-6));
    });

    test('no answer when gravity and field are parallel', () {
      expect(aimFrom((0, 0, 9.81), (0, 0, 40)), isNull);
    });
  });
}
