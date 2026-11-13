// Rig › Montierung › Schwenken: a target out of the catalogue search or typed
// coordinates, always J2000, sent to NINA's slew (optionally with its centring) after
// asking. The mount reports JNow; nothing here compares its numbers with the target's –
// only a solved frame says whether the field is right.

import 'package:material_ui/material_ui.dart';

import '../../api/bortle_client.dart';
import '../../api/models.dart';
import '../../design.dart';
import '../../l10n.dart';
import '../coords.dart';
import '../rig_models.dart';
import '../rig_session.dart';
import 'common.dart';
import 'mount_page.dart' show FrameCallback, mountSummary;

class SlewTab extends StatefulWidget {
  const SlewTab({required this.session, required this.mount, this.onFrame, super.key});

  final RigSession session;
  final MountState mount;
  final FrameCallback? onFrame;

  @override
  State<SlewTab> createState() => _SlewTabState();
}

class _SlewTabState extends State<SlewTab> {
  final _ra = TextEditingController();
  final _dec = TextEditingController();
  bool _center = true;

  /// The catalogue's name for the coordinates in the fields; null once they are typed.
  String? _name;
  int _searchSeq = 0;
  Iterable<SearchHit> _lastHits = const [];

  RigSession get _s => widget.session;

  @override
  void dispose() {
    _ra.dispose();
    _dec.dispose();
    super.dispose();
  }

  /// As you type, debounced, like the Plan tab's search.
  Future<Iterable<SearchHit>> _search(String text) async {
    final seq = ++_searchSeq;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (seq != _searchSeq) return _lastHits;
    Iterable<SearchHit> hits;
    try {
      hits = await _s.client.search(text);
    } on Object {
      hits = const [];
    }
    if (seq == _searchSeq) _lastHits = hits;
    return hits;
  }

  Future<void> _pick(SearchHit hit) async {
    FocusManager.instance.primaryFocus?.unfocus();
    var ra = hit.raDeg, dec = hit.decDeg;
    if (ra == null || dec == null) {
      try {
        final o = await _s.client.resolve(hit.planName);
        ra = o.raDeg;
        dec = o.decDeg;
      } on BortleError catch (e) {
        if (mounted) RigSession.say(context, e.message);
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      // degrees, exactly as the catalogue holds them: a lone number is degrees
      _ra.text = ra!.toStringAsFixed(4);
      _dec.text = dec!.toStringAsFixed(4);
      _name = hit.planName;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final m = widget.mount;
    final ra = parseRa(_ra.text), dec = parseDec(_dec.text);
    final valid = ra != null && dec != null;
    final canSlew = valid && m.connected && !m.atPark && m.canSlew != false;
    final typed = _ra.text.trim().isNotEmpty || _dec.text.trim().isNotEmpty;
    return RigPageList(
      session: _s,
      children: [
        RigStatus(mountSummary(m)),
        const SizedBox(height: 8),
        Autocomplete<SearchHit>(
          displayStringForOption: (s) => s.planName,
          optionsBuilder: (value) => _search(value.text),
          onSelected: _pick,
          optionsViewBuilder: (context, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320, maxWidth: 560),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final hit in options)
                      ListTile(
                        key: Key('slew-hit-${hit.planName}'),
                        dense: true,
                        title: Text(hit.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [if (hit.planName != hit.name) hit.planName, ?hit.type].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: tones.muted, fontSize: 12),
                        ),
                        onTap: () => onSelected(hit),
                      ),
                  ],
                ),
              ),
            ),
          ),
          fieldViewBuilder: (context, controller, focus, submit) => TextField(
            key: const Key('slew-search'),
            controller: controller,
            focusNode: focus,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: tr('Ziel suchen', 'Find a target'),
              hintText: tr('z. B. NGC 7000, M31, Rosette', 'e.g. NGC 7000, M31, Rosette'),
              prefixIcon: const Icon(Icons.search),
            ),
          ),
        ),
        RigHeading(tr('oder Koordinaten (J2000)', 'or coordinates (J2000)')),
        rigRow([
          TextField(
            key: const Key('slew-ra'),
            controller: _ra,
            decoration: InputDecoration(labelText: tr('RA (J2000)', 'RA (J2000)'), hintText: '20 59 17', isDense: true),
            onChanged: (_) => setState(() => _name = null),
          ),
          TextField(
            key: const Key('slew-dec'),
            controller: _dec,
            decoration: InputDecoration(
              labelText: tr('Dec (J2000)', 'Dec (J2000)'),
              hintText: '+44 31 44',
              isDense: true,
            ),
            onChanged: (_) => setState(() => _name = null),
          ),
        ]),
        RigNote(
          tr(
            'RA: zwei oder drei Werte sind Stunden (20 59 17, 20:59:17), eine einzelne Zahl ist Grad (314.82). Dec immer in Grad.',
            'RA: two or three values are hours (20 59 17, 20:59:17), a single number is degrees (314.82). Dec always in degrees.',
          ),
        ),
        if (valid)
          RigNote(
            '${tr('Wird gesendet als', 'Sent as')} ${ra.toStringAsFixed(4)}° / ${dec.toStringAsFixed(4)}° · '
            '${formatRa(ra)} · ${formatDec(dec)}${_name == null ? '' : ' · $_name'}',
            key: const Key('slew-parsed'),
          )
        else if (typed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              tr('Nicht lesbar oder außerhalb des Bereichs.', 'Not readable or out of range.'),
              style: TextStyle(color: tones.warn, fontSize: 12),
            ),
          ),
        SwitchListTile(
          key: const Key('slew-center'),
          contentPadding: EdgeInsets.zero,
          value: _center,
          onChanged: (v) => setState(() => _center = v),
          title: Text(tr('Zentrieren', 'Center')),
          subtitle: Text(
            tr(
              'NINA löst nach dem Schwenk eine Aufnahme und korrigiert nach.',
              'After the slew NINA solves a frame and corrects.',
            ),
            style: TextStyle(color: tones.muted, fontSize: 12),
          ),
        ),
        rigRow([
          rigButton(_s, 'slew', tr('Schwenken', 'Slew'), canSlew ? () => _slew(ra, dec) : null, primary: true),
          rigButton(
            _s,
            'slew-stop',
            tr('Stopp', 'Stop'),
            m.connected ? () => _s.run(context, 'slew-stop', 'slew-stop') : null,
            color: tones.danger,
          ),
        ]),
        if (widget.onFrame != null) ...[
          const SizedBox(height: 8),
          rigButton(
            _s,
            'frame-target',
            tr('Einrahmen', 'Frame'),
            valid ? () => widget.onFrame!(_name ?? '', ra, dec) : null,
          ),
        ],
        if (!m.connected) RigNote(tr('Die Montierung ist nicht verbunden.', 'The mount is not connected.')),
        if (m.connected && m.atPark)
          RigNote(tr('Die Montierung ist geparkt – erst entparken.', 'The mount is parked – unpark it first.')),
        RigNote(
          tr(
            'Die Montierung meldet ihre Position in JNow, Ziele sind J2000 – die beiden Zahlen nicht gegeneinander vergleichen. Ob der Ausschnitt stimmt, sagt nur eine gelöste Aufnahme.',
            'The mount reports its position in JNow, targets are J2000 – do not compare the two numbers. Only a solved frame says whether the field is right.',
          ),
        ),
      ],
    );
  }

  Future<void> _slew(double ra, double dec) async {
    final target = _name ?? '${formatRa(ra)} · ${formatDec(dec)}';
    await _s.run(
      context,
      'slew',
      'slew',
      params: {'ra_deg': ra, 'dec_deg': dec, 'center': _center},
      ask: (
        tr('Zu $target schwenken?', 'Slew to $target?'),
        tr(
          'Die Montierung schwenkt nach RA ${formatRa(ra)}, Dec ${formatDec(dec)} (J2000)${_center ? ', danach zentriert NINA per Plate-Solve' : ''}. Kabel im Blick behalten; läuft eine Sequenz, stört der Schwenk ihre Aufnahmen.',
          'The mount slews to RA ${formatRa(ra)}, Dec ${formatDec(dec)} (J2000)${_center ? ', then NINA centres with a plate solve' : ''}. Keep an eye on the cables; if a sequence runs, the slew disturbs its exposures.',
        ),
        tr('Schwenken', 'Slew'),
      ),
      timeout: const Duration(seconds: 300),
    );
  }
}
