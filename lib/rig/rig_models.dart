// What the rig's reads say, parsed by hand like the rest of the app. Shapes from the
// orchestrator's nina_live.py (live snapshot, devices_view, filters_view,
// autofocus_live_view, tppa_view) and app.py (/nina/cooling, /nina/preflight).

double? _d(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
int? _i(Object? v) => v is num ? v.toInt() : null;
bool _b(Object? v) => v == true;
String? _s(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
Map _m(Object? v) => v is Map ? v : const {};

/// The rig right now, from /nina/live with NINA's own field names.
class RigState {
  const RigState({
    required this.reachable,
    required this.camera,
    required this.mount,
    required this.focuser,
    required this.filterwheel,
    required this.guider,
    required this.guidingActive,
    required this.rmsTotal,
    required this.sequenceRunning,
    this.rotator = const RotatorState(),
    this.flat = const FlatPanelState(),
  });

  factory RigState.fromJson(Map j) {
    final devices = _m(j['devices']);
    final guiding = _m(j['guiding']);
    final sequence = _m(j['sequence']);
    Map dev(String key) => _m(devices[key]);
    final reachable = devices.values.any((d) => d is Map && d['reachable'] == true) || sequence['reachable'] == true;
    return RigState(
      reachable: reachable,
      camera: CameraState.fromJson(dev('camera')),
      mount: MountState.fromJson(dev('mount')),
      focuser: FocuserState.fromJson(dev('focuser')),
      filterwheel: _b(dev('filterwheel')['connected']),
      guider: _b(dev('guider')['connected']),
      guidingActive: _b(guiding['active']),
      rmsTotal: _d(guiding['rms_total_arcsec']),
      sequenceRunning: _b(sequence['running']),
      rotator: RotatorState.fromJson(dev('rotator')),
      flat: FlatPanelState.fromJson(dev('flatdevice')),
    );
  }

  final bool reachable;
  final CameraState camera;
  final MountState mount;
  final FocuserState focuser;
  final bool filterwheel;
  final bool guider;
  final bool guidingActive;
  final double? rmsTotal;
  final bool sequenceRunning;
  final RotatorState rotator;
  final FlatPanelState flat;

  /// How many of the five main devices (camera, mount, focuser, wheel, guider) are connected.
  int get mainConnected =>
      [camera.connected, mount.connected, focuser.connected, filterwheel, guider].where((c) => c).length;
}

/// Whether a device NINA lists is really part of this rig: connected, or a driver is
/// chosen for it (NINA names it). NINA's placeholder for "nothing chosen" is not a device.
bool _present(bool connected, String? name) =>
    connected || (name != null && !const {'no device', 'kein gerät'}.contains(name.trim().toLowerCase()));

class CameraState {
  const CameraState({
    this.connected = false,
    this.temperature,
    this.targetTemp,
    this.coolerOn,
    this.coolerPower,
    this.gain,
    this.gainMin,
    this.gainMax,
    this.exposing = false,
  });

  factory CameraState.fromJson(Map j) => CameraState(
    connected: _b(j['connected']),
    temperature: _d(j['Temperature']),
    targetTemp: _d(j['TargetTemp']),
    coolerOn: j['CoolerOn'] is bool ? j['CoolerOn'] as bool : null,
    coolerPower: _d(j['CoolerPower']),
    gain: _i(j['Gain']),
    gainMin: _i(j['GainMin']),
    gainMax: _i(j['GainMax']),
    exposing: _b(j['IsExposing']),
  );

  final bool connected;
  final double? temperature;
  final double? targetTemp;
  final bool? coolerOn;
  final double? coolerPower;
  final int? gain;
  final int? gainMin;
  final int? gainMax;
  final bool exposing;
}

class MountState {
  const MountState({
    this.connected = false,
    this.atPark = false,
    this.slewing = false,
    this.tracking = false,
    this.altitude,
    this.sideOfPier,
    this.hoursToFlip,
    this.flipText,
    this.trackingMode,
    this.atHome = false,
    this.canFindHome,
    this.canSlew,
  });

  factory MountState.fromJson(Map j) => MountState(
    connected: _b(j['connected']),
    atPark: _b(j['AtPark']),
    slewing: _b(j['Slewing']),
    tracking: _b(j['TrackingEnabled']),
    altitude: _d(j['Altitude']),
    sideOfPier: _s(j['SideOfPier']),
    hoursToFlip: _d(j['TimeToMeridianFlip']),
    flipText: _s(j['TimeToMeridianFlipString']),
    trackingMode: _trackingMode(j['TrackingMode']),
    atHome: _b(j['AtHome']),
    canFindHome: j['CanFindHome'] is bool ? j['CanFindHome'] as bool : null,
    canSlew: j['CanSlew'] is bool ? j['CanSlew'] as bool : null,
  );

  /// NINA's TrackingMode arrives as its name or its index, in the order nina_live.py
  /// maps it.
  static String? _trackingMode(Object? v) {
    if (v is num && v.toInt() >= 0 && v.toInt() < trackingModes.length) return trackingModes[v.toInt()];
    final text = _s(v)?.toLowerCase();
    return trackingModes.contains(text) ? text : null;
  }

  /// The names the server's `tracking` action takes (nina_live._TRACKING_MODES).
  static const trackingModes = ['sidereal', 'lunar', 'solar', 'king', 'stopped'];

  final bool connected;
  final bool atPark;
  final bool slewing;
  final bool tracking;
  final double? altitude;
  final String? sideOfPier;

  /// NINA's TimeToMeridianFlip, in hours.
  final double? hoursToFlip;

  /// NINA's own text for it ("01:30:00").
  final String? flipText;

  /// sidereal | lunar | solar | king | stopped, when the mount says.
  final String? trackingMode;
  final bool atHome;

  /// The mount's capabilities; null when it did not say (then the button stays).
  final bool? canFindHome;
  final bool? canSlew;
}

class RotatorState {
  const RotatorState({this.connected = false, this.name, this.position, this.mechanical, this.moving = false});

  factory RotatorState.fromJson(Map j) => RotatorState(
    connected: _b(j['connected']),
    name: _s(j['Name']),
    position: _d(j['Position']),
    mechanical: _d(j['MechanicalPosition']),
    moving: _b(j['IsMoving']),
  );

  final bool connected;
  final String? name;

  /// Sky angle and mechanical angle, in degrees.
  final double? position;
  final double? mechanical;
  final bool moving;

  bool get present => _present(connected, name);
}

/// The flat panel (NINA's "flatdevice"): light, brightness, and a cover if it has one.
class FlatPanelState {
  const FlatPanelState({
    this.connected = false,
    this.name,
    this.coverState,
    this.lightOn,
    this.brightness,
    this.minBrightness,
    this.maxBrightness,
    this.supportsOpenClose,
    this.supportsOnOff,
  });

  factory FlatPanelState.fromJson(Map j) => FlatPanelState(
    connected: _b(j['connected']),
    name: _s(j['Name']),
    coverState: _s(j['LocalizedCoverState']) ?? _s(j['CoverState']),
    lightOn: j['LightOn'] is bool ? j['LightOn'] as bool : null,
    brightness: _i(j['Brightness']),
    minBrightness: _i(j['MinBrightness']),
    maxBrightness: _i(j['MaxBrightness']),
    supportsOpenClose: j['SupportsOpenClose'] is bool ? j['SupportsOpenClose'] as bool : null,
    supportsOnOff: j['SupportsOnOff'] is bool ? j['SupportsOnOff'] as bool : null,
  );

  final bool connected;
  final String? name;
  final String? coverState;
  final bool? lightOn;
  final int? brightness;
  final int? minBrightness;
  final int? maxBrightness;
  final bool? supportsOpenClose;
  final bool? supportsOnOff;

  bool get present => _present(connected, name);
}

/// One of NINA's allow-listed profile settings, as /nina/profile/settings describes it.
class ProfileSetting {
  const ProfileSetting({required this.path, required this.label, this.value, this.unit, this.note});

  factory ProfileSetting.fromJson(Map j) => ProfileSetting(
    path: '${j['path']}',
    label: _s(j['label']) ?? '${j['path']}',
    value: j['value'],
    unit: _s(j['unit']),
    note: _s(j['note']),
  );

  final String path;
  final String label;
  final Object? value;
  final String? unit;
  final String? note;

  /// The meridian flip's own settings, out of the server's "safety" group.
  static List<ProfileSetting> meridianFlip(Map j) => [
    for (final g in (j['groups'] as List? ?? const []))
      if (g is Map)
        for (final s in (g['settings'] as List? ?? const []))
          if (s is Map && '${s['path']}'.contains('MeridianFlip')) ProfileSetting.fromJson(s),
  ];
}

class FocuserState {
  const FocuserState({this.connected = false, this.position, this.moving = false, this.temperature});

  factory FocuserState.fromJson(Map j) => FocuserState(
    connected: _b(j['connected']),
    position: _i(j['Position']),
    moving: _b(j['IsMoving']),
    temperature: _d(j['Temperature']),
  );

  final bool connected;
  final int? position;
  final bool moving;
  final double? temperature;
}

/// One row of /nina/devices.
class RigDevice {
  const RigDevice({required this.key, required this.label, required this.connected, this.driver, this.error});

  factory RigDevice.fromJson(Map j) => RigDevice(
    key: '${j['key']}',
    label: _s(j['label']) ?? '${j['key']}',
    connected: _b(j['connected']),
    driver: _s(j['driver_name']),
    error: _s(j['error']),
  );

  final String key;
  final String label;
  final bool connected;
  final String? driver;
  final String? error;
}

/// /nina/filters: the wheel and the glass in it. Empty slots have no name and are left out.
class FilterWheel {
  const FilterWheel({required this.connected, required this.moving, required this.current, required this.names});

  factory FilterWheel.fromJson(Map j) => FilterWheel(
    connected: _b(j['connected']),
    moving: _b(j['moving']),
    current: _s(_m(j['current'])['name']),
    names: [
      for (final f in (j['filters'] as List? ?? const []))
        if (f is Map && _s(f['name']) != null) _s(f['name'])!,
    ],
  );

  final bool connected;
  final bool moving;
  final String? current;
  final List<String> names;
}

/// /nina/cooling: Bortle's derived setpoint and why.
class CoolingAdvice {
  const CoolingAdvice({this.setpoint, this.reason, this.warnings = const []});

  factory CoolingAdvice.fromJson(Map j) => CoolingAdvice(
    setpoint: _d(j['setpoint_c']),
    reason: _s(j['reason']),
    warnings: [for (final w in (j['warnings'] as List? ?? const [])) '$w'],
  );

  final double? setpoint;
  final String? reason;
  final List<String> warnings;
}

class PreflightCheck {
  const PreflightCheck({required this.title, required this.status, this.detail});

  factory PreflightCheck.fromJson(Map j) =>
      PreflightCheck(title: _s(j['title']) ?? '${j['key']}', status: '${j['status']}', detail: _s(j['detail']));

  final String title;

  /// pass | warn | block | skip
  final String status;
  final String? detail;
}

class Preflight {
  const Preflight({required this.ok, this.summary, this.checks = const []});

  factory Preflight.fromJson(Map j) => Preflight(
    ok: _b(j['ok']),
    summary: _s(j['summary']),
    checks: [for (final c in (j['checks'] as List? ?? const [])) PreflightCheck.fromJson(c as Map)],
  );

  final bool ok;
  final String? summary;
  final List<PreflightCheck> checks;
}

class FocusPoint {
  const FocusPoint(this.position, this.hfr);

  final double position;
  final double hfr;
}

/// /nina/autofocus/live: the points of a run while it is measured, and the last run.
class AutofocusLive {
  const AutofocusLive({
    required this.running,
    required this.points,
    this.expected,
    this.lastPoints = const [],
    this.lastPosition,
    this.lastHfr,
    this.lastRSquared,
    this.lastTrustworthy,
  });

  factory AutofocusLive.fromJson(Map j) {
    List<FocusPoint> points(Object? list) => [
      for (final p in (list as List? ?? const []))
        if (p is Map && _d(p['position']) != null && _d(p['hfr']) != null)
          FocusPoint(_d(p['position'])!, _d(p['hfr'])!),
    ];
    final last = _m(j['last']);
    return AutofocusLive(
      running: _b(j['running']),
      points: points(j['points']),
      expected: _i(j['expected_points']),
      lastPoints: points(last['points']),
      lastPosition: _d(last['calculated_position']),
      lastHfr: _d(last['calculated_hfr']),
      lastRSquared: _d(last['r_squared']),
      lastTrustworthy: last['trustworthy'] is bool ? last['trustworthy'] as bool : null,
    );
  }

  final bool running;
  final List<FocusPoint> points;
  final int? expected;
  final List<FocusPoint> lastPoints;
  final double? lastPosition;
  final double? lastHfr;
  final double? lastRSquared;
  final bool? lastTrustworthy;
}

/// /nina/tppa: the polar alignment as the orchestrator's websocket bridge folds it.
class TppaState {
  const TppaState({
    required this.available,
    required this.running,
    required this.paused,
    this.totalArcmin,
    this.azimuthArcmin,
    this.altitudeArcmin,
    this.status,
    this.progress,
    this.note,
    this.connectError,
  });

  factory TppaState.fromJson(Map j) {
    final last = _m(j['last']);
    return TppaState(
      available: _b(j['available']),
      running: _b(j['running']),
      paused: _b(j['paused']),
      totalArcmin: _d(j['error_arcmin']) ?? _d(last['total_arcmin']),
      azimuthArcmin: _d(last['azimuth_arcmin']),
      altitudeArcmin: _d(last['altitude_arcmin']),
      status: _s(last['status']),
      progress: _d(last['progress']),
      note: _s(j['note']),
      connectError: _s(j['connect_error']),
    );
  }

  final bool available;
  final bool running;
  final bool paused;
  final double? totalArcmin;
  final double? azimuthArcmin;
  final double? altitudeArcmin;
  final String? status;
  final double? progress;
  final String? note;
  final String? connectError;
}
