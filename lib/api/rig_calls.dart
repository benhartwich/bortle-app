// The rig's control surface: the same cockpit routes the web /rig pages call, nothing
// the cockpit does not already offer. A part of bortle_client.dart so it shares the one
// HTTP stack (token, error shape) without growing that file.
//
// Some of NINA's operations legitimately take long — a test exposure runs its whole
// duration, a nudge waits for the slew, a driver takes its time to connect — so these
// calls get their own timeout instead of the 20 s every other call has. A timeout here
// says only that the app stopped waiting, never that NINA failed.

part of 'bortle_client.dart';

extension RigCalls on BortleClient {
  Future<dynamic> _rigSend(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final request = http.Request(method, _uri(path, query))
      ..headers.addAll(authHeaders)
      ..headers['accept'] = 'application/json';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request).timeout(timeout));
    } on Exception {
      throw BortleError(
        0,
        tr(
          'Keine Antwort in ${timeout.inSeconds} s – NINA kann trotzdem weiterarbeiten.',
          'No answer within ${timeout.inSeconds} s – NINA may still be working on it.',
        ),
      );
    }
    final text = utf8.decode(response.bodyBytes);
    Object? json;
    try {
      json = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      json = null;
    }
    if (response.statusCode >= 400) {
      throw BortleError(response.statusCode, BortleClient._message(json) ?? 'HTTP ${response.statusCode}');
    }
    return json;
  }

  /// /nina/live with every raw device field (the overview's [live] keeps only a few).
  Future<Map> rigLive() async => await _rigSend('GET', '/api/bortle/nina/live') as Map;

  Future<Map> rigDevices() async =>
      await _rigSend('GET', '/api/bortle/nina/devices', timeout: const Duration(seconds: 40)) as Map;

  Future<Map> rigFilters() async => await _rigSend('GET', '/api/bortle/nina/filters') as Map;

  Future<Map> rigCooling() async => await _rigSend('GET', '/api/bortle/nina/cooling') as Map;

  Future<Map> rigPreflight() async =>
      await _rigSend('GET', '/api/bortle/nina/preflight', timeout: const Duration(seconds: 60)) as Map;

  Future<Map> rigAutofocusLive() async => await _rigSend('GET', '/api/bortle/nina/autofocus/live') as Map;

  Future<Map> rigTppa() async => await _rigSend('GET', '/api/bortle/nina/tppa') as Map;

  /// One of NINA's operations, with room for the slow ones. Refusals come back as the
  /// server's own words in [BortleError.message].
  Future<Map> rigControl(String action, Map<String, Object?> params, {Duration? timeout}) async => await _rigSend(
    'POST',
    '/api/bortle/nina/control',
    body: {'action': action, ...params},
    timeout: timeout ?? const Duration(seconds: 60),
  ) as Map;

  /// One measured step in a sky direction; Bortle computes the coordinate, NINA slews.
  Future<Map> rigNudge(String direction, double arcmin) async => await _rigSend(
    'POST',
    '/api/bortle/nina/nudge',
    body: {'direction': direction, 'arcmin': arcmin, 'center': false},
    timeout: const Duration(seconds: 120),
  ) as Map;

  /// The newest test exposure (a look, not a measurement).
  Future<Uint8List> rigCaptureImage() async {
    final response = await _http
        .get(_uri('/api/bortle/nina/capture', {'t': '${DateTime.now().millisecondsSinceEpoch}'}), headers: authHeaders)
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw BortleError(response.statusCode, 'HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }
}
