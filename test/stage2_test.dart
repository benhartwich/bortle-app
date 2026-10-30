// Stage 2: planning to NINA, and the telescope tab – for the operator, and closed to
// everyone else, as the cockpit closes it.

import 'package:bortle_app/api/bortle_client.dart';
import 'package:bortle_app/api/session_store.dart';
import 'package:bortle_app/main.dart';
import 'package:bortle_app/screens/telescope_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';

Widget app(FakeServer server) => BortleApp(
  store: MemorySessionStore()..session = const StoredSession('https://bortle.eu', FakeServer.token),
  clientFor: (url, token) => BortleClient(baseUrl: url, token: token, http_: server.client),
);

/// A phone, not the 800×600 test default: the telescope's first screen is its frame.
void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('plan an object and load it into NINA with the develop level', (tester) async {
    phone(tester);
    final server = FakeServer();
    await tester.pumpWidget(app(server));
    await tester.pumpAndSettle();
    await openTab(tester, 'Planen');

    await tester.enterText(find.byKey(const Key('object')), 'NGC 7');
    await tester.pumpAndSettle();
    await tester.tap(find.text('NGC7000').last);
    await tester.pumpAndSettle();

    // the real planner answer: no usable window tonight, and it says why
    expect(find.text('NGC 7000'), findsOneWidget);
    expect(find.textContaining('Kein brauchbares Fenster'), findsOneWidget);
    expect(find.text('Höhe heute Nacht'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('exposure')), '120');
    await tester.enterText(find.byKey(const Key('count')), '90');
    await tester.ensureVisible(find.byKey(const Key('send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('send')));
    await tester.pumpAndSettle();

    final sent = server.sentPlan!;
    expect(sent['object'], 'NGC 7000');
    expect(sent['exposure_s'], 120);
    expect(sent['count'], 90);
    expect(sent['develop_level'], 'guarded'); // the account's default, read from the server
    expect(sent['start'], isFalse);
    expect(sent.containsKey('user'), isFalse); // the proxy names the account
  });

  testWidgets('a recommendation for tonight brings its filter and exposure along', (tester) async {
    phone(tester);
    final server = FakeServer();
    await tester.pumpWidget(app(server));
    await tester.pumpAndSettle();
    await openTab(tester, 'Planen');

    expect(find.text('Empfehlungen für heute Nacht'), findsOneWidget);
    expect(find.textContaining('5,2 h dunkel und hoch genug'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rec-North America Nebula')));
    await tester.pumpAndSettle();

    expect(find.text('Filter: L-eXtreme (empfohlen)'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('exposure'))).controller!.text, '300');
    await tester.ensureVisible(find.byKey(const Key('send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('send')));
    await tester.pumpAndSettle();
    expect(server.sentPlan!['filter_name'], 'L-eXtreme');
    expect(server.sentPlan!['exposure_s'], 300);
  });

  testWidgets('the night at the telescope, and ending it through NINA', (tester) async {
    phone(tester);
    final server = FakeServer();
    await tester.pumpWidget(app(server));
    await tester.pumpAndSettle();
    await openTab(tester, 'Teleskop');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Sequenz läuft'), findsOneWidget);
    expect(find.text('NGC 7000 > Imaging > Smart Exposure'), findsOneWidget);
    expect(find.text('0,62″'), findsOneWidget);
    expect(find.textContaining('35 von 38 Lights brauchbar'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('end-night')),
      200,
      scrollable: find.descendant(of: find.byType(TelescopeScreen), matching: find.byType(Scrollable)).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('end-night')));
    await tester.pumpAndSettle();
    expect(find.text('Nacht beenden?'), findsOneWidget);
    expect(server.controls, isEmpty); // nothing before the confirmation
    await tester.tap(find.widgetWithText(FilledButton, 'Nacht beenden'));
    await tester.pumpAndSettle();
    expect(server.controls.single, {'action': 'sequence-skip', 'scope': 'end', 'confirm': true});

    // frames and history
    await tester.tap(find.text('Verlauf'));
    await tester.pumpAndSettle();
    expect(find.text('Sensor-Temperatur'), findsOneWidget);
    await tester.tap(find.text('Bilder'));
    await tester.pumpAndSettle();
    expect(find.text('HFR 4,1'), findsOneWidget);

    // leave the tab: the 10 s poll must stop with it
    await openTab(tester, 'Heute');
    final before = server.requests.where((r) => r.url.path == '/api/bortle/nina/live').length;
    await tester.pump(const Duration(seconds: 30));
    expect(server.requests.where((r) => r.url.path == '/api/bortle/nina/live').length, before);
  });

  testWidgets('by day NINA is not answering, and the tab says so', (tester) async {
    phone(tester);
    final server = FakeServer(ninaUp: false);
    await tester.pumpWidget(app(server));
    await tester.pumpAndSettle();
    await openTab(tester, 'Teleskop');
    await tester.pumpAndSettle();
    expect(find.textContaining('NINA antwortet gerade nicht'), findsOneWidget);
    expect(find.byKey(const Key('end-night')), findsNothing);
  });

  testWidgets('someone else’s account never touches the operator’s telescope', (tester) async {
    phone(tester);
    final server = FakeServer(admin: false);
    await tester.pumpWidget(app(server));
    await tester.pumpAndSettle();
    await openTab(tester, 'Teleskop');
    expect(find.textContaining('bedient nur ihr Betreiber'), findsOneWidget);
    await openTab(tester, 'Planen');
    await tester.enterText(find.byKey(const Key('object')), 'NGC7000');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('send')), findsNothing);
    expect(server.requests.where((r) => r.url.path.startsWith('/api/bortle/nina/')), isEmpty);
  });
}
