// Stage 1 as a user meets it: sign in with an own server, answer a hold, open a run,
// turn on red light, sign out. Against the scripted cockpit in fake_server.dart.

import 'package:bortle_app/api/bortle_client.dart';
import 'package:bortle_app/api/session_store.dart';
import 'package:bortle_app/design.dart';
import 'package:bortle_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';

Widget app(FakeServer server, MemorySessionStore store) => BortleApp(
  store: store,
  clientFor: (url, token) => BortleClient(baseUrl: url, token: token, http_: server.client),
);

void main() {
  testWidgets('sign in on an own server, answer the hold, sign out', (tester) async {
    final server = FakeServer();
    final store = MemorySessionStore();
    await tester.pumpWidget(app(server, store));
    await tester.pumpAndSettle();

    // bortle.eu is checked by itself; switch to an own install
    await tester.tap(find.text('Eigene Instanz'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('server')), 'bortle.sternwarte.test');
    await tester.tap(find.text('Prüfen'));
    await tester.pumpAndSettle();
    expect(find.text('Bortle 2026.10 gefunden'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login')), 'ben@example.org');
    await tester.enterText(find.byKey(const Key('password')), 'right');
    await tester.tap(find.byKey(const Key('sign-in')));
    await tester.pumpAndSettle();

    expect(store.session!.serverUrl, 'https://bortle.sternwarte.test');
    expect(store.session!.token, FakeServer.token);
    expect(server.requests.last.url.host, 'bortle.sternwarte.test');

    // Heute: the hold, the computing run, the night
    expect(find.text('Wartet auf dich: NGC 7000'), findsOneWidget);
    expect(find.text('NGC7000_emission'), findsOneWidget);
    expect(find.text('Läuft'), findsOneWidget);

    await tester.tap(find.text('Wartet auf dich: NGC 7000'));
    await tester.pumpAndSettle();
    expect(find.text('• Gradient 4,1 % in Nacht 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('approve')));
    await tester.pumpAndSettle();
    expect(server.approved, isTrue);
    expect(find.text('Wartet auf dich: NGC 7000'), findsNothing);

    // Mehr: red light, then sign out
    await tester.tap(find.text('Mehr'));
    await tester.pumpAndSettle();
    expect(find.text('Angemeldet als ben (Betreiber)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('red-light')));
    await tester.pumpAndSettle();
    expect(store.red, isTrue);
    final theme = Theme.of(tester.element(find.text('Mehr').last));
    expect(theme.extension<Tones>()!.red, isTrue);

    await tester.tap(find.byKey(const Key('sign-out')));
    await tester.pumpAndSettle();
    expect(server.signedOut, isTrue);
    expect(store.session, isNull);
    expect(find.text('Eigene Instanz'), findsOneWidget);
  });

  testWidgets('a revoked token sends the app back to the login', (tester) async {
    final server = FakeServer();
    final store = MemorySessionStore()..session = const StoredSession('https://bortle.eu', 'bat_revoked');
    await tester.pumpWidget(app(server, store));
    await tester.pumpAndSettle();
    expect(store.session, isNull);
    expect(find.byKey(const Key('sign-in')), findsOneWidget);
  });

  testWidgets('a local-mode install connects without a login', (tester) async {
    final server = FakeServer(localMode: true);
    final store = MemorySessionStore();
    await tester.pumpWidget(app(server, store));
    await tester.pumpAndSettle();
    expect(find.text('Bortle 2026.10 im lokalen Modus – keine Anmeldung nötig'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sign-in')));
    await tester.pumpAndSettle();
    expect(store.session!.token, isNull);
    expect(find.text('Wartet auf dich: NGC 7000'), findsOneWidget);
    expect(server.requests.where((r) => r.headers.containsKey('authorization')), isEmpty);
  });

  testWidgets('a running run shows where it is', (tester) async {
    final server = FakeServer();
    final store = MemorySessionStore()..session = const StoredSession('https://bortle.eu', FakeServer.token);
    await tester.pumpWidget(app(server, store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galerie'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Läufe'));
    await tester.pumpAndSettle();
    expect(find.text('rechnet'), findsOneWidget);
    await tester.tap(find.text('NGC7000_emission').last);
    await tester.pumpAndSettle();
    expect(find.text('Rechnet'), findsOneWidget);
    expect(find.text('kommt noch'), findsOneWidget);
    // the 15 s refresh timer must not outlive the screen
    Navigator.of(tester.element(find.text('Rechnet'))).pop();
    await tester.pumpAndSettle();
  });
}
