// Tools for the night, without an account (docs/CONCEPT.md, "Tools"): twilight and the
// moon, how high an object climbs and when, the optics' arithmetic, and the weather.
// Everything but the weather is computed on the phone; the site stays on it.

import 'package:flutter/material.dart';

import '../astro.dart';
import '../catalog.dart';
import '../charts.dart';
import '../design.dart';
import '../l10n.dart';
import '../optics.dart';
import '../widgets.dart';
import 'tools_store.dart';
import 'weather.dart';

class ToolsScreen extends StatefulWidget {
  ToolsScreen({
    ToolsStore? store,
    Locate? locate,
    FetchForecast? forecast,
    Future<Catalog> Function()? catalog,
    this.now,
    super.key,
  }) : store = store ?? SecureToolsStore(),
       locate = locate ?? locateWithGps,
       forecast = forecast ?? forecastFrom('https://bortle.eu'),
       catalog = catalog ?? Catalog.load;

  final ToolsStore store;
  final Locate locate;
  final FetchForecast forecast;
  final Future<Catalog> Function() catalog;

  /// The present, for tests; the clock otherwise.
  final DateTime? now;

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  Site? _site;
  bool _loaded = false;
  bool _locating = false;
  late final Future<Catalog> _catalog = widget.catalog();
  Optics? _optics;

  @override
  void initState() {
    super.initState();
    () async {
      final site = await widget.store.site();
      final optics = await widget.store.optics();
      if (mounted) {
        setState(() {
          _site = site;
          _optics = optics;
          _loaded = true;
        });
      }
    }();
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final site = await widget.locate();
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
      await _setSite(site);
    } on Exception {
      messenger.showSnackBar(SnackBar(content: Text(tr('Standort nicht gefunden.', 'Location not found.'))));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _setSite(Site site) async {
    await widget.store.setSite(site);
    if (mounted) setState(() => _site = site);
  }

  Future<void> _typeSite() async {
    final lat = TextEditingController(text: _site == null ? '' : _site!.lat.toStringAsFixed(3));
    final lon = TextEditingController(text: _site == null ? '' : _site!.lon.toStringAsFixed(3));
    final site = await showDialog<Site>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Standort eingeben', 'Enter a site')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('lat'),
              controller: lat,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(labelText: tr('Breite (Nord +, Süd −)', 'Latitude (north +, south −)')),
            ),
            TextField(
              key: const Key('lon'),
              controller: lon,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(labelText: tr('Länge (Ost +, West −)', 'Longitude (east +, west −)')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(
            key: const Key('site-ok'),
            onPressed: () {
              final a = double.tryParse(lat.text.replaceAll(',', '.'));
              final b = double.tryParse(lon.text.replaceAll(',', '.'));
              if (a == null || b == null || a.abs() > 90 || b.abs() > 180) return;
              Navigator.of(context).pop(Site(a, b));
            },
            child: Text(tr('Übernehmen', 'Use')),
          ),
        ],
      ),
    );
    if (site != null) await _setSite(site);
  }

  @override
  Widget build(BuildContext context) {
    final site = _site;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Werkzeuge für die Nacht', 'Tools for the night')),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: tr('Heute Nacht', 'Tonight')),
              Tab(text: tr('Objekte', 'Objects')),
              Tab(text: tr('Optik', 'Optics')),
              Tab(text: tr('Wetter', 'Weather')),
            ],
          ),
        ),
        body: Column(
          children: [
            Material(
              color: context.tones.surface,
              child: ListTile(
                key: const Key('site'),
                leading: const Icon(Icons.place_outlined),
                title: Text(site?.name ?? tr('Noch kein Standort', 'No site yet')),
                subtitle: Text(
                  tr('Bleibt auf dem Telefon.', 'Stays on the phone.'),
                  style: TextStyle(color: context.tones.muted, fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const Key('locate'),
                      tooltip: tr('Standort des Telefons', "The phone's location"),
                      onPressed: _locating ? null : _locate,
                      icon: _locating
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location),
                    ),
                    IconButton(
                      key: const Key('type-site'),
                      tooltip: tr('Eingeben', 'Type it'),
                      onPressed: _typeSite,
                      icon: const Icon(Icons.edit_location_alt_outlined),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [
                        site == null ? _NoSite(onLocate: _locate, onType: _typeSite) : _TonightTab(site, widget.now),
                        site == null
                            ? _NoSite(onLocate: _locate, onType: _typeSite)
                            : _ObjectsTab(site: site, catalog: _catalog, optics: _optics, now: widget.now),
                        _OpticsTab(
                          optics: _optics,
                          onChanged: (o) {
                            setState(() => _optics = o);
                            widget.store.setOptics(o);
                          },
                        ),
                        site == null
                            ? _NoSite(onLocate: _locate, onType: _typeSite)
                            : _WeatherTab(site: site, forecast: widget.forecast, now: widget.now),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoSite extends StatelessWidget {
  const _NoSite({required this.onLocate, required this.onType});

  final VoidCallback onLocate;
  final VoidCallback onType;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        tr(
          'Für Dämmerung, Mond und Objekthöhen braucht es den Ort, an dem du beobachtest. Er wird nur auf dem Telefon verwendet.',
          'Twilight, the moon and altitudes need the place you observe from. It is used on the phone only.',
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: onLocate,
        icon: const Icon(Icons.my_location),
        label: Text(tr('Standort des Telefons verwenden', "Use the phone's location")),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: onType,
        icon: const Icon(Icons.edit_location_alt_outlined),
        label: Text(tr('Breite und Länge eingeben', 'Enter latitude and longitude')),
      ),
    ],
  );
}

String _t(DateTime? t) => t == null ? '–' : clock(t);

String _hours(Duration d) => '${decimal(d.inMinutes / 60, 1)} h';

/// The evening a night belongs to: before noon it is still last night.
DateTime _evening(DateTime now) {
  final local = now.toLocal();
  final day = local.hour < 12 ? local.subtract(const Duration(days: 1)) : local;
  return DateTime(day.year, day.month, day.day);
}

class _TonightTab extends StatefulWidget {
  const _TonightTab(this.site, this.now);

  final Site site;
  final DateTime? now;

  @override
  State<_TonightTab> createState() => _TonightTabState();
}

class _TonightTabState extends State<_TonightTab> {
  int _offset = 0;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final day = _evening(widget.now ?? DateTime.now()).add(Duration(days: _offset));
    final night = Night.at(day, widget.site.lat, widget.site.lon);
    final mid = night.samples[night.samples.length ~/ 2].time;
    final illum = moonIllumination(mid);
    final moon = night.moonRiseSet;
    final window = night.bestWindow;
    final (sunset, sunrise) = night.sun;
    final (astroStart, astroEnd) = night.astronomical;
    final from = (sunset ?? night.from).subtract(const Duration(hours: 1));
    final to = (sunrise ?? night.to).add(const Duration(hours: 1));
    final shown = night.samples.where((s) => !s.time.isBefore(from) && !s.time.isAfter(to)).toList();
    Widget row(String label, String value, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: tones.muted)),
          ),
          Text(
            value,
            style: TextStyle(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: _offset > -1 ? () => setState(() => _offset--) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                switch (_offset) {
                  0 => tr('Heute Nacht', 'Tonight'),
                  1 => tr('Morgen Nacht', 'Tomorrow night'),
                  -1 => tr('Letzte Nacht', 'Last night'),
                  _ => tr(
                    'Nacht zum ${dayMonth(day.add(const Duration(days: 1)))}',
                    'Night to ${dayMonth(day.add(const Duration(days: 1)))}',
                  ),
                },
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              key: const Key('next-night'),
              onPressed: _offset < 30 ? () => setState(() => _offset++) : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  window == null
                      ? tr('Keine dunkle Stunde ohne Mond', 'No dark hour without the moon')
                      : tr(
                          'Dunkel ohne Mond: ${_t(window.$1)}–${_t(window.$2)}',
                          'Dark without the moon: ${_t(window.$1)}–${_t(window.$2)}',
                        ),
                  key: const Key('window'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  astroStart == null
                      ? tr(
                          'Es wird nicht astronomisch dunkel – die Sonne bleibt höher als 18° unter dem Horizont.',
                          'It does not get astronomically dark – the sun stays higher than 18° below the horizon.',
                        )
                      : tr(
                          '${_hours(night.darkness)} astronomisch dunkel, davon ${_hours(night.moonlessDarkness)} ohne Mond.',
                          '${_hours(night.darkness)} astronomically dark, ${_hours(night.moonlessDarkness)} of it without the moon.',
                        ),
                  style: TextStyle(color: tones.muted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tr('Sonne und Mond (Höhe in °)', 'Sun and moon (altitude in °)'),
          style: TextStyle(color: tones.muted, fontSize: 12),
        ),
        TimeChart(
          label: tr('Sonne und Mond (Höhe in °)', 'Sun and moon (altitude in °)'),
          series: [
            Series([for (final s in shown) ChartPoint(s.time, s.sun)], tones.warn),
            Series([for (final s in shown) ChartPoint(s.time, s.moon)], tones.muted, dashed: true),
          ],
          bands: [
            if (astroStart != null && astroEnd != null)
              TimeBand(astroStart, astroEnd, Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)),
            if (window != null)
              TimeBand(window.$1, window.$2, Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)),
          ],
          minY: -60,
          maxY: 60,
          guideY: 0,
          height: 170,
        ),
        SectionTitle(tr('Sonne', 'Sun')),
        row(tr('Untergang', 'Sunset'), _t(sunset)),
        row(tr('Bürgerliche Dämmerung bis', 'Civil twilight until'), _t(night.civil.$1)),
        row(tr('Nautische Dämmerung bis', 'Nautical twilight until'), _t(night.nautical.$1)),
        row(tr('Astronomisch dunkel ab', 'Astronomically dark from'), _t(astroStart)),
        row(tr('Astronomisch dunkel bis', 'Astronomically dark until'), _t(astroEnd)),
        row(tr('Aufgang', 'Sunrise'), _t(sunrise)),
        SectionTitle(tr('Mond', 'Moon')),
        row(
          tr('Beleuchtet', 'Illuminated'),
          '${(illum * 100).round()} % · ${moonWaxing(mid) ? tr('zunehmend', 'waxing') : tr('abnehmend', 'waning')}',
        ),
        row(tr('Aufgang', 'Moonrise'), _t(moon.$1)),
        row(tr('Untergang', 'Moonset'), _t(moon.$2)),
        const SizedBox(height: 12),
        Text(
          tr(
            'Zeiten in der Zeitzone des Telefons, auf etwa zwei Minuten genau; ohne Höhe über dem Meer und Gelände.',
            "Times in the phone's time zone, to about two minutes; without elevation and terrain.",
          ),
          style: TextStyle(color: tones.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _ObjectsTab extends StatefulWidget {
  const _ObjectsTab({required this.site, required this.catalog, required this.optics, required this.now});

  final Site site;
  final Future<Catalog> catalog;
  final Optics? optics;
  final DateTime? now;

  @override
  State<_ObjectsTab> createState() => _ObjectsTabState();
}

class _ObjectsTabState extends State<_ObjectsTab> {
  String _query = '';
  late final Night _night = Night.at(_evening(widget.now ?? DateTime.now()), widget.site.lat, widget.site.lon);
  List<(SkyObject, ObjectNight)>? _ranked;

  void _rank(Catalog c) {
    if (_ranked != null) return;
    final all = [for (final o in c.objects) (o, ObjectNight(_night, o.ra, o.dec))];
    all.sort(
      (a, b) => b.$2.usableMoonless.compareTo(a.$2.usableMoonless) != 0
          ? b.$2.usableMoonless.compareTo(a.$2.usableMoonless)
          : b.$2.usable.compareTo(a.$2.usable),
    );
    _ranked = all;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Catalog>(
    future: widget.catalog,
    builder: (context, snap) {
      final c = snap.data;
      if (c == null) return const Center(child: CircularProgressIndicator());
      _rank(c);
      final list = _query.trim().isEmpty
          ? _ranked!.where((e) => e.$1.curated || e.$1.ids.first.startsWith('M')).take(25).toList()
          : [for (final o in c.search(_query)) _ranked!.firstWhere((e) => e.$1 == o)];
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('object-search'),
            decoration: InputDecoration(
              labelText: tr('Objekt suchen', 'Search an object'),
              hintText: tr('z. B. M 31, Orion, NGC 7000', 'e.g. M 31, Orion, NGC 7000'),
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          if (_query.trim().isEmpty) SectionTitle(tr('Am besten heute Nacht', 'Best tonight')),
          for (final (o, v) in list)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(o.name),
              subtitle: Text(
                '${o.label} · ${o.typeName}\n${v.usable == Duration.zero ? tr('heute nicht über 30° im Dunkeln', 'not above 30° in the dark tonight') : tr('${_hours(v.usable)} über 30°, ${_hours(v.usableMoonless)} ohne Mond', '${_hours(v.usable)} above 30°, ${_hours(v.usableMoonless)} without the moon')}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _ObjectScreen(object: o, visibility: v, optics: widget.optics),
                ),
              ),
            ),
          if (list.isEmpty)
            Text(tr('Nichts gefunden.', 'Nothing found.'), style: TextStyle(color: context.tones.muted)),
          const SizedBox(height: 12),
          Text(
            tr(
              '511 Objekte: Bortles kuratierte Ziele, alle Messier-Objekte und helle NGC/IC-Objekte aus OpenNGC (CC BY-SA 4.0).',
              "511 objects: Bortle's curated targets, every Messier object and bright NGC/IC objects from OpenNGC (CC BY-SA 4.0).",
            ),
            style: TextStyle(color: context.tones.muted, fontSize: 12),
          ),
        ],
      );
    },
  );
}

class _ObjectScreen extends StatelessWidget {
  const _ObjectScreen({required this.object, required this.visibility, required this.optics});

  final SkyObject object;
  final ObjectNight visibility;
  final Optics? optics;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final night = visibility.night;
    final (sunset, sunrise) = night.sun;
    final (dark, dawn) = night.astronomical;
    final from = (sunset ?? night.from).subtract(const Duration(hours: 1));
    final to = (sunrise ?? night.to).add(const Duration(hours: 1));
    final idx = [
      for (var i = 0; i < night.samples.length; i++)
        if (!night.samples[i].time.isBefore(from) && !night.samples[i].time.isAfter(to)) i,
    ];
    final best = visibility.bestInDarkness;
    final o = optics;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: tones.muted)),
          ),
          Text(value),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(object.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${object.label} · ${object.typeName}', style: TextStyle(color: tones.muted)),
          const SizedBox(height: 12),
          Text(tr('Höhe heute Nacht (°)', 'Altitude tonight (°)'), style: TextStyle(color: tones.muted, fontSize: 12)),
          TimeChart(
            label: tr('Höhe heute Nacht (°)', 'Altitude tonight (°)'),
            series: [
              Series([
                for (final i in idx) ChartPoint(night.samples[i].time, visibility.altitudes[i]),
              ], Theme.of(context).colorScheme.primary),
              Series(
                [for (final i in idx) ChartPoint(night.samples[i].time, night.samples[i].moon)],
                tones.muted,
                dashed: true,
              ),
            ],
            bands: [
              if (dark != null && dawn != null)
                TimeBand(dark, dawn, Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)),
            ],
            minY: 0,
            maxY: 90,
            guideY: visibility.minAltitude,
            height: 190,
          ),
          const SizedBox(height: 8),
          row(
            tr('Am höchsten im Dunkeln', 'Highest in the dark'),
            best == null ? '–' : '${best.$1.round()}° · ${clock(best.$2)}',
          ),
          row(tr('Über 30° im Dunkeln', 'Above 30° in the dark'), _hours(visibility.usable)),
          row(tr('Davon ohne Mond', 'Of that without the moon'), _hours(visibility.usableMoonless)),
          row(tr('Abstand zum Mond', 'Distance to the moon'), '${visibility.moonDistance.round()}°'),
          if (object.size != null) row(tr('Größe', 'Size'), '${decimal(object.size!, object.size! < 10 ? 1 : 0)}′'),
          if (object.mag != null) row(tr('Helligkeit', 'Magnitude'), '${decimal(object.mag!, 1)} mag'),
          if (o != null && object.size != null) ...[
            SectionTitle(tr('Mit deiner Optik', 'With your optics')),
            row(
              tr('Füllt das Bildfeld', 'Fills the field'),
              '${(o.fill(object.size!) * 100).round()} % ${tr('der kurzen Seite', 'of the short side')}',
            ),
            Text(
              o.fill(object.size!) > 1
                  ? tr(
                      'Größer als das Feld – ein Mosaik oder kürzere Brennweite.',
                      'Larger than the field – a mosaic or a shorter focal length.',
                    )
                  : o.fill(object.size!) < 0.15
                  ? tr(
                      'Klein im Feld – längere Brennweite oder ein Ausschnitt.',
                      'Small in the field – a longer focal length or a crop.',
                    )
                  : tr('Passt gut.', 'Fits well.'),
              style: TextStyle(color: tones.muted),
            ),
          ],
          if (object.filter != null) ...[
            const SizedBox(height: 12),
            Text(switch (object.filter) {
              'narrowband' => tr(
                'Lohnt sich mit Schmalband (Hα/OIII) – auch unter hellem Himmel.',
                'Worth it in narrowband (Hα/OIII) – under a bright sky too.',
              ),
              'broadband' => tr(
                'Ein Breitband-Ziel: dunkler Himmel und wenig Mond zählen.',
                'A broadband target: a dark sky and little moon count.',
              ),
              _ => tr('Geht in Breitband wie Schmalband.', 'Works in broadband and narrowband alike.'),
            }, style: TextStyle(color: tones.muted)),
          ],
        ],
      ),
    );
  }
}

// Common astro cameras: pixel size and sensor in pixels.
const _cameras = <String, (double, int, int)>{
  'IMX571 (ASI2600, …)': (3.76, 6248, 4176),
  'IMX533 (ASI533, …)': (3.76, 3008, 3008),
  'IMX585 (ASI585, …)': (2.9, 3840, 2160),
  'IMX294 (ASI294, …)': (4.63, 4144, 2822),
  'IMX183 (ASI183, …)': (2.4, 5496, 3672),
  'IMX455 (ASI6200, …)': (3.76, 9576, 6388),
};

class _OpticsTab extends StatefulWidget {
  const _OpticsTab({required this.optics, required this.onChanged});

  final Optics? optics;
  final ValueChanged<Optics> onChanged;

  @override
  State<_OpticsTab> createState() => _OpticsTabState();
}

class _OpticsTabState extends State<_OpticsTab> {
  late final _focal = TextEditingController(text: _n(widget.optics?.focalMm ?? 530));
  late final _aperture = TextEditingController(text: _n(widget.optics?.apertureMm ?? 106));
  late final _pixel = TextEditingController(text: _n(widget.optics?.pixelUm ?? 3.76));
  late final _width = TextEditingController(text: '${widget.optics?.widthPx ?? 6248}');
  late final _height = TextEditingController(text: '${widget.optics?.heightPx ?? 4176}');
  late double _seeing = widget.optics?.seeingArcsec ?? 2.5;
  late int _bin = widget.optics?.binning ?? 1;

  static String _n(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

  Optics? get _current {
    double? d(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.'));
    final f = d(_focal), a = d(_aperture), p = d(_pixel);
    final w = int.tryParse(_width.text), h = int.tryParse(_height.text);
    if (f == null ||
        a == null ||
        p == null ||
        w == null ||
        h == null ||
        f <= 0 ||
        a <= 0 ||
        p <= 0 ||
        w <= 0 ||
        h <= 0) {
      return null;
    }
    return Optics(focalMm: f, apertureMm: a, pixelUm: p, widthPx: w, heightPx: h, seeingArcsec: _seeing, binning: _bin);
  }

  void _changed() {
    final o = _current;
    setState(() {});
    if (o != null) widget.onChanged(o);
  }

  Widget _field(TextEditingController c, String label, String suffix, Key key) => Expanded(
    child: TextField(
      key: key,
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      onChanged: (_) => _changed(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final o = _current;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: tones.muted)),
          ),
          Text(value, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            _field(_focal, tr('Brennweite', 'Focal length'), 'mm', const Key('focal')),
            const SizedBox(width: 12),
            _field(_aperture, tr('Öffnung', 'Aperture'), 'mm', const Key('aperture')),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in _cameras.entries)
              ActionChip(
                label: Text(e.key),
                onPressed: () {
                  _pixel.text = _n(e.value.$1);
                  _width.text = '${e.value.$2}';
                  _height.text = '${e.value.$3}';
                  _changed();
                },
              ),
          ],
        ),
        Row(
          children: [
            _field(_pixel, tr('Pixel', 'Pixel'), 'µm', const Key('pixel')),
            const SizedBox(width: 12),
            _field(_width, tr('Breite', 'Width'), 'px', const Key('width')),
            const SizedBox(width: 12),
            _field(_height, tr('Höhe', 'Height'), 'px', const Key('height')),
          ],
        ),
        const SizedBox(height: 12),
        Text('${tr('Seeing am Standort', 'Seeing at the site')}: ${decimal(_seeing, 1)}″'),
        Slider(
          value: _seeing,
          min: 1,
          max: 5,
          divisions: 40,
          label: '${decimal(_seeing, 1)}″',
          onChanged: (v) {
            _seeing = v;
            _changed();
          },
        ),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('Bin 1')),
            ButtonSegment(value: 2, label: Text('Bin 2')),
            ButtonSegment(value: 3, label: Text('Bin 3')),
          ],
          selected: {_bin},
          onSelectionChanged: (s) {
            _bin = s.first;
            _changed();
          },
        ),
        const SizedBox(height: 12),
        if (o == null)
          Text(
            tr('Alle Felder brauchen eine Zahl größer als 0.', 'Every field needs a number above 0.'),
            style: TextStyle(color: tones.warn),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  row(tr('Öffnungsverhältnis', 'Focal ratio'), 'f/${decimal(o.fRatio, 1)}'),
                  row(tr('Abbildungsmaßstab', 'Image scale'), '${decimal(o.scale, 2)}″/px'),
                  row(
                    tr('Bildfeld', 'Field of view'),
                    o.fieldWidth >= 60
                        ? '${decimal(o.fieldWidth / 60, 2)}° × ${decimal(o.fieldHeight / 60, 2)}°'
                        : '${decimal(o.fieldWidth, 1)}′ × ${decimal(o.fieldHeight, 1)}′',
                  ),
                  row(tr('Sensor', 'Sensor'), '${decimal(o.sensorWidthMm, 1)} × ${decimal(o.sensorHeightMm, 1)} mm'),
                  row(tr('Auflösungsgrenze (Dawes)', 'Resolving limit (Dawes)'), '${decimal(o.dawes, 2)}″'),
                  row(tr('Stern über Pixel (FWHM)', 'Star across pixels (FWHM)'), decimal(o.pixelsPerFwhm, 1)),
                  const SizedBox(height: 8),
                  Text(
                    switch (o.sampling) {
                      Sampling.under => tr(
                        'Unterabgetastet: ein Stern fällt auf weniger als 1,5 Pixel – Sterne wirken eckig, Details gehen verloren. Längere Brennweite, kleinere Pixel oder Drizzle helfen.',
                        'Undersampled: a star falls on fewer than 1.5 pixels – stars look blocky, detail is lost. A longer focal length, smaller pixels or drizzle help.',
                      ),
                      Sampling.good => tr(
                        'Gut abgetastet: 1,5 bis 3,5 Pixel pro Stern passen zum Seeing.',
                        'Well sampled: 1.5 to 3.5 pixels per star suit the seeing.',
                      ),
                      Sampling.over => tr(
                        'Überabgetastet: mehr als 3,5 Pixel pro Stern bringen keine Details, nur Rauschen pro Pixel. Binning 2× lohnt sich.',
                        'Oversampled: more than 3.5 pixels per star add no detail, only noise per pixel. Binning 2× pays off.',
                      ),
                    },
                    key: const Key('sampling'),
                    style: TextStyle(color: o.sampling == Sampling.good ? tones.good : tones.warn),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          tr(
            'Die Werte bleiben auf dem Telefon. Mit gespeicherter Optik zeigt jedes Objekt, wie viel vom Bildfeld es füllt.',
            'The values stay on the phone. With optics saved, every object shows how much of the field it fills.',
          ),
          style: TextStyle(color: tones.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _WeatherTab extends StatefulWidget {
  const _WeatherTab({required this.site, required this.forecast, required this.now});

  final Site site;
  final FetchForecast forecast;
  final DateTime? now;

  @override
  State<_WeatherTab> createState() => _WeatherTabState();
}

class _WeatherTabState extends State<_WeatherTab> {
  Future<Forecast>? _future;

  @override
  void didUpdateWidget(_WeatherTab old) {
    super.didUpdateWidget(old);
    if (old.site.lat != widget.site.lat || old.site.lon != widget.site.lon) _future = null;
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    if (_future == null) {
      // Asked for only when the person opens it: this is the one part that leaves the phone.
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            tr(
              'Die Vorhersage fragt bortle.eu mit deinem auf etwa 10 km gerundeten Ort; bortle.eu fragt Open-Meteo (Wolken, Feuchte, Wind) und 7Timer! (Seeing, Durchsicht). Gespeichert wird nichts.',
              'The forecast asks bortle.eu with your place rounded to about 10 km; bortle.eu asks Open-Meteo (clouds, humidity, wind) and 7Timer! (seeing, transparency). Nothing is kept.',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('load-weather'),
            onPressed: () => setState(() {
              _future = widget.forecast(widget.site.lat, widget.site.lon);
            }),
            icon: const Icon(Icons.cloud_download_outlined),
            label: Text(tr('Vorhersage laden', 'Load the forecast')),
          ),
        ],
      );
    }
    return FutureBuilder<Forecast>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return LoadError(
            snap.error!,
            onRetry: () => setState(() {
              _future = widget.forecast(widget.site.lat, widget.site.lon);
            }),
          );
        }
        final f = snap.data;
        if (f == null) return const Center(child: CircularProgressIndicator());
        final now = widget.now ?? DateTime.now();
        final night = Night.at(_evening(now), widget.site.lat, widget.site.lon);
        final (start, end) = night.astronomical;
        final dark = f.hours
            .where((h) => start != null && end != null && !h.time.isBefore(start) && h.time.isBefore(end))
            .toList();
        final clear = dark.where((h) => (h.cloud ?? 100) < 20).length;
        final hours = f.hours.where((h) => !h.time.isBefore(now.subtract(const Duration(hours: 1)))).take(36).toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              start == null
                  ? tr('Heute wird es nicht astronomisch dunkel.', 'It does not get astronomically dark tonight.')
                  : tr(
                      'Heute Nacht: $clear von ${dark.length} dunklen Stunden klar (Wolken unter 20 %).',
                      'Tonight: $clear of ${dark.length} dark hours clear (clouds under 20 %).',
                    ),
              key: const Key('clear-hours'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            for (final h in hours) _HourRow(h, dark: dark.contains(h)),
            const SizedBox(height: 12),
            Text(
              '${tr('Quellen', 'Sources')}: ${f.sources.join(' · ')}. '
              '${tr('Seeing und Durchsicht sind Modellwerte in Klassen, keine Messung.', 'Seeing and transparency are model classes, not measurements.')}',
              style: TextStyle(color: tones.muted, fontSize: 12),
            ),
          ],
        );
      },
    );
  }
}

class _HourRow extends StatelessWidget {
  const _HourRow(this.h, {required this.dark});

  final WeatherHour h;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final cloud = h.cloud ?? 0;
    final spread = h.dewSpread;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              clock(h.time),
              style: TextStyle(fontWeight: dark ? FontWeight.w700 : FontWeight.w400, color: dark ? null : tones.muted),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: cloud / 100,
                    minHeight: 6,
                    color: cloud < 20 ? tones.good : (cloud < 60 ? tones.warn : tones.danger),
                    backgroundColor: tones.line,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    '${tr('Wolken', 'Clouds')} ${cloud.round()} %',
                    if (h.seeing != null) 'Seeing ${seeingText(h.seeing!)}',
                    if (h.transparency != null) transparencyText(h.transparency!),
                    if (h.wind != null) '${tr('Wind', 'Wind')} ${h.wind!.round()} km/h',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12),
                ),
                if (spread != null && spread < 3)
                  Text(
                    tr(
                      'Taugefahr: nur ${decimal(spread, 1)} °C bis zum Taupunkt',
                      'Dew risk: only ${decimal(spread, 1)} °C to the dew point',
                    ),
                    style: TextStyle(color: tones.warn, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
