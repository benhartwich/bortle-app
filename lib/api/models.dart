// What the cockpit answers, read by hand (no code generation, as in allskyhub). Field
// names follow the orchestrator's JSON; anything the app does not show is left out, and
// anything missing reads as null rather than failing the whole screen.

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

int _int(Object? v) => v is num ? v.toInt() : 0;

class Me {
  const Me({required this.name, required this.admin});

  factory Me.fromJson(Map j) => Me(name: '${j['name']}', admin: j['admin'] == true);

  final String name;
  final bool admin;
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
  const PipelineHold({required this.point, required this.reason, required this.findings, this.since});

  factory PipelineHold.fromJson(Map j) => PipelineHold(
    point: '${j['point']}',
    reason: '${j['reason'] ?? ''}',
    findings: [for (final f in (j['findings'] as List? ?? const [])) '$f'],
    since: _date(j['since']),
  );

  final String point;
  final String reason;
  final List<String> findings;
  final DateTime? since;
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
  const RunStep({required this.op, required this.status, this.previews = const []});

  factory RunStep.fromJson(Map j) => RunStep(
    op: '${j['op']}',
    status: '${j['status'] ?? ''}',
    previews: [for (final p in (j['previews'] as List? ?? const [])) '$p'],
  );

  final String op;
  final String status;
  final List<String> previews;
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
