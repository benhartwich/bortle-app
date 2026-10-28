// "Teleskop": the night as NINA runs it – overview with the latest frame, every frame of
// the night, the curves over the night. Controlling the devices is stage 3.
//
// Only the operator: the instance's NINA is theirs (the cockpit answers 403 to anyone
// else). Polls while the tab is on screen, never in the background.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api/bortle_client.dart';
import '../api/models.dart';
import '../charts.dart';
import '../design.dart';
import '../l10n.dart';
import '../widgets.dart';

class TelescopeScreen extends StatefulWidget {
  const TelescopeScreen({
    required this.client,
    required this.me,
    required this.active,
    required this.onRedLight,
    super.key,
  });

  final BortleClient client;
  final Me? me;

  /// Whether the tab is on screen; polling runs only then.
  final bool active;
  final VoidCallback onRedLight;

  @override
  State<TelescopeScreen> createState() => _TelescopeScreenState();
}

enum _View { overview, frames, history, control }

class _TelescopeScreenState extends State<TelescopeScreen> {
  _View _view = _View.overview;

  bool get _operator => widget.me == null || widget.me!.admin;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Teleskop', 'Telescope')),
        actions: [
          IconButton(
            tooltip: tr('Rotlicht-Modus', 'Red light mode'),
            onPressed: widget.onRedLight,
            icon: Icon(Icons.dark_mode_outlined, color: tones.danger),
          ),
        ],
        bottom: _operator
            ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: SegmentedButton<_View>(
                    showSelectedIcon: false,
                    // four labels on a 360 pt phone: tighter than the default, never wrapping
                    style: SegmentedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      textStyle: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    segments: [
                      ButtonSegment(value: _View.overview, label: Text(tr('Übersicht', 'Overview'))),
                      ButtonSegment(value: _View.frames, label: Text(tr('Bilder', 'Frames'))),
                      ButtonSegment(value: _View.history, label: Text(tr('Verlauf', 'History'))),
                      ButtonSegment(value: _View.control, label: Text(tr('Steuern', 'Control'))),
                    ],
                    selected: {_view},
                    onSelectionChanged: (s) => setState(() => _view = s.first),
                  ),
                ),
              )
            : null,
      ),
      body: !_operator
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  tr(
                    'Das Teleskop dieser Instanz bedient nur ihr Betreiber. Dein eigenes Teleskop siehst du hier, wenn du dich mit deiner lokalen Bortle-Installation verbindest.',
                    'Only the operator uses this instance’s telescope. You see your own here when you connect to your local Bortle install.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tones.muted),
                ),
              ),
            )
          : switch (_view) {
              _View.overview => _Overview(client: widget.client, active: widget.active),
              _View.frames => _Frames(client: widget.client),
              _View.history => _History(client: widget.client),
              _View.control => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    tr(
                      'Montierung, Kamera, Fokus, Guiding und Filter steuern kommt in Stufe 3 – erst wenn die Steuerung an echter Hardware bewiesen ist.',
                      'Controlling mount, camera, focus, guiding and filters arrives in stage 3 – once control is proven on real hardware.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: tones.muted),
                  ),
                ),
              ),
            },
    );
  }
}

// --- overview ----------------------------------------------------------------------

class _Overview extends StatefulWidget {
  const _Overview({required this.client, required this.active});

  final BortleClient client;
  final bool active;

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  LiveSnapshot? _live;
  Object? _error;
  Uint8List? _frame;
  int? _frameIndex;
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _poll();
    _schedule();
  }

  @override
  void didUpdateWidget(_Overview old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      _schedule();
      if (widget.active) _poll();
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = widget.active ? Timer.periodic(const Duration(seconds: 10), (_) => _poll()) : null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final live = await widget.client.live();
      if (!mounted) return;
      setState(() {
        _live = live;
        _error = null;
      });
      final latest = live.latest;
      if (latest != null && latest.index != _frameIndex) {
        final bytes = await widget.client.liveFrame(index: latest.index, width: 1000);
        if (mounted) {
          setState(() {
            _frame = bytes;
            _frameIndex = latest.index;
          });
        }
      }
    } on BortleError catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _act(String title, String text, String action, String call, Map<String, Object?> params) async {
    final ok = await confirm(context, title, text, action);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.client.control(call, params);
      messenger.showSnackBar(SnackBar(content: Text(tr('NINA hat es angenommen.', 'NINA accepted it.'))));
    } on BortleError catch (e) {
      // NINA's or Bortle's refusal, word for word; never retried behind the user's back.
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
      _poll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final live = _live;
    if (live == null) {
      return _error != null ? LoadError(_error!, onRetry: _poll) : const Center(child: CircularProgressIndicator());
    }
    if (!live.ninaReachable) {
      return RefreshIndicator(
        onRefresh: _poll,
        child: ListView(
          padding: const EdgeInsets.all(32),
          children: [
            Icon(Icons.nights_stay_outlined, size: 40, color: tones.muted),
            const SizedBox(height: 12),
            Text(
              tr(
                'NINA antwortet gerade nicht – das Teleskop ist aus oder der Rechner schläft. Sobald NINA läuft, erscheint die Nacht hier.',
                'NINA is not answering – the telescope is off or its computer asleep. Once NINA runs, the night shows here.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: tones.muted),
            ),
          ],
        ),
      );
    }
    final latest = live.latest;
    return RefreshIndicator(
      onRefresh: _poll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Sky.radius),
            child: AspectRatio(
              aspectRatio: 3 / 2,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: tones.surface),
                  if (_frame != null) _RedAware(child: Image.memory(_frame!, fit: BoxFit.cover, gaplessPlayback: true)),
                  if (latest != null)
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xB3000000),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          [
                            if (latest.at != null) clock(latest.at!),
                            if (latest.exposure != null) '${decimal(latest.exposure!, 0)} s',
                            ?latest.filter,
                            if (latest.bad) tr('auffällig', 'off'),
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Metric('HFR', latest?.hfr == null ? '–' : decimal(latest!.hfr!, 2), warn: latest?.bad ?? false),
              const SizedBox(width: 8),
              _Metric(tr('Sterne', 'Stars'), latest?.stars == null ? '–' : '${latest!.stars}'),
              const SizedBox(width: 8),
              _Metric(
                'Guiding RMS',
                live.rmsTotal == null ? (live.guiding ? '…' : tr('aus', 'off')) : '${decimal(live.rmsTotal!, 2)}″',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StateDot(live.sequenceRunning ? tones.good : tones.muted),
                      const SizedBox(width: 8),
                      Text(
                        live.sequenceRunning
                            ? tr('Sequenz läuft', 'Sequence running')
                            : tr('Sequenz steht', 'Sequence idle'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  if (live.currentStep != null) ...[
                    const SizedBox(height: 6),
                    Text(live.currentStep!, style: TextStyle(color: tones.muted, fontSize: 13)),
                  ],
                  if (live.lights != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      tr(
                        '${live.usable ?? 0} von ${live.lights} Lights brauchbar · ${decimal((live.usableMinutes ?? 0) / 60, 1)} h belichtet',
                        '${live.usable ?? 0} of ${live.lights} lights usable · ${decimal((live.usableMinutes ?? 0) / 60, 1)} h integrated',
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final d in live.devices)
                Chip(
                  avatar: StateDot(d.connected ? tones.good : tones.muted),
                  label: Text(_deviceName(d.key), style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (live.sequenceRunning) ...[
            OutlinedButton(
              key: const Key('sequence-stop'),
              onPressed: _busy
                  ? null
                  : () => _act(
                      tr('Sequenz anhalten?', 'Stop the sequence?'),
                      tr(
                        'NINA hält an, die Montierung bleibt, wo sie ist, und führt weiter nach. Nichts wird geparkt.',
                        'NINA stops; the mount stays where it is and keeps tracking. Nothing is parked.',
                      ),
                      tr('Anhalten', 'Stop'),
                      'sequence-stop',
                      const {},
                    ),
              child: Text(tr('Sequenz anhalten …', 'Stop the sequence …')),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: const Key('end-night'),
              onPressed: _busy
                  ? null
                  : () => _act(
                      tr('Nacht beenden?', 'End the night?'),
                      tr(
                        'NINA springt in den Ende-Bereich der Sequenz: parken, aufwärmen, letzte Frames an Bortle, danach startet die Entwicklung. Die laufende Belichtung wird abgebrochen. Antwortet NINA nicht, sagt die App das.',
                        'NINA jumps to the end of the sequence: park, warm up, last frames to Bortle, then the develop starts. The running exposure is cut short. If NINA does not answer, the app says so.',
                      ),
                      tr('Nacht beenden', 'End the night'),
                      'sequence-skip',
                      const {'scope': 'end', 'confirm': true},
                    ),
              child: Text(tr('Nacht beenden …', 'End the night …'), style: TextStyle(color: tones.danger)),
            ),
          ],
        ],
      ),
    );
  }

  static String _deviceName(String key) => switch (key) {
    'camera' => tr('Kamera', 'Camera'),
    'mount' => tr('Montierung', 'Mount'),
    'focuser' => tr('Fokus', 'Focuser'),
    'filterwheel' => tr('Filterrad', 'Filter wheel'),
    'guider' => 'Guider',
    'rotator' => 'Rotator',
    'flatdevice' => tr('Flat-Panel', 'Flat panel'),
    'dome' => tr('Kuppel', 'Dome'),
    'weather' => tr('Wetter', 'Weather'),
    'safetymonitor' => tr('Sicherheit', 'Safety'),
    'switch' => tr('Schalter', 'Switch'),
    _ => key,
  };
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, {this.warn = false});

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: context.tones.muted, fontSize: 11)),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: warn ? context.tones.warn : null),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A frame in red light: the colours would undo the mode.
class _RedAware extends StatelessWidget {
  const _RedAware({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => !context.tones.red
      ? child
      : ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            .3, .4, .1, 0, 0, //
            0, 0, 0, 0, 0,
            0, 0, 0, 0, 0,
            0, 0, 0, 1, 0,
          ]),
          child: child,
        );
}

// --- frames ------------------------------------------------------------------------

class _Frames extends StatefulWidget {
  const _Frames({required this.client});

  final BortleClient client;

  @override
  State<_Frames> createState() => _FramesState();
}

class _FramesState extends State<_Frames> {
  late Future<FrameHistory> _history = widget.client.frames(limit: 120);
  final _thumbs = <int, Future<Uint8List>>{};

  Future<Uint8List> _thumb(int index) =>
      _thumbs.putIfAbsent(index, () => widget.client.liveFrame(index: index, width: 300));

  Future<void> _reload() async {
    setState(() {
      _history = widget.client.frames(limit: 120);
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FrameHistory>(
    future: _history,
    builder: (context, snap) {
      if (snap.hasError) return LoadError(snap.error!, onRetry: _reload);
      final history = snap.data;
      if (history == null) return const Center(child: CircularProgressIndicator());
      final frames = history.frames.reversed.toList();
      if (frames.isEmpty) {
        return Center(child: Text(tr('Heute Nacht noch kein Bild.', 'No frame yet tonight.')));
      }
      final tones = context.tones;
      return RefreshIndicator(
        onRefresh: _reload,
        child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 140,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemCount: frames.length,
          itemBuilder: (context, i) {
            final f = frames[i];
            return InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _FrameScreen(client: widget.client, frame: f),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: tones.surface),
                    FutureBuilder<Uint8List>(
                      future: _thumb(f.index),
                      builder: (context, s) => s.data == null
                          ? const SizedBox()
                          : _RedAware(child: Image.memory(s.data!, fit: BoxFit.cover)),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        color: const Color(0x99000000),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                f.hfr == null ? '#${f.index + 1}' : 'HFR ${decimal(f.hfr!, 1)}',
                                style: const TextStyle(fontSize: 11, color: Colors.white),
                              ),
                            ),
                            StateDot(f.bad ? tones.warn : tones.good),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

class _FrameScreen extends StatelessWidget {
  const _FrameScreen({required this.client, required this.frame});

  final BortleClient client;
  final LiveFrame frame;

  @override
  Widget build(BuildContext context) {
    final f = frame;
    final tones = context.tones;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Bild ${f.index + 1}', 'Frame ${f.index + 1}'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          AspectRatio(
            aspectRatio: 3 / 2,
            child: InteractiveViewer(
              maxScale: 8,
              child: FutureBuilder<Uint8List>(
                future: client.liveFrame(index: f.index, width: 1800),
                builder: (context, s) => s.hasError
                    ? Center(child: Text('${s.error}'))
                    : s.data == null
                    ? const Center(child: CircularProgressIndicator())
                    : _RedAware(child: Image.memory(s.data!, fit: BoxFit.contain)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              'Von NINA gestreckt – zum Ansehen, nicht zum Messen.',
              'Stretched by NINA – to look at, not to measure.',
            ),
            style: TextStyle(color: tones.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          for (final (label, value) in [
            (tr('Zeit', 'Time'), f.at == null ? '–' : when(f.at!)),
            (tr('Belichtung', 'Exposure'), f.exposure == null ? '–' : '${decimal(f.exposure!, 0)} s'),
            ('Filter', f.filter ?? '–'),
            (
              'HFR',
              f.hfr == null
                  ? '–'
                  : decimal(f.hfr!, 2) + (f.bad ? tr('  (über 1,5× Median)', '  (above 1.5× median)') : ''),
            ),
            (tr('Sterne', 'Stars'), '${f.stars ?? '–'}'),
            ('Guiding RMS', f.rmsArcsec == null ? '–' : '${decimal(f.rmsArcsec!, 2)}″'),
            (tr('Sensor', 'Sensor'), f.temperature == null ? '–' : '${decimal(f.temperature!, 1)} °C'),
            (tr('Fokus', 'Focus'), '${f.focus ?? '–'}'),
          ])
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              trailing: Text(value, style: const TextStyle(fontSize: 14)),
            ),
        ],
      ),
    );
  }
}

// --- history -----------------------------------------------------------------------

class _History extends StatefulWidget {
  const _History({required this.client});

  final BortleClient client;

  @override
  State<_History> createState() => _HistoryState();
}

class _HistoryState extends State<_History> {
  late Future<FrameHistory> _history = widget.client.frames();

  Future<void> _reload() async {
    setState(() {
      _history = widget.client.frames();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FrameHistory>(
    future: _history,
    builder: (context, snap) {
      if (snap.hasError) return LoadError(snap.error!, onRetry: _reload);
      final history = snap.data;
      if (history == null) return const Center(child: CircularProgressIndicator());
      final frames = [
        for (final f in history.frames)
          if (f.at != null && (f.type == null || f.type == 'LIGHT')) f,
      ];
      if (frames.length < 2) {
        return Center(child: Text(tr('Zu wenige Bilder für einen Verlauf.', 'Too few frames for a history.')));
      }
      final tones = context.tones;
      final primary = Theme.of(context).colorScheme.primary;
      Widget chart(String title, String now, Series series, {double? minY}) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Text(now, style: TextStyle(color: tones.muted)),
                ],
              ),
              const SizedBox(height: 6),
              TimeChart(series: [series], minY: minY, height: 110, label: title),
            ],
          ),
        ),
      );
      final last = frames.last;
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            chart(
              'HFR',
              [
                if (last.hfr != null) decimal(last.hfr!, 2),
                if (history.medianHfr != null)
                  tr('Median ${decimal(history.medianHfr!, 2)}', 'median ${decimal(history.medianHfr!, 2)}'),
              ].join(' · '),
              Series([for (final f in frames) ChartPoint(f.at!, f.hfr, marked: f.bad)], primary, dots: true),
            ),
            const SizedBox(height: 8),
            chart(
              tr('Sterne', 'Stars'),
              '${last.stars ?? '–'}',
              Series([for (final f in frames) ChartPoint(f.at!, f.stars?.toDouble())], tones.good, dots: true),
              minY: 0,
            ),
            const SizedBox(height: 8),
            chart(
              'Guiding RMS',
              last.rmsArcsec == null ? '–' : '${decimal(last.rmsArcsec!, 2)}″',
              Series(
                [for (final f in frames) ChartPoint(f.at!, f.rmsArcsec)],
                Theme.of(context).colorScheme.secondary,
                dots: true,
              ),
              minY: 0,
            ),
            const SizedBox(height: 8),
            chart(
              tr('Sensor-Temperatur', 'Sensor temperature'),
              last.temperature == null ? '–' : '${decimal(last.temperature!, 1)} °C',
              Series([for (final f in frames) ChartPoint(f.at!, f.temperature)], tones.warn),
            ),
            const SizedBox(height: 8),
            chart(
              tr('Fokusposition', 'Focus position'),
              '${last.focus ?? '–'}',
              Series([for (final f in frames) ChartPoint(f.at!, f.focus?.toDouble())], tones.muted),
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                'Ringe markieren Bilder mit HFR über dem 1,5-fachen Median dieser Nacht.',
                'Rings mark frames with HFR above 1.5× this night’s median.',
              ),
              style: TextStyle(color: tones.muted, fontSize: 12),
            ),
          ],
        ),
      );
    },
  );
}
