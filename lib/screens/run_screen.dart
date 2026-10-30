// One development run: while it computes, where it is and what is left; when it is done,
// the picture and every step it took.

import 'dart:async';

import 'package:flutter/material.dart';

import '../api/bortle_client.dart';
import '../api/models.dart';
import '../api/recipes.dart';
import '../design.dart';
import '../l10n.dart';
import '../params.dart';
import '../widgets.dart';
import 'redevelop_screen.dart';

class RunScreen extends StatefulWidget {
  const RunScreen({required this.client, required this.name, super.key});

  final BortleClient client;
  final String name;

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> {
  late Future<RunDetail> _run = widget.client.run(widget.name);
  late final Future<ParamDocs> _docs = widget.client.paramDocs().catchError((Object _) => ParamDocs.empty);
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
                if (r.status == 'done' && r.steps.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('develop-again'),
                    icon: const Icon(Icons.tune),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RedevelopScreen(client: widget.client, run: r),
                      ),
                    ),
                    label: Text(tr('Mit eigenen Werten neu entwickeln', 'Develop again with your own values')),
                  ),
                ],
                SectionTitle(tr('Schritte', 'Steps')),
                FutureBuilder<ParamDocs>(
                  future: _docs,
                  builder: (context, docsSnap) {
                    final docs = docsSnap.data ?? ParamDocs.empty;
                    return Column(
                      children: [
                        for (final (i, s) in r.steps.indexed)
                          _StepTile(client: widget.client, steps: r.steps, index: i, docs: docs, step: s),
                      ],
                    );
                  },
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

/// One step of the run: its state and duration; opened, the image before and after it,
/// what moved in the measurements, and the values it ran with.
class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.client,
    required this.steps,
    required this.index,
    required this.docs,
    required this.step,
  });

  final BortleClient client;
  final List<RunStep> steps;
  final int index;
  final ParamDocs docs;
  final RunStep step;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final before = stepBefore(steps, index);
    final shown = fullPreview(step.previews);
    final hasMore = shown != null || step.metrics.isNotEmpty || step.params.isNotEmpty || step.failed.isNotEmpty;
    final icon = Icon(switch (step.status) {
      'ok' => Icons.check,
      'skipped_missing' || 'skipped_off' => Icons.remove,
      'failed_keep' || 'failed_rollback' => Icons.close,
      _ => Icons.radio_button_unchecked,
    }, color: step.status.startsWith('failed') ? tones.danger : null);
    final state = [
      _stepState(step.status),
      if (step.seconds != null)
        step.seconds! >= 90 ? '${(step.seconds! / 60).round()} min' : '${step.seconds!.round()} s',
    ].join(' · ');
    final title = Text(docs.stepName(step.op));
    if (!hasMore) {
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: icon,
        title: title,
        trailing: Text(state, style: TextStyle(color: tones.muted, fontSize: 12)),
      );
    }
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        leading: icon,
        title: title,
        subtitle: Text(state, style: TextStyle(color: tones.muted, fontSize: 12)),
        childrenPadding: const EdgeInsets.only(left: 8, bottom: 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final f in step.failed) Text('• $f', style: TextStyle(color: tones.warn, fontSize: 13)),
          if (shown != null) ...[
            const SizedBox(height: 8),
            BeforeAfter(client: client, before: before == null ? null : fullPreview(before.previews), after: shown),
          ],
          if (step.metrics.isNotEmpty) ...[
            const SizedBox(height: 10),
            MetricsDelta(after: step.metrics, before: before?.metrics, linear: linearAt(steps, index)),
          ],
          if (step.params.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              tr('Werte dieses Schritts', 'Values of this step'),
              style: TextStyle(color: tones.muted, fontSize: 12),
            ),
            const SizedBox(height: 4),
            for (final e in step.params.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(docs.of(step.op, e.key)?.label?.text ?? e.key, style: const TextStyle(fontSize: 13)),
                    ),
                    Text(formatParam(e.value, docs.of(step.op, e.key)), style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
