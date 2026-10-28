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

  test('sign in, read everything stage 1 shows, sign out', () async {
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

    await client.logout();
    await expectLater(client.me(), throwsA(isA<BortleError>().having((e) => e.unauthorized, 'unauthorized', isTrue)));
  }, skip: skip);
}
