// Rig › Geräte: the pre-flight, every device NINA knows with its driver, connect and
// disconnect, and the way out to Touch'N'Stars.

import 'package:material_ui/material_ui.dart';

import '../../api/bortle_client.dart';
import '../../design.dart';
import '../../l10n.dart';
import '../../widgets.dart';
import '../rig_models.dart';
import '../rig_session.dart';
import '../touchnstars.dart';
import 'common.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({required this.session, required this.rig, this.touchNStars, super.key});

  final RigSession session;
  final RigState rig;
  final TouchNStars? touchNStars;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  List<RigDevice>? _devices;
  Preflight? _preflight;

  RigSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      final j = await _s.client.rigDevices();
      final rows = [for (final d in (j['devices'] as List? ?? const [])) RigDevice.fromJson(d as Map)];
      if (mounted) setState(() => _devices = rows);
    } on BortleError catch (e) {
      if (mounted) RigSession.say(context, e.message);
    }
  }

  Future<void> _runPreflight() async {
    _s.busy = 'preflight';
    try {
      final result = Preflight.fromJson(await _s.client.rigPreflight());
      if (mounted) setState(() => _preflight = result);
    } on BortleError catch (e) {
      if (mounted) RigSession.say(context, e.message);
    } finally {
      _s.busy = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final tns = widget.touchNStars;
    return RigPageList(
      session: _s,
      children: [
        _preflightCard(tones),
        RigStatus(
          tr(
            '${widget.rig.mainConnected} von 5 Hauptgeräten verbunden',
            '${widget.rig.mainConnected} of 5 main devices connected',
          ),
        ),
        _devicesBody(tones),
        if (tns != null) ...[
          const SizedBox(height: 20),
          OutlinedButton.icon(
            key: const Key('open-touchnstars'),
            style: ButtonStyle(minimumSize: WidgetStateProperty.all(const Size.fromHeight(52))),
            onPressed: () => tns.open(context),
            icon: const Icon(Icons.open_in_new),
            label: Text(tr('Touch’N’Stars öffnen', 'Open Touch’N’Stars')),
          ),
          RigNote(
            tr(
              'Touch’N’Stars ist NINAs eigene Weboberfläche (Plugin). Es öffnet im Browser des Telefons; die Adresse stellst du über das Menü rechts in der Geräteleiste ein.',
              'Touch’N’Stars is NINA’s own web interface (a plugin). It opens in the phone’s browser; set its address from the menu at the right of the device bar.',
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          tr(
            'Bortle löst nur NINAs eigene Funktionen aus. Parken bei Verbindungsverlust, Abbruch und Meridian-Flip bleiben NINAs Sicherheitsschicht – auch wenn Server, Netz oder App ausfallen.',
            'Bortle only triggers NINA’s own operations. Parking on connection loss, aborts and the meridian flip stay NINA’s safety layer – even if server, network or app fail.',
          ),
          style: TextStyle(color: tones.muted, fontSize: 12),
        ),
      ],
    );
  }

  // --- pre-flight ------------------------------------------------------------------

  Widget _preflightCard(Tones tones) {
    final p = _preflight;
    Color tone(String status) => switch (status) {
      'pass' => tones.good,
      'warn' => tones.warn,
      'block' => tones.danger,
      _ => tones.muted,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            rigButton(_s, 'preflight', tr('Pre-Flight prüfen', 'Run pre-flight'), _runPreflight, primary: true),
            if (p != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  StateDot(p.ok ? tones.good : tones.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.summary ?? (p.ok ? tr('alles bereit', 'all set') : tr('nicht bereit', 'not ready')),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              for (final c in p.checks)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(padding: const EdgeInsets.only(top: 5), child: StateDot(tone(c.status))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: c.title,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if (c.detail != null) TextSpan(text: ' – ${c.detail}'),
                            ],
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // --- devices ---------------------------------------------------------------------

  Widget _devicesBody(Tones tones) {
    final devices = _devices;
    if (devices == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        rigButton(
          _s,
          'connect-all',
          tr('Alle verbinden', 'Connect all'),
          () => _s.run(
            context,
            'connect-all',
            'connect-all',
            ask: (
              tr('Alle Geräte verbinden?', 'Connect every device?'),
              tr(
                'NINA verbindet jedes Gerät mit dem gewählten Treiber. Geräte, die nicht angeschlossen sind, melden einen Fehler; die anderen verbinden trotzdem.',
                'NINA connects every device with its chosen driver. Devices that are not plugged in report an error; the others connect anyway.',
              ),
              tr('Verbinden', 'Connect'),
            ),
            timeout: const Duration(seconds: 180),
            after: _loadDevices,
          ),
          primary: true,
        ),
        for (final d in devices)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                StateDot(d.connected ? tones.good : (d.error != null ? tones.danger : tones.muted)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        d.error ?? d.driver ?? tr('kein Treiber gewählt', 'no driver chosen'),
                        style: TextStyle(color: d.error != null ? tones.danger : tones.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 128,
                  child: d.connected
                      ? rigButton(
                          _s,
                          'disconnect-${d.key}',
                          tr('Trennen', 'Disconnect'),
                          () => _s.run(
                            context,
                            'disconnect-${d.key}',
                            'disconnect',
                            params: {'device': d.key, 'confirm': true},
                            ask: (
                              tr('${d.label} trennen?', 'Disconnect the ${d.label}?'),
                              tr(
                                'Trennen ist nicht das Gegenstück zum Verbinden: manche Treiber verbinden danach nicht mehr und brauchen einen Neustart der Hardware am Teleskop.',
                                'Disconnecting is not the twin of connecting: some drivers refuse to reconnect and need the hardware power-cycled at the telescope.',
                              ),
                              tr('Trennen', 'Disconnect'),
                            ),
                            after: _loadDevices,
                          ),
                          color: tones.danger,
                        )
                      : rigButton(
                          _s,
                          'connect-${d.key}',
                          tr('Verbinden', 'Connect'),
                          () => _s.run(
                            context,
                            'connect-${d.key}',
                            'connect',
                            params: {'device': d.key},
                            ask: (
                              tr('${d.label} verbinden?', 'Connect the ${d.label}?'),
                              d.driver == null
                                  ? tr(
                                      'NINA verbindet mit dem Treiber, den sein Auswahlfeld hält.',
                                      'NINA connects with the driver its chooser holds.',
                                    )
                                  : tr('NINA verbindet mit „${d.driver}“.', 'NINA connects with “${d.driver}”.'),
                              tr('Verbinden', 'Connect'),
                            ),
                            timeout: const Duration(seconds: 90),
                            after: _loadDevices,
                          ),
                        ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
