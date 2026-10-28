// The one HTTP client of the app. It speaks to the Bortle COCKPIT only (bortle.eu or the
// user's own install), never to the orchestrator behind it: the cockpit's proxy is where
// Bortle decides who may see and do what (docs/CONCEPT.md). Everything the browser
// reaches under /api/bortle/* the app reaches the same way, with its device token in
// place of the session cookie.
//
// Hand-written on package:http with hand-written fromJson, like allskyhub's HubClient.

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

const defaultServerUrl = 'https://bortle.eu';

/// The lowest /api/app/info `api` level this app can work with.
const minApiLevel = 1;

/// A call the server answered with an error.
class BortleError implements Exception {
  BortleError(this.status, this.message);

  final int status;
  final String message;

  bool get unauthorized => status == 401;

  @override
  String toString() => message;
}

/// What a server address turned out to be.
class ServerInfo {
  const ServerInfo({required this.version, required this.api, required this.needsLogin});

  final String version;
  final int api;
  final bool needsLogin;

  bool get supported => api >= minApiLevel;
}

class LoginResult {
  const LoginResult(this.token, this.user);

  final String token;
  final Me user;
}

class BortleClient {
  BortleClient({required String baseUrl, this.token, http.Client? http_})
    : baseUrl = normalizeServerUrl(baseUrl),
      _http = http_ ?? http.Client();

  final String baseUrl;

  /// This device's `bat_…` token; null before login and on an instance in local mode.
  final String? token;
  final http.Client _http;

  Map<String, String> get authHeaders => {if (token != null) 'authorization': 'Bearer $token'};

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<dynamic> _send(String method, String path, {Object? body, Map<String, String>? query}) async {
    final request = http.Request(method, _uri(path, query))
      ..headers.addAll(authHeaders)
      ..headers['accept'] = 'application/json';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request).timeout(const Duration(seconds: 20)));
    } on Exception {
      throw BortleError(0, 'Server nicht erreichbar');
    }
    final text = utf8.decode(response.bodyBytes);
    Object? json;
    try {
      json = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      json = null;
    }
    if (response.statusCode >= 400) {
      throw BortleError(response.statusCode, _message(json) ?? 'HTTP ${response.statusCode}');
    }
    return json;
  }

  static String? _message(Object? json) {
    if (json is Map) {
      final m = json['detail'] ?? json['error'];
      if (m is String) return m;
    }
    return null;
  }

  // --- the app's own endpoints ---------------------------------------------------

  /// Is there a Bortle at this address, and which one? Answers null for anything that
  /// is not a Bortle (a web page, another API, an old instance without /api/app/info).
  Future<ServerInfo?> info() async {
    try {
      final j = await _send('GET', '/api/app/info');
      if (j is! Map || j['name'] != 'bortle') return null;
      return ServerInfo(
        version: '${j['version'] ?? '?'}',
        api: (j['api'] as num?)?.toInt() ?? 0,
        needsLogin: j['auth'] != 'none',
      );
    } on BortleError catch (e) {
      if (e.status == 0) rethrow;
      return null;
    }
  }

  Future<LoginResult> login(String login, String password, String device) async {
    final j =
        await _send('POST', '/api/app/login', body: {'login': login, 'password': password, 'device': device}) as Map;
    return LoginResult(j['token'] as String, Me.fromJson(j['user'] as Map));
  }

  Future<Me> me() async => Me.fromJson((await _send('GET', '/api/app/session') as Map)['user'] as Map);

  Future<void> logout() async => _send('DELETE', '/api/app/session');

  Future<List<AppDevice>> devices() async {
    final j = await _send('GET', '/api/app/devices') as Map;
    return [for (final d in j['devices'] as List) AppDevice.fromJson(d as Map)];
  }

  Future<void> revokeDevice(String id) async => _send('DELETE', '/api/app/devices', query: {'id': id});

  // --- Bortle through the cockpit proxy -----------------------------------------

  Future<NightState> night() async => NightState.fromJson(await _send('GET', '/api/bortle/night') as Map);

  Future<List<BortleEvent>> events({int limit = 15}) async {
    final j = await _send('GET', '/api/bortle/events', query: {'limit': '$limit'}) as List;
    return [for (final e in j.reversed) BortleEvent.fromJson(e as Map)];
  }

  Future<List<Pipeline>> pipelines({bool waiting = false}) async {
    final j = await _send('GET', '/api/bortle/develop/pipelines', query: waiting ? {'waiting': 'true'} : null) as List;
    return [for (final p in j) Pipeline.fromJson(p as Map)];
  }

  Future<Pipeline> pipeline(String id) async =>
      Pipeline.fromJson(await _send('GET', '/api/bortle/develop/pipelines/${Uri.encodeComponent(id)}') as Map);

  Future<void> approve(String id, {String? note}) async =>
      _send('POST', '/api/bortle/develop/pipelines/${Uri.encodeComponent(id)}/approve', body: {'note': note});

  Future<void> cancel(String id, {String? note}) async =>
      _send('POST', '/api/bortle/develop/pipelines/${Uri.encodeComponent(id)}/cancel', body: {'note': note});

  Future<List<DevelopRun>> runs() async {
    final j = await _send('GET', '/api/bortle/develop/runs') as List;
    return [for (final r in j) DevelopRun.fromJson(r as Map)];
  }

  Future<RunDetail> run(String name) async =>
      RunDetail.fromJson(await _send('GET', '/api/bortle/develop/runs/${Uri.encodeComponent(name)}') as Map);

  Future<List<GalleryEntry>> gallery() async {
    final j = await _send('GET', '/api/bortle/gallery') as List;
    return [for (final g in j) GalleryEntry.fromJson(g as Map)];
  }

  /// A preview or result file under the data dir, as the cockpit serves it.
  String dataUrl(String relative) => '$baseUrl/api/bortle/data/$relative';

  final _images = <String, Future<Uint8List>>{};

  /// A preview's bytes, fetched once per client with this device's token. Through the
  /// same http stack as every other call, so tests and screenshots can serve it too.
  Future<Uint8List> dataBytes(String relative) => _images.putIfAbsent(relative, () async {
    final response = await _http.get(Uri.parse(dataUrl(relative)), headers: authHeaders);
    if (response.statusCode != 200) {
      _images.remove(relative);
      throw BortleError(response.statusCode, 'HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  });
}

/// "bortle.example.org" → "https://bortle.example.org"; no trailing slash.
String normalizeServerUrl(String raw) {
  var url = raw.trim();
  if (url.isEmpty) return url;
  if (!url.contains('://')) url = 'https://$url';
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

/// Plain http is fine on a home network and nowhere else.
bool isInsecureOutsideHome(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'http') return false;
  final h = uri.host;
  final private =
      h == 'localhost' ||
      h.endsWith('.local') ||
      h.startsWith('10.') ||
      h.startsWith('192.168.') ||
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(h) ||
      h.startsWith('127.') ||
      RegExp(r'^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.').hasMatch(h);
  return !private;
}
