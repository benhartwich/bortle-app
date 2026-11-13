// Rig › Sequenz: start and stop NINA's loaded sequence, after asking.

import 'package:material_ui/material_ui.dart';

import '../../l10n.dart';
import '../rig_models.dart';
import '../rig_session.dart';
import 'common.dart';

class SequencePage extends StatelessWidget {
  const SequencePage({required this.session, required this.rig, super.key});

  final RigSession session;
  final RigState rig;

  @override
  Widget build(BuildContext context) => RigPageList(
    session: session,
    children: [
      RigStatus(rig.sequenceRunning ? tr('Sequenz läuft', 'Sequence running') : tr('Sequenz steht', 'Sequence idle')),
      rigRow([
        rigButton(
          session,
          'sequence-start',
          tr('Starten', 'Start'),
          !rig.sequenceRunning
              ? () => session.run(
                  context,
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
        rigButton(
          session,
          'sequence-stop',
          tr('Anhalten', 'Stop'),
          rig.sequenceRunning
              ? () => session.run(
                  context,
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
      RigNote(
        tr(
          'Die Nacht beenden (parken, aufwärmen, entwickeln) geht über „Übersicht“.',
          'Ending the night (park, warm up, develop) is under “Overview”.',
        ),
      ),
    ],
  );
}
