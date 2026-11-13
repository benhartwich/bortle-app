// Draws the sky map: background, alt/az grid, constellation figures, stars, the ground
// below the horizon, the cardinal points and the markers. One CustomPainter, no widgets
// per star; every frame projects only what is in front and on the screen, and stops at
// the magnitude the zoom calls for (the catalogue is sorted brightest first).

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../design.dart';
import 'sky_catalog.dart';
import 'sky_math.dart';

enum MarkerKind { target, search, mount }

/// A labelled point on the map: tonight's targets, a search result, the mount.
class SkyMarker {
  const SkyMarker({required this.name, required this.ra, required this.dec, required this.kind, this.jNow = false});

  final String name;
  final double ra;
  final double dec;
  final MarkerKind kind;

  /// Of date rather than J2000 (the mount's own readout).
  final bool jNow;
}

/// The colours of one look: the night sky, or the red light mode.
class SkyColours {
  const SkyColours._({
    required this.top,
    required this.bottom,
    required this.ground,
    required this.horizon,
    required this.grid,
    required this.figure,
    required this.label,
    required this.star,
    required this.target,
    required this.search,
    required this.mount,
    required this.red,
  });

  static const day = SkyColours._(
    top: Color(0xFF02040C),
    bottom: Color(0xFF0B1430),
    ground: Color(0xE6070A10),
    horizon: Color(0xFF4FE3B0),
    grid: Color(0x337AA2F7),
    figure: Color(0x667AA2F7),
    label: Sky.text2,
    star: Sky.text,
    target: Sky.aurora,
    search: Sky.accent2,
    mount: Sky.warn,
    red: false,
  );

  static const night = SkyColours._(
    top: Red.bg,
    bottom: Color(0xFF0A0000),
    ground: Color(0xE6100100),
    horizon: Red.text2,
    grid: Red.line,
    figure: Color(0xFF5A1410),
    label: Red.text2,
    star: Red.strong,
    target: Red.text,
    search: Red.strong,
    mount: Red.strong,
    red: true,
  );

  final Color top;
  final Color bottom;
  final Color ground;
  final Color horizon;
  final Color grid;
  final Color figure;
  final Color label;
  final Color star;
  final Color target;
  final Color search;
  final Color mount;
  final bool red;
}

/// Text layouts kept across frames: laying out a label is the expensive part of a frame.
class LabelCache {
  final _cache = <String, TextPainter>{};

  TextPainter get(String text, Color colour, double size, {FontWeight weight = FontWeight.w400}) =>
      _cache.putIfAbsent('$text|${colour.toARGB32()}|$size|${weight.value}', () {
        if (_cache.length > 600) _cache.clear();
        return TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(color: colour, fontSize: size, fontWeight: weight),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
      });
}

/// The faintest stars worth drawing at a field of view: the whole sky shows the figures,
/// a zoomed view the stars between them.
double magnitudeLimit(double fov) => fov >= 150 ? 4.5 : (fov >= 90 ? 5.0 : 5.5);

class SkyPainter extends CustomPainter {
  SkyPainter({
    required this.catalog,
    required this.frame,
    required this.az,
    required this.alt,
    required this.fov,
    required this.markers,
    required this.colours,
    required this.labels,
    required this.english,
    this.selected,
    this.grid = true,
    this.centreY = 0.5,
  });

  final SkyCatalog catalog;
  final SkyFrame frame;
  final double az;
  final double alt;
  final double fov;
  final List<SkyMarker> markers;
  final SkyColours colours;
  final LabelCache labels;
  final bool english;
  final String? selected;
  final bool grid;

  /// Where the view's centre sits, as a fraction of the height.
  final double centreY;

  @override
  void paint(Canvas canvas, Size size) {
    final view = SkyView(az: az, alt: alt, fov: fov, size: size, centre: Offset(size.width / 2, size.height * centreY));
    final bounds = (Offset.zero & size).inflate(24);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colours.top, colours.bottom],
        ).createShader(Offset.zero & size),
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (grid) _grid(canvas, view, size);
    _figures(canvas, view, bounds, size);
    _stars(canvas, view, bounds);
    _ground(canvas, view, size);
    _cardinals(canvas, view, bounds);
    _markers(canvas, view, bounds);
    canvas.restore();
  }

  void _polyline(Canvas canvas, SkyView view, Iterable<(double, double)> azAlts, Paint paint, Size size) {
    final path = Path();
    Offset? last;
    final jump = size.longestSide * 2;
    for (final (a, h) in azAlts) {
      final p = view.projectAzAlt(a, h);
      if (p == null || (last != null && (p - last).distance > jump)) {
        last = null;
        if (p == null) continue;
      }
      if (last == null) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
      last = p;
    }
    canvas.drawPath(path, paint);
  }

  void _grid(Canvas canvas, SkyView view, Size size) {
    final paint = Paint()
      ..color = colours.grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final h in [30.0, 60.0]) {
      _polyline(canvas, view, [for (var a = 0; a <= 360; a += 4) (a.toDouble(), h)], paint, size);
    }
    for (var a = 0; a < 360; a += 30) {
      _polyline(canvas, view, [for (var h = 0; h <= 88; h += 4) (a.toDouble(), h.toDouble())], paint, size);
    }
  }

  void _figures(Canvas canvas, SkyView view, Rect bounds, Size size) {
    final m = frame.j2000.m;
    final path = Path();
    final jump = size.longestSide * 1.5;
    for (final line in catalog.lines) {
      Offset? last;
      for (var k = 0; k < line.length; k += 3) {
        final x = line[k], y = line[k + 1], z = line[k + 2];
        final p = view.project(
          m[0] * x + m[1] * y + m[2] * z,
          m[3] * x + m[4] * y + m[5] * z,
          m[6] * x + m[7] * y + m[8] * z,
        );
        if (p != null && last != null && (p - last).distance < jump && (bounds.contains(p) || bounds.contains(last))) {
          path
            ..moveTo(last.dx, last.dy)
            ..lineTo(p.dx, p.dy);
        }
        last = p;
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = colours.figure
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    if (fov > 140) return;
    for (final c in catalog.constellations) {
      final (a, h) = frame.horizontal(c.ra, c.dec);
      final p = view.projectAzAlt(a, h);
      if (p == null || !bounds.contains(p)) continue;
      final t = labels.get(c.name.toUpperCase(), colours.figure.withValues(alpha: 1), 10);
      t.paint(canvas, p - Offset(t.width / 2, t.height / 2));
    }
  }

  /// A star's colour from its B−V: blue-white to orange, kept pale (the eye sees star
  /// colour faintly); one hue in the red light mode.
  Color _starColour(double bv) {
    if (colours.red) return colours.star;
    final t = ((bv + 0.3) / 2.0).clamp(0.0, 1.0);
    return Color.lerp(const Color(0xFFD6E2FF), const Color(0xFFFFD9A8), t)!;
  }

  void _stars(Canvas canvas, SkyView view, Rect bounds) {
    final m = frame.j2000.m;
    final v = catalog.vectors;
    final limit = magnitudeLimit(fov);
    final zoom = math.sqrt(90 / fov).clamp(0.8, 2.2);
    final paint = Paint();
    final named = <(Offset, String)>[];
    for (var i = 0; i < catalog.length; i++) {
      final mag = catalog.mag[i];
      if (mag > limit) break;
      final x = v[i * 3], y = v[i * 3 + 1], z = v[i * 3 + 2];
      final p = view.project(
        m[0] * x + m[1] * y + m[2] * z,
        m[3] * x + m[4] * y + m[5] * z,
        m[6] * x + m[7] * y + m[8] * z,
      );
      if (p == null || !bounds.contains(p)) continue;
      final r = ((limit + 1.2 - mag) * 0.75 * zoom).clamp(0.6, 6.0);
      paint.color = _starColour(catalog.bv[i].toDouble());
      canvas.drawCircle(p, r, paint);
      final name = catalog.names[i];
      if (name != null && (mag <= (fov > 90 ? 1.6 : (fov > 40 ? 2.6 : 3.5)) || fov < 25)) named.add((p, name));
    }
    for (final (p, name) in named) {
      labels.get(name, colours.label, 11).paint(canvas, p + const Offset(6, -6));
    }
  }

  /// Everything below the horizon, darkened: stereographic maps the horizon to a circle
  /// (a line when looking exactly along it), so the ground is that circle's inside or
  /// outside, whichever does not hold the zenith.
  void _ground(Canvas canvas, SkyView view, Size size) {
    final a = view.projectAzAlt(view.az - 90, 0)!;
    final b = view.projectAzAlt(view.az + 90, 0)!;
    final c = view.projectAzAlt(view.az, 0)!;
    final zenith = view.projectAzAlt(0, 90) ?? Offset(size.width / 2, -1e6);
    final ground = Paint()..color = colours.ground;
    final line = Paint()
      ..color = colours.horizon
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final circle = _circleThrough(a, b, c);
    if (circle == null || circle.$2 > size.longestSide * 200) {
      // a straight horizon: the half-plane away from the zenith
      final dir = b - a;
      final unit = dir / dir.distance;
      final normal = Offset(-unit.dy, unit.dx);
      final side = (zenith - a).dx * normal.dx + (zenith - a).dy * normal.dy > 0 ? -1.0 : 1.0;
      final far = size.longestSide * 4;
      final p1 = a - unit * far, p2 = a + unit * far;
      canvas.drawPath(
        Path()
          ..moveTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..lineTo((p2 + normal * far * side).dx, (p2 + normal * far * side).dy)
          ..lineTo((p1 + normal * far * side).dx, (p1 + normal * far * side).dy)
          ..close(),
        ground,
      );
      canvas.drawLine(p1, p2, line);
      return;
    }
    final (centre, radius) = circle;
    final oval = Rect.fromCircle(center: centre, radius: radius);
    if ((zenith - centre).distance < radius) {
      canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect((Offset.zero & size).inflate(4))
          ..addOval(oval),
        ground,
      );
    } else {
      canvas.drawOval(oval, ground);
    }
    canvas.drawOval(oval, line);
  }

  static (Offset, double)? _circleThrough(Offset a, Offset b, Offset c) {
    final d = 2 * (a.dx * (b.dy - c.dy) + b.dx * (c.dy - a.dy) + c.dx * (a.dy - b.dy));
    if (d.abs() < 1e-6) return null;
    final a2 = a.dx * a.dx + a.dy * a.dy, b2 = b.dx * b.dx + b.dy * b.dy, c2 = c.dx * c.dx + c.dy * c.dy;
    final ux = (a2 * (b.dy - c.dy) + b2 * (c.dy - a.dy) + c2 * (a.dy - b.dy)) / d;
    final uy = (a2 * (c.dx - b.dx) + b2 * (a.dx - c.dx) + c2 * (b.dx - a.dx)) / d;
    final centre = Offset(ux, uy);
    return (centre, (a - centre).distance);
  }

  void _cardinals(Canvas canvas, SkyView view, Rect bounds) {
    for (var i = 0; i < 8; i++) {
      final p = view.projectAzAlt(i * 45.0, 0);
      if (p == null || !bounds.contains(p)) continue;
      final main = i.isEven;
      final t = labels.get(
        compassPoint(i * 45.0, english: english),
        main ? colours.horizon : colours.label,
        main ? 15 : 11,
        weight: main ? FontWeight.w700 : FontWeight.w400,
      );
      t.paint(canvas, p + Offset(-t.width / 2, 4));
    }
  }

  void _markers(Canvas canvas, SkyView view, Rect bounds) {
    for (final marker in markers) {
      final (a, h) = frame.horizontal(marker.ra, marker.dec, jNow: marker.jNow);
      final p = view.projectAzAlt(a, h);
      if (p == null || !bounds.contains(p)) continue;
      final colour = switch (marker.kind) {
        MarkerKind.target => colours.target,
        MarkerKind.search => colours.search,
        MarkerKind.mount => colours.mount,
      };
      final isSelected = marker.name == selected;
      final stroke = Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.5 : 1.5;
      switch (marker.kind) {
        case MarkerKind.target:
          canvas.drawCircle(p, 9, stroke);
          if (isSelected) canvas.drawCircle(p, 14, stroke..strokeWidth = 1);
        case MarkerKind.search:
          canvas.drawCircle(p, 11, stroke);
          for (final d in [const Offset(1, 0), const Offset(0, 1)]) {
            canvas.drawLine(p + d * 6, p + d * 16, stroke);
            canvas.drawLine(p - d * 6, p - d * 16, stroke);
          }
        case MarkerKind.mount:
          canvas.drawRect(Rect.fromCenter(center: p, width: 18, height: 18), stroke);
          canvas.drawLine(p + const Offset(-14, 0), p + const Offset(14, 0), stroke);
          canvas.drawLine(p + const Offset(0, -14), p + const Offset(0, 14), stroke);
      }
      final t = labels.get(marker.name, colour, 12, weight: FontWeight.w600);
      t.paint(canvas, p + const Offset(13, 2));
    }
  }

  @override
  bool shouldRepaint(SkyPainter old) =>
      old.az != az ||
      old.alt != alt ||
      old.fov != fov ||
      old.frame != frame ||
      old.markers != markers ||
      old.colours != colours ||
      old.selected != selected ||
      old.grid != grid ||
      old.centreY != centreY ||
      old.catalog != catalog;
}
