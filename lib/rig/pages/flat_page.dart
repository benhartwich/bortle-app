// Rig › Flatpanel, shown only when the rig has one: light, brightness and cover.

import 'package:material_ui/material_ui.dart';

import '../../l10n.dart';
import '../rig_models.dart';
import '../rig_session.dart';
import 'common.dart';

class FlatPage extends StatefulWidget {
  const FlatPage({required this.session, required this.rig, super.key});

  final RigSession session;
  final RigState rig;

  @override
  State<FlatPage> createState() => _FlatPageState();
}

class _FlatPageState extends State<FlatPage> {
  final _brightness = TextEditingController();

  RigSession get _s => widget.session;

  @override
  void dispose() {
    _brightness.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.rig.flat;
    final on = f.connected;
    return RigPageList(
      session: _s,
      children: [
        RigStatus(
          !f.connected
              ? tr('nicht verbunden', 'not connected')
              : [
                  if (f.lightOn != null) f.lightOn! ? tr('Licht an', 'light on') : tr('Licht aus', 'light off'),
                  if (f.brightness != null) tr('Helligkeit ${f.brightness}', 'brightness ${f.brightness}'),
                  ?f.coverState,
                ].join(' · '),
        ),
        if (f.name != null) RigNote(f.name!),
        if (f.supportsOnOff != false)
          rigRow([
            rigButton(
              _s,
              'flat-light-on',
              tr('Licht an', 'Light on'),
              on && f.lightOn != true
                  ? () => _s.run(
                      context,
                      'flat-light-on',
                      'flat-light',
                      params: {'on': true},
                      ask: (
                        tr('Flatpanel einschalten?', 'Switch the flat panel on?'),
                        tr(
                          'Das Licht scheint in die Optik. Läuft eine Sequenz mit Lights, sind ihre Aufnahmen damit verdorben.',
                          'The light shines into the optics. If a sequence takes lights, its exposures are spoiled.',
                        ),
                        tr('Einschalten', 'Switch on'),
                      ),
                    )
                  : null,
              primary: true,
            ),
            rigButton(
              _s,
              'flat-light-off',
              tr('Licht aus', 'Light off'),
              on && f.lightOn != false
                  ? () => _s.run(
                      context,
                      'flat-light-off',
                      'flat-light',
                      params: {'on': false},
                      ask: (
                        tr('Flatpanel ausschalten?', 'Switch the flat panel off?'),
                        tr(
                          'Laufen gerade Flats, werden die restlichen dunkel.',
                          'If flats are being taken, the rest come out dark.',
                        ),
                        tr('Ausschalten', 'Switch off'),
                      ),
                    )
                  : null,
            ),
          ]),
        rigRow([
          rigNumberField(
            _brightness,
            f.minBrightness != null && f.maxBrightness != null
                ? tr(
                    'Helligkeit ${f.minBrightness}–${f.maxBrightness}',
                    'Brightness ${f.minBrightness}–${f.maxBrightness}',
                  )
                : tr('Helligkeit', 'Brightness'),
            'flat-brightness-value',
          ),
          rigButton(_s, 'flat-brightness', tr('Setzen', 'Set'), on ? () => _setBrightness(f) : null),
        ]),
        if (f.supportsOpenClose == true)
          rigRow([
            rigButton(
              _s,
              'flat-cover-open',
              tr('Abdeckung öffnen', 'Open cover'),
              on
                  ? () => _s.run(
                      context,
                      'flat-cover-open',
                      'flat-cover',
                      params: {'closed': false},
                      ask: (
                        tr('Abdeckung öffnen?', 'Open the cover?'),
                        tr('Die Abdeckung fährt von der Optik weg.', 'The cover moves off the optics.'),
                        tr('Öffnen', 'Open'),
                      ),
                      timeout: const Duration(seconds: 120),
                    )
                  : null,
            ),
            rigButton(
              _s,
              'flat-cover-close',
              tr('Abdeckung schließen', 'Close cover'),
              on
                  ? () => _s.run(
                      context,
                      'flat-cover-close',
                      'flat-cover',
                      params: {'closed': true},
                      ask: (
                        tr('Abdeckung schließen?', 'Close the cover?'),
                        tr(
                          'Die Abdeckung fährt vor die Optik. Läuft eine Sequenz, sind ihre Aufnahmen danach schwarz.',
                          'The cover closes over the optics. If a sequence runs, its exposures are black from then on.',
                        ),
                        tr('Schließen', 'Close'),
                      ),
                      timeout: const Duration(seconds: 120),
                    )
                  : null,
            ),
          ]),
      ],
    );
  }

  Future<void> _setBrightness(FlatPanelState f) async {
    final value = parseNumber(_brightness.text)?.round();
    final lo = f.minBrightness ?? 0;
    if (value == null || value < lo || (f.maxBrightness != null && value > f.maxBrightness!)) {
      RigSession.say(
        context,
        tr(
          'Helligkeit außerhalb von $lo–${f.maxBrightness ?? '…'}.',
          'Brightness outside $lo–${f.maxBrightness ?? '…'}.',
        ),
      );
      return;
    }
    await _s.run(
      context,
      'flat-brightness',
      'flat-brightness',
      params: {'brightness': value},
      ask: (
        tr('Helligkeit auf $value?', 'Brightness to $value?'),
        tr('NINA stellt das Flatpanel auf diese Helligkeit.', 'NINA sets the flat panel to this brightness.'),
        tr('Setzen', 'Set'),
      ),
    );
  }
}
