// Framing: the survey picture with the rig's field, turned and shifted, handed to NINA.
// The frame's rotation is what NINA gets; the mount moves only after the answer to a
// question; a refusal comes back word for word; the nudge maths keeps a step on the sky
// the same size at any declination.

import 'dart:math' as math;

import 'package:bortle_app/api/bortle_client.dart';
import 'package:bortle_app/api/session_store.dart';
import 'package:bortle_app/design.dart';
import 'package:bortle_app/framing/framing_math.dart';
import 'package:bortle_app/framing/framing_screen.dart';
import 'package:bortle_app/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_server.dart';

Widget framing(FakeServer server, {double? rotation, bool red = false}) => MaterialApp(
  theme: bortleTheme(red: red),
  home: FramingScreen(
    client: BortleClient(baseUrl: 'https://bortle.eu', token: FakeServer.token, http_: server.client),
    target: 'NGC 7000',
    raDeg: 314.75,
    decDeg: 44.33,
    rotationDeg: rotation,
  ),
);

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> open(WidgetTester tester, FakeServer server, {double? rotation, bool red = false}) async {
  phone(tester);
  await tester.pumpWidget(framing(server, rotation: rotation, red: red));
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await tester.scrollUntilVisible(target, 200, scrollable: find.byType(Scrollable).first);
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

List<String?> actions(FakeServer server) => [for (final c in server.controls) c['action'] as String?];

void main() {
  group('nudge maths', () {
    test('a step north moves Dec by the step, RA untouched', () {
      final (ra, dec) = nudgeCentre(314.75, 44.33, northArcmin: 30);
      expect(ra, 314.75);
      expect(dec, closeTo(44.83, 1e-9));
    });

    test('a step east is an arcminute on the sky: RA grows by 1/cos(dec)', () {
      final (ra0, _) = nudgeCentre(100, 0, eastArcmin: 60);
      expect(ra0, closeTo(101, 1e-9));
      final (ra60, dec60) = nudgeCentre(100, 60, eastArcmin: 60);
      expect(ra60, closeTo(102, 1e-9)); // cos 60° = 0.5
      expect(dec60, 60);
      final (raW, _) = nudgeCentre(100, 60, eastArcmin: -30);
      expect(raW, closeTo(99, 1e-9));
    });

    test('RA wraps through 0/360 and Dec stops at the pole', () {
      expect(nudgeCentre(359.9, 0, eastArcmin: 60).$1, closeTo(0.9, 1e-9));
      expect(nudgeCentre(0.5, 0, eastArcmin: -60).$1, closeTo(359.5, 1e-9));
      expect(nudgeCentre(10, 89.9, northArcmin: 60).$2, 90);
      expect(nudgeCentre(10, -89.9, northArcmin: -60).$2, -90);
      final (ra, _) = nudgeCentre(10, 90, eastArcmin: 1);
      expect(ra.isFinite, isTrue);
    });

    test('on the picture east is left and north is up, scaled by cos(dec)', () {
      final (x, y) = offsetOnPicture(raDeg: 101, decDeg: 60.5, ra0: 100, dec0: 60, widthDeg: 2, heightDeg: 1);
      expect(x, closeTo(-math.cos(60 * math.pi / 180) / 2, 1e-9)); // east → left
      expect(y, closeTo(-.5, 1e-9)); // north → up
      final (xWrap, _) = offsetOnPicture(raDeg: 359.5, decDeg: 0, ra0: 0.5, dec0: 0, widthDeg: 2, heightDeg: 2);
      expect(xWrap, closeTo(.5, 1e-9)); // one degree west across 0h, not 359° east
    });

    test('coordinates read as the cockpit writes them', () {
      expect(formatRa(314.75), '20h 59m 00s');
      expect(formatDec(-5.391), '−05° 23′ 28″');
    });
  });

  testWidgets('the sky shows with the rig\'s field and the measured angle', (tester) async {
    final server = FakeServer(framingAngle: 37.5);
    await open(tester, server);
    expect(find.byKey(const Key('framing-picture')), findsOneWidget);
    expect(find.byKey(const Key('framing-fov')), findsOneWidget);
    expect(find.textContaining('37,5°'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('framing-rotation-value'))).data, '38°');
    expect(server.requests.any((r) => r.url.path == '/api/bortle/plan/framing'), isTrue);
    expect(server.requests.any((r) => r.url.path == '/api/bortle/plan/preview/image'), isTrue);
    expect(server.controls, isEmpty); // looking moves nothing
  });

  testWidgets('without a measured angle the frame starts level and says why', (tester) async {
    final server = FakeServer();
    await open(tester, server);
    expect(tester.widget<Text>(find.byKey(const Key('framing-rotation-value'))).data, '0°');
    expect(find.textContaining('noch nicht gemessen'), findsOneWidget);
  });

  testWidgets('the rotation chosen is the rotation_deg NINA gets, and reset goes back', (tester) async {
    final server = FakeServer();
    await open(tester, server);
    // the slider snaps to whole degrees
    final slider = tester.widget<Slider>(find.byKey(const Key('framing-rotation')));
    slider.onChanged!(41.6);
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tapKey(tester, 'framing-rotation-plus');
    }
    expect(tester.widget<Text>(find.byKey(const Key('framing-rotation-value'))).data, '45°');

    await tapKey(tester, 'framing-sequence-target');
    expect(actions(server), ['framing-set', 'framing-set-sequence-target']);
    expect(server.controls[0]['rotation_deg'], 45);
    expect(server.controls[0]['ra_deg'], 314.75);
    expect(server.controls[0]['dec_deg'], 44.33);
    expect(server.controls[1]['rotation_deg'], 45);
    expect(server.controls[1]['name'], 'NGC 7000');

    await tapKey(tester, 'framing-rotation-reset');
    expect(tester.widget<Text>(find.byKey(const Key('framing-rotation-value'))).data, '0°');
    // below zero wraps, never a negative angle
    await tapKey(tester, 'framing-rotation-minus');
    expect(tester.widget<Text>(find.byKey(const Key('framing-rotation-value'))).data, '359°');
  });

  testWidgets('a nudge moves the centre NINA gets, by the step on the sky', (tester) async {
    final server = FakeServer();
    await open(tester, server);
    await tapKey(tester, 'framing-step-30');
    await tapKey(tester, 'framing-nudge-n');
    await tapKey(tester, 'framing-nudge-e');
    await tapKey(tester, 'framing-sequence-target');
    final set = server.controls.first;
    expect(set['action'], 'framing-set');
    expect(set['dec_deg'] as double, closeTo(44.83, 1e-9));
    final (ra, _) = nudgeCentre(314.75, 44.83, eastArcmin: 30);
    expect(set['ra_deg'] as double, closeTo(ra, 1e-9));

    server.controls.clear();
    await tapKey(tester, 'framing-centre-reset');
    await tapKey(tester, 'framing-sequence-target');
    expect(server.controls.first['ra_deg'], 314.75);
    expect(server.controls.first['dec_deg'], 44.33);
  });

  testWidgets('slewing asks first and sends framing-set then framing-slew only after yes', (tester) async {
    final server = FakeServer();
    await open(tester, server, rotation: 12);
    await tapKey(tester, 'framing-slew');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(server.controls, isEmpty); // nothing before the answer
    await decline(tester);
    expect(server.controls, isEmpty);

    await tapKey(tester, 'framing-slew');
    await answer(tester);
    expect(actions(server), ['framing-set', 'framing-slew']);
    expect(server.controls[0]['rotation_deg'], 12);
    expect(server.controls[1]['center'], true);
    expect(find.byKey(const Key('framing-message')), findsOneWidget);
  });

  testWidgets('a refused framing-set stops the slew and says why, word for word', (tester) async {
    final server = FakeServer()..refusals['framing-set'] = 'NINA: framing assistant not ready';
    await open(tester, server);
    await tapKey(tester, 'framing-slew');
    await answer(tester);
    expect(actions(server), ['framing-set']); // no slew after a refusal
    expect(
      tester.widget<Text>(find.byKey(const Key('framing-message'))).data,
      'framing-set: NINA: framing assistant not ready',
    );
  });

  testWidgets('a parked mount cannot be slewed, and the screen says so', (tester) async {
    final server = FakeServer()..mountParked = true;
    await open(tester, server);
    await tester.scrollUntilVisible(
      find.byKey(const Key('framing-slew')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final button = tester.widget<FilledButton>(find.byKey(const Key('framing-slew')));
    expect(button.onPressed, isNull);
    expect(find.textContaining('geparkt'), findsOneWidget);
  });

  testWidgets('determining the rotation measures, reads the angle back and turns the frame', (tester) async {
    final server = FakeServer()..ninaRotation = 213.4;
    await open(tester, server);
    await tapKey(tester, 'framing-determine-rotation');
    expect(actions(server), ['framing-determine-rotation']);
    expect(find.byKey(const Key('framing-determined')), findsOneWidget);
    expect(find.textContaining('213,4°'), findsWidgets);
    expect(tester.widget<Text>(find.byKey(const Key('framing-rotation-value'))).data, '213°');

    // and the measured angle is what NINA gets next
    server.controls.clear();
    await tapKey(tester, 'framing-sequence-target');
    expect(server.controls.first['rotation_deg'], 213.4);
  });

  testWidgets('a refused measurement is shown as the server said it', (tester) async {
    final server = FakeServer()..refusals['framing-determine-rotation'] = 'camera is not connected';
    await open(tester, server);
    await tapKey(tester, 'framing-determine-rotation');
    expect(
      tester.widget<Text>(find.byKey(const Key('framing-message'))).data,
      'framing-determine-rotation: camera is not connected',
    );
    expect(find.byKey(const Key('framing-determined')), findsNothing);
  });

  testWidgets('the screen works in red light', (tester) async {
    final server = FakeServer(framingAngle: 10);
    await open(tester, server, red: true);
    expect(find.byKey(const Key('framing-fov')), findsOneWidget);
    expect(find.byType(ColorFiltered), findsOneWidget);
  });

  testWidgets('a plan card opens the framing on its target', (tester) async {
    phone(tester);
    final server = FakeServer();
    await tester.pumpWidget(
      BortleApp(
        store: MemorySessionStore()..session = const StoredSession('https://bortle.eu', FakeServer.token),
        clientFor: (url, token) => BortleClient(baseUrl: url, token: token, http_: server.client),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Planen')));
    await tester.pumpAndSettle();
    final chip = find.byKey(const Key('rec-frame-Pacman Nebula'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.byType(FramingScreen), findsOneWidget);
    expect(find.text('Einrahmen · Pacman Nebula'), findsOneWidget);
    expect(server.controls, isEmpty);
  });
}
