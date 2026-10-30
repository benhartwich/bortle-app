// What a processing step did and with which values, as on the cockpit's run page and
// step hold: the image before and after it, the measurements that moved, and every value
// as an explained slider (or its choices spelled out). The engine clamps into the
// corridor regardless of what is set here.

import 'package:flutter/material.dart';

import 'api/bortle_client.dart';
import 'api/models.dart';
import 'api/recipes.dart';
import 'design.dart';
import 'l10n.dart';
import 'widgets.dart';

/// One parameter: its name in words, the control, where the default sits, what less and
/// more do, and the caveats.
class ParamControl extends StatelessWidget {
  const ParamControl({
    required this.name,
    required this.corridor,
    required this.value,
    required this.original,
    required this.onChanged,
    this.doc,
    super.key,
  });

  final String name;
  final Corridor corridor;
  final ParamDoc? doc;
  final Object? value;

  /// What the run used; the reset goes back to it.
  final Object? original;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final small = TextStyle(color: tones.muted, fontSize: 12, height: 1.35);
    final changed = '$value' != '$original';
    final header = Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              text: doc?.label?.text ?? name,
              children: [
                if (changed)
                  TextSpan(
                    text: '  ${tr('geändert', 'changed')}',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 11),
                  ),
              ],
            ),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        if (changed)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: tr('Zurück auf den Wert dieses Laufs', "Back to this run's value"),
            icon: const Icon(Icons.undo, size: 18),
            onPressed: () => onChanged(original),
          ),
        if (corridor.numeric)
          Text(formatParam(value, doc), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
      ],
    );
    final words = [
      if (doc?.help != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(doc!.help!.text, style: small),
        ),
      if (doc?.note != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(doc!.note!.text, style: small.copyWith(color: tones.warn)),
        ),
    ];

    final choices = corridor.choices;
    if (choices != null) {
      final picked = choices.firstWhere((c) => '$c' == '$value', orElse: () => corridor.defaultValue);
      final about = doc?.choices['$picked'.toLowerCase()]?.text;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in choices)
                ChoiceChip(
                  label: Text(
                    '$c' == '${corridor.defaultValue}'
                        ? '${formatParam(c, doc)} · ${tr('Standard', 'default')}'
                        : formatParam(c, doc),
                  ),
                  selected: '$c' == '$picked',
                  onSelected: (_) => onChanged(c),
                ),
            ],
          ),
          if (about != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(about, style: const TextStyle(fontSize: 13)),
            ),
          ...words,
        ],
      );
    }
    if (!corridor.numeric) return const SizedBox.shrink();
    final min = corridor.min!;
    final max = corridor.max!;
    final current = (value is num ? (value as num).toDouble() : (corridor.defaultValue as num).toDouble()).clamp(
      min,
      max,
    );
    final span = max - min;
    final step = span >= 20 ? 0.5 : (span >= 2 ? 0.05 : 0.01);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        Slider(
          value: current,
          min: min,
          max: max,
          divisions: (span / step).round().clamp(1, 1000),
          label: formatParam(current, doc),
          onChanged: (v) => onChanged(double.parse(v.toStringAsFixed(3))),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text([formatParam(min, doc), ?doc?.low?.text].join('\n'), style: small)),
            const SizedBox(width: 12),
            Expanded(
              child: Text([formatParam(max, doc), ?doc?.high?.text].join('\n'), style: small, textAlign: TextAlign.end),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            [
              '${tr('Standard', 'Default')} ${formatParam(corridor.defaultValue, doc)}',
              if ('$original' != '${corridor.defaultValue}')
                '${tr('dieser Lauf', 'this run')} ${formatParam(original, doc)}',
            ].join(' · '),
            style: small,
          ),
        ),
        ...words,
      ],
    );
  }
}

/// Every parameter of one step under the step's name and what it does.
class StepParams extends StatelessWidget {
  const StepParams({
    required this.op,
    required this.params,
    required this.docs,
    required this.valueOf,
    required this.originalOf,
    required this.onChanged,
    this.badge,
    super.key,
  });

  final String op;
  final Map<String, Corridor> params;
  final ParamDocs docs;
  final Object? Function(String param, Corridor corridor) valueOf;
  final Object? Function(String param, Corridor corridor) originalOf;
  final void Function(String param, Object? value) onChanged;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final help = docs.stepHelp(op);
    // knobs that reach nothing today: named with their reason, not offered as dials
    final inert = [
      for (final p in params.keys)
        if (docs.of(op, p)?.inert ?? false) p,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(docs.stepName(op), style: Theme.of(context).textTheme.titleMedium),
            if (badge != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(badge!, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12)),
              ),
            if (help != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(help, style: TextStyle(color: context.tones.muted, fontSize: 13)),
              ),
            for (final e in params.entries.where((e) => !(docs.of(op, e.key)?.inert ?? false))) ...[
              const SizedBox(height: 14),
              ParamControl(
                name: e.key,
                corridor: e.value,
                doc: docs.of(op, e.key),
                value: valueOf(e.key, e.value),
                original: originalOf(e.key, e.value),
                onChanged: (v) => onChanged(e.key, v),
              ),
            ],
            if (inert.isNotEmpty)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    '${tr('Ohne Wirkung', 'No effect')} (${inert.length})',
                    style: TextStyle(color: context.tones.muted, fontSize: 13),
                  ),
                  children: [
                    for (final p in inert)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${docs.of(op, p)?.label?.text ?? p} – ${docs.of(op, p)?.note?.text ?? ''}',
                          style: TextStyle(color: context.tones.muted, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Metric {
  const _Metric(this.key, this.label, this.format, {this.stretchedOnly = false, this.share = false});

  final String key;
  final String Function() label;
  final String Function(double v) format;

  /// Only meaningful on a stretched image.
  final bool stretchedOnly;

  /// A share of pixels: a relative change of a tiny share would be a meaningless +3200 %.
  final bool share;
}

String _pct(double v) => '${decimal(v * 100, v < 0.01 ? 2 : 1)} %';

final _metrics = [
  _Metric('median', () => tr('Helligkeit', 'Brightness'), (v) => decimal(v, 3), stretchedOnly: true),
  _Metric('noise_sigma', () => tr('Rauschen', 'Noise'), (v) => v.toStringAsExponential(2)),
  _Metric('background_gradient', () => tr('Gradient', 'Gradient'), (v) => v.toStringAsExponential(2)),
  _Metric('star_count', () => tr('Sterne', 'Stars'), (v) => v.toStringAsFixed(0)),
  _Metric('fwhm_px', () => tr('Sterngröße', 'Star size'), (v) => '${decimal(v, 2)} px'),
  _Metric('highlight_clip_fraction', () => tr('Ausgebrannt', 'Blown out'), _pct, stretchedOnly: true, share: true),
  _Metric(
    'shadow_clip_fraction',
    () => tr('Schwarz abgeschnitten', 'Clipped to black'),
    _pct,
    stretchedOnly: true,
    share: true,
  ),
];

/// The measurements after a step next to those before it. Neutral on purpose: fewer
/// stars or a darker image can be exactly what was wanted.
class MetricsDelta extends StatelessWidget {
  const MetricsDelta({required this.after, this.before, this.linear = false, super.key});

  final Map<String, double> after;
  final Map<String, double>? before;

  /// The image is still linear (before the stretch).
  final bool linear;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final rows = _metrics.where((m) => after.containsKey(m.key) && !(linear && m.stretchedOnly)).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 18,
      runSpacing: 8,
      children: [
        for (final m in rows)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(m.label(), style: TextStyle(color: tones.muted, fontSize: 12)),
              Text(_change(m), style: const TextStyle(fontSize: 13, fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
      ],
    );
  }

  String _change(_Metric m) {
    final now = after[m.key]!;
    final was = before?[m.key];
    if (was == null || was == now) return m.format(now);
    final rel = was != 0 && !m.share ? (now - was) / was.abs() : null;
    final pct = rel != null && rel.abs() >= 0.005
        ? ' (${rel > 0 ? '+' : '−'}${decimal((rel * 100).abs(), rel.abs() < 0.1 ? 1 : 0)} %)'
        : '';
    return '${m.format(was)} → ${m.format(now)}$pct';
  }
}

/// The image before and after a step, one over the other with a divider to drag.
class BeforeAfter extends StatefulWidget {
  const BeforeAfter({required this.client, required this.after, this.before, super.key});

  final BortleClient client;
  final String after;
  final String? before;

  @override
  State<BeforeAfter> createState() => _BeforeAfterState();
}

class _BeforeAfterState extends State<BeforeAfter> {
  double _split = 0.5;

  @override
  Widget build(BuildContext context) {
    final after = ServerImage(client: widget.client, path: widget.after, fit: BoxFit.contain);
    final before = widget.before;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Sky.radius / 2),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: before == null
            ? after
            : LayoutBuilder(
                builder: (context, box) => GestureDetector(
                  onHorizontalDragUpdate: (d) =>
                      setState(() => _split = (d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0)),
                  onTapDown: (d) => setState(() => _split = (d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      after,
                      ClipRect(
                        clipper: _LeftOf(_split),
                        child: ServerImage(client: widget.client, path: before, fit: BoxFit.contain),
                      ),
                      Positioned(
                        left: box.maxWidth * _split - 1,
                        top: 0,
                        bottom: 0,
                        child: Container(width: 2, color: Colors.white70),
                      ),
                      Positioned(left: 8, top: 8, child: _Tag(tr('vorher', 'before'))),
                      Positioned(right: 8, top: 8, child: _Tag(tr('nachher', 'after'))),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _LeftOf extends CustomClipper<Rect> {
  const _LeftOf(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_LeftOf old) => old.fraction != fraction;
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(text.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, letterSpacing: 0.8)),
    ),
  );
}

/// The whole-frame preview of a step; the others are crops (center, corner, brightest).
String? fullPreview(List<String> previews) {
  if (previews.isEmpty) return null;
  return previews.firstWhere(
    (p) => RegExp(r'_full\.(jpe?g|png)$', caseSensitive: false).hasMatch(p),
    orElse: () => previews.first,
  );
}

/// Whether the image is still linear at step [index]: nothing up to it has stretched.
/// Brightness and clipping say nothing there.
bool linearAt(List<RunStep> steps, int index) => !steps.take(index + 1).any((s) => s.op == 'stretch');

/// The step before [index] that left an image or measurements – what "before" means.
RunStep? stepBefore(List<RunStep> steps, int index) {
  for (var i = index - 1; i >= 0; i--) {
    if (steps[i].previews.isNotEmpty || steps[i].metrics.isNotEmpty) return steps[i];
  }
  return null;
}
