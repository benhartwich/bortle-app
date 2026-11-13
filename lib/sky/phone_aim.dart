// "Handy-Ausrichtung": where the back of the phone points, from gravity and the magnetic
// field – the same construction as Android's SensorManager.getRotationMatrix: east is
// the field crossed with up, north is up crossed with east.
//
// Read only while the mode is on. Without the sensors (a desktop, a test, a phone without
// a magnetometer) the stream reports an error and the map stays where it was.
//
// What it does not do: correct for the magnetic declination (the compass points to
// magnetic north, a few degrees off true north in Europe, more elsewhere), nor for a
// magnetometer near a mount's motors or a steel tripod. It is for finding a part of the
// sky, not for aligning anything.

import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// The direction out of the phone's back, as azimuth (true or magnetic north, see above)
/// and altitude in degrees.
class PhoneAim {
  const PhoneAim(this.az, this.alt);

  final double az;
  final double alt;
}

/// The aim from one accelerometer reading (m/s², pointing up at rest, as sensors_plus
/// reports it on Android and iOS alike) and one magnetometer reading (µT), both in the
/// phone's axes: x right, y up the screen, z out of the screen. Null when the two are
/// (nearly) parallel – at a magnetic pole, or with a broken reading.
PhoneAim? aimFrom((double, double, double) gravity, (double, double, double) field) {
  final (ax, ay, az) = gravity;
  final (mx, my, mz) = field;
  // east = field × up
  var ex = my * az - mz * ay, ey = mz * ax - mx * az, ez = mx * ay - my * ax;
  final en = math.sqrt(ex * ex + ey * ey + ez * ez);
  final an = math.sqrt(ax * ax + ay * ay + az * az);
  if (en < 0.1 || an < 0.1) return null;
  ex /= en;
  ey /= en;
  ez /= en;
  final ux = ax / an, uy = ay / an, uz = az / an;
  // north = up × east
  final nz = ux * ey - uy * ex;
  // the back of the phone is −z: its world components are minus the z column
  final e = -ez, n = -nz, u = -uz;
  var azimuth = math.atan2(e, n) * 180 / math.pi;
  if (azimuth < 0) azimuth += 360;
  return PhoneAim(azimuth, math.asin(u.clamp(-1.0, 1.0)) * 180 / math.pi);
}

/// Where the aim comes from; injectable so tests and platforms without sensors can do
/// without them.
abstract class AimSource {
  Stream<PhoneAim> aims();
}

/// The phone's own sensors through sensors_plus, smoothed so the map does not tremble
/// with the hand: a low-pass on both vectors before they are combined.
class SensorAimSource implements AimSource {
  const SensorAimSource({this.smoothing = 0.2});

  /// The share of each new reading (0..1): lower is calmer and slower.
  final double smoothing;

  @override
  Stream<PhoneAim> aims() {
    late StreamController<PhoneAim> out;
    StreamSubscription<AccelerometerEvent>? accel;
    StreamSubscription<MagnetometerEvent>? magnet;
    (double, double, double)? g;
    (double, double, double)? m;
    (double, double, double) blend((double, double, double)? old, double x, double y, double z) {
      if (old == null) return (x, y, z);
      final k = smoothing;
      return (old.$1 + k * (x - old.$1), old.$2 + k * (y - old.$2), old.$3 + k * (z - old.$3));
    }

    void emit() {
      if (g == null || m == null) return;
      final aim = aimFrom(g!, m!);
      if (aim != null) out.add(aim);
    }

    out = StreamController<PhoneAim>(
      onListen: () {
        accel = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
            .listen((e) => g = blend(g, e.x, e.y, e.z), onError: out.addError, cancelOnError: true);
        magnet = magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen(
          (e) {
            m = blend(m, e.x, e.y, e.z);
            emit();
          },
          onError: out.addError,
          cancelOnError: true,
        );
      },
      onCancel: () async {
        await accel?.cancel();
        await magnet?.cancel();
      },
    );
    return out.stream;
  }
}
