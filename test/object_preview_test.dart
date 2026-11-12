// The Plan tab's object preview: the survey picture with the account's own field drawn
// on it, and the one line saying how the object sits in that field.

import 'package:bortle_app/api/bortle_client.dart';
import 'package:bortle_app/api/models.dart';
import 'package:bortle_app/api/session_store.dart';
import 'package:bortle_app/main.dart';
import 'package:bortle_app/object_preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_server.dart';

Widget app(FakeServer server) => BortleApp(
  store: MemorySessionStore()..session = const StoredSession('https://bortle.eu', FakeServer.token),
  clientFor: (url, token) => BortleClient(baseUrl: url, token: token, http_: server.client),
);

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> searchNgc7000(WidgetTester tester) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Planen')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('object')), 'NGC 7');
  await tester.pump(const Duration(milliseconds: 300)); // the search waits for typing to pause
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('hit-NGC 7000')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a searched object shows the sky with the rig\'s field and how it fits', (tester) async {
    phone(tester);
    final server = FakeServer();
    await tester.pumpWidget(app(server));
    await tester.pumpAndSettle();
    await searchNgc7000(tester);

    expect(find.byKey(const Key('object-preview')), findsOneWidget);
    expect(find.byKey(const Key('fov-frame')), findsOneWidget);
    expect(find.text('800 mm · f/5 · 100′×67′ Feld · Objekt 120′ – größer als das Feld – Mosaik'), findsOneWidget);
    // no solved frame of it yet: the frame is level, and it says so
    expect(find.textContaining('Drehwinkel noch nicht gemessen'), findsOneWidget);
    // the picture is the one the preview pointed at, fetched with the device's token
    // (the recommendation cards fetch their small 240 px thumbnails through the same route)
    final image = server.requests
        .where((r) => r.url.path == '/api/bortle/plan/preview/image' && r.url.queryParameters['width_px'] != '240')
        .single;
    expect(image.url.queryParameters['width_deg'], '2.6773');
    expect(image.headers['authorization'], 'Bearer ${FakeServer.token}');
  });

  testWidgets('without focal length and camera it says what is missing instead of a frame', (tester) async {
    phone(tester);
    final server = FakeServer(hasOptics: false);
    await tester.pumpWidget(app(server));
    await tester.pumpAndSettle();
    await searchNgc7000(tester);

    expect(find.byKey(const Key('object-preview')), findsOneWidget);
    expect(find.byKey(const Key('fov-frame')), findsNothing);
    expect(find.byKey(const Key('no-optics')), findsOneWidget);
  });

  testWidgets('the preview needs no site, like the object\'s position', (tester) async {
    phone(tester);
    final server = FakeServer(hasSite: false);
    await tester.pumpWidget(app(server));
    await tester.pumpAndSettle();
    await searchNgc7000(tester);

    expect(find.byKey(const Key('no-site')), findsWidgets);
    expect(find.byKey(const Key('object-preview')), findsOneWidget);
  });

  test('the line reads like the cockpit: focal length, ratio, field, object and verdict', () {
    const fits = ObjectPreview(
      name: 'NGC 7023',
      raDeg: 315.4,
      decDeg: 68.16,
      focalMm: 530,
      focalRatio: 3.3,
      fovArcmin: (152.0, 101.5),
      sizeArcmin: 18,
      verdict: 'fits well',
      imagePath: '/plan/preview/image',
      imageWidthDeg: 4.05,
      imageHeightDeg: 2.7,
    );
    expect(rigLine(fits), '530 mm · f/3,3 · 152′×102′ Feld · Objekt 18′ – passt gut');
    expect(verdictText('unknown (optics incomplete)'), isNull);
  });

  test('the field turns counter-clockwise with its position angle, as in the cockpit', () {
    const painter = FieldPainter(widthFraction: .625, heightFraction: .625, positionAngleDeg: 14.7, color: Colors.red);
    expect(painter.shouldRepaint(painter), isFalse);
    expect(
      painter.shouldRepaint(
        const FieldPainter(widthFraction: .625, heightFraction: .625, positionAngleDeg: 0, color: Colors.red),
      ),
      isTrue,
    );
  });
}
