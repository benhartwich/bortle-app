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
import 'recipes.dart';

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

  /// Push for this device: the cockpit sends to [token] in [lang] until the device signs
  /// out or [unregisterPush] (docs/CONCEPT.md, "Push").
  Future<void> registerPush(String token, String platform, String lang) async =>
      _send('PUT', '/api/app/push-token', body: {'token': token, 'platform': platform, 'lang': lang});

  Future<void> unregisterPush() async => _send('DELETE', '/api/app/push-token');

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

  /// Carry on. [changes] is what the person decided at the hold: `recipes` (master ->
  /// recipe) at the recipe hold; `redo` and `step_overrides` ({run: {op: {param: value}}})
  /// to repeat a step with other values.
  Future<void> approve(String id, {String? note, Map<String, Object?> changes = const {}}) async => _send(
    'POST',
    '/api/bortle/develop/pipelines/${Uri.encodeComponent(id)}/approve',
    body: {'note': note, 'changes': changes},
  );

  /// Every recipe with its corridors, the person's own included.
  Future<List<RecipeSpec>> recipes() async {
    final j = await _send('GET', '/api/bortle/recipes') as Map;
    return [for (final e in j.entries) RecipeSpec.fromJson('${e.key}', e.value as Map)];
  }

  /// The words for every parameter; empty from a server too old to have them.
  Future<ParamDocs> paramDocs() async {
    try {
      return ParamDocs.fromJson(await _send('GET', '/api/bortle/recipes/docs') as Map);
    } on BortleError catch (e) {
      if (e.status == 404) return ParamDocs.empty;
      rethrow;
    }
  }

  /// Develop a finished run again with other values: from [resumeFrom] on when only
  /// values of that step and later ones changed, else from the start. Answers the new
  /// run's name.
  Future<String> redevelop(
    String name, {
    required Map<String, Map<String, Object?>> overrides,
    String? resumeFrom,
    String? recipe,
  }) async {
    final j =
        await _send(
              'POST',
              '/api/bortle/develop/runs/${Uri.encodeComponent(name)}/redevelop',
              body: {'recipe': recipe, 'overrides': overrides, 'resume_from': resumeFrom},
            )
            as Map;
    return '${j['run']}';
  }

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

  // --- planning (stage 2) --------------------------------------------------------
  // Site, horizon and tonight's plan are the signed-in account's: the proxy names it.

  Future<List<Suggestion>> suggest(String q) async {
    if (q.trim().length < 2) return const [];
    final j = await _send('GET', '/api/bortle/plan/suggest', query: {'q': q.trim()}) as List;
    return [for (final s in j) Suggestion.fromJson(s as Map)];
  }

  Future<NightPlan> plan(String object) async =>
      NightPlan.fromJson(await _send('GET', '/api/bortle/plan', query: {'object': object}) as Map);

  /// The account's default develop level: stepwise | guarded | auto.
  Future<String> developLevel() async =>
      '${((await _send('GET', '/api/bortle/develop/level')) as Map)['level'] ?? 'auto'}';

  /// Builds the sequence and loads it into NINA; `start` also starts it. Only the
  /// operator may (the instance's telescope is theirs); others get a 403.
  Future<Map> sendToNina({
    required NightPlan plan,
    required double exposureS,
    required int count,
    required String developLevel,
    bool start = false,
  }) async =>
      await _send(
            'POST',
            '/api/bortle/plan/nina',
            body: {
              'object': plan.object,
              'ra_deg': plan.raDeg,
              'dec_deg': plan.decDeg,
              'exposure_s': exposureS,
              'count': count,
              'window_end': plan.windowEnd?.toIso8601String(),
              'develop_level': developLevel,
              'start': start,
            },
          )
          as Map;

  // --- the telescope (stage 2) ------------------------------------------------------

  Future<LiveSnapshot> live() async => LiveSnapshot.fromJson(await _send('GET', '/api/bortle/nina/live') as Map);

  Future<FrameHistory> frames({int limit = 300}) async =>
      FrameHistory.fromJson(await _send('GET', '/api/bortle/nina/frames', query: {'limit': '$limit'}) as Map);

  /// One of tonight's frames as NINA renders it (stretched, a look, not a measurement).
  Future<Uint8List> liveFrame({int index = -1, int width = 900}) async {
    final response = await _http
        .get(_uri('/api/bortle/nina/live/frame', {'index': '$index', 'width': '$width'}), headers: authHeaders)
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) throw BortleError(response.statusCode, 'HTTP ${response.statusCode}');
    return response.bodyBytes;
  }

  /// One of NINA's own operations (docs/CONCEPT.md, "Control and safety"). The app
  /// asks before calling this; a refusal comes back as the server's words.
  Future<Map> control(String action, [Map<String, Object?> params = const {}]) async =>
      await _send('POST', '/api/bortle/nina/control', body: {'action': action, ...params}) as Map;

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
