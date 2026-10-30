// "Planen": an object, its altitude over the night at the account's site, moon and clouds,
// then the sequence to NINA with the develop level for when the night ends.

import 'package:flutter/material.dart';

import '../api/bortle_client.dart';
import '../api/models.dart';
import '../charts.dart';
import '../design.dart';
import '../l10n.dart';
import '../widgets.dart';

class PlanScreen extends StatefulWidget {
  const PlanScreen({required this.client, required this.me, super.key});

  final BortleClient client;

  /// Null in local mode, where the one user is the operator.
  final Me? me;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  Future<NightPlan>? _plan;
  String? _object;
  final _exposure = TextEditingController(text: '180');
  final _count = TextEditingController(text: '60');
  String _level = 'auto';
  String? _filter;
  late final Future<List<Recommendation>> _recommended = widget.client.recommend().catchError(
    (Object _) => const <Recommendation>[],
  );
  bool _start = false;
  bool _busy = false;

  bool get _operator => widget.me == null || widget.me!.admin;

  @override
  void initState() {
    super.initState();
    widget.client.developLevel().then((l) {
      if (mounted) setState(() => _level = l);
    }, onError: (_) {});
  }

  void _pick(String object, {Recommendation? from}) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _object = object;
      _plan = widget.client.plan(object);
      // what the recommendation measured for this rig; a searched object keeps the defaults
      _filter = from?.filter;
      if (from?.exposureS != null) _exposure.text = from!.exposureS!.round().toString();
    });
  }

  Future<void> _send(NightPlan plan) async {
    final exposure = double.tryParse(_exposure.text.replaceAll(',', '.'));
    final count = int.tryParse(_count.text);
    final messenger = ScaffoldMessenger.of(context);
    if (exposure == null || exposure <= 0 || count == null || count <= 0) {
      messenger.showSnackBar(SnackBar(content: Text(tr('Belichtung und Anzahl prüfen.', 'Check exposure and count.'))));
      return;
    }
    if (_start) {
      final ok = await confirm(
        context,
        tr('Sequenz laden und starten?', 'Load and start the sequence?'),
        tr(
          'NINA lädt die Sequenz für ${plan.object} und startet sie sofort: Kühlen, Entparken, Anfahren, Belichten. Die Sicherheit (Parken, Meridian-Flip) bleibt bei NINA.',
          'NINA loads the sequence for ${plan.object} and starts it at once: cool, unpark, slew, expose. Safety (parking, meridian flip) stays with NINA.',
        ),
        tr('Starten', 'Start'),
      );
      if (!ok) return;
    }
    setState(() => _busy = true);
    try {
      await widget.client.sendToNina(
        plan: plan,
        exposureS: exposure,
        count: count,
        developLevel: _level,
        start: _start,
        filter: _filter,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _start
                ? tr('NINA hat die Sequenz und startet.', 'NINA has the sequence and starts.')
                : tr(
                    'Sequenz in NINA geladen – starten im Teleskop-Reiter oder in NINA.',
                    'Sequence loaded into NINA – start it in the Telescope tab or in NINA.',
                  ),
          ),
        ),
      );
    } on BortleError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Planen', 'Plan'))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Autocomplete<Suggestion>(
          displayStringForOption: (s) => s.label,
          optionsBuilder: (value) => widget.client.suggest(value.text).catchError((_) => const <Suggestion>[]),
          onSelected: (s) => _pick(s.name),
          fieldViewBuilder: (context, controller, focus, submit) => TextField(
            key: const Key('object'),
            controller: controller,
            focusNode: focus,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: tr('Objekt', 'Object'),
              hintText: tr('z. B. NGC 7000, M31, Rosette', 'e.g. NGC 7000, M31, Rosette'),
              prefixIcon: const Icon(Icons.search),
            ),
            onSubmitted: (text) {
              if (text.trim().isNotEmpty) _pick(text.trim());
            },
          ),
        ),
        if (_plan == null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              tr(
                'Sichtbarkeit, Mond und Wolken rechnet Bortle für den Standort und Horizont aus deinem Profil.',
                'Bortle computes visibility, moon and clouds for the site and horizon in your profile.',
              ),
              style: TextStyle(color: context.tones.muted),
            ),
          ),
          SectionTitle(tr('Empfehlungen für heute Nacht', 'Recommended for tonight')),
          FutureBuilder<List<Recommendation>>(
            future: _recommended,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
              final list = snap.data ?? const <Recommendation>[];
              if (list.isEmpty) {
                return Text(
                  tr(
                    'Keine Empfehlungen – ist im Profil ein Standort eingetragen?',
                    'No recommendations – is a site set in your profile?',
                  ),
                  style: TextStyle(color: context.tones.muted),
                );
              }
              return Column(
                children: [
                  for (final r in list)
                    Card(
                      child: ListTile(
                        key: Key('rec-${r.name}'),
                        leading: Icon(r.favorite ? Icons.star : Icons.auto_awesome_outlined),
                        title: Text(r.name),
                        subtitle: Text(
                          [
                            if (r.visibleHours > 0)
                              tr(
                                '${decimal(r.visibleHours, 1)} h dunkel und hoch genug',
                                '${decimal(r.visibleHours, 1)} h dark and high enough',
                              )
                            else
                              tr('heute kein dunkles Fenster', 'no dark window tonight'),
                            if (r.filter != null)
                              '${r.filter}${r.exposureS != null ? ' · ${r.exposureS!.round()} s' : ''}',
                            if (r.alreadyHours > 0)
                              tr(
                                'schon ${decimal(r.alreadyHours, 1)} h im Kasten',
                                '${decimal(r.alreadyHours, 1)} h already',
                              ),
                          ].join('\n'),
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _pick(r.name, from: r),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
        if (_plan != null)
          FutureBuilder<NightPlan>(
            future: _plan,
            builder: (context, snap) {
              if (snap.hasError) return LoadError(snap.error!, onRetry: () => _pick(_object!));
              final plan = snap.data;
              if (plan == null) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return _planView(context, plan);
            },
          ),
      ],
    ),
  );

  Widget _planView(BuildContext context, NightPlan plan) {
    final tones = context.tones;
    final primary = Theme.of(context).colorScheme.primary;
    final from = plan.nightStart?.subtract(const Duration(hours: 1));
    final to = plan.nightEnd?.add(const Duration(hours: 1));
    final points = [
      for (final p in plan.points)
        if ((from == null || !p.time.isBefore(from)) && (to == null || !p.time.isAfter(to))) p,
    ];
    final clouds = plan.clouds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(plan.object, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Höhe heute Nacht', 'Altitude tonight'), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TimeChart(
                  label: tr('Höhenkurve', 'Altitude curve'),
                  minY: 0,
                  maxY: 90,
                  guideY: 30,
                  bands: [
                    if (plan.nightStart != null && plan.nightEnd != null)
                      TimeBand(plan.nightStart!, plan.nightEnd!, tones.line),
                    if (plan.windowStart != null && plan.windowEnd != null)
                      TimeBand(plan.windowStart!, plan.windowEnd!, primary.withValues(alpha: .14)),
                  ],
                  series: [
                    Series([for (final p in points) ChartPoint(p.time, p.altitude)], primary),
                    Series([for (final p in points) ChartPoint(p.time, p.horizon)], tones.muted, dashed: true),
                    Series(
                      [for (final p in points) ChartPoint(p.time, p.cloudCover == null ? null : p.cloudCover! * 90)],
                      tones.warn.withValues(alpha: .7),
                      dashed: true,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  children: [
                    _Legend(primary, tr('Objekt', 'Object')),
                    _Legend(tones.warn, tr('Wolken', 'Clouds')),
                    _Legend(tones.muted, tr('Horizont', 'Horizon')),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Two rows that grow with their text: a fixed tile height clipped the detail line on
        // a narrow phone with the real fonts.
        _FactRows(
          facts: [
            _Fact(
              tr('Belichtbar', 'Imaging window'),
              plan.windowHours > 0 ? '${decimal(plan.windowHours, 1)} h' : tr('keins', 'none'),
              timeRange(plan.windowStart, plan.windowEnd),
              color: plan.windowHours > 0 ? null : tones.warn,
            ),
            _Fact(
              tr('Max. Höhe', 'Max altitude'),
              plan.maxAltitude == null ? '–' : '${decimal(plan.maxAltitude!, 0)}°',
              plan.maxAltitudeTime == null
                  ? null
                  : tr('um ${clock(plan.maxAltitudeTime!)}', 'at ${clock(plan.maxAltitudeTime!)}'),
            ),
            _Fact(
              tr('Mond', 'Moon'),
              plan.moonIllumination == null ? '–' : '${(plan.moonIllumination! * 100).round()} %',
              plan.moonSeparation == null
                  ? null
                  : tr('${plan.moonSeparation!.round()}° entfernt', '${plan.moonSeparation!.round()}° away'),
            ),
            _Fact(
              tr('Wolken', 'Clouds'),
              clouds == null ? '–' : '${(clouds * 100).round()} %',
              tr('Vorhersage, Mittel', 'forecast, mean'),
              color: clouds != null && clouds > .5 ? tones.warn : null,
            ),
          ],
        ),
        for (final w in plan.warnings)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_outlined, size: 18, color: tones.warn),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(w, style: TextStyle(color: tones.warn)),
                ),
              ],
            ),
          ),
        SectionTitle(tr('Aufnahme', 'Capture')),
        if (_filter != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InputChip(
              key: const Key('filter'),
              avatar: const Icon(Icons.filter_alt_outlined, size: 18),
              label: Text(tr('Filter: $_filter (empfohlen)', 'Filter: $_filter (recommended)')),
              onDeleted: () => setState(() => _filter = null),
              deleteButtonTooltipMessage: tr('Filter nicht setzen', "Don't set a filter"),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('exposure'),
                controller: _exposure,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tr('Belichtung (s)', 'Exposure (s)')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const Key('count'),
                controller: _count,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('Anzahl', 'Count')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _level,
          decoration: InputDecoration(labelText: tr('Danach entwickeln', 'Develop afterwards')),
          items: [
            DropdownMenuItem(
              value: 'stepwise',
              child: Text(
                tr('Schrittweise – nach jeder Phase fragen', 'Step by step – ask after every phase'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownMenuItem(
              value: 'guarded',
              child: Text(
                tr('Geprüft – nur bei Auffälligem fragen', 'Guarded – ask only when something is off'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownMenuItem(
              value: 'auto',
              child: Text(tr('Automatisch', 'Automatic'), overflow: TextOverflow.ellipsis),
            ),
          ],
          onChanged: (v) => setState(() => _level = v ?? _level),
        ),
        const SizedBox(height: 8),
        if (_operator) ...[
          SwitchListTile(
            key: const Key('start'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Gleich starten', 'Start right away')),
            subtitle: Text(tr('Sonst nur laden, starten später.', 'Otherwise load only, start later.')),
            value: _start,
            onChanged: (v) => setState(() => _start = v),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('send'),
            onPressed: _busy ? null : () => _send(plan),
            child: Text(
              _start
                  ? tr('An NINA senden und starten …', 'Send to NINA and start …')
                  : tr('An NINA senden', 'Send to NINA'),
            ),
          ),
        ] else
          Text(
            tr(
              'An NINA sendet hier nur der Betreiber dieser Instanz. Dein eigenes Teleskop planst du über deine lokale Bortle-Installation.',
              'Only the operator of this instance sends to its NINA. Your own telescope is planned through your local Bortle install.',
            ),
            style: TextStyle(color: tones.muted, fontSize: 13),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _FactRows extends StatelessWidget {
  const _FactRows({required this.facts});

  final List<Widget> facts;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < facts.length; i += 2)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: facts[i]),
                const SizedBox(width: 10),
                Expanded(child: i + 1 < facts.length ? facts[i + 1] : const SizedBox()),
              ],
            ),
          ),
        ),
    ],
  );
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, this.detail, {this.color});

  final String label;
  final String value;
  final String? detail;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(color: context.tones.muted, fontSize: 12)),
          Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color)),
          if (detail != null)
            Text(detail!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.text);

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 3, color: color),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(color: context.tones.muted, fontSize: 12)),
    ],
  );
}
