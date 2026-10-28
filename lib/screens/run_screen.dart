// One development run: while it computes, where it is and what is left; when it is done,
// the picture and every step it took.

import 'dart:async';

import 'package:flutter/material.dart';

import '../api/bortle_client.dart';
import '../api/models.dart';
import '../design.dart';
import '../l10n.dart';
import '../widgets.dart';

class RunScreen extends StatefulWidget {
  const RunScreen({required this.client, required this.name, super.key});

  final BortleClient client;
  final String name;

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> {
  late Future<RunDetail> _run = widget.client.run(widget.name);
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // A computing run moves; refresh it while it is on screen.
    _poll = Timer.periodic(const Duration(seconds: 15), (_) async {
      final r = await _run.catchError((_) => const RunDetail(name: '', recipe: ''));
      if (r.status == 'running' && mounted) _reload();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _reload() => setState(() {
    _run = widget.client.run(widget.name);
  });

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Lauf', 'Run'))),
      body: FutureBuilder<RunDetail>(
        future: _run,
        builder: (context, snap) {
          if (snap.hasError) return LoadError(snap.error!, onRetry: _reload);
          final r = snap.data;
          if (r == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final total = r.totalSteps > 0 ? r.totalSteps : r.steps.length;
          // Engine step states: pending, ok, skipped_missing, skipped_off, failed_keep,
          // failed_rollback. Everything but pending is behind the run.
          final done = r.steps.where((s) => s.status != 'pending').length;
          final running = r.status == 'running';
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  running ? tr('Rechnet', 'Computing') : (r.status ?? ''),
                  style: TextStyle(color: running ? Theme.of(context).colorScheme.primary : tones.muted),
                ),
                Text(r.displayTitle, style: Theme.of(context).textTheme.headlineSmall),
                Text(tr('Rezept ${r.recipe}', 'Recipe ${r.recipe}'), style: TextStyle(color: tones.muted)),
                if (running) ...[
                  const SizedBox(height: 14),
                  LinearProgressIndicator(value: total > 0 ? done / total : null),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (r.currentOp != null) opLabel(r.currentOp!),
                      if (total > 0) '$done/$total',
                      if (r.worker != null) r.worker!,
                    ].join(' · '),
                  ),
                ],
                if (r.preview != null) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Sky.radius),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: InteractiveViewer(
                        maxScale: 6,
                        child: ServerImage(client: widget.client, path: r.preview!, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ],
                SectionTitle(tr('Schritte', 'Steps')),
                for (final s in r.steps)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(switch (s.status) {
                      'ok' => Icons.check,
                      'skipped_missing' || 'skipped_off' => Icons.remove,
                      'failed_keep' || 'failed_rollback' => Icons.close,
                      _ => Icons.radio_button_unchecked,
                    }, color: s.status.startsWith('failed') ? tones.danger : null),
                    title: Text(opLabel(s.op)),
                    trailing: Text(_stepState(s.status), style: TextStyle(color: tones.muted, fontSize: 12)),
                  ),
                if (r.steps.isEmpty)
                  Text(tr('Noch kein Schritt fertig.', 'No step finished yet.'), style: TextStyle(color: tones.muted)),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _stepState(String status) => switch (status) {
  'ok' => tr('fertig', 'done'),
  'pending' => tr('kommt noch', 'to come'),
  'skipped_missing' => tr('übersprungen, Werkzeug fehlt', 'skipped, tool missing'),
  'skipped_off' => tr('abgeschaltet', 'switched off'),
  'failed_keep' => tr('fehlgeschlagen, behalten', 'failed, kept'),
  'failed_rollback' => tr('fehlgeschlagen, zurückgenommen', 'failed, rolled back'),
  _ => status,
};
