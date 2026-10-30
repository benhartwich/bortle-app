// What the tools without an account remember on the phone: the site and the optics.
// Nothing of it leaves the phone but the site, rounded, when the weather is asked for.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';

import '../l10n.dart';
import '../optics.dart';

class Site {
  const Site(this.lat, this.lon, {this.label});

  factory Site.fromJson(Map j) =>
      Site((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble(), label: j['label'] as String?);

  final double lat;
  final double lon;
  final String? label;

  Map<String, Object?> toJson() => {'lat': lat, 'lon': lon, 'label': label};

  /// "48,2° N · 14,2° O", or the name given to it.
  String get name =>
      label ??
      '${decimal(lat.abs(), 1)}° ${lat >= 0 ? 'N' : 'S'} · '
          '${decimal(lon.abs(), 1)}° ${lon >= 0 ? tr('O', 'E') : tr('W', 'W')}';
}

abstract class ToolsStore {
  Future<Site?> site();
  Future<void> setSite(Site site);
  Future<Optics?> optics();
  Future<void> setOptics(Optics optics);
}

class SecureToolsStore implements ToolsStore {
  SecureToolsStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<Site?> site() async {
    final raw = await _storage.read(key: 'tools_site');
    return raw == null ? null : Site.fromJson(jsonDecode(raw) as Map);
  }

  @override
  Future<void> setSite(Site site) => _storage.write(key: 'tools_site', value: jsonEncode(site.toJson()));

  @override
  Future<Optics?> optics() async {
    final raw = await _storage.read(key: 'tools_optics');
    return raw == null ? null : opticsFromJson(jsonDecode(raw) as Map);
  }

  @override
  Future<void> setOptics(Optics optics) => _storage.write(key: 'tools_optics', value: jsonEncode(opticsToJson(optics)));
}

class MemoryToolsStore implements ToolsStore {
  Site? stored;
  Optics? storedOptics;

  @override
  Future<Site?> site() async => stored;

  @override
  Future<void> setSite(Site site) async => stored = site;

  @override
  Future<Optics?> optics() async => storedOptics;

  @override
  Future<void> setOptics(Optics optics) async => storedOptics = optics;
}

Map<String, Object?> opticsToJson(Optics o) => {
  'focal': o.focalMm,
  'aperture': o.apertureMm,
  'pixel': o.pixelUm,
  'w': o.widthPx,
  'h': o.heightPx,
  'seeing': o.seeingArcsec,
  'bin': o.binning,
};

Optics opticsFromJson(Map j) => Optics(
  focalMm: (j['focal'] as num).toDouble(),
  apertureMm: (j['aperture'] as num).toDouble(),
  pixelUm: (j['pixel'] as num).toDouble(),
  widthPx: (j['w'] as num).toInt(),
  heightPx: (j['h'] as num).toInt(),
  seeingArcsec: (j['seeing'] as num?)?.toDouble() ?? 2.5,
  binning: (j['bin'] as num?)?.toInt() ?? 1,
);

/// Where the phone is, coarse: a town's precision is all twilight and altitudes need.
/// Null when location is off or refused; the person can still type a place.
typedef Locate = Future<Site?> Function();

Future<Site?> locateWithGps() async {
  if (!await Geolocator.isLocationServiceEnabled()) return null;
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
  final p = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 20)),
  );
  return Site(p.latitude, p.longitude);
}
