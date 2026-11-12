// Telescope → Control: the rig's devices at the telescope, in the dark, with gloves.
// Everything here asks NINA to run one of its own operations through the routes the
// cockpit's /rig pages use (POST /nina/control, /nina/nudge); the app implements none
// of them, and safety (park on loss, aborts, meridian flip) stays NINA's.
//
// The rules the cockpit follows, kept here:
// - anything that moves hardware asks first; a refusal is shown in NINA's or Bortle's
//   own words and never retried behind the user's back;
// - the same bounds: a test exposure 0–120 s, nudges of 1–30′, focuser steps of at most
//   1000 and never below position 0, no focuser move while an autofocus runs;
// - disconnecting is not the reversible twin of connecting (the Lacerta focuser had to
//   be power-cycled on 2026-08-13), so it says so and sends confirm=true only then.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../api/bortle_client.dart';
import '../design.dart';
import '../l10n.dart';
import '../widgets.dart';
import 'rig_models.dart';
import 'tppa_screen.dart';

/// Nudge steps in arcminutes, as the cockpit's mount page offers them.
const nudgeArcmin = [1, 2, 5, 10, 30];

/// Relative focuser steps, as the cockpit's focus page offers them.
const focusSteps = [-1000, -100, -10, 10, 100, 1000];

/// The test exposure's range; the server refuses anything outside it as well.
const maxTestExposureS = 120.0;

class RigControl extends StatefulWidget {
  const RigControl({required this.client, required this.active, super.key});

  final BortleClient client;

  /// Whether the tab is on screen; polling runs only then.
  final bool active;

  @override
  State<RigControl> createState() => _RigControlState();
}

class _RigControlState extends State<RigControl> {
  RigState? _rig;
  Object? _error;
  Timer? _timer;

  /// The action running right now; every other button waits for it.
  String? _busy;

  List<RigDevice>? _devices;
  FilterWheel? _filters;
  CoolingAdvice? _cooling;
  Preflight? _preflight;
  AutofocusLive? _af;
  Uint8List? _capture;
  String? _captureNote;

  bool _nudgeArmed = false;
  bool _focusArmed = false;
  int _nudgeStep = 5;

  final _coolTemp = TextEditingController();
  final _coolMinutes = TextEditingController(text: '10');
  final _exposure = TextEditingController(text: '5');
  final _gain = TextEditingController();
  final _focusTarget = TextEditingController();

  @override
  void initState() {
    super.initState();
    _poll();
    _schedule();
  }

  @override
  void didUpdateWidget(RigControl old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      _schedule();
      if (widget.active) _poll();
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = widget.active ? Timer.periodic(const Duration(seconds: 5), (_) => _poll()) : null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [_coolTemp, _coolMinutes, _exposure, _gain, _focusTarget]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final rig = RigState.fromJson(await widget.client.rigLive());
      if (!mounted) return;
      setState(() {
        _rig = rig;
        _error = null;
        if (_gain.text.isEmpty && rig.camera.gain != null) _gain.text = '${rig.camera.gain}';
      });
      if (_af != null && (_af!.running || _busy == 'autofocus')) await _loadAutofocus();
    } on BortleError catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadDevices() async {
    try {
      final j = await widget.client.rigDevices();
      final rows = [for (final d in (j['devices'] as List? ?? const [])) RigDevice.fromJson(d as Map)];
      if (mounted) setState(() => _devices = rows);
    } on BortleError catch (e) {
      _say(e.message);
    }
  }

  Future<void> _loadFilters() async {
    try {
      final wheel = FilterWheel.fromJson(await widget.client.rigFilters());
      if (mounted) setState(() => _filters = wheel);
    } on BortleError catch (e) {
      _say(e.message);
    }
  }

  Future<void> _loadCooling() async {
    try {
      final advice = CoolingAdvice.fromJson(await widget.client.rigCooling());
      if (!mounted) return;
      setState(() {
        _cooling = advice;
        if (_coolTemp.text.isEmpty && advice.setpoint != null) _coolTemp.text = decimal(advice.setpoint!, 0);
      });
    } on BortleError catch (e) {
      _say(e.message);
    }
  }

  Future<void> _loadAutofocus() async {
    try {
      final af = AutofocusLive.fromJson(await widget.client.rigAutofocusLive());
      if (mounted) setState(() => _af = af);
    } on BortleError catch (e) {
      _say(e.message);
    }
  }

  Future<void> _runPreflight() async {
    setState(() => _busy = 'preflight');
    try {
      final result = Preflight.fromJson(await widget.client.rigPreflight());
      if (mounted) setState(() => _preflight = result);
    } on BortleError catch (e) {
      _say(e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _say(String text) {
    if (!mounted) return;
    // the newest answer replaces the last one at once instead of queueing behind it
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// One of NINA's operations: ask first (unless [ask] is null), run it, say what NINA
  /// answered, read the rig again. A refusal is the server's words, never retried.
  Future<Map?> _run(
    String key,
    String action, {
    Map<String, Object?> params = const {},
    (String, String, String)? ask,
    Duration? timeout,
    Future<void> Function()? after,
  }) async {
    if (ask != null) {
      final ok = await confirm(context, ask.$1, ask.$2, ask.$3);
      if (!ok || !mounted) return null;
    }
    setState(() => _busy = key);
    try {
      final result = await widget.client.rigControl(action, params, timeout: timeout);
      _say(tr('NINA hat es angenommen.', 'NINA accepted it.'));
      return result;
    } on BortleError catch (e) {
      _say(e.message);
      return null;
    } finally {
      if (mounted) setState(() => _busy = null);
      await _poll();
      if (after != null) await after();
    }
  }

  // --- the view ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final rig = _rig;
    if (rig == null) {
      return _error != null ? LoadError(_error!, onRetry: _poll) : const Center(child: CircularProgressIndicator());
    }
    if (!rig.reachable) {
      return RefreshIndicator(
        onRefresh: _poll,
        child: ListView(
          padding: const EdgeInsets.all(32),
          children: [
            Icon(Icons.nights_stay_outlined, size: 40, color: tones.muted),
            const SizedBox(height: 12),
            Text(
              tr(
                'NINA antwortet gerade nicht – ohne NINA gibt es nichts zu steuern. Sobald NINA läuft, erscheinen die Geräte hier.',
                'NINA is not answering – without NINA there is nothing to control. Once NINA runs, the devices show here.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: tones.muted),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _poll,
      child: ListView(
        key: const Key('rig-control'),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          _preflightCard(tones),
          _section(
            'devices',
            Icons.cable_outlined,
            tr('Geräte', 'Devices'),
            _devicesSummary(rig),
            onOpen: _loadDevices,
            child: _devicesBody(tones),
          ),
          _section(
            'camera',
            Icons.photo_camera_outlined,
            tr('Kamera', 'Camera'),
            _cameraSummary(rig.camera),
            onOpen: () async {
              await Future.wait([_loadCooling(), _loadFilters()]);
            },
            child: _cameraBody(rig, tones),
          ),
          _section(
            'mount',
            Icons.explore_outlined,
            tr('Montierung', 'Mount'),
            _mountSummary(rig.mount),
            child: _mountBody(rig.mount, tones),
          ),
          _section(
            'filter',
            Icons.filter_tilt_shift,
            'Filter',
            _filters?.current ??
                (rig.filterwheel ? tr('verbunden', 'connected') : tr('nicht verbunden', 'not connected')),
            onOpen: _loadFilters,
            child: _filterBody(rig, tones),
          ),
          _section(
            'focus',
            Icons.center_focus_strong_outlined,
            tr('Fokus', 'Focus'),
            rig.focuser.connected
                ? tr('Position ${rig.focuser.position ?? '–'}', 'position ${rig.focuser.position ?? '–'}')
                : tr('nicht verbunden', 'not connected'),
            onOpen: _loadAutofocus,
            child: _focusBody(rig.focuser, tones),
          ),
          _section(
            'guiding',
            Icons.track_changes,
            'Guiding',
            rig.guidingActive
                ? (rig.rmsTotal == null ? tr('läuft', 'running') : 'RMS ${decimal(rig.rmsTotal!, 2)}″')
                : tr('aus', 'off'),
            child: _guidingBody(rig, tones),
          ),
          _section(
            'sequence',
            Icons.playlist_play,
            tr('Sequenz', 'Sequence'),
            rig.sequenceRunning ? tr('läuft', 'running') : tr('steht', 'idle'),
            child: _sequenceBody(rig, tones),
          ),
          const SizedBox(height: 12),
          Text(
            tr(
              'Bortle löst nur NINAs eigene Funktionen aus. Parken bei Verbindungsverlust, Abbruch und Meridian-Flip bleiben NINAs Sicherheitsschicht – auch wenn Server, Netz oder App ausfallen.',
              'Bortle only triggers NINA’s own operations. Parking on connection loss, aborts and the meridian flip stay NINA’s safety layer – even if server, network or app fail.',
            ),
            style: TextStyle(color: tones.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _section(
    String key,
    IconData icon,
    String title,
    String summary, {
    required Widget child,
    Future<void> Function()? onOpen,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      key: Key('rig-$key'),
      minTileHeight: 64,
      leading: Icon(icon, size: 28),
      title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      subtitle: Text(summary, style: TextStyle(color: context.tones.muted)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      onExpansionChanged: (open) {
        if (open && onOpen != null) onOpen();
      },
      children: [child],
    ),
  );

  /// A big, gloved-finger target.
  Widget _button(String key, String label, VoidCallback? onPressed, {bool primary = false, Color? color}) {
    final style = ButtonStyle(minimumSize: WidgetStateProperty.all(const Size.fromHeight(52)));
    final text = Text(
      _busy == key ? '…' : label,
      style: TextStyle(fontSize: 15, color: onPressed == null ? null : color),
    );
    final enabled = _busy == null ? onPressed : null;
    return primary
        ? FilledButton(key: Key(key), style: style, onPressed: enabled, child: text)
        : OutlinedButton(key: Key(key), style: style, onPressed: enabled, child: text);
  }

  Widget _row(List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: c)],
      ],
    ),
  );

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(text, style: TextStyle(color: context.tones.muted, fontSize: 12)),
  );

  Widget _numberField(TextEditingController c, String label, String key, {String? suffix}) => TextField(
    key: Key(key),
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
    decoration: InputDecoration(labelText: label, suffixText: suffix, isDense: true),
  );

  static double? _parse(String text) => double.tryParse(text.trim().replaceAll(',', '.'));

  // --- pre-flight ------------------------------------------------------------------

  Widget _preflightCard(Tones tones) {
    final p = _preflight;
    Color tone(String status) => switch (status) {
      'pass' => tones.good,
      'warn' => tones.warn,
      'block' => tones.danger,
      _ => tones.muted,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _button('preflight', tr('Pre-Flight prüfen', 'Run pre-flight'), _runPreflight, primary: true),
            if (p != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  StateDot(p.ok ? tones.good : tones.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.summary ?? (p.ok ? tr('alles bereit', 'all set') : tr('nicht bereit', 'not ready')),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              for (final c in p.checks)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(padding: const EdgeInsets.only(top: 5), child: StateDot(tone(c.status))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: c.title,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if (c.detail != null) TextSpan(text: ' – ${c.detail}'),
                            ],
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // --- devices ---------------------------------------------------------------------

  String _devicesSummary(RigState rig) {
    final on = [
      rig.camera.connected,
      rig.mount.connected,
      rig.focuser.connected,
      rig.filterwheel,
      rig.guider,
    ].where((c) => c).length;
    return tr('$on von 5 Hauptgeräten verbunden', '$on of 5 main devices connected');
  }

  Widget _devicesBody(Tones tones) {
    final devices = _devices;
    if (devices == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _button(
          'connect-all',
          tr('Alle verbinden', 'Connect all'),
          () => _run(
            'connect-all',
            'connect-all',
            ask: (
              tr('Alle Geräte verbinden?', 'Connect every device?'),
              tr(
                'NINA verbindet jedes Gerät mit dem gewählten Treiber. Geräte, die nicht angeschlossen sind, melden einen Fehler; die anderen verbinden trotzdem.',
                'NINA connects every device with its chosen driver. Devices that are not plugged in report an error; the others connect anyway.',
              ),
              tr('Verbinden', 'Connect'),
            ),
            timeout: const Duration(seconds: 180),
            after: _loadDevices,
          ),
          primary: true,
        ),
        for (final d in devices)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                StateDot(d.connected ? tones.good : (d.error != null ? tones.danger : tones.muted)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        d.error ?? d.driver ?? tr('kein Treiber gewählt', 'no driver chosen'),
                        style: TextStyle(color: d.error != null ? tones.danger : tones.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 128,
                  child: d.connected
                      ? _button(
                          'disconnect-${d.key}',
                          tr('Trennen', 'Disconnect'),
                          () => _run(
                            'disconnect-${d.key}',
                            'disconnect',
                            params: {'device': d.key, 'confirm': true},
                            ask: (
                              tr('${d.label} trennen?', 'Disconnect the ${d.label}?'),
                              tr(
                                'Trennen ist nicht das Gegenstück zum Verbinden: manche Treiber verbinden danach nicht mehr und brauchen einen Neustart der Hardware am Teleskop.',
                                'Disconnecting is not the twin of connecting: some drivers refuse to reconnect and need the hardware power-cycled at the telescope.',
                              ),
                              tr('Trennen', 'Disconnect'),
                            ),
                            after: _loadDevices,
                          ),
                          color: tones.danger,
                        )
                      : _button(
                          'connect-${d.key}',
                          tr('Verbinden', 'Connect'),
                          () => _run(
                            'connect-${d.key}',
                            'connect',
                            params: {'device': d.key},
                            ask: (
                              tr('${d.label} verbinden?', 'Connect the ${d.label}?'),
                              d.driver == null
                                  ? tr(
                                      'NINA verbindet mit dem Treiber, den sein Auswahlfeld hält.',
                                      'NINA connects with the driver its chooser holds.',
                                    )
                                  : tr('NINA verbindet mit „${d.driver}“.', 'NINA connects with “${d.driver}”.'),
                              tr('Verbinden', 'Connect'),
                            ),
                            timeout: const Duration(seconds: 90),
                            after: _loadDevices,
                          ),
                        ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // --- camera ----------------------------------------------------------------------

  String _cameraSummary(CameraState c) {
    if (!c.connected) return tr('nicht verbunden', 'not connected');
    return [
      if (c.temperature != null) '${decimal(c.temperature!, 1)} °C',
      if (c.coolerOn == true && c.coolerPower != null)
        tr('Kühler ${c.coolerPower!.round()} %', 'cooler ${c.coolerPower!.round()} %'),
      if (c.gain != null) 'Gain ${c.gain}',
      if (c.exposing) tr('belichtet', 'exposing'),
    ].join(' · ');
  }

  Widget _cameraBody(RigState rig, Tones tones) {
    final c = rig.camera;
    final advice = _cooling;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('Kühlung', 'Cooling'), style: const TextStyle(fontWeight: FontWeight.w600)),
        if (c.targetTemp != null)
          _note(
            tr('Sollwert in NINA: ${decimal(c.targetTemp!, 0)} °C', 'NINA’s setpoint: ${decimal(c.targetTemp!, 0)} °C'),
          ),
        if (advice?.setpoint != null)
          _note(
            tr(
              'Bortles Vorschlag: ${decimal(advice!.setpoint!, 0)} °C – ${advice.reason ?? ''}',
              'Bortle suggests ${decimal(advice.setpoint!, 0)} °C – ${advice.reason ?? ''}',
            ),
          ),
        for (final w in advice?.warnings ?? const <String>[]) _note('⚠ $w'),
        _row([
          _numberField(_coolTemp, tr('Ziel', 'Target'), 'cool-temp', suffix: '°C'),
          _numberField(_coolMinutes, tr('Dauer', 'Duration'), 'cool-minutes', suffix: 'min'),
        ]),
        _row([
          _button('cool', tr('Kühlen', 'Cool'), c.connected ? _cool : null, primary: true),
          _button(
            'warm',
            tr('Aufwärmen', 'Warm up'),
            c.connected
                ? () => _run(
                    'warm',
                    'warm',
                    params: {'minutes': _parse(_coolMinutes.text) ?? 10},
                    ask: (
                      tr('Kamera aufwärmen?', 'Warm the camera?'),
                      tr('Das beendet die Kühlung.', 'This ends the cooling.'),
                      tr('Aufwärmen', 'Warm up'),
                    ),
                  )
                : null,
          ),
        ]),
        const SizedBox(height: 16),
        Text(tr('Testaufnahme', 'Test exposure'), style: const TextStyle(fontWeight: FontWeight.w600)),
        _note(
          tr(
            'Filter: ${_filters?.current ?? '–'} (wechseln unter „Filter“). Ein Blick, keine Messung – die Aufnahme geht nicht in NINAs Bildverlauf.',
            'Filter: ${_filters?.current ?? '–'} (change it under “Filter”). A look, not a measurement – it does not enter NINA’s image history.',
          ),
        ),
        _row([
          _numberField(_exposure, tr('Belichtung', 'Exposure'), 'capture-exposure', suffix: 's'),
          _numberField(
            _gain,
            c.gainMin != null && c.gainMax != null ? 'Gain ${c.gainMin}–${c.gainMax}' : 'Gain',
            'capture-gain',
          ),
        ]),
        _row([
          _button('capture', tr('Belichten', 'Expose'), c.connected ? () => _captureNow(c) : null, primary: true),
          _button(
            'abort-exposure',
            tr('Abbrechen', 'Abort'),
            c.connected && c.exposing ? () => _run('abort-exposure', 'abort-exposure') : null,
          ),
        ]),
        if (_captureNote != null) _note(_captureNote!),
        if (_capture != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Sky.radius),
              child: InteractiveViewer(
                maxScale: 6,
                child: _redAware(tones, Image.memory(_capture!, key: const Key('capture-image'), fit: BoxFit.contain)),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _cool() async {
    final temperature = _parse(_coolTemp.text);
    final minutes = _parse(_coolMinutes.text) ?? 10;
    if (temperature == null || temperature < -40 || temperature > 20) {
      _say(tr('Bitte ein Ziel zwischen −40 und 20 °C.', 'Please a target between −40 and 20 °C.'));
      return;
    }
    if (minutes < 0 || minutes > 60) {
      _say(tr('Die Dauer liegt zwischen 0 und 60 min.', 'The duration is between 0 and 60 min.'));
      return;
    }
    await _run(
      'cool',
      'cool',
      params: {'temperature': temperature, 'minutes': minutes},
      ask: (
        tr('Auf ${decimal(temperature, 0)} °C kühlen?', 'Cool to ${decimal(temperature, 0)} °C?'),
        tr(
          'NINA fährt den Kühler über ${decimal(minutes, 0)} min auf den Sollwert.',
          'NINA ramps the cooler to the setpoint over ${decimal(minutes, 0)} min.',
        ),
        tr('Kühlen', 'Cool'),
      ),
    );
  }

  Future<void> _captureNow(CameraState c) async {
    final seconds = _parse(_exposure.text);
    if (seconds == null || seconds < 0 || seconds > maxTestExposureS) {
      _say(tr('Eine Testaufnahme dauert 0 bis 120 s.', 'A test exposure runs 0 to 120 s.'));
      return;
    }
    final gain = _parse(_gain.text)?.round();
    if (gain != null && ((c.gainMin != null && gain < c.gainMin!) || (c.gainMax != null && gain > c.gainMax!))) {
      _say(tr('Gain außerhalb von ${c.gainMin}–${c.gainMax}.', 'Gain outside ${c.gainMin}–${c.gainMax}.'));
      return;
    }
    final result = await _run(
      'capture',
      'capture',
      params: {'duration': seconds, 'gain': ?gain},
      timeout: Duration(seconds: seconds.ceil() + 90),
    );
    if (result == null) return;
    try {
      final bytes = await widget.client.rigCaptureImage();
      if (mounted) {
        setState(() {
          _capture = bytes;
          _captureNote = result['result'] is String ? result['result'] as String : null;
        });
      }
    } on BortleError catch (e) {
      _say(e.message);
    }
  }

  // --- mount -----------------------------------------------------------------------

  String _mountSummary(MountState m) {
    if (!m.connected) return tr('nicht verbunden', 'not connected');
    return [
      if (m.atPark) tr('geparkt', 'parked'),
      if (m.slewing) tr('schwenkt', 'slewing'),
      if (!m.atPark) m.tracking ? tr('führt nach', 'tracking') : tr('kein Tracking', 'not tracking'),
      if (m.altitude != null) tr('Höhe ${decimal(m.altitude!, 0)}°', 'alt ${decimal(m.altitude!, 0)}°'),
    ].join(' · ');
  }

  Widget _mountBody(MountState m, Tones tones) {
    final canNudge = m.connected && !m.atPark && !m.slewing;
    Widget arrow(String direction, String label) =>
        SizedBox(height: 64, child: _button('nudge-$direction', label, canNudge ? () => _nudge(direction) : null));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (m.hoursToFlip != null && m.hoursToFlip! > 0)
          _note(tr('Meridian-Flip in ${_hm(m.hoursToFlip!)} (NINA)', 'Meridian flip in ${_hm(m.hoursToFlip!)} (NINA)')),
        _row([
          m.atPark
              ? _button(
                  'unpark',
                  tr('Entparken', 'Unpark'),
                  m.connected
                      ? () => _run(
                          'unpark',
                          'unpark',
                          ask: (
                            tr('Montierung entparken?', 'Unpark the mount?'),
                            tr(
                              'Die Montierung verlässt die Parkposition und beginnt nachzuführen.',
                              'The mount leaves its park position and starts tracking.',
                            ),
                            tr('Entparken', 'Unpark'),
                          ),
                          timeout: const Duration(seconds: 120),
                        )
                      : null,
                  primary: true,
                )
              : _button(
                  'park',
                  tr('Parken', 'Park'),
                  m.connected
                      ? () => _run(
                          'park',
                          'park',
                          ask: (
                            tr('Montierung parken?', 'Park the mount?'),
                            tr(
                              'Die Montierung schwenkt in NINAs Parkposition und hört auf nachzuführen. Kabel und Taukappe im Blick behalten.',
                              'The mount slews to NINA’s park position and stops tracking. Keep an eye on cables and dew shield.',
                            ),
                            tr('Parken', 'Park'),
                          ),
                          timeout: const Duration(seconds: 180),
                        )
                      : null,
                ),
          _button(
            'tracking',
            m.tracking ? tr('Tracking aus', 'Stop tracking') : tr('Tracking an', 'Start tracking'),
            m.connected && !m.atPark
                ? () => _run(
                    'tracking',
                    'tracking',
                    params: {'mode': m.tracking ? 'stopped' : 'sidereal'},
                    ask: m.tracking
                        ? (
                            tr('Nachführung stoppen?', 'Stop tracking?'),
                            tr(
                              'Die Sterne wandern aus dem Bild, bis die Nachführung wieder läuft.',
                              'Stars drift out of the frame until tracking runs again.',
                            ),
                            tr('Stoppen', 'Stop'),
                          )
                        : (
                            tr('Siderisch nachführen?', 'Track at sidereal rate?'),
                            tr('NINA startet die siderische Nachführung.', 'NINA starts sidereal tracking.'),
                            tr('Starten', 'Start'),
                          ),
                  )
                : null,
          ),
        ]),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(tr('Feinjustage', 'Nudge'), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            SegmentedButton<int>(
              key: const Key('nudge-step'),
              showSelectedIcon: false,
              segments: [for (final a in nudgeArcmin) ButtonSegment(value: a, label: Text('$a′'))],
              selected: {_nudgeStep},
              onSelectionChanged: (s) => setState(() => _nudgeStep = s.first),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Spacer(),
            Expanded(child: arrow('north', tr('Nord', 'North'))),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // laid out as the cockpit's pad: west left, east right
            Expanded(child: arrow('west', 'West')),
            const SizedBox(width: 8),
            Expanded(
              child: Center(
                child: Text('$_nudgeStep′', style: TextStyle(color: tones.muted)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: arrow('east', tr('Ost', 'East'))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Spacer(),
            Expanded(child: arrow('south', tr('Süd', 'South'))),
            const Spacer(),
          ],
        ),
        _note(
          tr(
            'Ein Druck, ein Schritt: Bortle rechnet aus der Position der Montierung das Ziel in J2000 und lässt NINA dorthin schwenken. Die Tasten benennen die Himmelsrichtung, nicht die Richtung im Bild.',
            'One press, one step: Bortle turns the mount’s position into a J2000 target and NINA slews there. The keys name the sky direction, not the direction in the frame.',
          ),
        ),
        const SizedBox(height: 12),
        _button(
          'open-tppa',
          tr('Polausrichtung (TPPA) …', 'Polar alignment (TPPA) …'),
          () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TppaScreen(client: widget.client))),
        ),
      ],
    );
  }

  static String _hm(double hours) {
    final minutes = (hours * 60).round();
    return minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _nudge(String direction) async {
    if (!_nudgeArmed) {
      final ok = await confirm(
        context,
        tr('Feinjustage freigeben?', 'Allow nudging?'),
        tr(
          'Jeder Druck auf eine Richtungstaste schwenkt die Montierung um den gewählten Schritt ($_nudgeStep′). Das gilt, bis du diese Ansicht verlässt.',
          'Every press on a direction key slews the mount by the chosen step ($_nudgeStep′). This holds until you leave this view.',
        ),
        tr('Freigeben', 'Allow'),
      );
      if (!ok || !mounted) return;
      setState(() => _nudgeArmed = true);
    }
    setState(() => _busy = 'nudge-$direction');
    try {
      await widget.client.rigNudge(direction, _nudgeStep.toDouble());
      _say(tr('$_nudgeStep′ nach ${_directionDe(direction)}', '$_nudgeStep′ $direction'));
    } on BortleError catch (e) {
      _say(e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
      await _poll();
    }
  }

  static String _directionDe(String d) =>
      const {'north': 'Nord', 'south': 'Süd', 'east': 'Ost', 'west': 'West'}[d] ?? d;

  // --- filter ----------------------------------------------------------------------

  Widget _filterBody(RigState rig, Tones tones) {
    final wheel = _filters;
    if (wheel == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!wheel.connected) return _note(tr('Das Filterrad ist nicht verbunden.', 'The filter wheel is not connected.'));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final name in wheel.names)
          SizedBox(
            height: 52,
            child: name == wheel.current
                ? FilledButton(key: Key('filter-$name'), onPressed: null, child: Text(name))
                : OutlinedButton(
                    key: Key('filter-$name'),
                    onPressed: _busy != null || wheel.moving
                        ? null
                        : () => _run(
                            'filter-$name',
                            'filter',
                            params: {'filter': name},
                            ask: (
                              tr('Filter wechseln?', 'Change the filter?'),
                              tr(
                                'Das Filterrad dreht auf „$name“. Läuft eine Sequenz, wechselt sie den Filter vielleicht gleich zurück.',
                                'The wheel turns to “$name”. If a sequence runs, it may change the filter right back.',
                              ),
                              tr('Wechseln', 'Change'),
                            ),
                            after: _loadFilters,
                          ),
                    child: Text(name),
                  ),
          ),
      ],
    );
  }

  // --- focus -----------------------------------------------------------------------

  Widget _focusBody(FocuserState f, Tones tones) {
    final af = _af;
    final afRunning = af?.running ?? false;
    final canMove = f.connected && !f.moving && !afRunning && f.position != null;
    final points = af == null ? const <FocusPoint>[] : (af.running ? af.points : af.lastPoints);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          [
            tr('Position ${f.position ?? '–'}', 'Position ${f.position ?? '–'}'),
            if (f.moving) tr('fährt', 'moving'),
            if (f.temperature != null) '${decimal(f.temperature!, 1)} °C',
          ].join(' · '),
          style: const TextStyle(fontSize: 16),
        ),
        if (afRunning)
          _note(
            tr(
              'Autofokus läuft (${af!.points.length}${af.expected == null ? '' : ' von ${af.expected}'} Punkte) – der Fokus bleibt so lange gesperrt.',
              'Autofocus running (${af.points.length}${af.expected == null ? '' : ' of ${af.expected}'} points) – the focuser stays locked meanwhile.',
            ),
          ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final delta in focusSteps)
              SizedBox(
                width: 96,
                child: _button(
                  'focus-step-$delta',
                  delta > 0 ? '+$delta' : '$delta',
                  canMove ? () => _focusStep(f, delta) : null,
                ),
              ),
          ],
        ),
        _row([
          _numberField(_focusTarget, tr('Position', 'Position'), 'focus-target'),
          _button('focus-move', tr('Fahren', 'Move'), canMove ? () => _focusAbsolute(f) : null),
        ]),
        _row([
          _button(
            'autofocus',
            tr('Autofokus', 'Autofocus'),
            f.connected && !afRunning
                ? () => _run(
                    'autofocus',
                    'autofocus',
                    ask: (
                      tr('Autofokus starten?', 'Start an autofocus?'),
                      tr(
                        'NINA fährt den Fokus durch seine Messpunkte und stellt danach auf das gefundene Minimum. Währenddessen keine Belichtung starten.',
                        'NINA moves the focuser through its sweep and then to the minimum it found. Start no exposure meanwhile.',
                      ),
                      tr('Starten', 'Start'),
                    ),
                    after: _loadAutofocus,
                  )
                : null,
            primary: true,
          ),
          _button(
            'focus-stop',
            tr('Stopp', 'Stop'),
            f.connected && f.moving ? () => _run('focus-stop', 'focus-stop') : null,
          ),
        ]),
        if (points.length >= 2) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: CustomPaint(
              key: const Key('focus-curve'),
              painter: _FocusCurve(points, Theme.of(context).colorScheme.primary, tones.muted),
            ),
          ),
          if (!afRunning && af!.lastPosition != null)
            _note(
              [
                tr('Letzter Lauf: ${af.lastPosition!.round()}', 'Last run: ${af.lastPosition!.round()}'),
                if (af.lastHfr != null) 'HFR ${decimal(af.lastHfr!, 2)}',
                if (af.lastRSquared != null) 'R² ${decimal(af.lastRSquared!, 3)}',
                if (af.lastTrustworthy == false) tr('nicht vertrauenswürdig', 'not trustworthy'),
              ].join(' · '),
            ),
        ],
      ],
    );
  }

  Future<void> _armFocus() async {
    if (_focusArmed) return;
    final ok = await confirm(
      context,
      tr('Fokus fahren freigeben?', 'Allow focuser moves?'),
      tr(
        'Jeder Druck fährt den Fokussierer sofort. Läuft eine Sequenz, verschiebt das den Fokus der laufenden Aufnahmen. Das gilt, bis du diese Ansicht verlässt.',
        'Every press moves the focuser at once. If a sequence runs, this shifts the focus of its exposures. This holds until you leave this view.',
      ),
      tr('Freigeben', 'Allow'),
    );
    if (ok && mounted) setState(() => _focusArmed = true);
  }

  Future<void> _focusStep(FocuserState f, int delta) async {
    await _armFocus();
    if (!_focusArmed) return;
    if ((f.position ?? 0) + delta < 0) {
      _say(tr('Unter Position 0 fährt kein Fokussierer.', 'No focuser moves below position 0.'));
      return;
    }
    await _run('focus-step-$delta', 'focus-step', params: {'steps': delta});
  }

  Future<void> _focusAbsolute(FocuserState f) async {
    final target = _parse(_focusTarget.text)?.round();
    if (target == null || target < 0) {
      _say(tr('Bitte eine Position ab 0.', 'Please a position from 0.'));
      return;
    }
    await _armFocus();
    if (!_focusArmed) return;
    await _run('focus-move', 'focuser-move', params: {'position': target}, timeout: const Duration(seconds: 120));
  }

  // --- guiding ---------------------------------------------------------------------

  Widget _guidingBody(RigState rig, Tones tones) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        rig.guidingActive
            ? (rig.rmsTotal == null
                  ? tr('Guiding läuft', 'Guiding')
                  : tr(
                      'Guiding läuft · RMS ${decimal(rig.rmsTotal!, 2)}″',
                      'Guiding · RMS ${decimal(rig.rmsTotal!, 2)}″',
                    ))
            : tr('Guiding aus', 'Guiding off'),
        style: const TextStyle(fontSize: 16),
      ),
      _row([
        _button(
          'guiding-start',
          tr('Starten', 'Start'),
          rig.guider && !rig.guidingActive
              ? () => _run(
                  'guiding-start',
                  'guiding-start',
                  ask: (
                    tr('Guiding starten?', 'Start guiding?'),
                    tr(
                      'Mit der gespeicherten Kalibrierung – eine erzwungene Kalibrierung hängt mit dem MGEN-3, Bortle verlangt sie deshalb nie.',
                      'With the stored calibration – a forced calibration hangs the MGEN-3, so Bortle never asks for one.',
                    ),
                    tr('Starten', 'Start'),
                  ),
                )
              : null,
          primary: true,
        ),
        _button(
          'guiding-stop',
          tr('Stoppen', 'Stop'),
          rig.guidingActive
              ? () => _run(
                  'guiding-stop',
                  'guiding-stop',
                  ask: (
                    tr('Guiding stoppen?', 'Stop guiding?'),
                    tr(
                      'Läuft eine Sequenz, werden ihre Aufnahmen ohne Guiding wahrscheinlich unbrauchbar.',
                      'If a sequence runs, its exposures will likely be useless without guiding.',
                    ),
                    tr('Stoppen', 'Stop'),
                  ),
                )
              : null,
        ),
      ]),
      if (!rig.guider) _note(tr('Der Guider ist nicht verbunden.', 'The guider is not connected.')),
    ],
  );

  // --- sequence --------------------------------------------------------------------

  Widget _sequenceBody(RigState rig, Tones tones) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _row([
        _button(
          'sequence-start',
          tr('Starten', 'Start'),
          !rig.sequenceRunning
              ? () => _run(
                  'sequence-start',
                  'sequence-start',
                  ask: (
                    tr('Sequenz starten?', 'Start the sequence?'),
                    tr(
                      'NINA startet die geladene Sequenz – mit allem, was darin steht: Kühlen, Schwenken, Zentrieren, Guiding, Autofokus.',
                      'NINA starts the loaded sequence – with everything in it: cooling, slewing, centring, guiding, autofocus.',
                    ),
                    tr('Starten', 'Start'),
                  ),
                )
              : null,
          primary: true,
        ),
        _button(
          'sequence-stop',
          tr('Anhalten', 'Stop'),
          rig.sequenceRunning
              ? () => _run(
                  'sequence-stop',
                  'sequence-stop',
                  ask: (
                    tr('Sequenz anhalten?', 'Stop the sequence?'),
                    tr(
                      'NINA hält an, die Montierung bleibt, wo sie ist, und führt weiter nach. Nichts wird geparkt.',
                      'NINA stops; the mount stays where it is and keeps tracking. Nothing is parked.',
                    ),
                    tr('Anhalten', 'Stop'),
                  ),
                )
              : null,
        ),
      ]),
      _note(
        tr(
          'Die Nacht beenden (parken, aufwärmen, entwickeln) geht über „Übersicht“.',
          'Ending the night (park, warm up, develop) is under “Overview”.',
        ),
      ),
    ],
  );

  static Widget _redAware(Tones tones, Widget child) => !tones.red
      ? child
      : ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            .3, .4, .1, 0, 0, //
            0, 0, 0, 0, 0,
            0, 0, 0, 0, 0,
            0, 0, 0, 1, 0,
          ]),
          child: child,
        );
}

/// HFR over focuser position, the measured points only: no fit is drawn that NINA
/// did not report.
class _FocusCurve extends CustomPainter {
  _FocusCurve(this.points, this.color, this.axis);

  final List<FocusPoint> points;
  final Color color;
  final Color axis;

  @override
  void paint(Canvas canvas, Size size) {
    final xs = points.map((p) => p.position);
    final ys = points.map((p) => p.hfr);
    final x0 = xs.reduce(math.min), x1 = xs.reduce(math.max);
    final y0 = 0.0, y1 = ys.reduce(math.max) * 1.1;
    Offset at(FocusPoint p) => Offset(
      x1 == x0 ? size.width / 2 : (p.position - x0) / (x1 - x0) * (size.width - 12) + 6,
      size.height - 6 - (p.hfr - y0) / (y1 - y0 == 0 ? 1 : y1 - y0) * (size.height - 12),
    );
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      Paint()
        ..color = axis
        ..strokeWidth = 1,
    );
    final sorted = [...points]..sort((a, b) => a.position.compareTo(b.position));
    final path = Path()..moveTo(at(sorted.first).dx, at(sorted.first).dy);
    for (final p in sorted.skip(1)) {
      path.lineTo(at(p).dx, at(p).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: .5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    for (final p in sorted) {
      canvas.drawCircle(at(p), 4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_FocusCurve old) => old.points != points || old.color != color;
}
