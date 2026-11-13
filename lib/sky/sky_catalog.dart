// The sky map's stars and constellation figures (assets/sky.json, built by
// tool/build_sky.py from d3-celestial, BSD-3-Clause – assets/SKY.md).
//
// Kept as J2000 unit vectors in flat typed lists: the painter rotates them into the
// horizon every frame and never touches a trigonometric function per star.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'sky_math.dart';

class SkyCatalog {
  SkyCatalog._({
    required this.vectors,
    required this.mag,
    required this.bv,
    required this.ra,
    required this.dec,
    required this.names,
    required this.lines,
    required this.constellations,
  });

  /// From the packed JSON: positions in hundredths of a degree, stars brightest first.
  factory SkyCatalog.parse(String text) {
    final j = jsonDecode(text) as Map;
    final packed = (j['stars'] as List).cast<num>();
    final n = packed.length ~/ 4;
    final vectors = Float64List(n * 3);
    final mag = Float32List(n);
    final bv = Float32List(n);
    final ra = Float32List(n);
    final dec = Float32List(n);
    for (var i = 0; i < n; i++) {
      ra[i] = packed[i * 4] / 100;
      dec[i] = packed[i * 4 + 1] / 100;
      mag[i] = packed[i * 4 + 2] / 100;
      bv[i] = packed[i * 4 + 3] / 100;
      final (x, y, z) = unitVector(ra[i].toDouble(), dec[i].toDouble());
      vectors
        ..[i * 3] = x
        ..[i * 3 + 1] = y
        ..[i * 3 + 2] = z;
    }
    final lines = <Float64List>[];
    for (final figure in j['lines'] as List) {
      for (final poly in (figure as List)[1] as List) {
        final pts = (poly as List).cast<num>();
        final v = Float64List(pts.length ~/ 2 * 3);
        for (var k = 0; k < pts.length ~/ 2; k++) {
          final (x, y, z) = unitVector(pts[k * 2] / 100, pts[k * 2 + 1] / 100);
          v
            ..[k * 3] = x
            ..[k * 3 + 1] = y
            ..[k * 3 + 2] = z;
        }
        lines.add(v);
      }
    }
    return SkyCatalog._(
      vectors: vectors,
      mag: mag,
      bv: bv,
      ra: ra,
      dec: dec,
      names: {for (final e in j['star_names'] as List) ((e as List)[0] as num).toInt(): '${e[1]}'},
      lines: lines,
      constellations: [
        for (final c in j['constellations'] as List)
          (name: '${(c as List)[1]}', ra: (c[2] as num) / 100, dec: (c[3] as num) / 100),
      ],
    );
  }

  /// The bundled catalogue. Read as bytes and decoded here: AssetBundle.loadString hands
  /// anything over 50 KB to an isolate, which a widget test's fake clock never runs.
  static Future<SkyCatalog> load([AssetBundle? bundle]) async {
    final data = await (bundle ?? rootBundle).load('assets/sky.json');
    return SkyCatalog.parse(utf8.decode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)));
  }

  /// x, y, z per star (J2000), brightest first.
  final Float64List vectors;
  final Float32List mag;
  final Float32List bv;
  final Float32List ra;
  final Float32List dec;

  /// Proper names of the bright stars, Bayer letters of the others, by star index.
  final Map<int, String> names;

  /// Constellation figures: polylines of J2000 unit vectors, x, y, z per vertex.
  final List<Float64List> lines;

  /// Latin IAU names and where their label goes.
  final List<({String name, double ra, double dec})> constellations;

  int get length => mag.length;

  /// The index of a named star, or null.
  int? find(String name) {
    final lower = name.trim().toLowerCase();
    for (final e in names.entries) {
      if (e.value.toLowerCase() == lower) return e.key;
    }
    return null;
  }
}
