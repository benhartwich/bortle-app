// The camera's field on the framing picture: like the Plan tab's FieldPainter
// (lib/object_preview.dart), but the frame's centre can sit off the picture's middle,
// and a small cross marks it.

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

class FramingPainter extends CustomPainter {
  const FramingPainter({
    required this.widthFraction,
    required this.heightFraction,
    required this.offsetX,
    required this.offsetY,
    required this.positionAngleDeg,
    required this.color,
  });

  /// The field's size as fractions of the picture's width and height.
  final double widthFraction;
  final double heightFraction;

  /// The field's centre relative to the picture's middle, as fractions of its span
  /// (x to the right, y down) – see offsetOnPicture.
  final double offsetX;
  final double offsetY;

  /// Degrees east of north. The picture is north up, east left, so a positive angle
  /// turns the frame counter-clockwise, as the cockpit draws it (`rotate(-pa)`).
  final double positionAngleDeg;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: size.width * widthFraction,
      height: size.height * heightFraction,
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..translate(size.width * (.5 + offsetX), size.height * (.5 + offsetY))
      ..rotate(-positionAngleDeg * math.pi / 180)
      ..drawRect(rect, stroke)
      // which way is "up" on the sensor, so a turned frame can be read
      ..drawLine(rect.topCenter, rect.topCenter.translate(0, -12), stroke)
      ..drawLine(const Offset(-6, 0), const Offset(6, 0), stroke..strokeWidth = 1)
      ..drawLine(const Offset(0, -6), const Offset(0, 6), stroke)
      ..restore();
  }

  @override
  bool shouldRepaint(FramingPainter old) =>
      old.widthFraction != widthFraction ||
      old.heightFraction != heightFraction ||
      old.offsetX != offsetX ||
      old.offsetY != offsetY ||
      old.positionAngleDeg != positionAngleDeg ||
      old.color != color;
}
