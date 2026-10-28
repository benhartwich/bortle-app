// One processing run waiting at a hold (PLAN.md Phase 10): what Bortle found there, and
// the answer – carry on, or stop for good. Changing parameters at the hold stays in the
// browser for now; the app says so instead of pretending.

import 'package:flutter/material.dart';

import '../api/bortle_client.dart';
import '../api/models.dart';
import '../design.dart';
import '../l10n.dart';
import '../widgets.dart';
import 'run_screen.dart';

class HoldScreen extends StatefulWidget {
  const HoldScreen({required this.client, required this.pipelineId, super.key});

  final BortleClient client;
  final String pipelineId;

  @override
  State<HoldScreen> createState() => _HoldScreenState();
}

class _HoldScreenState extends State<HoldScreen> {
  late Future<Pipeline> _pipeline = widget.client.pipeline(widget.pipelineId);
  bool _busy = false;

  void _reload() => setState(() {
    _pipeline = widget.client.pipeline(widget.pipelineId);
  });

  Future<void> _answer(Future<void> Function() call, String done) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await call();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      if (mounted) Navigator.of(context).pop();
    } on BortleError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _point(String point) => switch (point) {
    'intake' => tr('nach dem Einsortieren', 'after intake'),
    'stacking' => tr('nach dem Stacking', 'after stacking'),
    'combine' => tr('vor dem Kombinieren', 'before combining'),
    'recipe' => tr('nach der Rezeptwahl', 'after the recipe choice'),
    'steps' => tr('nach einem Schritt', 'after a step'),
    'gallery' => tr('vor der Galerie', 'before the gallery'),
    _ => point,
  };

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Freigabe', 'Approval'))),
      body: FutureBuilder<Pipeline>(
        future: _pipeline,
        builder: (context, snap) {
          if (snap.hasError) return LoadError(snap.error!, onRetry: _reload);
          final p = snap.data;
          if (p == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final hold = p.hold;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                p.waiting
                    ? tr('Wartet auf dich · ${_point(hold!.point)}', 'Waiting for you · ${_point(hold.point)}')
                    : tr('Status: ${p.state}', 'State: ${p.state}'),
                style: TextStyle(color: p.waiting ? tones.warn : tones.muted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(p.subject, style: Theme.of(context).textTheme.headlineSmall),
              if (hold != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Was Bortle gefunden hat', 'What Bortle found'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(hold.reason),
                        for (final f in hold.findings)
                          Padding(padding: const EdgeInsets.only(top: 6), child: Text('• $f')),
                      ],
                    ),
                  ),
                ),
              ],
              for (final r in p.runs)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(r, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(tr('Protokoll des Laufs', 'Run log')),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RunScreen(client: widget.client, name: r),
                    ),
                  ),
                ),
              if (p.waiting) ...[
                const SizedBox(height: 16),
                Text(
                  tr(
                    'Parameter am Haltepunkt ändern geht vorerst nur im Browser-Cockpit.',
                    'Changing parameters at the hold is browser-only for now.',
                  ),
                  style: TextStyle(color: tones.muted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('approve'),
                  onPressed: _busy
                      ? null
                      : () => _answer(
                          () => widget.client.approve(p.id),
                          tr('Freigegeben – Bortle macht weiter.', 'Approved – Bortle carries on.'),
                        ),
                  child: Text(tr('Weiter entwickeln', 'Carry on')),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  key: const Key('cancel'),
                  onPressed: _busy
                      ? null
                      : () async {
                          final ok = await confirm(
                            context,
                            tr('Lauf abbrechen?', 'Stop this run?'),
                            tr(
                              'Der Lauf endet endgültig. Was er schon erzeugt hat, bleibt unter Läufe, wird aber nicht veröffentlicht.',
                              'The run ends for good. What it produced stays under Runs, unpublished.',
                            ),
                            tr('Abbrechen', 'Stop'),
                          );
                          if (ok) {
                            await _answer(() => widget.client.cancel(p.id), tr('Abgebrochen.', 'Stopped.'));
                          }
                        },
                  child: Text(tr('Abbrechen …', 'Stop …'), style: TextStyle(color: tones.danger)),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
