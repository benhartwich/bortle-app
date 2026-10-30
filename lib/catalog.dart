// The objects the tools offer without an account (assets/catalog.json, see
// assets/CATALOG.md): Bortle's curated targets and the Messier and bright NGC/IC objects
// from OpenNGC. Read once, searched on the phone.

import 'dart:convert';

import 'package:flutter/services.dart';

import 'l10n.dart';

class SkyObject {
  const SkyObject({
    required this.name,
    required this.ids,
    required this.type,
    required this.ra,
    required this.dec,
    this.size,
    this.mag,
    this.curated = false,
    this.filter,
  });

  factory SkyObject.fromJson(Map j) => SkyObject(
    name: '${j['name']}',
    ids: [for (final i in (j['ids'] as List? ?? const [])) '$i'],
    type: '${j['type']}',
    ra: (j['ra'] as num).toDouble(),
    dec: (j['dec'] as num).toDouble(),
    size: (j['size'] as num?)?.toDouble(),
    mag: (j['mag'] as num?)?.toDouble(),
    curated: j['src'] == 'bortle',
    filter: j['filter'] as String?,
  );

  final String name;

  /// Catalogue identifiers, Messier first where there is one: M31, NGC224.
  final List<String> ids;
  final String type;

  /// J2000, degrees.
  final double ra;
  final double dec;

  /// Largest dimension in arcminutes.
  final double? size;
  final double? mag;

  /// One of Bortle's curated targets (what the planner recommends from).
  final bool curated;

  /// narrowband | broadband | either, for the curated ones.
  final String? filter;

  /// "M 31 · NGC 224", the identifiers as people write them.
  String get label =>
      ids.map((i) => i.replaceFirstMapped(RegExp(r'^([A-Z]+)(\d)'), (m) => '${m[1]} ${m[2]}')).join(' · ');

  String get typeName => switch (type) {
    'galaxy' => tr('Galaxie', 'Galaxy'),
    'emission_nebula' => tr('Emissionsnebel', 'Emission nebula'),
    'reflection_nebula' => tr('Reflexionsnebel', 'Reflection nebula'),
    'planetary_nebula' => tr('Planetarischer Nebel', 'Planetary nebula'),
    'supernova_remnant' => tr('Supernova-Überrest', 'Supernova remnant'),
    'globular_cluster' => tr('Kugelsternhaufen', 'Globular cluster'),
    'open_cluster' => tr('Offener Sternhaufen', 'Open cluster'),
    'dark_nebula' => tr('Dunkelnebel', 'Dark nebula'),
    _ => tr('Nebel', 'Nebula'),
  };
}

class Catalog {
  const Catalog(this.objects);

  static Future<Catalog> load([AssetBundle? bundle]) async =>
      parse(await (bundle ?? rootBundle).loadString('assets/catalog.json'));

  static Catalog parse(String json) =>
      Catalog([for (final o in jsonDecode(json) as List) SkyObject.fromJson(o as Map)]);

  final List<SkyObject> objects;

  static String _key(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s\-_.]'), '');

  /// Objects whose name or identifier contains [query] ("m31", "andromeda", "ngc 7000"),
  /// exact identifiers first.
  List<SkyObject> search(String query, {int limit = 30}) {
    final q = _key(query);
    if (q.isEmpty) return const [];
    final exact = <SkyObject>[];
    final starts = <SkyObject>[];
    final contains = <SkyObject>[];
    for (final o in objects) {
      final keys = [for (final i in o.ids) _key(i), _key(o.name)];
      if (keys.any((k) => k == q)) {
        exact.add(o);
      } else if (keys.any((k) => k.startsWith(q))) {
        starts.add(o);
      } else if (keys.any((k) => k.contains(q))) {
        contains.add(o);
      }
    }
    return [...exact, ...starts, ...contains].take(limit).toList();
  }
}
