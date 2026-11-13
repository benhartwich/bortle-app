// Telescope → Control: the rig's devices from the phone. Everything that moves hardware
// asks first and sends nothing before the answer; a refusal comes back word for word;
// the review account and other accounts control nothing.

import 'package:bortle_app/api/bortle_client.dart';
import 'package:bortle_app/api/session_store.dart';
import 'package:bortle_app/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_server.dart';

MemorySessionStore signedIn() =>
    MemorySessionStore()..session = const StoredSession('https://bortle.eu', FakeServer.token);

Widget app(FakeServer server, [MemorySessionStore? store]) => BortleApp(
  store: store ?? signedIn(),
  clientFor: (url, token) => BortleClient(baseUrl: url, token: token, http_: server.client),
);

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> openControl(WidgetTester tester, FakeServer server, [MemorySessionStore? store]) async {
  phone(tester);
  await tester.pumpWidget(app(server, store));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Teleskop')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Steuern'));
  await tester.pumpAndSettle();
}

final _page = find.byKey(const Key('rig-page'));

/// Opens a device's page from the bar at the top.
Future<void> open(WidgetTester tester, String section) async {
  final button = find.byKey(Key('rig-$section'));
  // the whole strip is built (it is short); bring the one button into sight
  await tester.ensureVisible(find.byKey(Key('rig-$section'), skipOffstage: false));
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// One of the mount page's tabs: control | slew | tppa | flip.
Future<void> mountTab(WidgetTester tester, String tab) async {
  await tester.tap(find.byKey(Key('mount-tab-$tab')));
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find.descendant(of: _page, matching: find.byType(Scrollable)).first,
  );
  // the last answer's snack bar floats over the bottom of the page; a hand would wait
  ScaffoldMessenger.of(tester.element(target)).removeCurrentSnackBar();
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> answer(WidgetTester tester) async {
  await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
  await tester.pumpAndSettle();
}

Future<void> decline(WidgetTester tester) async {
  await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextButton)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the pre-flight runs from the phone and says what blocks the night', (tester) async {
    final server = FakeServer();
    await openControl(tester, server);
    expect(find.byKey(const Key('rig-camera')), findsOneWidget);
    await tester.tap(find.byKey(const Key('preflight')));
    await tester.pumpAndSettle();
    expect(find.text('1 blocking, 1 to look at'), findsOneWidget);
    expect(find.textContaining('Focuser'), findsWidgets);
    expect(find.textContaining('10 s, solve needs 20 s'), findsOneWidget);
    expect(server.controls, isEmpty);
  });

  testWidgets('the camera cools to Bortle’s setpoint after asking, and a test exposure shows its frame', (
    tester,
  ) async {
    final server = FakeServer();
    await openControl(tester, server);
    await open(tester, 'camera');

    // the derived setpoint, filled in, with its reason
    expect(tester.widget<TextField>(find.byKey(const Key('cool-temp'))).controller!.text, '-15');
    expect(find.textContaining('darks on disk at -15 °C'), findsOneWidget);

    await tapKey(tester, 'cool');
    expect(find.text('Auf -15 °C kühlen?'), findsOneWidget);
    expect(server.controls, isEmpty); // nothing before the answer
    await decline(tester);
    expect(server.controls, isEmpty);
    await tapKey(tester, 'cool');
    await answer(tester);
    expect(server.controls.single, {'action': 'cool', 'temperature': -15.0, 'minutes': 10.0});

    // out of range never reaches the server
    await tester.enterText(find.byKey(const Key('capture-exposure')), '300');
    await tapKey(tester, 'capture');
    expect(find.text('Eine Testaufnahme dauert 0 bis 120 s.'), findsOneWidget);
    expect(server.controls, hasLength(1));

    await tester.enterText(find.byKey(const Key('capture-exposure')), '5');
    await tapKey(tester, 'capture');
    expect(server.controls.last, {'action': 'capture', 'duration': 5.0, 'gain': 100});
    await tester.scrollUntilVisible(
      find.byKey(const Key('capture-image')),
      200,
      scrollable: find.descendant(of: _page, matching: find.byType(Scrollable)).first,
    );
    expect(find.byKey(const Key('capture-image')), findsOneWidget);
    expect(find.textContaining('a look, not a measurement'), findsOneWidget);
  });

  testWidgets('the mount parks only after asking, and nudging is allowed once per visit', (tester) async {
    final server = FakeServer();
    await openControl(tester, server);
    await open(tester, 'mount');
    expect(find.textContaining('Meridian-Flip in 1 h 30'), findsOneWidget);

    await tapKey(tester, 'park');
    expect(find.text('Montierung parken?'), findsOneWidget);
    expect(server.controls, isEmpty);
    await answer(tester);
    expect(server.controls.single, {'action': 'park'});

    await tapKey(tester, 'nudge-north');
    expect(find.text('Feinjustage freigeben?'), findsOneWidget);
    expect(server.nudges, isEmpty);
    await answer(tester);
    expect(server.nudges.single, {'direction': 'north', 'arcmin': 5.0, 'center': false});
    await tester.ensureVisible(find.text('10′'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10′'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'nudge-west');
    expect(find.byType(AlertDialog), findsNothing); // allowed for this visit
    expect(server.nudges.last, {'direction': 'west', 'arcmin': 10.0, 'center': false});
  });

  testWidgets('a filter change asks, by the wheel’s own names', (tester) async {
    final server = FakeServer();
    await openControl(tester, server);
    await open(tester, 'filter');
    // the current filter is not a choice, an empty slot is not shown
    expect(tester.widget<FilledButton>(find.byKey(const Key('filter-Optolong L Pro'))).onPressed, isNull);
    expect(find.byKey(const Key('filter-')), findsNothing);
    await tapKey(tester, 'filter-Antlia H Alpha & OIII');
    expect(server.controls, isEmpty);
    await answer(tester);
    expect(server.controls.single, {'action': 'filter', 'filter': 'Antlia H Alpha & OIII'});
  });

  testWidgets('the focuser moves after one permission, and the last autofocus curve is drawn', (tester) async {
    final server = FakeServer();
    await openControl(tester, server);
    await open(tester, 'focus');
    expect(find.byKey(const Key('focus-curve')), findsOneWidget);
    expect(find.textContaining('Letzter Lauf: 8150'), findsOneWidget);
    expect(find.textContaining('R² 0,996'), findsOneWidget);

    await tapKey(tester, 'focus-step-100');
    expect(find.text('Fokus fahren freigeben?'), findsOneWidget);
    await answer(tester);
    expect(server.controls.single, {'action': 'focus-step', 'steps': 100});
    await tapKey(tester, 'focus-step--10');
    expect(find.byType(AlertDialog), findsNothing);
    expect(server.controls.last, {'action': 'focus-step', 'steps': -10});

    await tester.enterText(find.byKey(const Key('focus-target')), '-5');
    await tapKey(tester, 'focus-move');
    expect(find.text('Bitte eine Position ab 0.'), findsOneWidget);
    expect(server.controls, hasLength(2));
  });

  testWidgets('disconnecting says it may not come back, and sends confirm only then', (tester) async {
    final server = FakeServer();
    await openControl(tester, server);
    await open(tester, 'devices');
    expect(find.text('ATR2600C (k_0-12b7)'), findsOneWidget);
    await tapKey(tester, 'disconnect-camera');
    expect(find.textContaining('Hardware am Teleskop'), findsOneWidget);
    expect(server.controls, isEmpty);
    await answer(tester);
    expect(server.controls.single, {'action': 'disconnect', 'device': 'camera', 'confirm': true});
    await tapKey(tester, 'connect-focuser');
    await answer(tester);
    expect(server.controls.last, {'action': 'connect', 'device': 'focuser'});
  });

  testWidgets('a refusal is shown in the server’s own words and not retried', (tester) async {
    final server = FakeServer()
      ..refusals['autofocus'] = 'NINA runs an autofocus right now — a second one corrupts the curve.';
    await openControl(tester, server);
    await open(tester, 'focus');
    await tapKey(tester, 'autofocus');
    await answer(tester);
    expect(find.text('NINA runs an autofocus right now — a second one corrupts the curve.'), findsOneWidget);
    expect(server.controls.where((c) => c['action'] == 'autofocus'), hasLength(1));
  });

  testWidgets('guiding and the sequence start and stop only after asking', (tester) async {
    final server = FakeServer();
    await openControl(tester, server);
    await open(tester, 'guiding');
    expect(find.textContaining('RMS 0,62″'), findsWidgets);
    await tapKey(tester, 'guiding-stop');
    expect(server.controls, isEmpty);
    await answer(tester);
    expect(server.controls.single, {'action': 'guiding-stop'});
    await open(tester, 'sequence');
    await tapKey(tester, 'sequence-stop');
    await answer(tester);
    expect(server.controls.last, {'action': 'sequence-stop'});
  });

  testWidgets('polar alignment: start asks, the error shows signed, polling ends with the screen', (tester) async {
    final server = FakeServer();
    await openControl(tester, server);
    await open(tester, 'mount');
    await mountTab(tester, 'tppa');
    await tapKey(tester, 'open-tppa');
    expect(find.text('Polausrichtung'), findsOneWidget);
    expect(find.byKey(const Key('tppa-total')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tppa-start')));
    await tester.pumpAndSettle();
    expect(find.text('Polausrichtung starten?'), findsOneWidget);
    expect(server.controls, isEmpty);
    await answer(tester);
    expect(server.controls.single, {'action': 'tppa-start'});
    expect(tester.widget<Text>(find.byKey(const Key('tppa-total'))).data, '3,42′');
    expect(tester.widget<Text>(find.byKey(const Key('tppa-az'))).data, '-2,10′');
    expect(tester.widget<Text>(find.byKey(const Key('tppa-alt'))).data, '+2,70′');

    await tester.tap(find.byKey(const Key('tppa-stop')));
    await tester.pumpAndSettle();
    expect(server.controls.last, {'action': 'tppa-stop'});

    Navigator.of(tester.element(find.byKey(const Key('tppa-total')))).pop();
    await tester.pumpAndSettle();
    final polls = server.tppaPolls;
    await tester.pump(const Duration(seconds: 10));
    expect(server.tppaPolls, polls);
  });

  testWidgets('without the TPPA plugin the screen says so and offers nothing', (tester) async {
    final server = FakeServer()..tppaAvailable = false;
    await openControl(tester, server);
    await open(tester, 'mount');
    await mountTab(tester, 'tppa');
    await tapKey(tester, 'open-tppa');
    expect(find.byKey(const Key('tppa-unavailable')), findsOneWidget);
    expect(find.byKey(const Key('tppa-start')), findsNothing);
  });

  testWidgets('by day the control view says NINA is not answering', (tester) async {
    final server = FakeServer(ninaUp: false);
    await openControl(tester, server);
    expect(find.textContaining('ohne NINA gibt es nichts zu steuern'), findsOneWidget);
    expect(find.byKey(const Key('rig-camera')), findsNothing);
  });

  testWidgets('the review account sees no controls and sends nothing', (tester) async {
    final server = FakeServer(admin: false, demo: true);
    await openControl(tester, server);
    expect(find.byKey(const Key('rig-control')), findsNothing);
    expect(find.byKey(const Key('preflight')), findsNothing);
    expect(server.controls, isEmpty);
    expect(server.requests.where((r) => r.method == 'POST' && r.url.path.startsWith('/api/bortle/nina/')), isEmpty);
  });
}
