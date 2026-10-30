// Develop a finished run again with other values, as the cockpit's "Neu entwickeln": the
// recipe's steps as explained sliders, starting from what this run used. Only the steps
// from the earliest changed one on are computed again; everything before is reused.

import 'package:flutter/material.dart';

import '../api/bortle_client.dart';
import '../api/models.dart';
import '../api/recipes.dart';
import '../design.dart';
import '../l10n.dart';
import '../params.dart';
import '../widgets.dart';
import 'run_screen.dart';

class RedevelopScreen extends StatefulWidget {
  const RedevelopScreen({required this.client, required this.run, super.key});

  final BortleClient client;
  final RunDetail run;

  @override
  State<RedevelopScreen> createState() => _RedevelopScreenState();
}

class _RedevelopScreenState extends State<RedevelopScreen> {
  late final Future<(List<RecipeSpec>, ParamDocs)> _context = _load();
  final Map<String, Map<String, Object?>> _values = {};
  bool _busy = false;

  Future<(List<RecipeSpec>, ParamDocs)> _load() async {
    final specs = widget.client.recipes();
    final docs = widget.client.paramDocs();
    return (await specs, await docs);
  }

  /// What the run used, per op (the last step of that name wins, as on the cockpit).
  /// What the run used, per step key (a protocol from before step keys gets them from
  /// its op sequence).
  late final Map<String, Map<String, Object?>> _used = () {
    final keys = stepKeys([for (final s in widget.run.steps) s.op]);
    return {for (final (i, s) in widget.run.steps.indexed) s.key ?? keys[i]: s.params};
  }();

  Object? _original(String op, String param, Corridor c) => _used[op]?[param] ?? c.defaultValue;

  Object? _value(String op, String param, Corridor c) =>
      _values[op]?.containsKey(param) ?? false ? _values[op]![param] : _original(op, param, c);

  /// The steps whose values differ from the run, in recipe order.
  List<String> _changed(RecipeSpec spec) => [
    for (final s in spec.changeable)
      if (s.params.entries.any((e) => '${_value(s.key, e.key, e.value)}' != '${_original(s.key, e.key, e.value)}'))
        s.key,
  ];

  /// Values away from the recipe default – what makes the new run this run, plus the
  /// changes. The server clamps each into its corridor.
  Map<String, Map<String, Object?>> _overrides(RecipeSpec spec) {
    final out = <String, Map<String, Object?>>{};
    for (final s in spec.changeable) {
      for (final e in s.params.entries) {
        final v = _value(s.key, e.key, e.value);
        if ('$v' != '${e.value.defaultValue}') (out[s.key] ??= {})[e.key] = v;
      }
    }
    return out;
  }

  String? _badge(ChangeableStep s, List<String> changed) {
    final parts = [
      if (s.pass != null) tr('${s.pass}. Durchgang', 'pass ${s.pass}'),
      if (changed.isNotEmpty && changed.first == s.key) tr('← startet hier neu', '← starts again here'),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Future<void> _start(RecipeSpec spec, ParamDocs docs) async {
    final changed = _changed(spec);
    final from = changed.isEmpty ? null : changed.first;
    final ok = await confirm(
      context,
      tr('Neu entwickeln?', 'Develop again?'),
      from == null
          ? tr(
              'Nichts geändert – der Lauf würde identisch neu rechnen.',
              'Nothing changed – the run would compute the same again.',
            )
          : tr(
              'Ab „${docs.stepName(from)}“ wird neu gerechnet, alles davor aus diesem Lauf übernommen. Das Ergebnis erscheint als neuer Lauf.',
              'Computing starts again from “${docs.stepName(from)}”; everything before is taken from this run. The result appears as a new run.',
            ),
      tr('Starten', 'Start'),
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final name = await widget.client.redevelop(widget.run.name, overrides: _overrides(spec), resumeFrom: from);
      messenger.showSnackBar(SnackBar(content: Text(tr('Eingereiht als $name.', 'Queued as $name.'))));
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => RunScreen(client: widget.client, name: name),
        ),
      );
    } on BortleError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Neu entwickeln', 'Develop again'))),
      body: FutureBuilder(
        future: _context,
        builder: (context, snap) {
          if (snap.hasError) return LoadError(snap.error!, onRetry: () => setState(() {}));
          final data = snap.data;
          if (data == null) return const Center(child: CircularProgressIndicator());
          final (specs, docs) = data;
          final spec = specs.where((s) => s.name == widget.run.recipe).firstOrNull;
          if (spec == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  tr(
                    'Das Rezept „${widget.run.recipe}“ gibt es auf dem Server nicht mehr.',
                    'The recipe “${widget.run.recipe}” no longer exists on the server.',
                  ),
                ),
              ),
            );
          }
          final changed = _changed(spec);
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(widget.run.displayTitle, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      tr(
                        'Jeder Wert bleibt im Korridor des Rezepts. ↺ setzt auf den Wert dieses Laufs zurück.',
                        "Every value stays within the recipe's corridor. ↺ goes back to this run's value.",
                      ),
                      style: TextStyle(color: context.tones.muted, fontSize: 13),
                    ),
                    for (final s in spec.changeable)
                      if (s.params.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: StepParams(
                            op: s.op,
                            params: s.params,
                            docs: docs,
                            valueOf: (p, c) => _value(s.key, p, c),
                            originalOf: (p, c) => _original(s.key, p, c),
                            onChanged: (p, v) => setState(() => (_values[s.key] ??= {})[p] = v),
                            badge: _badge(s, changed),
                          ),
                        ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('redevelop'),
                      onPressed: _busy || changed.isEmpty ? null : () => _start(spec, docs),
                      child: Text(
                        changed.isEmpty
                            ? tr('Noch nichts geändert', 'Nothing changed yet')
                            : tr(
                                'Neu ab „${docs.stepName(changed.first)}“',
                                'Again from “${docs.stepName(changed.first)}”',
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
