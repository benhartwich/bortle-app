// Polar alignment with the Three Point Polar Alignment plugin, at the mount with the
// phone in one hand and the alt/az screws in the other.
//
// The plugin has no REST surface: the orchestrator owns its websocket and folds the
// push stream into GET /nina/tppa, which this screen polls every 2 s while it is open
// (and only then). Start/pause/stop go through POST /nina/control as tppa-* actions.
//
// The error is shown as the plugin reports it: azimuth and altitude with their signs,
// and the total. Which screw turns which way depends on the mount, so the bubble
// shows where the error stands relative to zero – it does not claim a direction to
// turn that the plugin never said.

import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../api/bortle_client.dart';
import '../design.dart';
import '../l10n.dart';
import '../widgets.dart';
import 'rig_models.dart';

class TppaScreen extends StatefulWidget {
  const TppaScreen({required this.client, super.key});

  final BortleClient client;

  @override
  State<TppaScreen> createState() => _TppaScreenState();
}

class _TppaScreenState extends State<TppaScreen> {
  TppaState? _state;
  Object? _error;
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final state = TppaState.fromJson(await widget.client.rigTppa());
      if (!mounted) return;
      setState(() {
        _state = state;
        _error = null;
      });
    } on BortleError catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _act(String action, {(String, String, String)? ask}) async {
    if (ask != null) {
      final ok = await confirm(context, ask.$1, ask.$2, ask.$3);
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.client.rigControl(action, const {});
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr('NINA hat es angenommen.', 'NINA accepted it.'))));
    } on BortleError catch (e) {
      // the bridge's or NINA's refusal, word for word; never retried
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
      await _poll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final s = _state;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Polausrichtung', 'Polar alignment'))),
      body: s == null
          ? (_error != null ? LoadError(_error!, onRetry: _poll) : const Center(child: CircularProgressIndicator()))
          : !s.available
          ? Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                s.note ??
                    tr(
                      'Das TPPA-Plugin ist in NINA nicht geladen. Ohne das Plugin gibt es keine Einnordungsmessung – hier wird keine erfunden.',
                      'The TPPA plugin is not loaded in NINA. Without it there is no alignment measurement – none is made up here.',
                    ),
                key: const Key('tppa-unavailable'),
                textAlign: TextAlign.center,
                style: TextStyle(color: tones.muted),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _total(s, tones),
                const SizedBox(height: 16),
                AspectRatio(
                  aspectRatio: 1,
                  child: CustomPaint(
                    key: const Key('tppa-bubble'),
                    painter: _Bubble(
                      az: s.azimuthArcmin,
                      alt: s.altitudeArcmin,
                      ring: tones.muted,
                      good: tones.good,
                      warn: tones.warn,
                      bad: tones.danger,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _axis(tr('Azimut', 'Azimuth'), s.azimuthArcmin, 'tppa-az'),
                    const SizedBox(width: 8),
                    _axis(tr('Höhe', 'Altitude'), s.altitudeArcmin, 'tppa-alt'),
                  ],
                ),
                if (s.status != null || s.progress != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    [
                      ?s.status,
                      if (s.progress != null) '${(s.progress! <= 1 ? s.progress! * 100 : s.progress!).round()} %',
                    ].join(' · '),
                    style: TextStyle(color: tones.muted),
                  ),
                ],
                if (s.connectError != null) ...[
                  const SizedBox(height: 8),
                  Text(s.connectError!, style: TextStyle(color: tones.danger, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                _big(
                  'tppa-start',
                  tr('Start', 'Start'),
                  s.running
                      ? null
                      : () => _act(
                          'tppa-start',
                          ask: (
                            tr('Polausrichtung starten?', 'Start polar alignment?'),
                            tr(
                              'TPPA dreht die Montierung zwischen drei Aufnahmen in Rektaszension und misst nach jedem Schritt. Kabel im Blick behalten und währenddessen keine Sequenz starten.',
                              'TPPA rotates the mount in right ascension between three exposures and measures after each step. Watch the cables and start no sequence meanwhile.',
                            ),
                            tr('Starten', 'Start'),
                          ),
                        ),
                  primary: true,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _big(
                        'tppa-pause',
                        s.paused ? tr('Fortsetzen', 'Resume') : tr('Pause', 'Pause'),
                        s.running ? () => _act('tppa-pause') : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _big('tppa-stop', tr('Stopp', 'Stop'), s.running ? () => _act('tppa-stop') : null)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  tr(
                    'Die Werte kommen vom Plugin, mit Vorzeichen. Welche Schraube in welche Richtung dreht, hängt von der Montierung ab – der Kreis zeigt nur, wo der Fehler gegenüber null steht. Ringe: 1′, 5′, 15′.',
                    'The values come from the plugin, signed. Which screw turns which way depends on the mount – the circle only shows where the error stands relative to zero. Rings: 1′, 5′, 15′.',
                  ),
                  style: TextStyle(color: tones.muted, fontSize: 12),
                ),
              ],
            ),
    );
  }

  Widget _total(TppaState s, Tones tones) {
    final total = s.totalArcmin;
    final color = total == null
        ? tones.muted
        : total <= 1
        ? tones.good
        : total <= 5
        ? tones.warn
        : tones.danger;
    return Column(
      children: [
        Text(tr('Gesamtfehler', 'Total error'), style: TextStyle(color: tones.muted)),
        Text(
          total == null ? '–' : '${decimal(total, 2)}′',
          key: const Key('tppa-total'),
          style: TextStyle(fontSize: 44, fontWeight: FontWeight.w700, color: color),
        ),
        Text(
          s.running ? (s.paused ? tr('pausiert', 'paused') : tr('misst', 'measuring')) : tr('gestoppt', 'stopped'),
          style: TextStyle(color: tones.muted),
        ),
      ],
    );
  }

  Widget _axis(String label, double? value, String key) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: context.tones.muted, fontSize: 12)),
            Text(
              value == null ? '–' : '${value > 0 ? '+' : ''}${decimal(value, 2)}′',
              key: Key(key),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _big(String key, String label, VoidCallback? onPressed, {bool primary = false}) {
    final style = ButtonStyle(minimumSize: WidgetStateProperty.all(const Size.fromHeight(56)));
    final enabled = _busy ? null : onPressed;
    final child = Text(label, style: const TextStyle(fontSize: 16));
    return primary
        ? FilledButton(key: Key(key), style: style, onPressed: enabled, child: child)
        : OutlinedButton(key: Key(key), style: style, onPressed: enabled, child: child);
  }
}

/// Azimuth error across, altitude error up, on a square root scale so 1′ and 15′
/// both stay readable. The dot is where the error stands; zero is the centre.
class _Bubble extends CustomPainter {
  _Bubble({
    required this.az,
    required this.alt,
    required this.ring,
    required this.good,
    required this.warn,
    required this.bad,
  });

  final double? az;
  final double? alt;
  final Color ring;
  final Color good;
  final Color warn;
  final Color bad;

  static const _outer = 15.0;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 8;
    double scale(double arcmin) => math.sqrt(math.min(arcmin.abs(), _outer) / _outer) * r * arcmin.sign;
    final line = Paint()
      ..color = ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final m in [1.0, 5.0, 15.0]) {
      canvas.drawCircle(c, scale(m), line);
    }
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), line);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), line);
    if (az == null || alt == null) return;
    final total = math.sqrt(az! * az! + alt! * alt!);
    final color = total <= 1
        ? good
        : total <= 5
        ? warn
        : bad;
    canvas.drawCircle(Offset(c.dx + scale(az!), c.dy - scale(alt!)), 10, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Bubble old) => old.az != az || old.alt != alt || old.ring != ring;
}
