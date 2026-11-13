// Rig › Kamera: cooling to Bortle's derived setpoint, warming, and a test exposure that
// is a look, not a measurement.

import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../api/bortle_client.dart';
import '../../design.dart';
import '../../l10n.dart';
import '../rig_models.dart';
import '../rig_session.dart';
import 'common.dart';

/// The test exposure's range; the server refuses anything outside it as well.
const maxTestExposureS = 120.0;

class CameraPage extends StatefulWidget {
  const CameraPage({required this.session, required this.rig, super.key});

  final RigSession session;
  final RigState rig;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  FilterWheel? _filters;
  CoolingAdvice? _cooling;
  Uint8List? _capture;
  String? _captureNote;

  final _coolTemp = TextEditingController();
  final _coolMinutes = TextEditingController(text: '10');
  final _exposure = TextEditingController(text: '5');
  final _gain = TextEditingController();

  RigSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _fillGain();
    _loadCooling();
    _loadFilters();
  }

  @override
  void didUpdateWidget(CameraPage old) {
    super.didUpdateWidget(old);
    _fillGain();
  }

  void _fillGain() {
    final gain = widget.rig.camera.gain;
    if (_gain.text.isEmpty && gain != null) _gain.text = '$gain';
  }

  @override
  void dispose() {
    for (final c in [_coolTemp, _coolMinutes, _exposure, _gain]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadFilters() async {
    try {
      final wheel = FilterWheel.fromJson(await _s.client.rigFilters());
      if (mounted) setState(() => _filters = wheel);
    } on BortleError catch (e) {
      if (mounted) RigSession.say(context, e.message);
    }
  }

  Future<void> _loadCooling() async {
    try {
      final advice = CoolingAdvice.fromJson(await _s.client.rigCooling());
      if (!mounted) return;
      setState(() {
        _cooling = advice;
        if (_coolTemp.text.isEmpty && advice.setpoint != null) _coolTemp.text = decimal(advice.setpoint!, 0);
      });
    } on BortleError catch (e) {
      if (mounted) RigSession.say(context, e.message);
    }
  }

  static String summary(CameraState c) {
    if (!c.connected) return tr('nicht verbunden', 'not connected');
    return [
      if (c.temperature != null) '${decimal(c.temperature!, 1)} °C',
      if (c.coolerOn == true && c.coolerPower != null)
        tr('Kühler ${c.coolerPower!.round()} %', 'cooler ${c.coolerPower!.round()} %'),
      if (c.gain != null) 'Gain ${c.gain}',
      if (c.exposing) tr('belichtet', 'exposing'),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final c = widget.rig.camera;
    final advice = _cooling;
    return RigPageList(
      session: _s,
      children: [
        RigStatus(summary(c)),
        RigHeading(tr('Kühlung', 'Cooling')),
        if (c.targetTemp != null)
          RigNote(
            tr('Sollwert in NINA: ${decimal(c.targetTemp!, 0)} °C', 'NINA’s setpoint: ${decimal(c.targetTemp!, 0)} °C'),
          ),
        if (advice?.setpoint != null)
          RigNote(
            tr(
              'Bortles Vorschlag: ${decimal(advice!.setpoint!, 0)} °C – ${advice.reason ?? ''}',
              'Bortle suggests ${decimal(advice.setpoint!, 0)} °C – ${advice.reason ?? ''}',
            ),
          ),
        for (final w in advice?.warnings ?? const <String>[]) RigNote('⚠ $w'),
        rigRow([
          rigNumberField(_coolTemp, tr('Ziel', 'Target'), 'cool-temp', suffix: '°C'),
          rigNumberField(_coolMinutes, tr('Dauer', 'Duration'), 'cool-minutes', suffix: 'min'),
        ]),
        rigRow([
          rigButton(_s, 'cool', tr('Kühlen', 'Cool'), c.connected ? _cool : null, primary: true),
          rigButton(
            _s,
            'warm',
            tr('Aufwärmen', 'Warm up'),
            c.connected
                ? () => _s.run(
                    context,
                    'warm',
                    'warm',
                    params: {'minutes': parseNumber(_coolMinutes.text) ?? 10},
                    ask: (
                      tr('Kamera aufwärmen?', 'Warm the camera?'),
                      tr('Das beendet die Kühlung.', 'This ends the cooling.'),
                      tr('Aufwärmen', 'Warm up'),
                    ),
                  )
                : null,
          ),
        ]),
        RigHeading(tr('Testaufnahme', 'Test exposure')),
        RigNote(
          tr(
            'Filter: ${_filters?.current ?? '–'} (wechseln unter „Filter“). Ein Blick, keine Messung – die Aufnahme geht nicht in NINAs Bildverlauf.',
            'Filter: ${_filters?.current ?? '–'} (change it under “Filter”). A look, not a measurement – it does not enter NINA’s image history.',
          ),
        ),
        rigRow([
          rigNumberField(_exposure, tr('Belichtung', 'Exposure'), 'capture-exposure', suffix: 's'),
          rigNumberField(
            _gain,
            c.gainMin != null && c.gainMax != null ? 'Gain ${c.gainMin}–${c.gainMax}' : 'Gain',
            'capture-gain',
          ),
        ]),
        rigRow([
          rigButton(_s, 'capture', tr('Belichten', 'Expose'), c.connected ? () => _captureNow(c) : null, primary: true),
          rigButton(
            _s,
            'abort-exposure',
            tr('Abbrechen', 'Abort'),
            c.connected && c.exposing ? () => _s.run(context, 'abort-exposure', 'abort-exposure') : null,
          ),
        ]),
        if (_captureNote != null) RigNote(_captureNote!),
        if (_capture != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Sky.radius),
              child: InteractiveViewer(
                maxScale: 6,
                child: redAware(tones, Image.memory(_capture!, key: const Key('capture-image'), fit: BoxFit.contain)),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _cool() async {
    final temperature = parseNumber(_coolTemp.text);
    final minutes = parseNumber(_coolMinutes.text) ?? 10;
    if (temperature == null || temperature < -40 || temperature > 20) {
      RigSession.say(context, tr('Bitte ein Ziel zwischen −40 und 20 °C.', 'Please a target between −40 and 20 °C.'));
      return;
    }
    if (minutes < 0 || minutes > 60) {
      RigSession.say(context, tr('Die Dauer liegt zwischen 0 und 60 min.', 'The duration is between 0 and 60 min.'));
      return;
    }
    await _s.run(
      context,
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
    final seconds = parseNumber(_exposure.text);
    if (seconds == null || seconds < 0 || seconds > maxTestExposureS) {
      RigSession.say(context, tr('Eine Testaufnahme dauert 0 bis 120 s.', 'A test exposure runs 0 to 120 s.'));
      return;
    }
    final gain = parseNumber(_gain.text)?.round();
    if (gain != null && ((c.gainMin != null && gain < c.gainMin!) || (c.gainMax != null && gain > c.gainMax!))) {
      RigSession.say(
        context,
        tr('Gain außerhalb von ${c.gainMin}–${c.gainMax}.', 'Gain outside ${c.gainMin}–${c.gainMax}.'),
      );
      return;
    }
    final result = await _s.run(
      context,
      'capture',
      'capture',
      params: {'duration': seconds, 'gain': ?gain},
      timeout: Duration(seconds: seconds.ceil() + 90),
    );
    if (result == null) return;
    try {
      final bytes = await _s.client.rigCaptureImage();
      if (mounted) {
        setState(() {
          _capture = bytes;
          _captureNote = result['result'] is String ? result['result'] as String : null;
        });
      }
    } on BortleError catch (e) {
      if (mounted) RigSession.say(context, e.message);
    }
  }
}
