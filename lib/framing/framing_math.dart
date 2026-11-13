// The arithmetic of the framing screen, kept apart so it can be tested without a widget:
// moving a J2000 centre by arcminutes on the sky, and where a centre lands on a survey
// picture that is north up and east left.

import 'dart:math' as math;

/// Steps for the nudge arrows, in arcminutes (the cockpit's framing panel offers the same).
const framingStepsArcmin = [1, 5, 10, 30, 60];

/// RA in [0, 360).
double wrapRa(double ra) {
  final r = ra % 360;
  return r < 0 ? r + 360 : r;
}

/// An angle in [0, 360).
double wrapAngle(double a) => wrapRa(a);

/// The centre moved by [eastArcmin] towards east and [northArcmin] towards north.
///
/// An arcminute east is an arcminute on the sky, not of RA: a step in RA is divided by
/// cos(dec), so the frame moves by the same distance near the pole as on the equator.
/// The cosine is floored like the cockpit's (1e-3) so a step at the pole stays finite,
/// and Dec is clamped to ±90°.
(double, double) nudgeCentre(double raDeg, double decDeg, {double eastArcmin = 0, double northArcmin = 0}) {
  final cos = math.max(math.cos(decDeg * math.pi / 180), 1e-3);
  final ra = wrapRa(raDeg + eastArcmin / 60 / cos);
  final dec = (decDeg + northArcmin / 60).clamp(-90.0, 90.0);
  return (ra, dec);
}

/// Where ([raDeg], [decDeg]) sits relative to a picture centred on ([ra0], [dec0]), as
/// fractions of the picture's span: x to the right, y downward, (0, 0) the middle.
/// East is left on the picture, so a larger RA moves left. A small-field (tangent-plane)
/// approximation, which is all a frame on a survey cut-out of a few degrees needs.
(double, double) offsetOnPicture({
  required double raDeg,
  required double decDeg,
  required double ra0,
  required double dec0,
  required double widthDeg,
  required double heightDeg,
}) {
  var dRa = raDeg - ra0;
  if (dRa > 180) dRa -= 360;
  if (dRa < -180) dRa += 360;
  final east = dRa * math.cos(dec0 * math.pi / 180);
  final north = decDeg - dec0;
  return (-east / widthDeg, -north / heightDeg);
}

/// "20h 59m 00s"
String formatRa(double raDeg) {
  final totalSeconds = (wrapRa(raDeg) / 15 * 3600).round() % (24 * 3600);
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(h)}h ${two(m)}m ${two(s)}s';
}

/// "+44° 20′ 00″"
String formatDec(double decDeg) {
  final sign = decDeg < 0 ? '−' : '+';
  final totalSeconds = (decDeg.abs() * 3600).round();
  final d = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return '$sign${two(d)}° ${two(m)}′ ${two(s)}″';
}

/// GET /plan/framing: the framing angle measured from this account's solved frames
/// (services/planner/framing.py FramingAdvice.as_dict).
class MeasuredFraming {
  const MeasuredFraming({required this.known, this.positionAngleDeg, this.measuredAt, this.frames = 0, this.note});

  factory MeasuredFraming.fromJson(Map j) => MeasuredFraming(
    known: j['known'] == true,
    positionAngleDeg: j['position_angle_deg'] is num ? (j['position_angle_deg'] as num).toDouble() : null,
    measuredAt: j['measured_at'] is String ? DateTime.tryParse(j['measured_at'] as String) : null,
    frames: j['frames'] is num ? (j['frames'] as num).toInt() : 0,
    note: j['note'] is String && (j['note'] as String).trim().isNotEmpty ? j['note'] as String : null,
  );

  final bool known;
  final double? positionAngleDeg;
  final DateTime? measuredAt;
  final int frames;
  final String? note;

  /// The angle, only when it was measured.
  double? get angle => known ? positionAngleDeg : null;
}
