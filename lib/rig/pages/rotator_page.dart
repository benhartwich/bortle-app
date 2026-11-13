// Rig › Rotator, shown only when the rig has one: its angle, and a move after asking.

import 'package:material_ui/material_ui.dart';

import '../../l10n.dart';
import '../rig_models.dart';
import '../rig_session.dart';
import 'common.dart';

class RotatorPage extends StatefulWidget {
  const RotatorPage({required this.session, required this.rig, super.key});

  final RigSession session;
  final RigState rig;

  @override
  State<RotatorPage> createState() => _RotatorPageState();
}

class _RotatorPageState extends State<RotatorPage> {
  final _target = TextEditingController();

  RigSession get _s => widget.session;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rig.rotator;
    return RigPageList(
      session: _s,
      children: [
        RigStatus(
          !r.connected
              ? tr('nicht verbunden', 'not connected')
              : [
                  if (r.position != null) tr('Winkel ${decimal(r.position!, 1)}°', 'angle ${decimal(r.position!, 1)}°'),
                  if (r.mechanical != null)
                    tr('mechanisch ${decimal(r.mechanical!, 1)}°', 'mechanical ${decimal(r.mechanical!, 1)}°'),
                  if (r.moving) tr('dreht', 'moving'),
                ].join(' · '),
        ),
        if (r.name != null) RigNote(r.name!),
        rigRow([
          rigNumberField(_target, tr('Winkel', 'Angle'), 'rotator-target', suffix: '°'),
          rigButton(_s, 'rotator-move', tr('Drehen', 'Rotate'), r.connected && !r.moving ? _move : null),
        ]),
        RigNote(
          tr(
            'Der Winkel ist NINAs Himmelswinkel des Rotators. Läuft eine Sequenz, verdreht das ihr Bildfeld.',
            'The angle is NINA’s sky angle of the rotator. If a sequence runs, this turns its field.',
          ),
        ),
      ],
    );
  }

  Future<void> _move() async {
    final angle = parseNumber(_target.text);
    if (angle == null || angle < 0 || angle >= 360) {
      RigSession.say(context, tr('Bitte einen Winkel von 0 bis 360°.', 'Please an angle from 0 to 360°.'));
      return;
    }
    await _s.run(
      context,
      'rotator-move',
      'rotator-move',
      params: {'position': angle},
      ask: (
        tr('Rotator auf ${decimal(angle, 1)}° drehen?', 'Turn the rotator to ${decimal(angle, 1)}°?'),
        tr('Kabel am Rotator im Blick behalten.', 'Keep an eye on the cables at the rotator.'),
        tr('Drehen', 'Rotate'),
      ),
      timeout: const Duration(seconds: 120),
    );
  }
}
