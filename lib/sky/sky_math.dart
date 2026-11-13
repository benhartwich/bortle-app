// The sky map's geometry: from a catalogue position to the observer's horizon, and from
// the horizon onto the screen.
//
// Both steps are rotations of unit vectors, built once per frame and applied to every
// star with nine multiplications – cheap enough for a few thousand stars at 60 fps on a
// mid-range phone. The horizon frame is east–north–up (ENU); azimuth counts from north
// through east. The screen is a stereographic projection centred on the view direction:
// circles on the sky stay circles (the horizon, the altitude rings), and shapes near the
// centre are true, which is what someone holding the phone against the sky compares.
//
// Precision: the same low-precision series as lib/astro.dart (precession, sidereal time)
// and no refraction, nutation or aberration – a few hundredths of a degree, far below a
// star's dot. This shows where things are; it does not point a telescope.

import 'dart:math' as math;
import 'dart:ui';

import '../astro.dart';

const _deg = math.pi / 180;

/// A 3×3 rotation, row-major.
class Rotation {
  const Rotation(this.m);

  final List<double> m;

  static const identity = Rotation([1, 0, 0, 0, 1, 0, 0, 0, 1]);

  Rotation operator *(Rotation o) {
    final a = m;
    final b = o.m;
    return Rotation([
      for (var r = 0; r < 3; r++)
        for (var c = 0; c < 3; c++) a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c],
    ]);
  }
}

/// The unit vector of a position given in degrees (RA/Dec, or azimuth/altitude with
/// [enu]: east, north, up).
(double, double, double) unitVector(double lonDeg, double latDeg, {bool enu = false}) {
  final l = lonDeg * _deg;
  final b = latDeg * _deg;
  final cb = math.cos(b);
  return enu ? (cb * math.sin(l), cb * math.cos(l), math.sin(b)) : (cb * math.cos(l), cb * math.sin(l), math.sin(b));
}

/// Azimuth (from north through east) and altitude in degrees of an ENU vector.
(double, double) azAlt(double e, double n, double u) {
  var az = math.atan2(e, n) / _deg;
  if (az < 0) az += 360;
  return (az, math.asin(u.clamp(-1.0, 1.0)) / _deg);
}

/// Where the sky stands for a site at an instant: equatorial vectors to the horizon.
class SkyFrame {
  SkyFrame._(this.lat, this.lon, this.time, this.ofDate, this.j2000);

  factory SkyFrame.at(double latDeg, double lonDeg, DateTime t) {
    // Equator of date → horizon: rotate by the local sidereal time into hour angle
    // (x towards the meridian), then tilt by the latitude into east–north–up.
    final lst = (gmst(t) + lonDeg) * _deg;
    final cl = math.cos(lst), sl = math.sin(lst);
    final hourAngle = Rotation([cl, sl, 0, sl, -cl, 0, 0, 0, 1]);
    final phi = latDeg * _deg;
    final cp = math.cos(phi), sp = math.sin(phi);
    final tilt = Rotation([0, -1, 0, -sp, 0, cp, cp, 0, sp]);
    final ofDate = tilt * hourAngle;
    // J2000 → equinox of date, built from lib/astro.dart's precess() itself: the
    // columns are the precessed basis vectors, so both agree by construction.
    final cols = [
      for (final (ra, dec) in [(0.0, 0.0), (90.0, 0.0), (0.0, 90.0)])
        () {
          final p = precess(ra, dec, t);
          return unitVector(p.ra, p.dec);
        }(),
    ];
    final precession = Rotation([
      cols[0].$1, cols[1].$1, cols[2].$1, //
      cols[0].$2, cols[1].$2, cols[2].$2,
      cols[0].$3, cols[1].$3, cols[2].$3,
    ]);
    return SkyFrame._(latDeg, lonDeg, t, ofDate, ofDate * precession);
  }

  final double lat;
  final double lon;
  final DateTime time;

  /// Equatorial of date (JNow, what a mount reports) → ENU.
  final Rotation ofDate;

  /// Catalogue J2000 → ENU, precession included.
  final Rotation j2000;

  /// Azimuth and altitude in degrees of a J2000 position (or one of date with [jNow]).
  (double, double) horizontal(double raDeg, double decDeg, {bool jNow = false}) {
    final (x, y, z) = unitVector(raDeg, decDeg);
    final m = (jNow ? ofDate : j2000).m;
    return azAlt(m[0] * x + m[1] * y + m[2] * z, m[3] * x + m[4] * y + m[5] * z, m[6] * x + m[7] * y + m[8] * z);
  }
}

/// The screen: a stereographic view centred on an azimuth and altitude, [fov] degrees
/// across the shorter side of [size]. The view's centre lands on [centre] – the middle of
/// [size] unless the screen puts controls over part of it.
class SkyView {
  SkyView({required this.az, required this.alt, required this.fov, required this.size, Offset? centre}) {
    final a = az * _deg, h = alt * _deg;
    final ca = math.cos(a), sa = math.sin(a), ch = math.cos(h), sh = math.sin(h);
    // forward, right (east when facing north) and up = right × forward; defined at the
    // zenith too, where "up" on the screen is the direction away from [az]
    _f = (ch * sa, ch * ca, sh);
    _r = (ca, -sa, 0);
    _u = (-sh * sa, -sh * ca, ch);
    scale = size.shortestSide / 2 / (2 * math.tan(fov * _deg / 4));
    this.centre = centre ?? size.center(Offset.zero);
  }

  final double az;
  final double alt;
  final double fov;
  final Size size;

  late final (double, double, double) _f;
  late final (double, double, double) _r;
  late final (double, double, double) _u;

  /// Pixels per unit of the projection plane.
  late final double scale;
  late final Offset centre;

  /// Degrees per pixel at the centre.
  double get degreesPerPixel => 1 / scale / _deg;

  /// The screen point of an ENU vector, or null behind the observer (more than ~160°
  /// from the centre, where the projection runs off to infinity).
  Offset? project(double e, double n, double u) {
    final z = e * _f.$1 + n * _f.$2 + u * _f.$3;
    if (z < -0.94) return null;
    final k = 2 * scale / (1 + z);
    final x = e * _r.$1 + n * _r.$2;
    final y = e * _u.$1 + n * _u.$2 + u * _u.$3;
    return Offset(centre.dx + x * k, centre.dy - y * k);
  }

  Offset? projectAzAlt(double azDeg, double altDeg) {
    final (e, n, u) = unitVector(azDeg, altDeg, enu: true);
    return project(e, n, u);
  }

  /// The azimuth and altitude under a screen point (the inverse projection).
  (double, double) unproject(Offset p) {
    final x = (p.dx - centre.dx) / (2 * scale);
    final y = -(p.dy - centre.dy) / (2 * scale);
    final rr = x * x + y * y;
    final z = (1 - rr) / (1 + rr);
    final s = 2 / (1 + rr);
    final xs = x * s, ys = y * s;
    final e = xs * _r.$1 + ys * _u.$1 + z * _f.$1;
    final n = xs * _r.$2 + ys * _u.$2 + z * _f.$2;
    final u = ys * _u.$3 + z * _f.$3;
    return azAlt(e, n, u);
  }
}

/// "NW", "SO" … for an azimuth: the eight points of the compass.
String compassPoint(double az, {required bool english}) {
  const de = ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'];
  const en = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  final i = ((az % 360) / 45).round() % 8;
  return (english ? en : de)[i];
}
