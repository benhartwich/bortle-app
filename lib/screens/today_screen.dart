// "Heute": the night's state, what waits for an answer, what is computing, the latest
// finished images and the latest events. Fetched fresh on every open and pull.

import 'package:flutter/material.dart';

import '../api/bortle_client.dart';
import '../api/models.dart';
import '../design.dart';
import '../l10n.dart';
import '../widgets.dart';
import 'hold_screen.dart';
import 'run_screen.dart';

class TodayData {
  const TodayData(this.night, this.waiting, this.running, this.recent, this.events);

  final NightState night;
  final List<Pipeline> waiting;
  final List<DevelopRun> running;
  final List<GalleryEntry> recent;
  final List<BortleEvent> events;

  static Future<TodayData> load(BortleClient c) async {
    final results = await Future.wait([
      c.night(),
      c.pipelines(waiting: true),
      c.runs(),
      c.gallery(),
      c.events(limit: 8),
    ]);
    final gallery = (results[3] as List<GalleryEntry>).where((g) => g.kind == 'developed').toList()
      ..sort((a, b) => (b.modified ?? DateTime(0)).compareTo(a.modified ?? DateTime(0)));
    return TodayData(
      results[0] as NightState,
      results[1] as List<Pipeline>,
      (results[2] as List<DevelopRun>).where((r) => r.running).toList(),
      gallery.take(3).toList(),
      results[4] as List<BortleEvent>,
    );
  }
}

class TodayScreen extends StatefulWidget {
  const TodayScreen({required this.client, required this.onRedLight, super.key});

  final BortleClient client;
  final VoidCallback onRedLight;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late Future<TodayData> _data = TodayData.load(widget.client);

  Future<void> _reload() async {
    final next = TodayData.load(widget.client);
    setState(() {
      _data = next;
    });
    await next.catchError((_) => TodayData(const NightState(), const [], const [], const [], const []));
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Heute', 'Tonight')),
        actions: [
          IconButton(
            tooltip: tr('Rotlicht-Modus', 'Red light mode'),
            onPressed: widget.onRedLight,
            icon: Icon(Icons.dark_mode_outlined, color: tones.danger),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<TodayData>(
          future: _data,
          builder: (context, snap) {
            if (snap.hasError) {
              return ListView(children: [LoadError(snap.error!, onRetry: _reload)]);
            }
            final d = snap.data;
            if (d == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                for (final p in d.waiting)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Sky.radius),
                        side: BorderSide(color: tones.warn),
                      ),
                      child: ListTile(
                        leading: Icon(Icons.pending_actions_outlined, color: tones.warn),
                        title: Text(tr('Wartet auf dich: ${p.subject}', 'Waiting for you: ${p.subject}')),
                        subtitle: Text(p.hold?.reason ?? ''),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(HoldScreen(client: widget.client, pipelineId: p.id)),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _Tile(
                        label: tr('Nacht', 'Night'),
                        value: d.night.activeSession == null
                            ? tr('Keine aktiv', 'None active')
                            : tr('Läuft', 'Running'),
                        color: d.night.activeSession == null ? null : tones.good,
                        detail: d.night.activeSession,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Tile(
                        label: tr('Läufe', 'Runs'),
                        value: d.running.isEmpty
                            ? tr('Keiner rechnet', 'None computing')
                            : tr('${d.running.length} rechnen', '${d.running.length} computing'),
                      ),
                    ),
                  ],
                ),
                if (d.running.isNotEmpty) SectionTitle(tr('Entwicklung läuft', 'Developing')),
                for (final r in d.running)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 6),
                            LinearProgressIndicator(value: r.progress),
                            const SizedBox(height: 6),
                            Text(
                              [
                                if (r.currentOp != null) opLabel(r.currentOp!),
                                if (r.totalSteps > 0) '${r.stepsDone}/${r.totalSteps}',
                                if (r.eta != null) tr('noch ~${duration(r.eta!)}', '~${duration(r.eta!)} left'),
                              ].join(' · '),
                            ),
                          ],
                        ),
                        onTap: () => _open(RunScreen(client: widget.client, name: r.name)),
                      ),
                    ),
                  ),
                if (d.recent.isNotEmpty) SectionTitle(tr('Zuletzt fertig', 'Recently finished')),
                if (d.recent.isNotEmpty)
                  Row(
                    children: [
                      for (final g in d.recent)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (g.preview != null) ServerImage(client: widget.client, path: g.preview!),
                                    Align(
                                      alignment: Alignment.bottomLeft,
                                      child: Container(
                                        width: double.infinity,
                                        color: const Color(0x99000000),
                                        padding: const EdgeInsets.all(6),
                                        child: Text(
                                          g.displayTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                if (d.events.isNotEmpty) SectionTitle(tr('Ereignisse', 'Events')),
                for (final e in d.events)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 92,
                          child: Text(
                            e.at == null ? '' : when(e.at!),
                            style: TextStyle(color: tones.muted, fontSize: 13),
                          ),
                        ),
                        Expanded(child: Text(e.text, style: const TextStyle(fontSize: 14))),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.color, this.detail});

  final String label;
  final String value;
  final Color? color;
  final String? detail;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: context.tones.muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color)),
          if (detail != null)
            Text(detail!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}
