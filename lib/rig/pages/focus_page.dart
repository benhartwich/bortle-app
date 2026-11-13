// Rig › Fokus: steps and absolute moves after one permission per visit, NINA's
// autofocus, and the measured points of the last run.

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../api/bortle_client.dart';
import '../../design.dart';
import '../../l10n.dart';
import '../../widgets.dart';
import '../rig_models.dart';
import '../rig_session.dart';
import 'common.dart';

/// Relative focuser steps, as the cockpit's focus page offers them.
const focusSteps = [-1000, -100, -10, 10, 100, 1000];

class FocusPage extends StatefulWidget {
  const FocusPage({required this.session, required this.rig, super.key});

  final RigSession session;
  final RigState rig;

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  AutofocusLive? _af;
  bool _focusArmed = false;
  final _focusTarget = TextEditingController();

  RigSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _loadAutofocus();
  }

  @override
  void didUpdateWidget(FocusPage old) {
    super.didUpdateWidget(old);
    // a new snapshot: while an autofocus runs, its points come along
    if (old.rig != widget.rig && _af != null && (_af!.running || _s.busy == 'autofocus')) _loadAutofocus();
  }

  @override
  void dispose() {
    _focusTarget.dispose();
    super.dispose();
  }

  Future<void> _loadAutofocus() async {
    try {
      final af = AutofocusLive.fromJson(await _s.client.rigAutofocusLive());
      if (mounted) setState(() => _af = af);
    } on BortleError catch (e) {
      if (mounted) RigSession.say(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final f = widget.rig.focuser;
    final af = _af;
    final afRunning = af?.running ?? false;
    final canMove = f.connected && !f.moving && !afRunning && f.position != null;
    final points = af == null ? const <FocusPoint>[] : (af.running ? af.points : af.lastPoints);
    return RigPageList(
      session: _s,
      children: [
        if (!f.connected) RigStatus(tr('nicht verbunden', 'not connected')),
        RigStatus(
          [
            tr('Position ${f.position ?? '–'}', 'Position ${f.position ?? '–'}'),
            if (f.moving) tr('fährt', 'moving'),
            if (f.temperature != null) '${decimal(f.temperature!, 1)} °C',
          ].join(' · '),
        ),
        if (afRunning)
          RigNote(
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
                child: rigButton(
                  _s,
                  'focus-step-$delta',
                  delta > 0 ? '+$delta' : '$delta',
                  canMove ? () => _focusStep(f, delta) : null,
                ),
              ),
          ],
        ),
        rigRow([
          rigNumberField(_focusTarget, tr('Position', 'Position'), 'focus-target'),
          rigButton(_s, 'focus-move', tr('Fahren', 'Move'), canMove ? () => _focusAbsolute(f) : null),
        ]),
        rigRow([
          rigButton(
            _s,
            'autofocus',
            tr('Autofokus', 'Autofocus'),
            f.connected && !afRunning
                ? () => _s.run(
                    context,
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
          rigButton(
            _s,
            'focus-stop',
            tr('Stopp', 'Stop'),
            f.connected && f.moving ? () => _s.run(context, 'focus-stop', 'focus-stop') : null,
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
            RigNote(
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
    if (!_focusArmed || !mounted) return;
    if ((f.position ?? 0) + delta < 0) {
      RigSession.say(context, tr('Unter Position 0 fährt kein Fokussierer.', 'No focuser moves below position 0.'));
      return;
    }
    await _s.run(context, 'focus-step-$delta', 'focus-step', params: {'steps': delta});
  }

  Future<void> _focusAbsolute(FocuserState f) async {
    final target = parseNumber(_focusTarget.text)?.round();
    if (target == null || target < 0) {
      RigSession.say(context, tr('Bitte eine Position ab 0.', 'Please a position from 0.'));
      return;
    }
    await _armFocus();
    if (!_focusArmed || !mounted) return;
    await _s.run(
      context,
      'focus-move',
      'focuser-move',
      params: {'position': target},
      timeout: const Duration(seconds: 120),
    );
  }
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
