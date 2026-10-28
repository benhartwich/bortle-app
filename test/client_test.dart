import 'package:bortle_app/api/bortle_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';

void main() {
  test('an address becomes a base URL', () {
    expect(normalizeServerUrl(' bortle.example.org/ '), 'https://bortle.example.org');
    expect(normalizeServerUrl('http://192.168.1.20:3100'), 'http://192.168.1.20:3100');
  });

  test('plain http is only fine at home', () {
    expect(isInsecureOutsideHome('http://192.168.1.20:3100'), isFalse);
    expect(isInsecureOutsideHome('http://bortle.local'), isFalse);
    expect(isInsecureOutsideHome('http://100.100.1.2'), isFalse);
    expect(isInsecureOutsideHome('http://bortle.example.org'), isTrue);
    expect(isInsecureOutsideHome('https://bortle.example.org'), isFalse);
  });

  test('info tells a Bortle from anything else', () async {
    final server = FakeServer();
    final info = await BortleClient(baseUrl: 'https://b.test', http_: server.client).info();
    expect(info!.version, '2026.10');
    expect(info.needsLogin, isTrue);
    expect(info.supported, isTrue);

    final notBortle = await BortleClient(baseUrl: 'https://b.test/x', http_: server.client).info();
    expect(notBortle, isNull);
  });

  test('the token goes with every call, and only the token', () async {
    final server = FakeServer();
    final anonymous = BortleClient(baseUrl: 'https://b.test', http_: server.client);
    final result = await anonymous.login('ben@example.org', 'right', 'Bortle App (Android)');
    expect(result.token, FakeServer.token);
    expect(result.user.admin, isTrue);

    final client = BortleClient(baseUrl: 'https://b.test', token: result.token, http_: server.client);
    final waiting = await client.pipelines(waiting: true);
    expect(waiting.single.waiting, isTrue);
    expect(server.requests.last.headers['authorization'], 'Bearer ${FakeServer.token}');
    expect(server.requests.last.url.queryParameters['waiting'], 'true');
    // the account is never named by the app: the proxy takes it from the token
    expect(server.requests.any((r) => r.url.queryParameters.containsKey('user')), isFalse);
  });

  test('a wrong password is an error with the server’s words', () async {
    final server = FakeServer();
    final client = BortleClient(baseUrl: 'https://b.test', http_: server.client);
    await expectLater(
      client.login('ben@example.org', 'wrong', 'x'),
      throwsA(
        isA<BortleError>()
            .having((e) => e.status, 'status', 401)
            .having((e) => e.message, 'message', contains('falsch')),
      ),
    );
  });

  test('runs read the engine’s fields', () async {
    final server = FakeServer();
    final client = BortleClient(baseUrl: 'https://b.test', token: FakeServer.token, http_: server.client);
    final runs = await client.runs();
    expect(runs.first.running, isTrue);
    expect(runs.first.progress, closeTo(.4, 1e-9));
    expect(runs.first.eta, const Duration(minutes: 14));
  });
}
