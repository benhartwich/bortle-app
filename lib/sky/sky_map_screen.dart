// "Sternkarte": the sky over the account's site, now or up to twelve hours either way,
// with tonight's recommended targets, the catalogue search, where the mount points and
// – optionally – the part of the sky the phone is held against.
//
// Everything is computed on the phone (lib/sky/sky_math.dart on top of lib/astro.dart);
// the server is asked for the site and the targets (plan/recommend), for names
// (plan/search, plan/resolve) and, for the operator, for the mount (nina/live).

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../api/bortle_client.dart';
import '../api/models.dart';
import '../design.dart';
import '../l10n.dart';
import '../rig/rig_models.dart';
import 'phone_aim.dart';
import 'sky_catalog.dart';
import 'sky_math.dart';
import 'sky_painter.dart';

/// What "Einrahmen" hands on: the name and its J2000 position.
typedef FrameObject = void Function(String name, double raDeg, double decDeg);

class SkyMapScreen extends StatefulWidget {
  const SkyMapScreen({
    required this.client,
    this.highlightTarget,
    this.onFrame,
    this.site,
    this.catalog,
    this.aimSource,
    this.clock,
    super.key,
  });

  final BortleClient client;

  /// A target to centre and select once the map is up: one of tonight's, or any name
  /// the server can resolve.
  final String? highlightTarget;

  /// "Einrahmen" on the object card; the button is hidden without it.
  final FrameObject? onFrame;

  /// Latitude and longitude to use instead of the account's site (the tools without an
  /// account have their own).
  final (double, double)? site;

  /// The stars and figures; the bundled asset when null.
  final SkyCatalog? catalog;

  /// The phone's orientation; its sensors when null.
  final AimSource? aimSource;

  /// The present; DateTime.now when null.
  final DateTime Function()? clock;

  @override
  State<SkyMapScreen> createState() => SkyMapScreenState();
}

/// What a tap picked, for the card.
class _Picked {
  const _Picked({
    required this.name,
    required this.ra,
    required this.dec,
    this.jNow = false,
    this.detail,
    this.frame = true,
  });

  final String name;
  final double ra;
  final double dec;
  final bool jNow;
  final String? detail;

  /// Whether "Einrahmen" makes sense (not for the mount's own position).
  final bool frame;
}

class SkyMapScreenState extends State<SkyMapScreen> {
  SkyCatalog? _catalog;
  Object? _catalogError;

  (double, double)? _site;
  bool _siteLoading = true;

  List<Recommendation> _targets = const [];
  SkyMarker? _searchMarker;
  SkyMarker? _mountMarker;
  _Picked? _picked;

  // the view: an all-sky circle around the zenith to begin with
  double _az = 180;
  double _alt = 90;
  double _fov = 190;
  double _fovAtStart = 190;
  bool _grid = true;

  /// Minutes from now, −720 … 720.
  double _offset = 0;
  Timer? _tick;

  bool _aiming = false;
  StreamSubscription<PhoneAim>? _aim;
  Timer? _aimWatchdog;
  PhoneAim? _phone;

  bool _mountShown = false;
  bool _mountFollow = false;
  Timer? _mountTimer;
  String? _mountNote;

  final _search = TextEditingController();
  int _searchSeq = 0;
  List<SearchHit> _hits = const [];

  final _labels = LabelCache();

  DateTime get _now => (widget.clock ?? DateTime.now)();

  /// The instant the map shows.
  DateTime get time => _now.add(Duration(minutes: _offset.round()));

  /// The view's centre, for tests and the compass: azimuth, altitude, field of view.
  (double, double, double) get view => (_az, _alt, _fov);

  /// Where the centre of the view sits on the canvas, as a fraction of its height: above
  /// the middle, in the part the search field and the controls leave free.
  static const centreY = 0.42;

  /// The projection for a canvas of [size], as the painter and the taps use it.
  SkyView viewFor(Size size) =>
      SkyView(az: _az, alt: _alt, fov: _fov, size: size, centre: Offset(size.width / 2, size.height * centreY));

  @override
  void initState() {
    super.initState();
    _loadCatalog();
    _loadSite();
    // the sky turns a quarter of a degree a minute: redraw now and then
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _aim?.cancel();
    _aimWatchdog?.cancel();
    _mountTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    try {
      final c = widget.catalog ?? await SkyCatalog.load();
      if (mounted) setState(() => _catalog = c);
    } on Object catch (e) {
      if (mounted) setState(() => _catalogError = e);
    }
  }

  /// The site: given, else the account's (the recommendation says which it ranked for),
  /// else the one the mount believes in.
  Future<void> _loadSite() async {
    (double, double)? site = widget.site;
    try {
      final night = await widget.client.recommendNight();
      _targets = [
        for (final t in night.targets)
          if (t.raDeg != null && t.decDeg != null) t,
      ];
      if (site == null && night.siteLat != null && night.siteLon != null) site = (night.siteLat!, night.siteLon!);
    } on Object {
      // no site in the profile, or no server: the targets stay empty
    }
    if (site == null) {
      try {
        final mount = RigState.fromJson(await widget.client.rigLive()).mount;
        if (mount.siteLat != null && mount.siteLon != null) site = (mount.siteLat!, mount.siteLon!);
      } on Object {
        // not the operator, or NINA away
      }
    }
    if (!mounted) return;
    setState(() {
      _site = site;
      _siteLoading = false;
    });
    final highlight = widget.highlightTarget;
    if (site != null && highlight != null && highlight.trim().isNotEmpty) await _highlight(highlight);
  }

  Future<void> _highlight(String name) async {
    final lower = name.trim().toLowerCase();
    for (final t in _targets) {
      if (t.name.toLowerCase() == lower) {
        _centreOn(t.raDeg!, t.decDeg!);
        setState(() => _picked = _Picked(name: t.name, ra: t.raDeg!, dec: t.decDeg!, detail: _typeName(t.type)));
        return;
      }
    }
    await _goTo(name, name);
  }

  SkyFrame? get _frame => _site == null ? null : SkyFrame.at(_site!.$1, _site!.$2, time);

  void _centreOn(double ra, double dec, {bool jNow = false, bool zoom = true}) {
    final frame = _frame;
    if (frame == null) return;
    final (a, h) = frame.horizontal(ra, dec, jNow: jNow);
    setState(() {
      _az = a;
      _alt = h.clamp(-60.0, 90.0);
      if (zoom && _fov > 70) _fov = 70;
    });
  }

  // --- search --------------------------------------------------------------------

  Future<void> _onSearch(String text) async {
    final seq = ++_searchSeq;
    if (text.trim().length < 2) {
      setState(() => _hits = const []);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (seq != _searchSeq) return;
    List<SearchHit> hits;
    try {
      hits = await widget.client.search(text, limit: 6);
    } on Object {
      hits = const [];
    }
    if (mounted && seq == _searchSeq) setState(() => _hits = hits);
  }

  Future<void> _goTo(String planName, String label) async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _hits = const []);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final hit = await widget.client.resolve(planName);
      if (!mounted) return;
      final name = label == planName ? (hit.common != null ? '${hit.name} · ${hit.common}' : hit.name) : label;
      setState(() {
        _searchMarker = SkyMarker(name: name, ra: hit.raDeg, dec: hit.decDeg, kind: MarkerKind.search);
        _picked = _Picked(name: name, ra: hit.raDeg, dec: hit.decDeg, detail: planName == label ? null : planName);
        _stopFollowing();
      });
      _centreOn(hit.raDeg, hit.decDeg);
    } on Object {
      messenger.showSnackBar(
        SnackBar(content: Text(tr('„$label“ kennt Bortle nicht.', 'Bortle does not know "$label".'))),
      );
    }
  }

  /// Centre the map on a search hit, as tapping it in the list does.
  Future<void> centreOnSearchHit(SearchHit hit) => _goTo(hit.planName, hit.name);

  // --- phone orientation ---------------------------------------------------------

  void _setAiming(bool on) {
    _aim?.cancel();
    _aim = null;
    _aimWatchdog?.cancel();
    if (!on) {
      setState(() {
        _aiming = false;
        _phone = null;
      });
      return;
    }
    setState(() {
      _aiming = true;
      _mountFollow = false;
    });
    void unavailable() {
      if (!mounted || !_aiming) return;
      _setAiming(false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Keine Lage-Sensoren: dieses Gerät meldet keinen Kompass oder keine Neigung.',
              'No orientation sensors: this device reports no compass or tilt.',
            ),
          ),
        ),
      );
    }

    // no reading within a few seconds is as good as no sensor
    _aimWatchdog = Timer(const Duration(seconds: 3), () {
      if (_phone == null) unavailable();
    });
    try {
      _aim = (widget.aimSource ?? const SensorAimSource()).aims().listen((aim) {
        if (!mounted) return;
        setState(() {
          _phone = aim;
          _az = aim.az;
          _alt = aim.alt.clamp(-60.0, 90.0);
        });
      }, onError: (Object _) => unavailable());
    } on Object {
      unavailable();
    }
  }

  // --- the mount -----------------------------------------------------------------

  void _setMountShown(bool on) {
    _mountTimer?.cancel();
    setState(() {
      _mountShown = on;
      if (!on) {
        _mountFollow = false;
        _mountMarker = null;
        _mountNote = null;
      }
    });
    if (on) {
      _pollMount();
      _mountTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollMount());
    }
  }

  void _setMountFollow(bool on) {
    if (on && !_mountShown) _setMountShown(true);
    if (on && _aiming) _setAiming(false);
    setState(() => _mountFollow = on);
    final m = _mountMarker;
    if (on && m != null) _centreOn(m.ra, m.dec, jNow: true, zoom: false);
  }

  void _stopFollowing() => _mountFollow = false;

  Future<void> _pollMount() async {
    String? note;
    SkyMarker? marker;
    try {
      final mount = RigState.fromJson(await widget.client.rigLive()).mount;
      if (!mount.connected) {
        note = tr('Montierung nicht verbunden', 'Mount not connected');
      } else if (mount.raDeg == null || mount.decDeg == null) {
        note = tr('Montierung meldet keine Koordinaten', 'Mount reports no coordinates');
      } else {
        // The mount reads out of date (JNow), the catalogue is J2000: the marker is
        // placed with the frame of date, not precessed a second time. Mixing them
        // up would cost ~0.35° today – invisible on a whole-sky map, but no reason
        // to be wrong.
        marker = SkyMarker(
          name: tr('Montierung', 'Mount'),
          ra: mount.raDeg!,
          dec: mount.decDeg!,
          kind: MarkerKind.mount,
          jNow: true,
        );
      }
    } on BortleError catch (e) {
      note = e.message;
    } on Object {
      note = tr('Montierung nicht erreichbar', 'Mount not reachable');
    }
    if (!mounted || !_mountShown) return;
    setState(() {
      _mountMarker = marker;
      _mountNote = note;
    });
    if (_mountFollow && marker != null) _centreOn(marker.ra, marker.dec, jNow: true, zoom: false);
  }

  // --- gestures ------------------------------------------------------------------

  void _onScaleStart(ScaleStartDetails d) => _fovAtStart = _fov;

  void _onScaleUpdate(ScaleUpdateDetails d, Size size) {
    final view = viewFor(size);
    final dpp = view.degreesPerPixel;
    setState(() {
      if (d.pointerCount > 1 || d.scale != 1) _fov = (_fovAtStart / d.scale).clamp(5.0, 200.0);
      // the phone or the mount steers; a drag then only zooms
      if (_aiming || _mountFollow) return;
      _az = (_az - d.focalPointDelta.dx * dpp) % 360;
      _alt = (_alt + d.focalPointDelta.dy * dpp).clamp(-60.0, 90.0);
    });
  }

  void _onTap(Offset at, Size size) {
    final frame = _frame;
    final catalog = _catalog;
    if (frame == null || catalog == null) return;
    final view = viewFor(size);
    _Picked? best;
    var bestDistance = 28.0;
    for (final m in _markers) {
      final (a, h) = frame.horizontal(m.ra, m.dec, jNow: m.jNow);
      final p = view.projectAzAlt(a, h);
      if (p == null) continue;
      final d = (p - at).distance;
      if (d < bestDistance) {
        bestDistance = d;
        final target = _targets.where((t) => t.name == m.name).firstOrNull;
        best = _Picked(
          name: m.name,
          ra: m.ra,
          dec: m.dec,
          jNow: m.jNow,
          frame: m.kind != MarkerKind.mount,
          detail: m.kind == MarkerKind.mount ? 'JNow' : _typeName(target?.type),
        );
      }
    }
    if (best == null) {
      // the stars: a little closer, so a target next to a bright star stays reachable
      bestDistance = 20;
      final limit = magnitudeLimit(_fov);
      for (var i = 0; i < catalog.length && catalog.mag[i] <= limit; i++) {
        final (a, h) = frame.horizontal(catalog.ra[i].toDouble(), catalog.dec[i].toDouble());
        final p = view.projectAzAlt(a, h);
        if (p == null) continue;
        final d = (p - at).distance;
        if (d < bestDistance) {
          bestDistance = d;
          best = _Picked(
            name: catalog.names[i] ?? tr('Stern', 'Star'),
            ra: catalog.ra[i].toDouble(),
            dec: catalog.dec[i].toDouble(),
            detail: '${tr('Helligkeit', 'Magnitude')} ${decimal(catalog.mag[i], 1)}',
          );
        }
      }
    }
    setState(() => _picked = best);
  }

  // --- building ------------------------------------------------------------------

  List<SkyMarker> get _markers => [
    for (final t in _targets) SkyMarker(name: t.name, ra: t.raDeg!, dec: t.decDeg!, kind: MarkerKind.target),
    ?_searchMarker,
    ?_mountMarker,
  ];

  static String? _typeName(String? type) => type?.replaceAll('_', ' ');

  String _heading(double az) => '${compassPoint(az, english: appEnglish)} ${decimal(az, 1)}°';

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Sternkarte', 'Sky map'))),
      body: _body(context, tones),
    );
  }

  Widget _body(BuildContext context, Tones tones) {
    if (_catalogError != null) {
      return Center(child: Text(tr('Sternkatalog nicht lesbar.', 'Star catalogue unreadable.')));
    }
    final catalog = _catalog;
    if (catalog == null || _siteLoading) return const Center(child: CircularProgressIndicator());
    final frame = _frame;
    if (frame == null) {
      return Center(
        key: const Key('sky-no-site'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            tr(
              'Für die Sternkarte braucht Bortle deinen Standort. Trage ihn unter „Planen“ ein.',
              'The sky map needs your site. Set it under "Plan".',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final colours = tones.red ? SkyColours.night : SkyColours.day;
    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, box) {
              final size = box.biggest;
              return GestureDetector(
                key: const Key('sky-canvas'),
                behavior: HitTestBehavior.opaque,
                onScaleStart: _onScaleStart,
                onScaleUpdate: (d) => _onScaleUpdate(d, size),
                onTapUp: (d) => _onTap(d.localPosition, size),
                child: CustomPaint(
                  size: size,
                  painter: SkyPainter(
                    catalog: catalog,
                    frame: frame,
                    az: _az,
                    alt: _alt,
                    fov: _fov,
                    markers: _markers,
                    colours: colours,
                    labels: _labels,
                    english: appEnglish,
                    selected: _picked?.name,
                    grid: _grid,
                    centreY: centreY,
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(top: 8, left: 8, right: 8, child: _searchBox(tones)),
        Positioned(top: 64, right: 8, child: _compass(tones)),
        Positioned(left: 8, right: 8, bottom: 8, child: _controls(context, frame, tones)),
      ],
    );
  }

  Widget _searchBox(Tones tones) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const Key('sky-search'),
        controller: _search,
        onChanged: _onSearch,
        textInputAction: TextInputAction.search,
        onSubmitted: (text) {
          if (_hits.isNotEmpty) {
            centreOnSearchHit(_hits.first);
          } else if (text.trim().length >= 2) {
            _goTo(text.trim(), text.trim());
          }
        },
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: tones.surface,
          prefixIcon: const Icon(Icons.search),
          hintText: tr('Objekt suchen, z. B. M 31', 'Find an object, e.g. M 31'),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      if (_hits.isNotEmpty)
        Card(
          child: Column(
            children: [
              for (final hit in _hits)
                ListTile(
                  dense: true,
                  key: Key('sky-hit-${hit.planName}'),
                  title: Text(hit.name),
                  subtitle: Text([hit.planName, ?hit.type].join(' · ')),
                  onTap: () => centreOnSearchHit(hit),
                ),
            ],
          ),
        ),
    ],
  );

  Widget _compass(Tones tones) {
    final az = _phone?.az ?? _az;
    return Chip(
      key: const Key('sky-compass'),
      avatar: Icon(_aiming ? Icons.explore : Icons.explore_outlined, size: 18),
      label: Text(_heading(az)),
      backgroundColor: tones.surface,
    );
  }

  Widget _controls(BuildContext context, SkyFrame frame, Tones tones) {
    final picked = _picked;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (picked != null) _card(context, frame, picked, tones),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 104,
                      child: Text(
                        _offset == 0 ? '${tr('Jetzt', 'Now')}\n${when(time)}' : when(time),
                        key: const Key('sky-time'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        key: const Key('sky-time-slider'),
                        value: _offset,
                        min: -720,
                        max: 720,
                        divisions: 96,
                        label: _offset == 0
                            ? tr('jetzt', 'now')
                            : '${_offset > 0 ? '+' : '−'}${decimal(_offset.abs() / 60, _offset % 60 == 0 ? 0 : 2)} h',
                        onChanged: (v) {
                          setState(() => _offset = v);
                          final m = _mountMarker;
                          if (_mountFollow && m != null) _centreOn(m.ra, m.dec, jNow: true, zoom: false);
                        },
                      ),
                    ),
                    TextButton(
                      key: const Key('sky-now'),
                      onPressed: _offset == 0 ? null : () => setState(() => _offset = 0),
                      child: Text(tr('Jetzt', 'Now')),
                    ),
                  ],
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: 8,
                    children: [
                      FilterChip(
                        key: const Key('sky-aim'),
                        label: Text(tr('Handy-Ausrichtung', 'Point the phone')),
                        selected: _aiming,
                        onSelected: _setAiming,
                      ),
                      FilterChip(
                        key: const Key('sky-mount'),
                        label: Text(tr('Montierung zeigen', 'Show mount')),
                        selected: _mountShown,
                        onSelected: _setMountShown,
                      ),
                      FilterChip(
                        key: const Key('sky-mount-follow'),
                        label: Text(tr('Montierung folgen', 'Follow mount')),
                        selected: _mountFollow,
                        onSelected: _setMountFollow,
                      ),
                      FilterChip(
                        key: const Key('sky-grid'),
                        label: Text(tr('Gitter', 'Grid')),
                        selected: _grid,
                        onSelected: (v) => setState(() => _grid = v),
                      ),
                    ],
                  ),
                ),
                if (_mountShown && _mountNote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _mountNote!,
                      key: const Key('sky-mount-note'),
                      style: TextStyle(color: tones.warn),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(BuildContext context, SkyFrame frame, _Picked picked, Tones tones) {
    final (a, h) = frame.horizontal(picked.ra, picked.dec, jNow: picked.jNow);
    final position = h < 0
        ? tr('unter dem Horizont (${decimal(h, 1)}°)', 'below the horizon (${decimal(h, 1)}°)')
        : '${tr('Höhe', 'Altitude')} ${decimal(h, 1)}° · ${tr('Azimut', 'Azimuth')} ${_heading(a)}';
    final onFrame = widget.onFrame;
    return Card(
      key: const Key('sky-card'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(picked.name, style: Theme.of(context).textTheme.titleMedium),
                  if (picked.detail != null) Text(picked.detail!, style: TextStyle(color: tones.muted)),
                  Text(position, key: const Key('sky-card-altitude')),
                ],
              ),
            ),
            if (onFrame != null && picked.frame)
              FilledButton(
                key: const Key('sky-frame'),
                onPressed: () => onFrame(picked.name, picked.ra, picked.dec),
                child: Text(tr('Einrahmen', 'Frame it')),
              ),
            IconButton(
              tooltip: tr('Schließen', 'Close'),
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _picked = null),
            ),
          ],
        ),
      ),
    );
  }
}
