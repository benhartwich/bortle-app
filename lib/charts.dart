// Small line charts over time, drawn by hand: the night's curves need no chart library.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'design.dart';
import 'l10n.dart';

class ChartPoint {
  const ChartPoint(this.at, this.value, {this.marked = false});

  final DateTime at;
  final double? value;

  /// Drawn as a ring: a frame the server called bad, for instance.
  final bool marked;
}

class Series {
  const Series(this.points, this.color, {this.dashed = false, this.dots = false});

  final List<ChartPoint> points;
  final Color color;
  final bool dashed;
  final bool dots;
}

/// A band along the time axis, e.g. the dark hours or the imaging window.
class TimeBand {
  const TimeBand(this.from, this.to, this.color);

  final DateTime from;
  final DateTime to;
  final Color color;
}

class TimeChart extends StatelessWidget {
  const TimeChart({
    required this.series,
    this.bands = const [],
    this.minY,
    this.maxY,
    this.guideY,
    this.height = 140,
    this.label,
    super.key,
  });

  final List<Series> series;
  final List<TimeBand> bands;
  final double? minY;
  final double? maxY;

  /// A dashed horizontal line, e.g. 30° altitude.
  final double? guideY;
  final double height;

  /// Read aloud by screen readers; the chart itself is a picture.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final labelStyle = (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
      color: tones.muted,
      fontSize: 10,
    );
    return Semantics(
      label: label,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _TimeChartPainter(
            series: series,
            bands: bands,
            minY: minY,
            maxY: maxY,
            guideY: guideY,
            grid: tones.line,
            labelStyle: labelStyle,
          ),
        ),
      ),
    );
  }
}

class _TimeChartPainter extends CustomPainter {
  _TimeChartPainter({
    required this.series,
    required this.bands,
    required this.minY,
    required this.maxY,
    required this.guideY,
    required this.grid,
    required this.labelStyle,
  });

  final List<Series> series;
  final List<TimeBand> bands;
  final double? minY;
  final double? maxY;
  final double? guideY;
  final Color grid;
  final TextStyle labelStyle;

  static const _bottom = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [for (final s in series) ...s.points];
    if (all.isEmpty) return;
    final t0 = all.map((p) => p.at.millisecondsSinceEpoch).reduce(math.min).toDouble();
    final t1 = all.map((p) => p.at.millisecondsSinceEpoch).reduce(math.max).toDouble();
    final values = [for (final p in all) ?p.value];
    if (values.isEmpty) return;
    var lo = minY ?? values.reduce(math.min);
    var hi = maxY ?? values.reduce(math.max);
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    final h = size.height - _bottom;
    double x(DateTime t) => t1 == t0 ? size.width / 2 : (t.millisecondsSinceEpoch - t0) / (t1 - t0) * size.width;
    double y(double v) => h - ((v - lo) / (hi - lo)).clamp(0, 1) * h;

    for (final b in bands) {
      canvas.drawRect(Rect.fromLTRB(x(b.from), 0, x(b.to), h), Paint()..color = b.color);
    }
    canvas.drawLine(Offset(0, h), Offset(size.width, h), Paint()..color = grid);
    if (guideY != null) {
      final gy = y(guideY!);
      final dash = Paint()
        ..color = grid
        ..strokeWidth = 1;
      for (var dx = 0.0; dx < size.width; dx += 8) {
        canvas.drawLine(Offset(dx, gy), Offset(math.min(dx + 4, size.width), gy), dash);
      }
    }

    for (final s in series) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final path = Path();
      var open = false;
      for (final p in s.points) {
        if (p.value == null) {
          open = false;
          continue;
        }
        final o = Offset(x(p.at), y(p.value!));
        if (!open) {
          path.moveTo(o.dx, o.dy);
          open = true;
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      if (s.dashed) {
        for (final metric in path.computeMetrics()) {
          for (var d = 0.0; d < metric.length; d += 7) {
            canvas.drawPath(metric.extractPath(d, math.min(d + 4, metric.length)), paint);
          }
        }
      } else if (!s.dots) {
        canvas.drawPath(path, paint);
      }
      if (s.dots || s.points.any((p) => p.marked)) {
        for (final p in s.points) {
          if (p.value == null) continue;
          final o = Offset(x(p.at), y(p.value!));
          if (p.marked) {
            canvas.drawCircle(
              o,
              4,
              Paint()
                ..color = s.color
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5,
            );
          } else if (s.dots) {
            canvas.drawCircle(o, 2.2, Paint()..color = s.color);
          }
        }
      }
    }

    // Hours along the bottom, at most five labels.
    final span = Duration(milliseconds: (t1 - t0).round());
    final step = span.inHours >= 8 ? 2 : 1;
    final start = DateTime.fromMillisecondsSinceEpoch(t0.round()).toLocal();
    var tick = DateTime(start.year, start.month, start.day, start.hour + 1);
    while (tick.millisecondsSinceEpoch <= t1) {
      final tx = x(tick);
      final tp = TextPainter(
        text: TextSpan(text: '${tick.hour.toString().padLeft(2, '0')} h', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      if (tx - tp.width / 2 > 0 && tx + tp.width / 2 < size.width) {
        tp.paint(canvas, Offset(tx - tp.width / 2, h + 4));
      }
      tick = tick.add(Duration(hours: step));
    }
  }

  @override
  bool shouldRepaint(_TimeChartPainter old) => true;
}

/// "18:40–03:50".
String timeRange(DateTime? from, DateTime? to) => from == null || to == null ? '–' : '${clock(from)}–${clock(to)}';
