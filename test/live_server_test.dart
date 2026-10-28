// The real client against a real Bortle cockpit, over real HTTP. Skipped unless pointed at
// one; the account must not be an admin:
//
//   BORTLE_E2E_URL=http://127.0.0.1:3199 BORTLE_E2E_LOGIN=… BORTLE_E2E_PASSWORD=… \
//     flutter test test/live_server_test.dart

import 'dart:io';

import 'package:bortle_app/api/bortle_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final url = Platform.environment['BORTLE_E2E_URL'];
  final login = Platform.environment['BORTLE_E2E_LOGIN'];
  final password = Platform.environment['BORTLE_E2E_PASSWORD'];
  final skip = url == null || login == null || password == null ? 'no live cockpit given' : null;

  test('sign in, read what stages 1 and 2 show, sign out', () async {
    final anonymous = BortleClient(baseUrl: url!);
    final info = await anonymous.info();
    expect(info, isNotNull);
    expect(info!.supported, isTrue);

    final result = await anonymous.login(login!, password!, 'live_server_test');
    expect(result.token, startsWith('bat_'));
    expect(result.user.admin, isFalse);

    final client = BortleClient(baseUrl: url, token: result.token);
    expect((await client.me()).name, result.user.name);
    expect((await client.devices()).map((d) => d.label), contains('live_server_test'));
    await client.night();
    await client.pipelines(waiting: true);
    await client.runs();
    await client.gallery();
    await client.events();

    // stage 2: planning answers for this account's site …
    expect(await client.suggest('NGC 70'), isNotEmpty);
    await client.developLevel();
    try {
      final plan = await client.plan('NGC 7000');
      expect(plan.object, 'NGC 7000');
    } on BortleError catch (e) {
      // an account without a site gets the planner's own words, not a crash
      expect(e.status, 400);
      expect(e.message, contains('Standort'));
    }
    // … and the operator's telescope stays closed to this (non-admin) account
    await expectLater(client.live(), throwsA(isA<BortleError>().having((e) => e.status, 'status', 403)));

    await client.logout();
    await expectLater(client.me(), throwsA(isA<BortleError>().having((e) => e.unauthorized, 'unauthorized', isTrue)));
  }, skip: skip);
}
