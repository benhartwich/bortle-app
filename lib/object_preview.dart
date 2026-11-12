// What the account's rig would see of an object: a survey picture of the sky around it,
// north up and east left, with the camera's field drawn on top, and one line saying how
// the object sits in that field. The same picture and frame the cockpit's framing wizard
// shows, sized by the server from the equipment profile (GET /plan/preview).

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'api/bortle_client.dart';
import 'api/models.dart';
import 'design.dart';
import 'l10n.dart';

class ObjectPreviewCard extends StatefulWidget {
  const ObjectPreviewCard({required this.client, required this.object, super.key});

  final BortleClient client;
  final String object;

  @override
  State<ObjectPreviewCard> createState() => _ObjectPreviewCardState();
}

class _ObjectPreviewCardState extends State<ObjectPreviewCard> {
  late Future<ObjectPreview> _preview = _load();
  Future<Uint8List>? _image;

  // A picture is a help, not the plan: a failure here never shows as an error of the screen.
  Future<ObjectPreview> _load() => widget.client.preview(widget.object)..ignore();

  @override
  void didUpdateWidget(ObjectPreviewCard old) {
    super.didUpdateWidget(old);
    if (old.object != widget.object) {
      _preview = _load();
      _image = null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ObjectPreview>(
    future: _preview,
    builder: (context, snap) {
      final p = snap.data;
      if (p == null) return const SizedBox.shrink();
      _image ??= widget.client.previewImage(p.imagePath)..ignore();
      return Card(
        key: const Key('object-preview'),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(aspectRatio: p.imageWidthDeg / p.imageHeightDeg, child: _picture(context, p)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p.fovArcmin != null)
                    Text(
                      rigLine(p),
                      key: const Key('rig-line'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    )
                  else
                    Text(
                      tr(
                        'Ohne Brennweite und Kamera im Profil kann Bortle kein Bildfeld zeigen – trag sie im Web unter Equipment ein.',
                        'Without focal length and camera in your profile Bortle cannot show a field – add them on the web under Equipment.',
                      ),
                      key: const Key('no-optics'),
                      style: TextStyle(color: context.tones.warn),
                    ),
                  if (p.fovArcmin != null && p.positionAngleDeg == null)
                    Text(
                      tr(
                        'Drehwinkel noch nicht gemessen – der Rahmen steht waagerecht.',
                        'Rotation not measured yet – the frame is drawn level.',
                      ),
                      style: TextStyle(color: context.tones.muted, fontSize: 12),
                    ),
                  if (p.credit != null) Text(p.credit!, style: TextStyle(color: context.tones.muted, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _picture(BuildContext context, ObjectPreview p) => FutureBuilder<Uint8List>(
    future: _image,
    builder: (context, snap) {
      final fov = p.fovArcmin;
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          if (snap.hasData) Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true),
          if (snap.hasError)
            Center(
              child: Text(
                tr('Himmelsbild gerade nicht verfügbar', 'Sky picture not available right now'),
                style: TextStyle(color: context.tones.muted),
              ),
            ),
          if (!snap.hasData && !snap.hasError) const Center(child: CircularProgressIndicator()),
          if (fov != null)
            CustomPaint(
              key: const Key('fov-frame'),
              painter: FieldPainter(
                widthFraction: fov.$1 / 60 / p.imageWidthDeg,
                heightFraction: fov.$2 / 60 / p.imageHeightDeg,
                positionAngleDeg: p.positionAngleDeg ?? 0,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
        ],
      );
    },
  );
}

/// "800 mm · f/5 · 100′×67′ Feld · Objekt 20′ – passt gut"
String rigLine(ObjectPreview p) {
  String num1(double v) => v == v.roundToDouble() ? v.round().toString() : decimal(v, 1);
  final fov = p.fovArcmin;
  return [
    if (p.focalMm != null) '${p.focalMm!.round()} mm',
    if (p.focalRatio != null) 'f/${num1(p.focalRatio!)}',
    if (fov != null) tr('${fov.$1.round()}′×${fov.$2.round()}′ Feld', '${fov.$1.round()}′×${fov.$2.round()}′ field'),
    if (p.sizeArcmin != null)
      [
        tr('Objekt ${p.sizeArcmin!.round()}′', 'object ${p.sizeArcmin!.round()}′'),
        if (verdictText(p.verdict) != null) verdictText(p.verdict),
      ].join(' – '),
  ].join(' · ');
}

/// The server's verdict in the reader's language; null when there is none to say.
String? verdictText(String? verdict) => switch (verdict) {
  'fits well' => tr('passt gut', 'fits well'),
  'fills the frame' => tr('füllt das Feld', 'fills the frame'),
  'small in frame' => tr('klein im Feld', 'small in the frame'),
  'larger than the frame — mosaic' => tr('größer als das Feld – Mosaik', 'larger than the field – mosaic'),
  _ => null,
};

/// The camera's field, centred and turned by its position angle. The picture is north up
/// and east left, so an angle east of north turns the frame counter-clockwise – the way
/// the cockpit's framing wizard draws it (`rotate(-pa)`).
class FieldPainter extends CustomPainter {
  const FieldPainter({
    required this.widthFraction,
    required this.heightFraction,
    required this.positionAngleDeg,
    required this.color,
  });

  final double widthFraction;
  final double heightFraction;
  final double positionAngleDeg;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: size.width * widthFraction,
      height: size.height * heightFraction,
    );
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..translate(size.width / 2, size.height / 2)
      ..rotate(-positionAngleDeg * math.pi / 180);
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
    // which way is "up" on the sensor, so a turned frame can be read
    canvas.drawLine(
      rect.topCenter,
      rect.topCenter.translate(0, -10),
      Paint()
        ..color = color
        ..strokeWidth = 2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(FieldPainter old) =>
      old.widthFraction != widthFraction ||
      old.heightFraction != heightFraction ||
      old.positionAngleDeg != positionAngleDeg ||
      old.color != color;
}
