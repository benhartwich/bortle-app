// The recipe parameters as people meet them (docs/CONCEPT.md, "Holds"): the corridor the
// engine clamps to (GET /recipes) and what moving the value does, in words
// (GET /recipes/docs, from the server's services/processing/core/param_docs.yaml).

import '../l10n.dart';

/// A bounded parameter: a numeric range, or a set of choices.
class Corridor {
  const Corridor({required this.defaultValue, this.min, this.max, this.choices});

  factory Corridor.fromJson(Map j) => Corridor(
    defaultValue: j['default'],
    min: (j['min'] as num?)?.toDouble(),
    max: (j['max'] as num?)?.toDouble(),
    choices: j['choices'] is List ? List<Object?>.from(j['choices'] as List) : null,
  );

  final Object? defaultValue;
  final double? min;
  final double? max;
  final List<Object?>? choices;

  bool get numeric => choices == null && min != null && max != null;
}

class RecipeStepSpec {
  const RecipeStepSpec(this.op, this.params);

  final String op;
  final Map<String, Corridor> params;
}

class RecipeSpec {
  const RecipeSpec({required this.name, required this.steps, this.own = false});

  factory RecipeSpec.fromJson(String name, Map j) => RecipeSpec(
    name: name,
    own: j['source'] == 'user',
    steps: [
      for (final s in (j['steps'] as List? ?? const []))
        RecipeStepSpec('${(s as Map)['op']}', {
          for (final e in ((s['params'] as Map?) ?? const {}).entries) '${e.key}': Corridor.fromJson(e.value as Map),
        }),
    ],
  );

  final String name;
  final List<RecipeStepSpec> steps;

  /// One of the person's own tuned recipes rather than a curated one.
  final bool own;

  Map<String, Corridor> paramsOf(String op) =>
      steps.firstWhere((s) => s.op == op, orElse: () => RecipeStepSpec(op, const {})).params;

  /// The steps with their keys, as the engine names them (Recipe.step_keys on the
  /// server): the op, or `op#n` for an op the recipe runs more than once – emission-nebula
  /// sharpens the object (`deconvolve_or_sharpen#1`), then the stars (`#2`), each with its
  /// own values.
  List<ChangeableStep> get changeable {
    final keys = stepKeys([for (final s in steps) s.op]);
    return [for (var i = 0; i < steps.length; i++) ChangeableStep(steps[i].op, steps[i].params, key: keys[i])];
  }
}

/// One key per op in order: `op`, or `op#n` (1-based) for an op that occurs more than once.
List<String> stepKeys(List<String> ops) {
  final counts = <String, int>{};
  for (final op in ops) {
    counts[op] = (counts[op] ?? 0) + 1;
  }
  final seen = <String, int>{};
  return [for (final op in ops) (counts[op]! > 1) ? '$op#${seen[op] = (seen[op] ?? 0) + 1}' : op];
}

class ChangeableStep {
  const ChangeableStep(this.op, this.params, {required this.key});

  final String op;
  final Map<String, Corridor> params;

  /// `op`, or `op#n` – what a value, a hold and a resume name this step by.
  final String key;

  /// Which pass of an op the recipe runs more than once, else null.
  int? get pass => key.contains('#') ? int.tryParse(key.split('#').last) : null;
}

/// A text in both languages; [text] is the app's.
class Words {
  const Words(this.de, this.en);

  static Words? fromJson(Object? j) => j is Map ? Words('${j['de'] ?? ''}', '${j['en'] ?? j['de'] ?? ''}') : null;

  final String de;
  final String en;

  String get text => tr(de, en);
}

class ParamDoc {
  const ParamDoc({
    this.label,
    this.help,
    this.low,
    this.high,
    this.note,
    this.unit,
    this.percent = false,
    this.inert = false,
    this.choices = const {},
  });

  factory ParamDoc.fromJson(Map j) => ParamDoc(
    label: Words.fromJson(j['label']),
    help: Words.fromJson(j['help']),
    low: Words.fromJson(j['low']),
    high: Words.fromJson(j['high']),
    note: Words.fromJson(j['note']),
    unit: j['unit'] is String ? j['unit'] as String : null,
    percent: j['percent'] == true,
    inert: j['inert'] == true,
    choices: {
      for (final e in ((j['choices'] as Map?) ?? const {}).entries)
        if (Words.fromJson(e.value) != null) '${e.key}'.toLowerCase(): Words.fromJson(e.value)!,
    },
  );

  final Words? label;
  final Words? help;
  final Words? low;
  final Words? high;
  final Words? note;
  final String? unit;
  final bool percent;

  /// Reaches nothing in any develop today: shown folded away with its [note].
  final bool inert;
  final Map<String, Words> choices;
}

/// op -> its own words (`_op`) and those of each parameter. Empty when the server is too
/// old to have them; the controls then show the bare names.
class ParamDocs {
  const ParamDocs(this._docs);

  factory ParamDocs.fromJson(Map j) => ParamDocs({
    for (final op in j.entries)
      '${op.key}': {
        for (final p in ((op.value as Map?) ?? const {}).entries)
          if (p.value is Map) '${p.key}': ParamDoc.fromJson(p.value as Map),
      },
  });

  static const empty = ParamDocs({});

  final Map<String, Map<String, ParamDoc>> _docs;

  ParamDoc? of(String op, String param) => _docs[op]?[param];

  /// The step's name in words, or the op itself; a key `op#2` adds its pass.
  String stepName(String key) {
    final parts = key.split('#');
    final name = _docs[parts.first]?['_op']?.label?.text ?? parts.first.replaceAll('_', ' ');
    return parts.length > 1 ? '$name (${parts.last}. ${tr('Durchgang', 'pass')})' : name;
  }

  String? stepHelp(String op) => _docs[op]?['_op']?.help?.text;
}

/// A value as people read it: percent for 0..1 dials that say so, the unit otherwise,
/// on/off for switches.
String formatParam(Object? value, ParamDoc? doc) {
  if (value == true) return tr('An', 'On');
  if (value == false) return tr('Aus', 'Off');
  if (value is! num) return '$value';
  if (doc?.percent ?? false) return '${(value * 100).round()} %';
  final v = value.toDouble();
  final digits = v.abs() >= 10 ? 1 : (v == v.roundToDouble() ? 0 : (v.abs() < 0.1 ? 3 : 2));
  final text = decimal(v, digits);
  return doc?.unit != null ? '$text ${doc!.unit}' : text;
}
