// Values in words, as on the cockpit: a step hold shows the step's parameters as
// explained controls and repeats the step with what the person set; a finished run can be
// developed again from the first changed step. Against the scripted cockpit.

import 'package:bortle_app/api/bortle_client.dart';
import 'package:bortle_app/design.dart';
import 'package:bortle_app/screens/develop_screen.dart';
import 'package:bortle_app/screens/hold_screen.dart';
import 'package:bortle_app/screens/run_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';

Widget _screen(Widget child) => MaterialApp(theme: bortleTheme(), home: child);

BortleClient _client(FakeServer server) =>
    BortleClient(baseUrl: 'https://bortle.eu', token: FakeServer.token, http_: server.client);

void main() {
  testWidgets('a step hold explains its values and repeats the step with a changed one', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final server = FakeServer();
    await tester.pumpWidget(_screen(HoldScreen(client: _client(server), pipelineId: 'p2')));
    await tester.pumpAndSettle();

    expect(find.text('Fertig: Strecken · als Nächstes: finish'), findsOneWidget);
    // named, explained, with what less and more do
    expect(find.text('Hintergrund-Ziel'), findsOneWidget);
    expect(find.text('Wie hell der Himmel wird.'), findsOneWidget);
    expect(find.textContaining('weniger: dunkler'), findsOneWidget);
    expect(find.text('20 %'), findsOneWidget);
    // the knob that does nothing is folded away, not offered as a dial
    expect(find.text('Sternlicht-Grenze'), findsNothing);
    expect(find.text('Ohne Wirkung (1)'), findsOneWidget);
    // no redo before anything changed
    expect(find.byKey(const Key('redo')), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Aus'));
    await tester.pumpAndSettle();
    expect(find.text('je Kanal'), findsOneWidget);
    await tester.tap(find.byKey(const Key('redo')));
    await tester.pumpAndSettle();

    // a real false, not the text "false" the engine would have replaced by its default
    expect(server.stepAnswer!['changes'], {
      'redo': true,
      'step_overrides': {
        'M33_galaxy': {
          'stretch': {'linked': false},
        },
      },
    });
  });

  testWidgets('a finished run shows its steps by name and develops again from the changed one', (tester) async {
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final server = FakeServer();
    await tester.pumpWidget(_screen(RunScreen(client: _client(server), name: 'M33_galaxy')));
    await tester.pumpAndSettle();

    expect(find.text('Strecken'), findsOneWidget);
    await tester.tap(find.text('Strecken'));
    await tester.pumpAndSettle();
    expect(find.text('Kanäle verknüpft'), findsOneWidget);
    expect(find.text('1650'), findsNothing); // counts read as a change against the step before
    expect(find.text('1700 → 1650 (−2,9 %)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('develop-again')));
    await tester.pumpAndSettle();
    // the sharpen runs twice, once for the object and once for the stars: two cards,
    // each with its own values
    expect(find.text('Entfalten / Schärfen'), findsNWidgets(2));
    expect(find.text('1. Durchgang'), findsOneWidget);
    expect(find.text('2. Durchgang'), findsOneWidget);
    expect(find.text('Ziel'), findsNWidgets(2));

    // the second pass to the object: only that occurrence changes, from there on
    await tester.tap(find.widgetWithText(ChoiceChip, 'object').last);
    await tester.pumpAndSettle();
    expect(find.text('Neu ab „Entfalten / Schärfen (2. Durchgang)“'), findsOneWidget);
    await tester.tap(find.byKey(const Key('redevelop')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Starten'));
    await tester.pumpAndSettle();

    expect(server.redevelopBody, {
      'recipe': null,
      'overrides': {
        'deconvolve_or_sharpen#2': {'target': 'object'},
      },
      'resume_from': 'deconvolve_or_sharpen#2',
    });
  });

  testWidgets('at phone width nothing runs off the screen', (tester) async {
    // 360 points wide, a common phone; an overflow is an error in a widget test
    tester.view.physicalSize = const Size(1080, 9000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final server = FakeServer();
    await tester.pumpWidget(_screen(HoldScreen(client: _client(server), pipelineId: 'p2')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_screen(RunScreen(client: _client(server), name: 'M33_galaxy')));
    await tester.pumpAndSettle();
    for (final step in ['Strecken', 'Entfalten / Schärfen']) {
      await tester.tap(find.textContaining(step).first);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('develop-again')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Aus'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Nextcloud project goes into production at the chosen level', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final server = FakeServer();
    await tester.pumpWidget(_screen(DevelopScreen(client: _client(server))));
    await tester.pumpAndSettle();

    // the account's default is preselected; the choice is for this run
    expect(find.text('Mit Leitplanken'), findsOneWidget);
    await tester.tap(find.byKey(const Key('level-stepwise')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nebel'));
    await tester.pumpAndSettle();
    expect(find.text('Projekt'), findsOneWidget);
    await tester.tap(find.byKey(const Key('start-NGC 7000')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tier-slow')));
    await tester.pumpAndSettle();

    // no account named: the cockpit takes it from the signed-in session
    expect(server.nextcloudStart, {'project': 'Nebel/NGC 7000', 'tier': 'slow', 'level': 'stepwise'});
  });
}
