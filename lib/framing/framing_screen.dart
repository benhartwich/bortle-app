// Framing: the survey picture of a target with the camera's field on it, turned and
// shifted until the frame is the one wanted, then handed to NINA's framing assistant.
// The picture and the field are the ones the Plan tab shows (GET /plan/preview); the
// operations are NINA's own, through POST /nina/control, as the cockpit's framing panel
// (services/cockpit/web/components/rig/framing-panel.tsx) calls them.
//
// Kept from the cockpit:
// - coordinates are J2000, like every target coordinate in Bortle; the mount's JNow
//   readout is not shown next to them;
// - every action first pushes the frame with `framing-set`, then reports what NINA
//   answered, never what was asked for; a refusal is shown in the server's words;
// - the measured framing angle comes from solved frames (GET /plan/framing) or from
//   "determine rotation" (an exposure and a solve) – an unknown angle is not 0;
// - anything that moves the mount asks first. Safety (park, limits, flips) stays NINA's.

import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../api/bortle_client.dart';
import '../api/models.dart';
import '../design.dart';
import '../l10n.dart';
import '../rig/rig_models.dart';
import '../widgets.dart';
import 'framing_math.dart';
import 'framing_painter.dart';

class FramingScreen extends StatefulWidget {
  const FramingScreen({
    required this.client,
    required this.target,
    this.raDeg,
    this.decDeg,
    this.rotationDeg,
    super.key,
  });

  final BortleClient client;

  /// The object's name; resolved by the server for the picture and the field.
  final String target;

  /// Start the frame here (J2000) instead of at the object's catalogue position.
  final double? raDeg;
  final double? decDeg;

  /// Start the frame turned by this angle (degrees east of north) instead of the measured one.
  final double? rotationDeg;

  @override
  State<FramingScreen> createState() => _FramingScreenState();
}

/// The survey picture on screen and the sky it covers.
class _Picture {
  const _Picture(this.path, this.ra, this.dec, this.widthDeg, this.heightDeg);

  final String path;
  final double ra;
  final double dec;
  final double widthDeg;
  final double heightDeg;
}

class _FramingScreenState extends State<FramingScreen> {
  ObjectPreview? _preview;
  Object? _previewError;
  MeasuredFraming? _measured;
  _Picture? _picture;
  Future<Uint8List>? _image;

  RigState? _rig;
  String? _rigError;
  Timer? _timer;

  double? _ra;
  double? _dec;
  double _rotation = 0;
  bool _rotationTouched = false;
  int _step = 5;

  /// The operation running right now; every other button waits for it.
  String? _busy;
  String? _message;
  bool _messageIsError = false;

  /// What "determine rotation" measured last, degrees east of north.
  double? _determined;

  @override
  void initState() {
    super.initState();
    _ra = widget.raDeg;
    _dec = widget.decDeg;
    if (widget.rotationDeg != null) {
      _rotation = wrapAngle(widget.rotationDeg!);
      _rotationTouched = true;
    }
    _loadPreview();
    _loadMeasured();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    try {
      final p = await widget.client.preview(widget.target);
      if (!mounted) return;
      setState(() {
        _preview = p;
        _previewError = null;
        _ra ??= p.raDeg;
        _dec ??= p.decDeg;
        if (!_rotationTouched && _measured?.angle == null && p.positionAngleDeg != null) {
          _rotation = wrapAngle(p.positionAngleDeg!);
        }
        _picture = _Picture(p.imagePath, p.raDeg, p.decDeg, p.imageWidthDeg, p.imageHeightDeg);
        _image = widget.client.previewImage(p.imagePath)..ignore();
      });
      _followFrame();
    } on BortleError catch (e) {
      if (mounted) setState(() => _previewError = e);
    }
  }

  Future<void> _loadMeasured() async {
    try {
      final m = MeasuredFraming.fromJson(await widget.client.planFraming(widget.target));
      if (!mounted) return;
      setState(() {
        _measured = m;
        if (!_rotationTouched && m.angle != null) _rotation = wrapAngle(m.angle!);
      });
    } on BortleError {
      // the angle is a help; without it the frame starts level and says so
    }
  }

  Future<void> _poll() async {
    try {
      final rig = RigState.fromJson(await widget.client.rigLive());
      if (mounted) {
        setState(() {
          _rig = rig;
          _rigError = null;
        });
      }
    } on BortleError catch (e) {
      if (mounted) setState(() => _rigError = e.message);
    }
  }

  /// The angle "Zurücksetzen" goes back to: the one asked for, else the measured one.
  double get _startRotation => wrapAngle(widget.rotationDeg ?? _measured?.angle ?? _preview?.positionAngleDeg ?? 0);

  void _setRotation(double value) => setState(() {
    _rotation = wrapAngle(value);
    _rotationTouched = true;
  });

  void _nudge(double east, double north) {
    final ra = _ra, dec = _dec;
    if (ra == null || dec == null) return;
    final (r, d) = nudgeCentre(ra, dec, eastArcmin: east, northArcmin: north);
    setState(() {
      _ra = r;
      _dec = d;
    });
    _followFrame();
  }

  void _resetCentre() {
    setState(() {
      _ra = widget.raDeg ?? _preview?.raDeg;
      _dec = widget.decDeg ?? _preview?.decDeg;
    });
    _followFrame();
  }

  /// When the frame wanders towards the picture's edge, fetch the sky around it instead.
  void _followFrame() {
    final pic = _picture, ra = _ra, dec = _dec;
    if (pic == null || ra == null || dec == null) return;
    final (x, y) = offsetOnPicture(
      raDeg: ra,
      decDeg: dec,
      ra0: pic.ra,
      dec0: pic.dec,
      widthDeg: pic.widthDeg,
      heightDeg: pic.heightDeg,
    );
    if (x.abs() <= .3 && y.abs() <= .3) return;
    String f(double v) => v.toStringAsFixed(4);
    final path =
        '/plan/preview/image?ra=${f(ra)}&dec=${f(dec)}&width_deg=${f(pic.widthDeg)}&height_deg=${f(pic.heightDeg)}'
        '&survey=dss2';
    setState(() {
      _picture = _Picture(path, ra, dec, pic.widthDeg, pic.heightDeg);
      _image = widget.client.previewImage(path)..ignore();
    });
  }

  // --- talking to NINA -------------------------------------------------------------

  void _say(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _messageIsError = error;
    });
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// One control action; a refusal is said in the server's words and ends the flow.
  Future<Map?> _control(String action, Map<String, Object?> params, {Duration? timeout}) async {
    try {
      return await widget.client.rigControl(action, params, timeout: timeout);
    } on BortleError catch (e) {
      _say('$action: ${e.message}', error: true);
      return null;
    }
  }

  Map<String, Object?> get _frame => {'ra_deg': _ra, 'dec_deg': _dec, 'rotation_deg': _rotation};

  Future<void> _busyWith(String key, Future<void> Function() body) async {
    setState(() => _busy = key);
    try {
      await body();
    } finally {
      if (mounted) setState(() => _busy = null);
      await _poll();
    }
  }

  Future<void> _slew() async {
    final running = _rig?.sequenceRunning ?? false;
    final ok = await confirm(
      context,
      tr('Schwenken & zentrieren?', 'Slew & centre?'),
      [
        tr(
          'Die Montierung fährt zu ${formatRa(_ra!)} ${formatDec(_dec!)}, NINA nimmt ein Bild auf, löst es und korrigiert, bis der Rahmen sitzt.',
          'The mount moves to ${formatRa(_ra!)} ${formatDec(_dec!)}; NINA takes a frame, solves it and corrects until the frame sits.',
        ),
        if (running)
          tr(
            'Eine Sequenz läuft gerade – der Schwenk unterbricht ihre Aufnahmen.',
            'A sequence is running – the slew interrupts its exposures.',
          ),
      ].join('\n\n'),
      tr('Schwenken', 'Slew'),
    );
    if (!ok || !mounted) return;
    await _busyWith('slew', () async {
      if (await _control('framing-set', _frame) == null) return;
      if (await _control('framing-slew', {'center': true}, timeout: const Duration(minutes: 5)) == null) return;
      _say(tr('NINA hat geschwenkt und zentriert.', 'NINA slewed and centred.'));
    });
  }

  Future<void> _sequenceTarget() => _busyWith('sequence', () async {
    if (await _control('framing-set', _frame) == null) return;
    if (await _control('framing-set-sequence-target', {'name': widget.target, ..._frame}) == null) return;
    _say(
      tr(
        'NINA hat „${widget.target}“ als Sequenzziel übernommen.',
        'NINA took “${widget.target}” as the sequence target.',
      ),
    );
  });

  Future<void> _determineRotation() => _busyWith('rotation', () async {
    final result = await _control('framing-determine-rotation', const {}, timeout: const Duration(minutes: 3));
    if (result == null) return;
    // NINA leaves the solved angle on its framing assistant; /nina/framing reads it back
    // with NINA's internal flip undone. A number in the answer itself is taken as well.
    double? angle = result['result'] is num ? (result['result'] as num).toDouble() : null;
    try {
      final read = await widget.client.ninaFraming();
      if (read['rotation_deg'] is num) angle = (read['rotation_deg'] as num).toDouble();
    } on BortleError catch (e) {
      if (angle == null) {
        _say(
          tr(
            'Gemessen, aber der Winkel ließ sich nicht lesen: ${e.message}',
            'Measured, but the angle could not be read: ${e.message}',
          ),
          error: true,
        );
        return;
      }
    }
    if (angle == null) {
      _say(
        tr('NINA hat gemessen, aber keinen Winkel zurückgegeben.', 'NINA measured but returned no angle.'),
        error: true,
      );
      return;
    }
    final measured = wrapAngle(angle);
    setState(() {
      _determined = measured;
      _rotation = measured;
      _rotationTouched = true;
    });
    _say(
      tr(
        'Kamera steht bei ${decimal(measured, 1)}° – der Rahmen ist jetzt so gedreht.',
        'The camera sits at ${decimal(measured, 1)}° – the frame is turned to match.',
      ),
    );
  });

  /// Why the mount cannot be slewed right now; null when it can.
  String? get _slewBlocked {
    if (_ra == null || _dec == null) return tr('Noch keine Koordinaten.', 'No coordinates yet.');
    if (_rigError != null) {
      return tr('Zustand der Montierung unbekannt: $_rigError', 'Mount state unknown: $_rigError');
    }
    final rig = _rig;
    if (rig == null) return tr('Lese den Zustand der Montierung …', 'Reading the mount state …');
    if (!rig.reachable) return tr('NINA antwortet gerade nicht.', 'NINA is not answering.');
    if (!rig.mount.connected) return tr('Die Montierung ist nicht verbunden.', 'The mount is not connected.');
    if (rig.mount.atPark) {
      return tr('Die Montierung ist geparkt – erst entparken.', 'The mount is parked – unpark it first.');
    }
    if (rig.mount.slewing) return tr('Die Montierung schwenkt gerade.', 'The mount is slewing right now.');
    return null;
  }

  /// Why NINA cannot take the frame or measure; null when it can.
  String? get _ninaBlocked {
    if (_rigError != null) return _rigError;
    final rig = _rig;
    if (rig == null) return tr('Lese den Zustand von NINA …', 'Reading NINA’s state …');
    if (!rig.reachable) return tr('NINA antwortet gerade nicht.', 'NINA is not answering.');
    return null;
  }

  // --- the view ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Einrahmen · ${widget.target}', 'Framing · ${widget.target}'))),
      body: ListView(
        key: const Key('framing'),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          _pictureCard(context),
          const SizedBox(height: 8),
          if (_ra != null && _dec != null)
            Text(
              '${formatRa(_ra!)}  ${formatDec(_dec!)}  ·  ${_rotation.round()}°  (J2000)',
              key: const Key('framing-coords'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontWeight: FontWeight.w600),
            ),
          const SizedBox(height: 12),
          _rotationCard(context),
          const SizedBox(height: 12),
          _nudgeCard(context),
          const SizedBox(height: 12),
          _actionsCard(context),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _message!,
                key: const Key('framing-message'),
                style: TextStyle(color: _messageIsError ? tones.danger : tones.good),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pictureCard(BuildContext context) {
    final tones = context.tones;
    final p = _preview;
    final pic = _picture;
    if (p == null || pic == null) {
      return Card(
        child: SizedBox(
          height: 220,
          child: _previewError != null
              ? LoadError(_previewError!, onRetry: _loadPreview)
              : const Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final fov = p.fovArcmin;
    final (dx, dy) = offsetOnPicture(
      raDeg: _ra ?? pic.ra,
      decDeg: _dec ?? pic.dec,
      ra0: pic.ra,
      dec0: pic.dec,
      widthDeg: pic.widthDeg,
      heightDeg: pic.heightDeg,
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: pic.widthDeg / pic.heightDeg,
            child: FutureBuilder<Uint8List>(
              future: _image,
              builder: (context, snap) => Stack(
                key: const Key('framing-picture'),
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.black),
                  if (snap.hasData)
                    _redAware(tones, Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true)),
                  if (snap.hasError)
                    Center(
                      child: Text(
                        tr('Himmelsbild gerade nicht verfügbar', 'Sky picture not available right now'),
                        style: TextStyle(color: tones.muted),
                      ),
                    ),
                  if (fov != null)
                    CustomPaint(
                      key: const Key('framing-fov'),
                      painter: FramingPainter(
                        widthFraction: fov.$1 / 60 / pic.widthDeg,
                        heightFraction: fov.$2 / 60 / pic.heightDeg,
                        offsetX: dx,
                        offsetY: dy,
                        positionAngleDeg: _rotation,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  Positioned(
                    left: 8,
                    top: 6,
                    child: Text('N ↑   ${tr('O', 'E')} ←', style: TextStyle(color: tones.muted, fontSize: 11)),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (fov == null)
                  Text(
                    tr(
                      'Ohne Brennweite und Kamera im Profil kann Bortle kein Bildfeld zeigen – trag sie im Web unter Equipment ein.',
                      'Without focal length and camera in your profile Bortle cannot show a field – add them on the web under Equipment.',
                    ),
                    key: const Key('framing-no-optics'),
                    style: TextStyle(color: tones.warn),
                  ),
                if (p.credit != null) Text(p.credit!, style: TextStyle(color: tones.muted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rotationCard(BuildContext context) {
    final tones = context.tones;
    final measured = _measured?.angle;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Drehung', 'Rotation'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${_rotation.round()}°',
                  key: const Key('framing-rotation-value'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            Row(
              children: [
                IconButton(
                  key: const Key('framing-rotation-minus'),
                  tooltip: '−1°',
                  onPressed: () => _setRotation(_rotation.roundToDouble() - 1),
                  icon: const Icon(Icons.remove),
                ),
                Expanded(
                  child: Slider(
                    key: const Key('framing-rotation'),
                    min: 0,
                    max: 360,
                    divisions: 360,
                    value: _rotation.clamp(0, 360),
                    label: '${_rotation.round()}°',
                    onChanged: (v) => _setRotation(v.roundToDouble()),
                  ),
                ),
                IconButton(
                  key: const Key('framing-rotation-plus'),
                  tooltip: '+1°',
                  onPressed: () => _setRotation(_rotation.roundToDouble() + 1),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    measured != null
                        ? tr(
                            'Gemessen aus ${_measured!.frames} gelösten Bildern: ${decimal(measured, 1)}°',
                            'Measured from ${_measured!.frames} solved frames: ${decimal(measured, 1)}°',
                          )
                        : tr(
                            'Drehwinkel noch nicht gemessen – erst ein gelöstes Bild sagt, wie die Kamera steht.',
                            'Rotation not measured yet – only a solved frame says how the camera sits.',
                          ),
                    key: const Key('framing-measured'),
                    style: TextStyle(color: tones.muted, fontSize: 12),
                  ),
                ),
                TextButton(
                  key: const Key('framing-rotation-reset'),
                  onPressed: () => setState(() {
                    _rotation = _startRotation;
                    _rotationTouched = widget.rotationDeg != null;
                  }),
                  child: Text(tr('Zurücksetzen', 'Reset')),
                ),
              ],
            ),
            if (_determined != null)
              Text(
                tr(
                  'Drehung bestimmt: ${decimal(_determined!, 1)}°',
                  'Rotation determined: ${decimal(_determined!, 1)}°',
                ),
                key: const Key('framing-determined'),
                style: TextStyle(color: tones.good, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
    );
  }

  Widget _nudgeCard(BuildContext context) {
    Widget arrow(String key, IconData icon, String tip, double east, double north) => IconButton.outlined(
      key: Key('framing-nudge-$key'),
      tooltip: tip,
      iconSize: 30,
      onPressed: _ra == null ? null : () => _nudge(east, north),
      icon: Icon(icon),
    );
    final s = _step.toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Verschieben', 'Shift'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final step in framingStepsArcmin)
                  ChoiceChip(
                    key: Key('framing-step-$step'),
                    label: Text('$step′'),
                    selected: _step == step,
                    onSelected: (_) => setState(() => _step = step),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // laid out as the picture is: north up, east left
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [arrow('n', Icons.keyboard_arrow_up, tr('Nach Norden', 'North'), 0, s)],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 8,
              children: [
                arrow('e', Icons.keyboard_arrow_left, tr('Nach Osten', 'East'), s, 0),
                IconButton(
                  key: const Key('framing-centre-reset'),
                  tooltip: tr('Zurück aufs Objekt', 'Back to the object'),
                  onPressed: _resetCentre,
                  icon: const Icon(Icons.center_focus_strong_outlined),
                ),
                arrow('w', Icons.keyboard_arrow_right, tr('Nach Westen', 'West'), -s, 0),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [arrow('s', Icons.keyboard_arrow_down, tr('Nach Süden', 'South'), 0, -s)],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionsCard(BuildContext context) {
    final tones = context.tones;
    final slewBlocked = _slewBlocked;
    final ninaBlocked = _ninaBlocked;
    final hasFrame = _ra != null && _dec != null;
    final idle = _busy == null;
    final style = ButtonStyle(minimumSize: WidgetStateProperty.all(const Size.fromHeight(52)));
    Widget label(String key, String text, String busyText) =>
        Text(_busy == key ? busyText : text, style: const TextStyle(fontSize: 15));
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              key: const Key('framing-slew'),
              style: style,
              onPressed: idle && slewBlocked == null ? _slew : null,
              child: label('slew', tr('Schwenken & zentrieren', 'Slew & centre'), tr('Schwenkt …', 'Slewing …')),
            ),
            if (slewBlocked != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  slewBlocked,
                  key: const Key('framing-slew-reason'),
                  style: TextStyle(color: tones.warn, fontSize: 12),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('framing-sequence-target'),
              style: style,
              onPressed: idle && hasFrame && ninaBlocked == null ? _sequenceTarget : null,
              child: label('sequence', tr('Als Sequenzziel', 'As sequence target'), '…'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('framing-determine-rotation'),
              style: style,
              onPressed: idle && ninaBlocked == null ? _determineRotation : null,
              child: label('rotation', tr('Drehung bestimmen', 'Determine rotation'), tr('Misst …', 'Measuring …')),
            ),
            if (_busy == 'rotation') ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(key: Key('framing-rotation-progress')),
              const SizedBox(height: 4),
              Text(
                tr(
                  'NINA nimmt ein Bild auf und löst es – das dauert so lange wie Belichtung und Plate Solve.',
                  'NINA takes a frame and solves it – this takes as long as the exposure and the plate solve.',
                ),
                style: TextStyle(color: tones.muted, fontSize: 12),
              ),
            ],
            if (ninaBlocked != null && slewBlocked != ninaBlocked)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(ninaBlocked, style: TextStyle(color: tones.warn, fontSize: 12)),
              ),
            const SizedBox(height: 8),
            Text(
              tr(
                'Jede Aktion übergibt den Rahmen zuerst an NINAs Framing-Assistenten und meldet dann, was NINA geantwortet hat. „Drehung bestimmen“ nimmt ein Bild auf und löst es – der einzige ehrliche Weg zum Winkel einer manuell gedrehten Kamera.',
                'Every action first hands the frame to NINA’s framing assistant, then reports what NINA answered. “Determine rotation” takes a frame and solves it – the only honest way to the angle of a manually turned camera.',
              ),
              style: TextStyle(color: tones.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

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
