// "Galerie": the finished images, and the runs – computing ones first, with progress.
// On a tablet on its side the run opens beside the list instead of over it.

import 'package:material_ui/material_ui.dart';

import '../api/bortle_client.dart';
import '../api/models.dart';
import '../design.dart';
import '../l10n.dart';
import '../layout.dart';
import '../widgets.dart';
import 'run_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({required this.client, super.key});

  final BortleClient client;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  bool _runs = false;
  late Future<List<GalleryEntry>> _images = _loadImages();
  late Future<List<DevelopRun>> _runList = widget.client.runs();

  Future<List<GalleryEntry>> _loadImages() async {
    final all = await widget.client.gallery();
    final developed = all.where((g) => g.kind == 'developed' && g.preview != null).toList()
      ..sort((a, b) => (b.modified ?? DateTime(0)).compareTo(a.modified ?? DateTime(0)));
    return developed;
  }

  Future<void> _reload() async {
    setState(() {
      _images = _loadImages();
      _runList = widget.client.runs();
    });
  }

  /// The run shown beside the list in two panes; the phone pushes it instead.
  String? _chosen;

  void _open(String run) {
    if (context.twoPane) {
      setState(() => _chosen = run);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RunScreen(client: widget.client, name: run),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!context.twoPane) return _list(context);
    final chosen = _chosen;
    return TwoPane(
      list: _list(context),
      listWidth: 420,
      detail: chosen == null
          ? NothingChosen(
              icon: Icons.photo_library_outlined,
              text: tr('Wähle links ein Bild oder einen Lauf.', 'Choose an image or a run on the left.'),
            )
          : RunScreen(key: ValueKey(chosen), client: widget.client, name: chosen),
    );
  }

  Widget _list(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr('Galerie', 'Gallery')),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(tr('Bilder', 'Images'))),
              ButtonSegment(value: true, label: Text(tr('Läufe', 'Runs'))),
            ],
            selected: {_runs},
            onSelectionChanged: (s) => setState(() => _runs = s.first),
          ),
        ),
      ),
    ),
    body: RefreshIndicator(onRefresh: _reload, child: _runs ? _runsView() : _imagesView()),
  );

  Widget _imagesView() => FutureBuilder<List<GalleryEntry>>(
    future: _images,
    builder: (context, snap) {
      if (snap.hasError) {
        return ListView(children: [LoadError(snap.error!, onRetry: _reload)]);
      }
      final list = snap.data;
      if (list == null) return const Center(child: CircularProgressIndicator());
      if (list.isEmpty) {
        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(tr('Noch kein fertiges Bild.', 'No finished image yet.'), textAlign: TextAlign.center),
            ),
          ],
        );
      }
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: .82,
        ),
        itemCount: list.length,
        itemBuilder: (context, i) {
          final g = list[i];
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _open(g.name),
            child: Card(
              clipBehavior: Clip.antiAlias,
              shape: g.name == _chosen && context.twoPane
                  ? RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
                    )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: ServerImage(client: widget.client, path: g.preview!),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          [
                            if (g.recipe != null) g.recipe!,
                            if (g.hours != null) '${decimal(g.hours!, 1)} h',
                          ].join(' · '),
                          style: TextStyle(color: context.tones.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  Widget _runsView() => FutureBuilder<List<DevelopRun>>(
    future: _runList,
    builder: (context, snap) {
      if (snap.hasError) {
        return ListView(children: [LoadError(snap.error!, onRetry: _reload)]);
      }
      final list = snap.data;
      if (list == null) return const Center(child: CircularProgressIndicator());
      final tones = context.tones;
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: list.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, i) {
          final r = list[i];
          return ListTile(
            selected: r.name == _chosen && context.twoPane,
            title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: r.running
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: r.progress),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (r.currentOp != null) opLabel(r.currentOp!),
                          if (r.eta != null) tr('noch ~${duration(r.eta!)}', '~${duration(r.eta!)} left'),
                        ].join(' · '),
                      ),
                    ],
                  )
                : Text(r.recipe ?? ''),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StateDot(switch (r.status) {
                  'running' => Theme.of(context).colorScheme.primary,
                  'done' => tones.good,
                  'failed' => tones.danger,
                  _ => tones.muted,
                }),
                const SizedBox(width: 6),
                Text(runStateLabel(r.status), style: TextStyle(color: tones.muted, fontSize: 12)),
              ],
            ),
            onTap: () => _open(r.name),
          );
        },
      );
    },
  );
}

/// A run's status in words, for the list and the run page alike.
String runStateLabel(String status) => switch (status) {
  'running' => tr('rechnet', 'computing'),
  'done' => tr('fertig', 'done'),
  'failed' => tr('fehlgeschlagen', 'failed'),
  'waiting' => tr('wartet', 'waiting'),
  'stale' => tr('hängt', 'stalled'),
  _ => status,
};
