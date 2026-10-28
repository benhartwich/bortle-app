// Push: the app registers with the server it is signed in to, drops it before signing out,
// and a tapped notification opens what it is about – but only from its own server.

import 'dart:convert';

import 'package:bortle_app/api/bortle_client.dart';
import 'package:bortle_app/api/session_store.dart';
import 'package:bortle_app/main.dart';
import 'package:bortle_app/push.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';

void main() {
  late NoPush push;
  setUp(() => pushService = push = NoPush());

  Widget app(FakeServer server, MemorySessionStore store) => BortleApp(
    store: store,
    clientFor: (url, token) => BortleClient(baseUrl: url, token: token, http_: server.client),
  );

  MemorySessionStore signedIn() =>
      MemorySessionStore()..session = const StoredSession('https://bortle.eu', FakeServer.token);

  test('the token goes to the cockpit with platform and language', () async {
    final server = FakeServer();
    final client = BortleClient(baseUrl: 'https://bortle.eu', token: FakeServer.token, http_: server.client);
    await client.registerPush('fcm-token', 'android', 'en');
    expect(server.pushRegistration, {'token': 'fcm-token', 'platform': 'android', 'lang': 'en'});
    final put = server.requests.last;
    expect(put.method, 'PUT');
    expect(put.headers['authorization'], 'Bearer ${FakeServer.token}');
    expect(jsonDecode(put.body), isA<Map<String, dynamic>>());
    await client.unregisterPush();
    expect(server.pushDropped, isTrue);
  });

  testWidgets('signed in registers, signing out unregisters first', (tester) async {
    final server = FakeServer();
    await tester.pumpWidget(app(server, signedIn()));
    await tester.pumpAndSettle();
    expect(push.registered, 1);

    await tester.tap(find.text('Mehr'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sign-out')));
    await tester.pumpAndSettle();
    expect(push.unregistered, 1);
    expect(server.signedOut, isTrue);
  });

  testWidgets('a tapped hold opens it; another server’s message opens nothing', (tester) async {
    final server = FakeServer();
    await tester.pumpWidget(app(server, signedIn()));
    await tester.pumpAndSettle();

    push.controller.add(const PushTap(path: '/holds/p1', server: 'https://other.example'));
    await tester.pumpAndSettle();
    expect(find.text('Freigabe'), findsNothing);

    push.controller.add(const PushTap(path: '/holds/p1', server: 'https://bortle.eu/'));
    await tester.pumpAndSettle();
    expect(find.text('Freigabe'), findsOneWidget);
  });

  testWidgets('a tapped run opens the run; the telescope opens its tab', (tester) async {
    final server = FakeServer();
    await tester.pumpWidget(app(server, signedIn()));
    await tester.pumpAndSettle();

    push.controller.add(const PushTap(path: '/runs/NGC7000_emission', server: 'https://bortle.eu'));
    await tester.pumpAndSettle();
    expect(find.text('Lauf'), findsOneWidget);
  });

  testWidgets('with the app open a message shows as a bar to open', (tester) async {
    final server = FakeServer();
    await tester.pumpWidget(app(server, signedIn()));
    await tester.pumpAndSettle();

    push.controller.add(
      const PushTap(
        path: '/holds/p1',
        server: 'https://bortle.eu',
        title: 'NGC 7000 wartet auf dich',
        body: 'Gradient',
        opened: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750)); // the bar slides in
    expect(find.text('NGC 7000 wartet auf dich – Gradient'), findsOneWidget);
    expect(find.text('Freigabe'), findsNothing);
    // The bar's action, called as a tap would (the test window's bar has no height to hit).
    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
    await tester.pumpAndSettle();
    expect(find.text('Freigabe'), findsOneWidget);
  });
}
