// One recommended target of a night, as a card that says what makes it differ from the
// next one: the sky around it with the rig's field, when it can be imaged, how high it
// stands, how it fits the frame, what is already collected and how it ranks.

import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../api/bortle_client.dart';
import '../api/models.dart';
import '../charts.dart' show timeRange;
import '../design.dart';
import '../framing/framing_screen.dart';
import '../l10n.dart';
import '../object_preview.dart';

class RecommendationCard extends StatelessWidget {
  const RecommendationCard({
    required this.target,
    required this.client,
    required this.onTap,
    this.fovArcmin,
    super.key,
  });

  final Recommendation target;
  final BortleClient client;
  final VoidCallback onTap;

  /// The rig's field in arcminutes, from the same answer; null without optics.
  final (double, double)? fovArcmin;

  @override
  Widget build(BuildContext context) {
    final r = target;
    final tones = context.tones;
    final primary = Theme.of(context).colorScheme.primary;
    final muted = TextStyle(color: tones.muted, fontSize: 13);
    final blocked = r.visibleHours <= 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('rec-${r.name}'),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkyThumb(client: client, target: r, fovArcmin: fovArcmin),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                r.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (r.favorite)
                              Icon(Icons.star, key: const Key('rec-favorite'), size: 18, color: tones.warn),
                          ],
                        ),
                        const SizedBox(height: 2),
                        if (blocked)
                          Text(
                            blockedText(r),
                            key: Key('rec-blocked-${r.name}'),
                            style: TextStyle(color: tones.warn, fontSize: 13),
                          )
                        else
                          Text(
                            '${timeRange(r.windowStart, r.windowEnd)} · ${decimal(r.visibleHours, 1)} h',
                            key: Key('rec-window-${r.name}'),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        if (altitudeText(r) case final alt?) Text(alt, style: muted),
                        if (frameText(r) case final frame?) Text(frame, style: muted),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (r.filter != null)
                    _Tag(
                      Icons.filter_alt_outlined,
                      '${r.filter}${r.exposureS != null ? ' · ${r.exposureS!.round()} s' : ''}',
                    ),
                  if (r.alreadyHours > 0)
                    _Tag(
                      Icons.inventory_2_outlined,
                      tr('${decimal(r.alreadyHours, 1)} h gesammelt', '${decimal(r.alreadyHours, 1)} h collected'),
                      color: tones.good,
                      key: Key('rec-collected-${r.name}'),
                    ),
                  ActionChip(
                    key: Key('rec-frame-${r.name}'),
                    avatar: const Icon(Icons.crop_rotate, size: 16),
                    label: Text(tr('Einrahmen', 'Frame')),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => FramingScreen(client: client, target: r.name, raDeg: r.raDeg, decDeg: r.decDeg),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // the rank as a quiet bar along the bottom edge: it orders, it does not shout
            LinearProgressIndicator(
              key: Key('rec-score-${r.name}'),
              value: (r.score / 100).clamp(0.0, 1.0),
              minHeight: 3,
              color: blocked ? tones.muted : primary.withValues(alpha: .8),
              backgroundColor: tones.line,
            ),
          ],
        ),
      ),
    );
  }
}

/// Why a target has no window tonight, in a few words.
String blockedText(Recommendation r) => switch (r.blockedBy) {
  'clouds' => tr(
    'bewölkt – sonst ${decimal(r.darkHoursAboveHorizon, 1)} h dunkel und hoch genug',
    'clouded out – otherwise ${decimal(r.darkHoursAboveHorizon, 1)} h dark and high enough',
  ),
  _ => tr('steht nicht hoch genug im Dunkeln', 'not high enough while it is dark'),
};

/// "max. 76° · Ø 75°, Luftmasse 1,03"
String? altitudeText(Recommendation r) {
  if (r.maxAltitude == null) return null;
  final mean = r.meanAltitude;
  return [
    tr('max. ${r.maxAltitude!.round()}°', 'max ${r.maxAltitude!.round()}°'),
    if (mean != null && mean > 0 && r.airmass != null)
      tr(
        'Ø ${mean.round()}°, Luftmasse ${decimal(r.airmass!, 2)}',
        'avg ${mean.round()}°, airmass ${decimal(r.airmass!, 2)}',
      ),
  ].join(' · ');
}

/// "passt gut ins Feld" and friends; null when the profile has no optics.
String? frameText(Recommendation r) {
  final verdict = verdictText(r.fovVerdict);
  if (verdict == null) return null;
  return tr('Bildfeld: $verdict', 'Frame: $verdict');
}

class _Tag extends StatelessWidget {
  const _Tag(this.icon, this.text, {this.color, super.key});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.tones.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: context.tones.line),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: c),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small survey picture around the target, the rig's field drawn on it. Loaded lazily and
/// cached by the client; while it loads, or if the survey service is away, the card simply
/// shows the dark square — the list never waits for it.
class SkyThumb extends StatefulWidget {
  const SkyThumb({required this.client, required this.target, this.fovArcmin, super.key});

  final BortleClient client;
  final Recommendation target;
  final (double, double)? fovArcmin;

  static const double width = 96;

  /// Room around the field, as on the object preview.
  static const double margin = 1.6;

  @override
  State<SkyThumb> createState() => _SkyThumbState();
}

class _SkyThumbState extends State<SkyThumb> {
  Future<Uint8List>? _image;

  /// The span shown, width × height in degrees: the field with room around it, or a
  /// square degree and a half without optics.
  (double, double) get _span {
    final fov = widget.fovArcmin;
    if (fov == null) return (1.5, 1.5);
    final (w, h) = fov.$1 >= fov.$2 ? fov : (fov.$2, fov.$1);
    return (w * SkyThumb.margin / 60, h * SkyThumb.margin / 60);
  }

  @override
  void initState() {
    super.initState();
    final t = widget.target;
    if (t.raDeg != null && t.decDeg != null) {
      final (w, h) = _span;
      String f(double v) => v.toStringAsFixed(4);
      final path =
          '/plan/preview/image?ra=${f(t.raDeg!)}&dec=${f(t.decDeg!)}&width_deg=${f(w)}&height_deg=${f(h)}'
          '&survey=dss2&width_px=240';
      _image = widget.client.previewImage(path)..ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final (w, h) = _span;
    final fov = widget.fovArcmin;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        key: Key('rec-thumb-${widget.target.name}'),
        width: SkyThumb.width,
        height: SkyThumb.width * h / w,
        child: FutureBuilder<Uint8List>(
          future: _image,
          builder: (context, snap) => Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              if (snap.hasData) Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true),
              if (fov != null)
                CustomPaint(
                  painter: FieldPainter(
                    widthFraction: 1 / SkyThumb.margin,
                    heightFraction: 1 / SkyThumb.margin,
                    positionAngleDeg: 0,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: .9),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
