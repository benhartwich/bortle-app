// What the cockpit answers, read by hand (no code generation, as in allskyhub). Field
// names follow the orchestrator's JSON; anything the app does not show is left out, and
// anything missing reads as null rather than failing the whole screen.

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

int _int(Object? v) => v is num ? v.toInt() : 0;

class Me {
  const Me({required this.name, required this.admin, this.demo = false});

  factory Me.fromJson(Map j) => Me(name: '${j['name']}', admin: j['admin'] == true, demo: j['demo'] == true);

  final String name;
  final bool admin;

  /// The account the app stores review with: its Telescope tab shows a recorded night.
  final bool demo;
}

/// A name from the object search, placed in the sky (GET /plan/resolve, J2000). Needs no site.
class SkyObject {
  const SkyObject({required this.name, this.common, required this.raDeg, required this.decDeg});

  factory SkyObject.fromJson(Map j) => SkyObject(
    name: '${j['object']}',
    common: _str(j['common']),
    raDeg: (j['ra_deg'] as num).toDouble(),
    decDeg: (j['dec_deg'] as num).toDouble(),
  );

  final String name;
  final String? common;
  final double raDeg;
  final double decDeg;
}

class AppDevice {
  const AppDevice({required this.id, required this.label, this.createdAt, this.lastUsedAt});

  factory AppDevice.fromJson(Map j) => AppDevice(
    id: '${j['id']}',
    label: '${j['label']}',
    createdAt: _date(j['createdAt']),
    lastUsedAt: _date(j['lastUsedAt']),
  );

  final String id;
  final String label;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;
}

class NightState {
  const NightState({this.activeSession});

  factory NightState.fromJson(Map j) => NightState(activeSession: _str(j['active_session_id']));

  /// The capture session a running night writes into; null when no night runs.
  final String? activeSession;
}

class BortleEvent {
  const BortleEvent({required this.type, required this.severity, this.at, this.message});

  factory BortleEvent.fromJson(Map j) => BortleEvent(
    type: '${j['type']}',
    severity: '${j['severity'] ?? 'info'}',
    at: _date(j['timestamp']),
    message: _str(j['message']),
  );

  final String type;
  final String severity;
  final DateTime? at;
  final String? message;

  String get text => message ?? type;
}

class PipelineHold {
  const PipelineHold({
    required this.point,
    required this.reason,
    required this.findings,
    this.since,
    this.details = const {},
  });

  factory PipelineHold.fromJson(Map j) => PipelineHold(
    point: '${j['point']}',
    reason: '${j['reason'] ?? ''}',
    findings: [for (final f in (j['findings'] as List? ?? const [])) '$f'],
    since: _date(j['since']),
    details: j['details'] is Map ? Map<String, dynamic>.from(j['details'] as Map) : const {},
  );

  final String point;
  final String reason;
  final List<String> findings;
  final DateTime? since;

  /// What the hold shows, per point: at a step hold the run, recipe, step, next step,
  /// the values it ran with and its previews; at the recipe hold the choice per master.
  final Map<String, dynamic> details;
}

class Pipeline {
  const Pipeline({
    required this.id,
    required this.subject,
    required this.state,
    required this.level,
    this.hold,
    this.runs = const [],
    this.updatedAt,
  });

  factory Pipeline.fromJson(Map j) => Pipeline(
    id: '${j['id']}',
    subject: '${j['subject'] ?? j['id']}',
    state: '${j['state']}',
    level: '${j['level'] ?? 'auto'}',
    hold: j['hold'] is Map ? PipelineHold.fromJson(j['hold'] as Map) : null,
    runs: [for (final r in (j['runs'] as List? ?? const [])) '$r'],
    updatedAt: _date(j['updated_at']),
  );

  final String id;
  final String subject;

  /// running | waiting | done | failed | cancelled
  final String state;

  /// stepwise | guarded | auto
  final String level;
  final PipelineHold? hold;
  final List<String> runs;
  final DateTime? updatedAt;

  bool get waiting => state == 'waiting' && hold != null;
}

class DevelopRun {
  const DevelopRun({
    required this.name,
    required this.status,
    this.recipe,
    this.stepsDone = 0,
    this.totalSteps = 0,
    this.currentOp,
    this.eta,
    this.startedAt,
    this.worker,
  });

  factory DevelopRun.fromJson(Map j) => DevelopRun(
    name: '${j['name']}',
    status: '${j['status'] ?? 'unknown'}',
    recipe: _str(j['recipe']),
    stepsDone: _int(j['steps_done']),
    totalSteps: _int(j['total_steps']),
    currentOp: _str(j['current_op']),
    eta: j['eta_s'] is num ? Duration(seconds: (j['eta_s'] as num).round()) : null,
    startedAt: _date(j['started_at']),
    worker: _str(j['worker']),
  );

  final String name;

  /// running | done | failed | stale | unknown
  final String status;
  final String? recipe;
  final int stepsDone;
  final int totalSteps;
  final String? currentOp;
  final Duration? eta;
  final DateTime? startedAt;
  final String? worker;

  bool get running => status == 'running';

  /// 0..1 when the run knows its length.
  double? get progress => totalSteps > 0 ? (stepsDone / totalSteps).clamp(0, 1).toDouble() : null;
}

class RunStep {
  const RunStep({
    required this.op,
    required this.status,
    this.key,
    this.previews = const [],
    this.params = const {},
    this.metrics = const {},
    this.failed = const [],
    this.seconds,
  });

  factory RunStep.fromJson(Map j) {
    final iterations = j['iterations'] as List? ?? const [];
    final last = iterations.isEmpty ? const {} : iterations.last as Map;
    return RunStep(
      op: '${j['op']}',
      key: j['key'] is String ? j['key'] as String : null,
      status: '${j['status'] ?? ''}',
      previews: [for (final p in (j['previews'] as List? ?? const [])) '$p'],
      params: {
        for (final e in ((last['params'] as Map?) ?? const {}).entries)
          if (e.key != 'workdir') '${e.key}': e.value,
      },
      metrics: {
        for (final e in ((last['metrics_after'] as Map?) ?? const {}).entries)
          if (e.value is num && (e.value as num).isFinite) '${e.key}': (e.value as num).toDouble(),
      },
      failed: [for (final f in (last['failed_expectations'] as List? ?? const [])) '$f'],
      seconds: (j['duration_s'] as num?)?.toDouble(),
    );
  }

  final String op;

  /// `op#n` for an op the recipe runs more than once (null in protocols from before).
  final String? key;
  final String status;
  final List<String> previews;

  /// The values the step ran with (its last iteration).
  final Map<String, Object?> params;

  /// What was measured on the image after it: median, noise_sigma, star_count, fwhm_px …
  final Map<String, double> metrics;
  final List<String> failed;
  final double? seconds;
}

class RunDetail {
  const RunDetail({
    required this.name,
    required this.recipe,
    this.title,
    this.status,
    this.totalSteps = 0,
    this.steps = const [],
    this.finalPreviews = const {},
    this.currentOp,
    this.worker,
  });

  factory RunDetail.fromJson(Map j) => RunDetail(
    name: '${j['name']}',
    recipe: '${j['recipe'] ?? ''}',
    title: _str(j['title']),
    status: _str(j['status']),
    totalSteps: _int(j['total_steps']),
    steps: [for (final s in (j['steps'] as List? ?? const [])) RunStep.fromJson(s as Map)],
    finalPreviews: {for (final e in ((j['final_previews'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
    currentOp: _str(j['current_op']),
    worker: _str(j['worker']),
  );

  final String name;
  final String recipe;
  final String? title;
  final String? status;
  final int totalSteps;
  final List<RunStep> steps;
  final Map<String, String> finalPreviews;
  final String? currentOp;
  final String? worker;

  String get displayTitle => title ?? name;

  String? get preview => finalPreviews['full'] ?? (finalPreviews.isEmpty ? null : finalPreviews.values.first);
}

class GalleryEntry {
  const GalleryEntry({
    required this.name,
    required this.kind,
    required this.session,
    this.title,
    this.recipe,
    this.previews = const {},
    this.modified,
    this.hours,
  });

  factory GalleryEntry.fromJson(Map j) => GalleryEntry(
    name: '${j['name']}',
    kind: '${j['kind']}',
    session: '${j['session'] ?? ''}',
    title: _str(j['title']),
    recipe: _str(j['recipe']),
    previews: {for (final e in ((j['previews'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
    modified: j['modified'] is num
        ? DateTime.fromMillisecondsSinceEpoch(((j['modified'] as num) * 1000).round())
        : null,
    hours: (j['integration'] as Map?)?['total_hours'] as num?,
  );

  final String name;

  /// master | developed
  final String kind;
  final String session;
  final String? title;
  final String? recipe;
  final Map<String, String> previews;
  final DateTime? modified;
  final num? hours;

  String get displayTitle => title ?? session;

  String? get preview => previews['full'] ?? (previews.isEmpty ? null : previews.values.first);
}

// --- planning -------------------------------------------------------------------

double? _dbl(Object? v) => v is num ? v.toDouble() : null;

class Suggestion {
  const Suggestion(this.name, this.type, this.common);

  factory Suggestion.fromJson(Map j) => Suggestion('${j['name']}', _str(j['type']), _str(j['common']));

  final String name;
  final String? type;
  final String? common;

  String get label => common == null ? name : '$name · $common';
}

class PlanPoint {
  const PlanPoint(this.time, this.altitude, this.sunAltitude, this.cloudCover, this.horizon);

  factory PlanPoint.fromJson(Map j) => PlanPoint(
    _date(j['time'])!,
    _dbl(j['altitude_deg']) ?? 0,
    _dbl(j['sun_altitude_deg']) ?? 0,
    _dbl(j['cloud_cover']),
    _dbl(j['horizon_altitude_deg']),
  );

  final DateTime time;
  final double altitude;
  final double sunAltitude;

  /// 0..1, or null where the forecast ends.
  final double? cloudCover;

  /// The user's horizon at this azimuth, if they gave one.
  final double? horizon;
}

class NightPlan {
  const NightPlan({
    required this.object,
    required this.raDeg,
    required this.decDeg,
    this.nightStart,
    this.nightEnd,
    this.windowStart,
    this.windowEnd,
    this.windowHours = 0,
    this.maxAltitude,
    this.maxAltitudeTime,
    this.moonIllumination,
    this.moonSeparation,
    this.points = const [],
    this.warnings = const [],
  });

  factory NightPlan.fromJson(Map j) => NightPlan(
    object: '${j['object']}',
    raDeg: _dbl(j['ra_deg']) ?? 0,
    decDeg: _dbl(j['dec_deg']) ?? 0,
    nightStart: _date(j['night_start']),
    nightEnd: _date(j['night_end']),
    windowStart: _date(j['window_start']),
    windowEnd: _date(j['window_end']),
    windowHours: _dbl(j['window_hours']) ?? 0,
    maxAltitude: _dbl(j['max_altitude_deg']),
    maxAltitudeTime: _date(j['max_altitude_time']),
    moonIllumination: _dbl(j['moon_illumination']),
    moonSeparation: _dbl(j['moon_separation_deg']),
    points: [for (final p in (j['points'] as List? ?? const [])) PlanPoint.fromJson(p as Map)],
    warnings: [for (final w in (j['warnings'] as List? ?? const [])) '$w'],
  );

  final String object;
  final double raDeg;
  final double decDeg;
  final DateTime? nightStart;
  final DateTime? nightEnd;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final double windowHours;
  final double? maxAltitude;
  final DateTime? maxAltitudeTime;
  final double? moonIllumination;
  final double? moonSeparation;
  final List<PlanPoint> points;
  final List<String> warnings;

  /// Mean forecast cloud cover inside the window (or the dark hours), 0..1.
  double? get clouds {
    final from = windowStart ?? nightStart, to = windowEnd ?? nightEnd;
    final inside = [
      for (final p in points)
        if (p.cloudCover != null && (from == null || !p.time.isBefore(from)) && (to == null || !p.time.isAfter(to)))
          p.cloudCover!,
    ];
    if (inside.isEmpty) return null;
    return inside.reduce((a, b) => a + b) / inside.length;
  }
}

// --- the telescope ------------------------------------------------------------

class LiveFrame {
  const LiveFrame({
    required this.index,
    this.at,
    this.hfr,
    this.stars,
    this.rmsArcsec,
    this.exposure,
    this.filter,
    this.temperature,
    this.focus,
    this.type,
    this.bad = false,
  });

  factory LiveFrame.fromJson(Map j) => LiveFrame(
    index: _int(j['index']),
    at: _date(j['time'] ?? j['at']),
    hfr: _dbl(j['hfr']),
    stars: (j['stars'] as num?)?.toInt(),
    rmsArcsec: _dbl(j['rms_arcsec']),
    exposure: _dbl(j['exposure_s']),
    filter: _str(j['filter']),
    temperature: _dbl(j['temperature']),
    focus: (j['focus_position'] as num?)?.toInt(),
    type: _str(j['type']),
    bad: j['is_bad'] == true,
  );

  final int index;
  final DateTime? at;
  final double? hfr;
  final int? stars;
  final double? rmsArcsec;
  final double? exposure;
  final String? filter;
  final double? temperature;
  final int? focus;
  final String? type;

  /// HFR above 1.5× this night's own median (the server measures it).
  final bool bad;
}

class FrameHistory {
  const FrameHistory(this.frames, this.medianHfr);

  factory FrameHistory.fromJson(Map j) => FrameHistory([
    for (final f in (j['frames'] as List? ?? const [])) LiveFrame.fromJson(f as Map),
  ], _dbl(j['median_hfr']));

  final List<LiveFrame> frames;
  final double? medianHfr;
}

class DeviceState {
  const DeviceState(this.key, {required this.connected, required this.reachable, this.error});

  final String key;
  final bool connected;
  final bool reachable;
  final String? error;
}

class LiveSnapshot {
  const LiveSnapshot({
    required this.devices,
    required this.ninaReachable,
    this.rmsTotal,
    this.rmsRa,
    this.rmsDec,
    this.guiding = false,
    this.sequenceRunning = false,
    this.currentStep,
    this.lights,
    this.usable,
    this.usableMinutes,
    this.recent = const [],
    this.recordedTarget,
    this.recordedNight,
  });

  factory LiveSnapshot.fromJson(Map j) {
    final recorded = j['recorded'] as Map?;
    final devices = (j['devices'] as Map?) ?? const {};
    final guiding = (j['guiding'] as Map?) ?? const {};
    final sequence = (j['sequence'] as Map?) ?? const {};
    final frames = (j['frames'] as Map?) ?? const {};
    final progress = frames['progress'] as Map?;
    final states = [
      for (final e in devices.entries)
        DeviceState(
          '${e.key}',
          connected: (e.value as Map)['connected'] == true,
          reachable: (e.value as Map)['reachable'] == true,
          error: _str((e.value as Map)['error']),
        ),
    ];
    return LiveSnapshot(
      devices: states,
      ninaReachable: states.any((d) => d.reachable) || sequence['reachable'] == true,
      rmsTotal: _dbl(guiding['rms_total_arcsec']),
      rmsRa: _dbl(guiding['rms_ra_arcsec']),
      rmsDec: _dbl(guiding['rms_dec_arcsec']),
      guiding: guiding['active'] == true,
      sequenceRunning: sequence['running'] == true,
      currentStep: _str(sequence['current']),
      lights: (progress?['lights'] as num?)?.toInt(),
      usable: (progress?['usable'] as num?)?.toInt(),
      usableMinutes: _dbl(progress?['usable_minutes']),
      recent: [for (final f in (frames['recent'] as List? ?? const [])) LiveFrame.fromJson(f as Map)],
      recordedTarget: _str(recorded?['target']),
      recordedNight: _date(recorded?['night']),
    );
  }

  /// Set when this is a recorded night (the review account's), not the rig right now.
  final String? recordedTarget;
  final DateTime? recordedNight;

  final List<DeviceState> devices;

  /// Whether NINA answered at all; false by day or when the rig is off.
  final bool ninaReachable;
  final double? rmsTotal;
  final double? rmsRa;
  final double? rmsDec;
  final bool guiding;
  final bool sequenceRunning;

  /// "NGC 7000 > Imaging > Smart Exposure", the innermost running instruction.
  final String? currentStep;
  final int? lights;
  final int? usable;
  final double? usableMinutes;
  final List<LiveFrame> recent;

  LiveFrame? get latest => recent.isEmpty ? null : recent.last;
}

/// One folder of the account's Nextcloud (GET /equipment/nextcloud/browse).
class NextcloudFolder {
  const NextcloudFolder({required this.path, required this.parent, required this.dirs});

  factory NextcloudFolder.fromJson(Map j) => NextcloudFolder(
    path: '${j['path'] ?? ''}',
    parent: j['parent'] is String ? j['parent'] as String : null,
    dirs: [
      for (final d in (j['dirs'] as List? ?? const []).whereType<Map>())
        (name: '${d['name']}', project: d['has_lights'] == true),
    ],
  );

  final String path;

  /// The folder above, null at the top.
  final String? parent;
  final List<({String name, bool project})> dirs;
}

/// One of tonight's best targets for the account's site, horizon and rig
/// (GET /plan/recommend).
class Recommendation {
  const Recommendation({
    required this.name,
    required this.score,
    required this.visibleHours,
    required this.reasons,
    this.type,
    this.filter,
    this.exposureS,
    this.favorite = false,
    this.alreadyHours = 0,
    this.raDeg,
    this.decDeg,
    this.windowStart,
    this.windowEnd,
    this.maxAltitude,
    this.meanAltitude,
    this.airmass,
    this.fovVerdict,
    this.fovFill,
    this.meanCloud,
    this.blockedBy,
    this.darkHoursAboveHorizon = 0,
  });

  factory Recommendation.fromJson(Map j) => Recommendation(
    name: '${j['name']}',
    score: (j['score'] as num?)?.toDouble() ?? 0,
    visibleHours: (j['visible_hours'] as num?)?.toDouble() ?? 0,
    reasons: [for (final r in (j['reasons'] as List? ?? const [])) '$r'],
    type: _str(j['type']),
    filter: _str(j['recommended_filter']),
    exposureS: (j['recommended_exposure_s'] as num?)?.toDouble(),
    favorite: j['favorite'] == true,
    alreadyHours: (j['already_hours'] as num?)?.toDouble() ?? 0,
    raDeg: _dbl(j['ra_deg']),
    decDeg: _dbl(j['dec_deg']),
    windowStart: _date(j['window_start']),
    windowEnd: _date(j['window_end']),
    maxAltitude: _dbl(j['max_altitude_deg']),
    meanAltitude: _dbl(j['mean_altitude_deg']),
    airmass: _dbl(j['airmass']),
    fovVerdict: _str(j['fov_verdict']),
    fovFill: _dbl(j['fov_fill']),
    meanCloud: _dbl(j['mean_cloud']),
    blockedBy: _str(j['blocked_by']),
    darkHoursAboveHorizon: _dbl(j['dark_hours_above_horizon']) ?? 0,
  );

  final double? raDeg;
  final double? decDeg;

  /// The longest stretch tonight that is dark, above the horizon and not clouded out.
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final double? maxAltitude;

  /// Mean altitude through the window, and its airmass.
  final double? meanAltitude;
  final double? airmass;

  /// "fits well", "fills the frame", "small in frame", "larger than the frame — mosaic".
  final String? fovVerdict;
  final double? fovFill;
  final double? meanCloud;

  /// Why there is no window: "clouds" or "horizon"; null when there is one.
  final String? blockedBy;

  /// What a clear sky would give: dark and above the horizon, clouds ignored.
  final double darkHoursAboveHorizon;

  final String name;
  final double score;

  /// Hours in tonight's dark window above the horizon.
  final double visibleHours;
  final List<String> reasons;
  final String? type;
  final String? filter;
  final double? exposureS;
  final bool favorite;

  /// What is already integrated on it.
  final double alreadyHours;
}

// --- object preview (Plan tab): the survey picture framed by the account's rig -----------

/// GET /plan/preview: what this account's rig would see of an object. The field and the
/// verdict come from the equipment profile, measured the way the recommendations measure.
class ObjectPreview {
  const ObjectPreview({
    required this.name,
    this.common,
    required this.raDeg,
    required this.decDeg,
    this.focalMm,
    this.focalRatio,
    this.fovArcmin,
    this.sizeArcmin,
    this.fill,
    this.verdict,
    this.positionAngleDeg,
    required this.imagePath,
    required this.imageWidthDeg,
    required this.imageHeightDeg,
    this.credit,
  });

  factory ObjectPreview.fromJson(Map j) {
    final fov = j['fov_arcmin'];
    final image = (j['image'] as Map?) ?? const {};
    return ObjectPreview(
      name: '${j['object']}',
      common: _str(j['common']),
      raDeg: (j['ra_deg'] as num).toDouble(),
      decDeg: (j['dec_deg'] as num).toDouble(),
      focalMm: _dbl(j['focal_mm']),
      focalRatio: _dbl(j['focal_ratio']),
      fovArcmin: fov is List && fov.length == 2 ? ((fov[0] as num).toDouble(), (fov[1] as num).toDouble()) : null,
      sizeArcmin: _dbl(j['size_arcmin']),
      fill: _dbl(j['fill']),
      verdict: _str(j['verdict']),
      positionAngleDeg: _dbl(j['position_angle_deg']),
      imagePath: '${image['path']}',
      imageWidthDeg: _dbl(image['width_deg']) ?? 1,
      imageHeightDeg: _dbl(image['height_deg']) ?? 1,
      credit: _str(image['credit']),
    );
  }

  final String name;
  final String? common;
  final double raDeg;
  final double decDeg;
  final double? focalMm;
  final double? focalRatio;

  /// The camera's field (sensor width side, height side) in arcmin; null without optics.
  final (double, double)? fovArcmin;
  final double? sizeArcmin;
  final double? fill;

  /// The server's words: "fits well", "fills the frame", "small in frame",
  /// "larger than the frame — mosaic", "unknown (optics incomplete)".
  final String? verdict;

  /// Measured from this account's own solved frames of it; null until one exists.
  final double? positionAngleDeg;

  /// Path below /api/bortle of the survey picture, north up, east left.
  final String imagePath;
  final double imageWidthDeg;
  final double imageHeightDeg;
  final String? credit;
}

// --- Plan tab: a night's recommendations and the catalogue search ---------------------------

/// GET /plan/recommend: the ranked targets of one night and what holds for all of them.
class RecommendedNight {
  const RecommendedNight({
    required this.targets,
    this.nightStart,
    this.nightEnd,
    this.darkHours = 0,
    this.cloudedOut = false,
    this.fovArcmin,
  });

  factory RecommendedNight.fromJson(Map j) {
    final night = (j['night'] as Map?) ?? const {};
    final fov = j['fov_arcmin'];
    return RecommendedNight(
      targets: [for (final r in (j['recommendations'] as List? ?? const [])) Recommendation.fromJson(r as Map)],
      nightStart: _date(night['start']),
      nightEnd: _date(night['end']),
      darkHours: _dbl(night['hours']) ?? 0,
      cloudedOut: night['clouded_out'] == true,
      fovArcmin: fov is Map && fov['width'] is num && fov['height'] is num
          ? ((fov['width'] as num).toDouble(), (fov['height'] as num).toDouble())
          : null,
    );
  }

  final List<Recommendation> targets;
  final DateTime? nightStart;
  final DateTime? nightEnd;
  final double darkHours;

  /// The forecast covers (nearly) every target a clear sky would have given.
  final bool cloudedOut;

  /// The rig's field, width × height in arcminutes; null without optics in the profile.
  final (double, double)? fovArcmin;
}

/// One row of GET /plan/search: the offline catalogue of ~20 000 objects.
class SearchHit {
  const SearchHit({
    required this.name,
    required this.planName,
    this.aliases = const [],
    this.type,
    this.catalog,
    this.sizeArcmin,
  });

  factory SearchHit.fromJson(Map j) => SearchHit(
    name: '${j['name']}',
    planName: _str(j['plan_name']) ?? '${j['name']}',
    aliases: [for (final a in (j['aliases'] as List? ?? const [])) '$a'],
    type: _str(j['type']),
    catalog: _str(j['catalog']),
    sizeArcmin: _dbl(j['size_arcmin']),
  );

  /// How the catalogue names it, e.g. "Heart Nebula".
  final String name;

  /// The designation to plan with ("IC 1805"): what Sesame and NINA read.
  final String planName;
  final List<String> aliases;
  final String? type;
  final String? catalog;
  final double? sizeArcmin;
}
