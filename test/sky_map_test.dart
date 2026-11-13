// The sky map against the scripted cockpit: the site from the recommendation, tonight's
// targets, the search centring the map, the card's "Einrahmen", the mount marker and the
// phone's aim – and how it says so when one of them is missing.

import 'dart:async';
import 'dart:io';

import 'package:bortle_app/api/bortle_client.dart';
import 'package:bortle_app/design.dart';
import 'package:bortle_app/sky/phone_aim.dart';
import 'package:bortle_app/sky/sky_catalog.dart';
import 'package:bortle_app/sky/sky_map_screen.dart';
import 'package:bortle_app/sky/sky_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_server.dart';

final _catalog = SkyCatalog.parse(File('assets/sky.json').readAsStringSync());
final _t = DateTime.utc(2026, 11, 2, 19);

class _FakeAim implements AimSource {
  final controller = StreamController<PhoneAim>.broadcast();

  @override
  Stream<PhoneAim> aims() => controller.stream;
}

class _NoSensors implements AimSource {
  @override
  Stream<PhoneAim> aims() => Stream.error(UnsupportedError('no sensors'));
}

/// The mode chips sit in a row that scrolls sideways on a narrow phone.
Future<void> chip(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
}

double _azDiff(double a, double b) => ((a - b + 540) % 360 - 180).abs();

void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<SkyMapScreenState> open(
    WidgetTester tester,
    FakeServer server, {
    String? highlight,
    FrameObject? onFrame,
    AimSource? aim,
    bool red = false,
  }) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: bortleTheme(red: red),
        home: SkyMapScreen(
          client: BortleClient(baseUrl: 'https://bortle.eu', token: FakeServer.token, http_: server.client),
          highlightTarget: highlight,
          onFrame: onFrame,
          catalog: _catalog,
          aimSource: aim,
          clock: () => _t,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state<SkyMapScreenState>(find.byType(SkyMapScreen));
  }

  void expectCentredOn(SkyMapScreenState state, double ra, double dec, {bool jNow = false}) {
    final (az, alt) = SkyFrame.at(48.2, 14.2, _t).horizontal(ra, dec, jNow: jNow);
    final (vAz, vAlt, _) = state.view;
    expect(_azDiff(vAz, az), lessThan(1e-6));
    expect(vAlt, closeTo(alt, 1e-6));
  }

  testWidgets('the whole sky for the account\'s site, with the compass', (tester) async {
    final state = await open(tester, FakeServer());
    expect(find.byKey(const Key('sky-canvas')), findsOneWidget);
    expect(find.text('Sternkarte'), findsOneWidget);
    // the all-sky view, centred on the zenith, facing south
    expect(state.view, (180.0, 90.0, 190.0));
    expect(find.text('S 180,0°'), findsOneWidget);
    expect(find.byKey(const Key('sky-card')), findsNothing);
  });

  testWidgets('the bundled asset loads', (tester) async {
    final catalog = await tester.runAsync(SkyCatalog.load);
    expect(catalog!.length, _catalog.length);
  });

  testWidgets('the red light mode draws too', (tester) async {
    await open(tester, FakeServer(), red: true);
    expect(find.byKey(const Key('sky-canvas')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a search centres the map on the object and opens its card', (tester) async {
    final framed = <(String, double, double)>[];
    final state = await open(tester, FakeServer(), onFrame: (n, ra, dec) => framed.add((n, ra, dec)));
    await tester.enterText(find.byKey(const Key('sky-search')), 'NGC 7000');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sky-hit-NGC 7000')));
    await tester.pumpAndSettle();
    expectCentredOn(state, 314.75, 44.33);
    expect(state.view.$3, 70);
    expect(find.byKey(const Key('sky-card')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('sky-card')), matching: find.text('North America Nebula')),
      findsOneWidget,
    );
    expect(find.textContaining('Höhe'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sky-frame')));
    expect(framed, [('North America Nebula', 314.75, 44.33)]);
  });

  testWidgets('without onFrame there is no "Einrahmen"', (tester) async {
    await open(tester, FakeServer(), highlight: 'Pacman Nebula');
    expect(find.byKey(const Key('sky-card')), findsOneWidget);
    expect(find.byKey(const Key('sky-frame')), findsNothing);
  });

  testWidgets('a highlighted target of tonight is centred and selected', (tester) async {
    final state = await open(tester, FakeServer(), highlight: 'pacman nebula', onFrame: (_, _, _) {});
    expectCentredOn(state, 13.2, 56.6);
    expect(
      find.descendant(of: find.byKey(const Key('sky-card')), matching: find.text('Pacman Nebula')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sky-frame')), findsOneWidget);
  });

  testWidgets('tapping a target\'s marker opens its card', (tester) async {
    final state = await open(tester, FakeServer());
    final canvas = tester.getRect(find.byKey(const Key('sky-canvas')));
    final view = state.viewFor(canvas.size);
    final (az, alt) = SkyFrame.at(48.2, 14.2, _t).horizontal(314.75, 44.33);
    final at = canvas.topLeft + view.projectAzAlt(az, alt)!;
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byKey(const Key('sky-card')), matching: find.text('North America Nebula')),
      findsOneWidget,
    );
  });

  testWidgets('the time slider moves the sky, "Jetzt" brings it back', (tester) async {
    final state = await open(tester, FakeServer());
    expect(state.time, _t);
    await tester.drag(find.byKey(const Key('sky-time-slider')), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(state.time.isAfter(_t), isTrue);
    await tester.tap(find.byKey(const Key('sky-now')));
    await tester.pumpAndSettle();
    expect(state.time, _t);
  });

  testWidgets('following the mount keeps its JNow position in the centre', (tester) async {
    final state = await open(tester, FakeServer());
    await chip(tester, 'sky-mount-follow');
    await tester.pumpAndSettle();
    // 21.0 h, +44.43°: of date, so not precessed again
    expectCentredOn(state, 315.0, 44.43, jNow: true);
    expect(find.byKey(const Key('sky-mount-note')), findsNothing);
    await chip(tester, 'sky-mount');
    await tester.pumpAndSettle();
  });

  testWidgets('a mount out of reach is said, not drawn', (tester) async {
    await open(tester, FakeServer(admin: false));
    await chip(tester, 'sky-mount');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sky-mount-note')), findsOneWidget);
    await chip(tester, 'sky-mount');
    await tester.pumpAndSettle();
  });

  testWidgets('the phone\'s aim steers the view and the compass', (tester) async {
    final aim = _FakeAim();
    final state = await open(tester, FakeServer(), aim: aim);
    await chip(tester, 'sky-aim');
    await tester.pump();
    aim.controller.add(const PhoneAim(304.8, 20));
    await tester.pumpAndSettle();
    expect(state.view.$1, 304.8);
    expect(state.view.$2, 20);
    expect(find.text('NW 304,8°'), findsOneWidget);
    await chip(tester, 'sky-aim');
    await tester.pumpAndSettle();
  });

  testWidgets('without sensors the mode switches itself off and says why', (tester) async {
    await open(tester, FakeServer(), aim: _NoSensors());
    await chip(tester, 'sky-aim');
    await tester.pumpAndSettle();
    expect(find.textContaining('Keine Lage-Sensoren'), findsOneWidget);
    final aimChip = tester.widget<FilterChip>(find.byKey(const Key('sky-aim')));
    expect(aimChip.selected, isFalse);
  });

  testWidgets('no site in the profile: the mount\'s site stands in', (tester) async {
    await open(tester, FakeServer(hasSite: false));
    expect(find.byKey(const Key('sky-canvas')), findsOneWidget);
  });

  testWidgets('no site anywhere: the map says where to set it', (tester) async {
    await open(tester, FakeServer(hasSite: false, admin: false));
    expect(find.byKey(const Key('sky-no-site')), findsOneWidget);
  });
}
