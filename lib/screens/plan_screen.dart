// "Planen": an object, its altitude over the night at the account's site, moon and clouds,
// then the sequence to NINA with the develop level for when the night ends.

import 'package:material_ui/material_ui.dart';

import '../api/bortle_client.dart';
import '../api/models.dart';
import '../charts.dart';
import '../design.dart';
import '../l10n.dart';
import '../object_preview.dart';
import '../plan/recommendation_card.dart';
import '../tools/site_picker.dart';
import '../tools/tools_store.dart';
import '../widgets.dart';

class PlanScreen extends StatefulWidget {
  const PlanScreen({required this.client, required this.me, Locate? locate, super.key})
    : locate = locate ?? locateWithGps;

  final BortleClient client;

  /// Null in local mode, where the one user is the operator.
  final Me? me;

  /// The phone's coarse location, for an account whose profile has no site yet.
  final Locate locate;

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

  /// Which night the recommendations are for: 0 tonight, 1 tomorrow, 2 the day after.
  int _night = 0;
  late Future<RecommendedNight?> _recommended = _recommend();
  bool _start = false;
  bool _busy = false;
  bool _savingSite = false;

  /// The newest search wins; an older answer arriving late is dropped.
  int _searchSeq = 0;
  Iterable<SearchHit> _lastHits = const [];

  /// Null: the profile has no site, so there is nothing to rank by. Tonight goes without a
  /// date (what is left of it); later nights by the phone's local date, as the cockpit does.
  Future<RecommendedNight?> _recommend() {
    final date = _night == 0 ? null : DateTime.now().add(Duration(days: _night));
    return widget.client
        .recommendNight(date: date)
        .then<RecommendedNight?>(
          (night) => night,
          onError: (Object e) => BortleClient.isNoSite(e) ? null : const RecommendedNight(targets: []),
        );
  }

  void _showNight(int night) => setState(() {
    _night = night;
    _recommended = _recommend();
  });

  /// As you type, debounced: the catalogue search, or the older suggestions when the
  /// server does not have it yet.
  Future<Iterable<SearchHit>> _search(String text) async {
    final seq = ++_searchSeq;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (seq != _searchSeq) return _lastHits;
    Iterable<SearchHit> hits;
    try {
      hits = await widget.client.search(text);
    } on Object {
      try {
        hits = [
          for (final s in await widget.client.suggest(text))
            SearchHit(name: s.common ?? s.name, planName: s.name, type: s.type),
        ];
      } on Object {
        hits = const [];
      }
    }
    if (seq == _searchSeq) _lastHits = hits;
    return hits;
  }

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
      _plan = _planFor(object);
      // what the recommendation measured for this rig; a searched object keeps the defaults
      _filter = from?.filter;
      if (from?.exposureS != null) _exposure.text = from!.exposureS!.round().toString();
    });
  }

  /// The night for an object. Its error is the FutureBuilder's to show — the no-site 400
  /// among them — and may arrive before that builder listens, so it is marked handled here.
  Future<NightPlan> _planFor(String object) => widget.client.plan(object)..ignore();

  Future<void> _locateSite() async {
    final messenger = ScaffoldMessenger.of(context);
    Site? site;
    try {
      site = await widget.locate();
    } on Exception {
      site = null;
    }
    if (site == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Standort nicht verfügbar – ist er aus oder nicht erlaubt? Du kannst ihn auch eintippen.',
              'Location not available – is it off or not allowed? You can also type it.',
            ),
          ),
        ),
      );
      return;
    }
    await _saveSite(site);
  }

  Future<void> _typeSite() async {
    final site = await typeSite(context);
    if (site != null) await _saveSite(site);
  }

  /// Into the account's profile, rounded to about a kilometre: enough for altitudes and
  /// twilight, and no more of where someone lives than that.
  Future<void> _saveSite(Site site) async {
    setState(() => _savingSite = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      double round(double v) => (v * 100).roundToDouble() / 100;
      await widget.client.saveSite(round(site.lat), round(site.lon));
      if (!mounted) return;
      setState(() {
        _recommended = _recommend();
        if (_object != null) _plan = _planFor(_object!);
      });
      messenger.showSnackBar(
        SnackBar(content: Text(tr('Standort im Profil gespeichert.', 'Site saved in your profile.'))),
      );
    } on BortleError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _savingSite = false);
    }
  }

  Widget _siteChoice() => Card(
    key: const Key('no-site'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: SiteChoice(
        explanation: tr(
          'Für Höhe, Mond und das beste Fenster braucht Bortle den Ort, an dem du beobachtest. Er wird gerundet in deinem Profil gespeichert und gilt auch im Web.',
          'Altitude, the moon and the best window need the place you observe from. It is kept, rounded, in your profile and applies on the web too.',
        ),
        onLocate: _savingSite ? null : _locateSite,
        onType: _savingSite ? null : _typeSite,
      ),
    ),
  );

  /// What the search found, placed in the sky, while the night itself waits for a site.
  Widget _withoutSite(BuildContext context, String object) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 16),
      FutureBuilder<SkyObject>(
        future: widget.client.resolve(object),
        builder: (context, snap) {
          final hit = snap.data;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(hit?.name ?? object, style: Theme.of(context).textTheme.headlineSmall),
              if (hit != null)
                Text(
                  [?hit.common, 'RA ${_ra(hit.raDeg)} · Dec ${_dec(hit.decDeg)}'].join('\n'),
                  key: const Key('object-position'),
                  style: TextStyle(color: context.tones.muted),
                ),
              if (snap.hasError)
                Text(
                  tr('Dieses Objekt kennt Bortle nicht.', 'Bortle does not know this object.'),
                  style: TextStyle(color: context.tones.warn),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 12),
      _siteChoice(),
      const SizedBox(height: 12),
      // the framing needs no site, only the rig and the object; below the site, which is
      // what this view asks for
      ObjectPreviewCard(client: widget.client, object: object),
    ],
  );

  static String _ra(double deg) {
    final minutes = (deg / 15 * 60).round();
    return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
  }

  static String _dec(double deg) {
    final minutes = (deg.abs() * 60).round();
    return "${deg < 0 ? '−' : '+'}${minutes ~/ 60}° ${(minutes % 60).toString().padLeft(2, '0')}′";
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

  static List<String> get _nightLabels => [
    tr('Heute Nacht', 'Tonight'),
    tr('Morgen', 'Tomorrow'),
    tr('Übermorgen', 'Day after'),
  ];

  Widget _nightSelector() => SegmentedButton<int>(
    key: const Key('night-selector'),
    showSelectedIcon: false,
    segments: [
      for (final (i, label) in _nightLabels.indexed)
        ButtonSegment(
          value: i,
          label: Text(label, key: Key('night-$i'), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
    ],
    selected: {_night},
    onSelectionChanged: (s) => _showNight(s.first),
  );

  /// Nothing has a window: say whether the sky or the season is to blame, and where to look.
  Widget _nothingUsable(RecommendedNight night) {
    final tones = context.tones;
    final clouds = night.cloudedOut || night.targets.any((r) => r.blockedBy == 'clouds');
    final title = clouds
        ? (_night == 0
              ? tr('Rest der Nacht bewölkt', 'Rest of the night clouded out')
              : tr('Diese Nacht bewölkt', 'This night clouded out'))
        : tr('Kein Ziel hoch genug im Dunkeln', 'No target high enough while it is dark');
    return Card(
      key: const Key('nothing-usable'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(clouds ? Icons.cloud_outlined : Icons.landscape_outlined, color: tones.warn),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              clouds
                  ? tr(
                      'Die Vorhersage deckt die Ziele zu, die ein klarer Himmel geben würde. Die Liste unten zeigt sie trotzdem.',
                      'The forecast covers the targets a clear sky would give. The list below shows them anyway.',
                    )
                  : tr(
                      'Kein empfohlenes Ziel steht in dieser Nacht im Dunkeln über deinem Horizont.',
                      'No recommended target stands above your horizon in the dark this night.',
                    ),
              style: TextStyle(color: tones.muted),
            ),
            if (_night < 2) ...[
              const SizedBox(height: 10),
              FilledButton.tonal(
                key: const Key('next-night'),
                onPressed: () => _showNight(_night + 1),
                child: Text(
                  _night == 0
                      ? tr('Morgen ansehen', 'Look at tomorrow')
                      : tr('Übermorgen ansehen', 'Look at the day after'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Planen', 'Plan'))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Autocomplete<SearchHit>(
          displayStringForOption: (s) => s.planName,
          optionsBuilder: (value) => _search(value.text),
          onSelected: (s) => _pick(s.planName),
          optionsViewBuilder: (context, onSelected, options) => _SearchResults(options, onSelected),
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
          SectionTitle(tr('Empfehlungen', 'Recommendations')),
          _nightSelector(),
          if (_night > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                tr(
                  'Wolken aus der Vorhersage – je weiter voraus, desto unsicherer. Dunkelheit, Mond und Höhen stimmen genau.',
                  'Clouds from the forecast – the further ahead, the less certain. Darkness, moon and altitudes are exact.',
                ),
                key: const Key('forecast-hint'),
                style: TextStyle(color: context.tones.muted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          FutureBuilder<RecommendedNight?>(
            future: _recommended,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
              final night = snap.data;
              if (night == null) return _siteChoice();
              if (night.targets.isEmpty) {
                return Text(
                  tr('Für diese Nacht keine Empfehlungen.', 'No recommendations for this night.'),
                  style: TextStyle(color: context.tones.muted),
                );
              }
              final usable = night.targets.where((r) => r.visibleHours > 0).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (night.nightStart != null && night.nightEnd != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        tr(
                          'Astronomisch dunkel ${timeRange(night.nightStart, night.nightEnd)} · ${decimal(night.darkHours, 1)} h',
                          'Astronomically dark ${timeRange(night.nightStart, night.nightEnd)} · ${decimal(night.darkHours, 1)} h',
                        ),
                        key: const Key('night-span'),
                        style: TextStyle(color: context.tones.muted, fontSize: 13),
                      ),
                    ),
                  if (usable.isEmpty) _nothingUsable(night),
                  for (final r in usable.isEmpty ? night.targets : usable)
                    RecommendationCard(
                      target: r,
                      client: widget.client,
                      fovArcmin: night.fovArcmin,
                      onTap: () => _pick(r.name, from: r),
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
              if (snap.hasError && BortleClient.isNoSite(snap.error!)) return _withoutSite(context, _object!);
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
        ObjectPreviewCard(client: widget.client, object: plan.object),
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

/// The catalogue's answers under the search field: the name, how else it is called, what it
/// is and how big.
class _SearchResults extends StatelessWidget {
  const _SearchResults(this.options, this.onSelected);

  final Iterable<SearchHit> options;
  final AutocompleteOnSelected<SearchHit> onSelected;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Align(
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
                  key: Key('hit-${hit.planName}'),
                  dense: true,
                  title: Text(hit.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [
                      if (hit.planName != hit.name) hit.planName,
                      ...hit.aliases.where((a) => a != hit.name && a != hit.planName).take(2),
                      ?hit.type,
                      if (hit.sizeArcmin != null) '${hit.sizeArcmin!.round()}′',
                    ].join(' · '),
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
