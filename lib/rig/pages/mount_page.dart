// Rig › Montierung, four tabs as the cockpit's mount page has them: control (park,
// tracking, home, stop, the nudge pad), slewing to a target in J2000, polar alignment,
// and the meridian flip – which is NINA's and shown here read-only.
//
// Park, home and the meridian flip belong to NINA's safety layer: Bortle asks NINA to
// run its own operations (and asks the human first for the ones that move the mount),
// and the flip tab offers no control at all (CLAUDE.md §1 no. 3).

import 'package:material_ui/material_ui.dart';

import '../../api/bortle_client.dart';
import '../../design.dart';
import '../../l10n.dart';
import '../../widgets.dart';
import '../rig_models.dart';
import '../rig_session.dart';
import '../tppa_screen.dart';
import 'common.dart';
import 'mount_slew.dart';

/// Nudge steps in arcminutes, as the cockpit's mount page offers them.
const nudgeArcmin = [1, 2, 5, 10, 30];

/// Hands a target to the framing view: its name (empty for typed coordinates) and
/// J2000 degrees.
typedef FrameCallback = void Function(String name, double raDeg, double decDeg);

enum MountTab { control, slew, tppa, flip }

class MountPage extends StatefulWidget {
  const MountPage({required this.session, required this.rig, this.onFrame, super.key});

  final RigSession session;
  final RigState rig;
  final FrameCallback? onFrame;

  @override
  State<MountPage> createState() => _MountPageState();
}

class _MountPageState extends State<MountPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: MountTab.values.length, vsync: this)
    ..addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab = MountTab.values[_tabs.index];
    return Column(
      children: [
        TabBar(
          key: const Key('mount-tabs'),
          controller: _tabs,
          // four fixed tabs on a 360 pt phone: all in sight, a long label wraps at its hyphen
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          onTap: (_) => setState(() {}),
          tabs: [
            for (final (key, label) in [
              ('control', tr('Steuerung', 'Control')),
              ('slew', tr('Schwenken', 'Slew')),
              ('tppa', 'TPPA'),
              ('flip', tr('Meridian-Flip', 'Meridian flip')),
            ])
              Tab(
                key: Key('mount-tab-$key'),
                height: 52,
                child: Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
        Expanded(
          child: switch (tab) {
            MountTab.control => _ControlTab(session: widget.session, mount: widget.rig.mount),
            MountTab.slew => SlewTab(session: widget.session, mount: widget.rig.mount, onFrame: widget.onFrame),
            MountTab.tppa => _TppaTab(session: widget.session),
            MountTab.flip => _FlipTab(session: widget.session, mount: widget.rig.mount),
          },
        ),
      ],
    );
  }
}

String mountSummary(MountState m) {
  if (!m.connected) return tr('nicht verbunden', 'not connected');
  return [
    if (m.atPark) tr('geparkt', 'parked'),
    if (m.slewing) tr('schwenkt', 'slewing'),
    if (!m.atPark) m.tracking ? tr('führt nach', 'tracking') : tr('kein Tracking', 'not tracking'),
    if (m.altitude != null) tr('Höhe ${decimal(m.altitude!, 0)}°', 'alt ${decimal(m.altitude!, 0)}°'),
  ].join(' · ');
}

String hoursMinutes(double hours) {
  final minutes = (hours * 60).round();
  return minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';
}

String _trackingLabel(String mode) => switch (mode) {
  'sidereal' => tr('Siderisch', 'Sidereal'),
  'lunar' => tr('Mond', 'Lunar'),
  'solar' => tr('Sonne', 'Solar'),
  'king' => 'King',
  _ => tr('gestoppt', 'stopped'),
};

// --- Steuerung -----------------------------------------------------------------------

class _ControlTab extends StatefulWidget {
  const _ControlTab({required this.session, required this.mount});

  final RigSession session;
  final MountState mount;

  @override
  State<_ControlTab> createState() => _ControlTabState();
}

class _ControlTabState extends State<_ControlTab> {
  bool _nudgeArmed = false;
  int _nudgeStep = 5;

  RigSession get _s => widget.session;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final m = widget.mount;
    final canNudge = m.connected && !m.atPark && !m.slewing;
    Widget arrow(String direction, String label) => SizedBox(
      height: 64,
      child: rigButton(_s, 'nudge-$direction', label, canNudge ? () => _nudge(direction) : null),
    );
    final mode = m.tracking && m.trackingMode != 'stopped' ? m.trackingMode : null;
    return RigPageList(
      session: _s,
      children: [
        RigStatus(mountSummary(m)),
        if (m.hoursToFlip != null && m.hoursToFlip! > 0)
          RigNote(
            tr(
              'Meridian-Flip in ${hoursMinutes(m.hoursToFlip!)} (NINA)',
              'Meridian flip in ${hoursMinutes(m.hoursToFlip!)} (NINA)',
            ),
          ),
        rigRow([
          m.atPark
              ? rigButton(
                  _s,
                  'unpark',
                  tr('Entparken', 'Unpark'),
                  m.connected
                      ? () => _s.run(
                          context,
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
              : rigButton(
                  _s,
                  'park',
                  tr('Parken', 'Park'),
                  m.connected
                      ? () => _s.run(
                          context,
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
          rigButton(
            _s,
            'tracking',
            m.tracking ? tr('Tracking aus', 'Stop tracking') : tr('Tracking an', 'Start tracking'),
            m.connected && !m.atPark
                ? () => _s.run(
                    context,
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
        RigHeading(tr('Nachführrate', 'Tracking rate')),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          key: const Key('tracking-mode'),
          showSelectedIcon: false,
          // four rates on a 360 pt phone, never wrapping
          style: SegmentedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          emptySelectionAllowed: true,
          segments: [
            for (final mo in const ['sidereal', 'lunar', 'solar', 'king'])
              ButtonSegment(
                value: mo,
                label: Text(_trackingLabel(mo), key: Key('tracking-$mo')),
              ),
          ],
          selected: {?mode},
          onSelectionChanged: m.connected && !m.atPark && _s.busy == null
              ? (s) {
                  if (s.isEmpty || s.first == mode) return;
                  final next = s.first;
                  _s.run(
                    context,
                    'tracking-mode',
                    'tracking',
                    params: {'mode': next},
                    ask: (
                      tr('${_trackingLabel(next)} nachführen?', 'Track at the ${_trackingLabel(next)} rate?'),
                      tr(
                        'NINA stellt die Nachführung der Montierung auf diese Rate um.',
                        'NINA switches the mount’s tracking to this rate.',
                      ),
                      tr('Umstellen', 'Switch'),
                    ),
                  );
                }
              : null,
        ),
        rigRow([
          if (m.canFindHome != false)
            rigButton(
              _s,
              'mount-home',
              tr('Home', 'Home'),
              m.connected && !m.atPark
                  ? () => _s.run(
                      context,
                      'mount-home',
                      'mount-home',
                      params: {'confirm': true},
                      ask: (
                        tr('Montierung in die Home-Position fahren?', 'Send the mount home?'),
                        tr(
                          'Die Montierung schwenkt von wo sie steht quer über den Himmel in ihre Home-Position. Vorher die Kabel prüfen.',
                          'The mount swings across the sky from wherever it stands into its home position. Check the cables first.',
                        ),
                        tr('Home', 'Home'),
                      ),
                      timeout: const Duration(seconds: 180),
                    )
                  : null,
            ),
          // stopping is the safe direction: no question first
          rigButton(
            _s,
            'slew-stop',
            tr('Stopp', 'Stop'),
            m.connected ? () => _s.run(context, 'slew-stop', 'slew-stop') : null,
            color: tones.danger,
          ),
        ]),
        RigHeading(tr('Feinjustage', 'Nudge')),
        const SizedBox(height: 8),
        // under its heading rather than beside it: five steps do not fit next to a word on 360 pt
        SegmentedButton<int>(
          key: const Key('nudge-step'),
          showSelectedIcon: false,
          segments: [for (final a in nudgeArcmin) ButtonSegment(value: a, label: Text('$a′'))],
          selected: {_nudgeStep},
          onSelectionChanged: (s) => setState(() => _nudgeStep = s.first),
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
        RigNote(
          tr(
            'Ein Druck, ein Schritt: Bortle rechnet aus der Position der Montierung das Ziel in J2000 und lässt NINA dorthin schwenken. Die Tasten benennen die Himmelsrichtung, nicht die Richtung im Bild.',
            'One press, one step: Bortle turns the mount’s position into a J2000 target and NINA slews there. The keys name the sky direction, not the direction in the frame.',
          ),
        ),
        RigNote(
          tr(
            'Bortle löst nur NINAs eigene Funktionen aus. Parken, Abbruch und Meridian-Flip bleiben NINAs Sicherheitsschicht – auch wenn Server, Netz oder App ausfallen.',
            'Bortle only triggers NINA’s own operations. Parking, aborts and the meridian flip stay NINA’s safety layer – even if server, network or app fail.',
          ),
        ),
      ],
    );
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
    _s.busy = 'nudge-$direction';
    try {
      await _s.client.rigNudge(direction, _nudgeStep.toDouble());
      if (mounted) {
        RigSession.say(context, tr('$_nudgeStep′ nach ${_directionDe(direction)}', '$_nudgeStep′ $direction'));
      }
    } on BortleError catch (e) {
      if (mounted) RigSession.say(context, e.message);
    } finally {
      _s.busy = null;
      await _s.poll();
    }
  }

  static String _directionDe(String d) =>
      const {'north': 'Nord', 'south': 'Süd', 'east': 'Ost', 'west': 'West'}[d] ?? d;
}

// --- TPPA ----------------------------------------------------------------------------

class _TppaTab extends StatelessWidget {
  const _TppaTab({required this.session});

  final RigSession session;

  @override
  Widget build(BuildContext context) => RigPageList(
    session: session,
    children: [
      RigNote(
        tr(
          'Polausrichtung mit NINAs Three-Point-Polar-Alignment-Plugin: das Telefon in der einen Hand, die Azimut- und Höhenschrauben in der anderen. Die Messung kommt vom Plugin; Bortle erfindet keine.',
          'Polar alignment with NINA’s Three Point Polar Alignment plugin: the phone in one hand, the azimuth and altitude screws in the other. The measurement comes from the plugin; Bortle makes none up.',
        ),
      ),
      const SizedBox(height: 12),
      rigButton(
        session,
        'open-tppa',
        tr('Polausrichtung (TPPA) öffnen', 'Open polar alignment (TPPA)'),
        () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TppaScreen(client: session.client))),
        primary: true,
      ),
    ],
  );
}

// --- Meridian-Flip -------------------------------------------------------------------

class _FlipTab extends StatefulWidget {
  const _FlipTab({required this.session, required this.mount});

  final RigSession session;
  final MountState mount;

  @override
  State<_FlipTab> createState() => _FlipTabState();
}

class _FlipTabState extends State<_FlipTab> {
  /// Null while loading; empty when NINA gave none (or the server could not ask).
  List<ProfileSetting>? _settings;
  String? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Profile settings change in NINA, not here: read once per visit.
  Future<void> _load() async {
    try {
      final j = await widget.session.client.rigProfileSettings();
      final profile = j['profile'];
      if (mounted) {
        setState(() {
          _settings = ProfileSetting.meridianFlip(j);
          _profile = profile is Map && profile['name'] is String ? profile['name'] as String : null;
        });
      }
    } on BortleError {
      if (mounted) setState(() => _settings = const []);
    }
  }

  static String _value(ProfileSetting s) {
    final v = s.value;
    final unit = s.unit == null ? '' : ' ${s.unit}';
    return switch (v) {
      null => '–',
      bool b => b ? tr('an', 'on') : tr('aus', 'off'),
      int i => '$i$unit',
      num n => '${decimal(n, n == n.roundToDouble() ? 0 : 1)}$unit',
      _ => '$v$unit',
    };
  }

  static String _pier(String? side) => switch (side?.toLowerCase()) {
    'piereast' || 'east' => tr('Ost (Teleskop westlich)', 'east (scope pointing west)'),
    'pierwest' || 'west' => tr('West (Teleskop östlich)', 'west (scope pointing east)'),
    null => '–',
    _ => tr('unbekannt', 'unknown'),
  };

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final m = widget.mount;
    final settings = _settings;
    Widget line(String label, String value, {Key? key}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: tones.muted)),
          ),
          Text(
            value,
            key: key,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    return RigPageList(
      session: widget.session,
      children: [
        line(
          tr('Zeit bis zum Flip', 'Time to the flip'),
          m.hoursToFlip != null && m.hoursToFlip! > 0 ? hoursMinutes(m.hoursToFlip!) : (m.flipText ?? '–'),
          key: const Key('flip-time'),
        ),
        line(tr('Seite des Pfeilers (jetzt)', 'Side of pier (now)'), _pier(m.sideOfPier)),
        const Divider(),
        if (settings == null)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (settings.isEmpty)
          RigNote(
            tr(
              'NINA liefert hier keine Meridian-Flip-Einstellungen – in NINA einstellen (Optionen → Imaging → Meridian-Flip).',
              'NINA gives no meridian flip settings here – set them in NINA (Options → Imaging → Meridian Flip).',
            ),
            key: const Key('flip-in-nina'),
          )
        else ...[
          for (final s in settings) line(s.label, _value(s)),
          if (_profile != null) RigNote(tr('Profil: $_profile', 'Profile: $_profile')),
        ],
        RigNote(
          tr(
            'Diese Werte werden in NINA eingestellt und hier nur angezeigt. Der Meridian-Flip ist Teil von NINAs Sicherheitsschicht – Bortle liest ihn, ändert ihn nie.',
            'These values are set in NINA and only shown here. The meridian flip is part of NINA’s safety layer – Bortle reads it and never changes it.',
          ),
        ),
      ],
    );
  }
}
