// One processing run waiting at a hold (PLAN.md Phase 10), as on the cockpit's
// /pipelines page: what Bortle found there, and the answer. After a single step it shows
// the image before and after, what moved in the measurements, and the step's values as
// explained sliders – changed values repeat the step and stay for the rest of this
// develop. At the recipe hold each master's recipe can be changed.

import 'package:flutter/material.dart';

import '../api/bortle_client.dart';
import '../api/models.dart';
import '../api/recipes.dart';
import '../design.dart';
import '../l10n.dart';
import '../params.dart';
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

  // The owner's answer in the making: values for the held step, recipes per master.
  final Map<String, Object?> _stepValues = {};
  final Map<String, String> _recipes = {};

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

  static String _finding(String f) => switch (f) {
    'session_left_out' => tr(
      'eine Session wurde weggelassen (anderer Bildausschnitt)',
      'a session was left out (another field)',
    ),
    'pointing_strays' => tr(
      'Frames mit abweichender Ausrichtung weggelassen',
      'frames pointing elsewhere were left out',
    ),
    'qc_rejects_high' => tr(
      'mehr als 30 % der Lights von der QC verworfen',
      'QC rejected more than 30 % of the lights',
    ),
    'stack_softened' => tr('der Master hat beim Stacken an Schärfe verloren', 'the master lost sharpness in stacking'),
    'narrowband_mapping' => tr('Schmalband wird auf RGB abgebildet', 'narrowband is mapped to RGB'),
    'recipe_uncertain' => tr('die Rezeptwahl ist unsicher', 'the recipe choice is uncertain'),
    'recipe_fallback' => tr(
      'Claude war nicht erreichbar, die Regeln haben gewählt',
      'Claude was unreachable, the rules chose',
    ),
    'step_rolled_back' => tr('ein Schritt wurde zurückgerollt', 'a step was rolled back'),
    'colour_hint' => tr('die Farbprüfung hat angeschlagen', 'the colour check flagged something'),
    'gated' => tr('eine Messung liegt außerhalb ihres Korridors', 'a measurement is outside its corridor'),
    _ => f,
  };

  Map<String, Object?> _changes(PipelineHold hold, {required bool redo}) {
    final changes = <String, Object?>{};
    if (_recipes.isNotEmpty) changes['recipes'] = Map.of(_recipes);
    if (redo) {
      changes['redo'] = true;
      final run = '${hold.details['run'] ?? ''}';
      final step = '${hold.details['step'] ?? ''}';
      if (_stepValues.isNotEmpty) {
        changes['step_overrides'] = {
          run: {step: Map.of(_stepValues)},
        };
      }
    }
    return changes;
  }

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
          final atStep = p.waiting && hold?.point == 'steps';
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
              if (hold != null && (hold.findings.isNotEmpty || hold.point != 'steps')) ...[
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
                        if (hold.findings.isEmpty) ...[const SizedBox(height: 8), Text(hold.reason)],
                        for (final f in hold.findings)
                          Padding(padding: const EdgeInsets.only(top: 6), child: Text('• ${_finding(f)}')),
                        const SizedBox(height: 8),
                        _PointDetails(
                          hold: hold,
                          client: widget.client,
                          recipes: _recipes,
                          onRecipe: (key, recipe, original) => setState(() {
                            if (recipe == original) {
                              _recipes.remove(key);
                            } else {
                              _recipes[key] = recipe;
                            }
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (hold != null && hold.point == 'steps')
                _StepHold(
                  client: widget.client,
                  details: hold.details,
                  values: _stepValues,
                  onChanged: (param, value) => setState(() => _stepValues[param] = value),
                ),
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
                if (atStep && _stepValues.isNotEmpty) ...[
                  FilledButton.icon(
                    key: const Key('redo'),
                    icon: const Icon(Icons.replay),
                    onPressed: _busy
                        ? null
                        : () => _answer(
                            () => widget.client.approve(p.id, changes: _changes(hold!, redo: true)),
                            tr('Der Schritt läuft mit deinen Werten neu.', 'The step runs again with your values.'),
                          ),
                    label: Text(tr('Schritt mit diesen Werten wiederholen', 'Repeat the step with these values')),
                  ),
                  const SizedBox(height: 10),
                ],
                FilledButton.tonal(
                  key: const Key('approve'),
                  onPressed: _busy
                      ? null
                      : () => _answer(
                          () => widget.client.approve(p.id, changes: _changes(hold!, redo: false)),
                          tr('Freigegeben – Bortle macht weiter.', 'Approved – Bortle carries on.'),
                        ),
                  child: Text(switch (hold?.point) {
                    'steps' => tr('Weiter mit dem nächsten Schritt', 'Carry on with the next step'),
                    'gallery' => tr('In die Galerie übernehmen', 'Take into the gallery'),
                    _ =>
                      _recipes.isEmpty
                          ? tr('Weiter entwickeln', 'Carry on')
                          : tr('Mit diesen Rezepten weiter', 'Carry on with these recipes'),
                  }),
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

/// What a phase hold found, per point: the lights at intake, the cohorts at stacking,
/// the palette before combining, a recipe choice per master.
class _PointDetails extends StatelessWidget {
  const _PointDetails({required this.hold, required this.client, required this.recipes, required this.onRecipe});

  final PipelineHold hold;
  final BortleClient client;
  final Map<String, String> recipes;
  final void Function(String key, String recipe, String original) onRecipe;

  @override
  Widget build(BuildContext context) {
    final d = hold.details;
    final muted = TextStyle(color: context.tones.muted, fontSize: 13);
    switch (hold.point) {
      case 'intake':
        final lights = (d['lights'] as Map?) ?? const {};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Lights je Filter und Belichtung', 'Lights per filter and exposure'), style: muted),
            for (final e in lights.entries) Text('${e.key}: ${e.value}'),
          ],
        );
      case 'stacking':
        final cohorts = ((d['report'] as Map?)?['cohorts'] as List?) ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in cohorts.whereType<Map>())
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  [
                    '${c['cohort']}: ${c['stacked']} ${tr('gestackt', 'stacked')}',
                    if (((c['qc_excluded'] as num?) ?? 0) > 0)
                      '${c['qc_excluded']} ${tr('von der QC verworfen', 'rejected by QC')}',
                    if ((c['sessions_left_out'] as List? ?? const []).isNotEmpty)
                      '${tr('weggelassen', 'left out')}: ${(c['sessions_left_out'] as List).join(', ')}',
                  ].join(' · '),
                ),
              ),
          ],
        );
      case 'combine':
        return Text('${tr('Palette', 'Palette')}: ${d['palette'] ?? ''}');
      case 'recipe':
        final choices = d['choices'] is Map
            ? Map<String, dynamic>.from(d['choices'] as Map)
            : {
                'composite': {'recipe': '${d['recipe'] ?? ''}'},
              };
        return FutureBuilder<List<RecipeSpec>>(
          future: client.recipes(),
          builder: (context, snap) {
            final names = [for (final r in snap.data ?? const <RecipeSpec>[]) r.name]..sort();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in choices.entries) ...[
                  const SizedBox(height: 8),
                  Text(e.key, style: muted),
                  DropdownButton<String>(
                    key: Key('recipe-${e.key}'),
                    isExpanded: true,
                    value: recipes[e.key] ?? '${(e.value as Map)['recipe']}',
                    items: [
                      for (final n in {'${(e.value as Map)['recipe']}', ...names})
                        DropdownMenuItem(value: n, child: Text(n)),
                    ],
                    onChanged: (v) => v == null ? null : onRecipe(e.key, v, '${(e.value as Map)['recipe']}'),
                  ),
                  if ((e.value as Map)['rationale'] != null) Text('${(e.value as Map)['rationale']}', style: muted),
                ],
              ],
            );
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// A run that stopped after one processing step.
class _StepHold extends StatefulWidget {
  const _StepHold({required this.client, required this.details, required this.values, required this.onChanged});

  final BortleClient client;
  final Map<String, dynamic> details;
  final Map<String, Object?> values;
  final void Function(String param, Object? value) onChanged;

  @override
  State<_StepHold> createState() => _StepHoldState();
}

class _StepHoldState extends State<_StepHold> {
  late final Future<(List<RecipeSpec>, ParamDocs, RunDetail?)> _context = _load();

  Future<(List<RecipeSpec>, ParamDocs, RunDetail?)> _load() async {
    final run = '${widget.details['run'] ?? ''}';
    final specs = widget.client.recipes();
    final docs = widget.client.paramDocs();
    final detail = run.isEmpty
        ? Future<RunDetail?>.value()
        : widget.client.run(run).then<RunDetail?>((r) => r, onError: (Object _) => null);
    return (await specs, await docs, await detail);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.details;
    final op = '${d['step'] ?? ''}';
    final next = '${d['next'] ?? ''}';
    final used = d['params'] is Map ? Map<String, Object?>.from(d['params'] as Map) : const <String, Object?>{};
    final previews = [for (final p in (d['previews'] as List? ?? const [])) '$p'];
    final failed = [for (final f in (d['failed_expectations'] as List? ?? const [])) '$f'];
    return FutureBuilder(
      future: _context,
      builder: (context, snap) {
        final (specs, docs, run) = snap.data ?? (const <RecipeSpec>[], ParamDocs.empty, null);
        final spec = specs.where((s) => s.name == '${d['recipe']}').firstOrNull;
        final step = spec?.changeable.where((s) => s.op == op).firstOrNull;
        final steps = run?.steps ?? const <RunStep>[];
        final here = steps.lastIndexWhere((s) => s.op == op);
        final before = here > 0 ? stepBefore(steps, here) : null;
        final after = here >= 0 ? steps[here].metrics : const <String, double>{};
        final shown = fullPreview(previews);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Text(
              '${tr('Fertig', 'Done')}: ${docs.stepName(op)}'
              '${next.isNotEmpty ? ' · ${tr('als Nächstes', 'next')}: ${docs.stepName(next)}' : ''}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final f in failed) Text('• $f', style: TextStyle(color: context.tones.warn, fontSize: 13)),
            if (shown != null) ...[
              const SizedBox(height: 10),
              BeforeAfter(
                client: widget.client,
                before: before == null ? null : fullPreview(before.previews),
                after: shown,
              ),
            ],
            if (after.isNotEmpty) ...[
              const SizedBox(height: 10),
              MetricsDelta(after: after, before: before?.metrics, linear: linearAt(steps, here)),
            ],
            if (step != null && step.params.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                tr(
                  'Werte dieses Schritts – geänderte gelten, wenn du ihn wiederholst, und für den Rest dieser Entwicklung.',
                  'Values of this step – changed ones apply when you repeat it, and for the rest of this develop.',
                ),
                style: TextStyle(color: context.tones.muted, fontSize: 13),
              ),
              const SizedBox(height: 6),
              StepParams(
                op: op,
                params: step.params,
                docs: docs,
                valueOf: (p, c) => widget.values.containsKey(p) ? widget.values[p] : (used[p] ?? c.defaultValue),
                originalOf: (p, c) => used[p] ?? c.defaultValue,
                onChanged: widget.onChanged,
                badge: step.twice
                    ? tr('kommt zweimal vor – ein Wert gilt für beide', 'runs twice – a value applies to both')
                    : null,
              ),
            ],
            if (snap.connectionState == ConnectionState.waiting)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        );
      },
    );
  }
}
