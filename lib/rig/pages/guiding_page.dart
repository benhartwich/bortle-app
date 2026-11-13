// Rig › Guiding: start with the stored calibration, stop after asking.

import 'package:material_ui/material_ui.dart';

import '../../l10n.dart';
import '../rig_models.dart';
import '../rig_session.dart';
import 'common.dart';

class GuidingPage extends StatelessWidget {
  const GuidingPage({required this.session, required this.rig, super.key});

  final RigSession session;
  final RigState rig;

  @override
  Widget build(BuildContext context) => RigPageList(
    session: session,
    children: [
      RigStatus(
        rig.guidingActive
            ? (rig.rmsTotal == null
                  ? tr('Guiding läuft', 'Guiding')
                  : tr(
                      'Guiding läuft · RMS ${decimal(rig.rmsTotal!, 2)}″',
                      'Guiding · RMS ${decimal(rig.rmsTotal!, 2)}″',
                    ))
            : tr('Guiding aus', 'Guiding off'),
      ),
      rigRow([
        rigButton(
          session,
          'guiding-start',
          tr('Starten', 'Start'),
          rig.guider && !rig.guidingActive
              ? () => session.run(
                  context,
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
        rigButton(
          session,
          'guiding-stop',
          tr('Stoppen', 'Stop'),
          rig.guidingActive
              ? () => session.run(
                  context,
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
      if (!rig.guider) RigNote(tr('Der Guider ist nicht verbunden.', 'The guider is not connected.')),
    ],
  );
}
