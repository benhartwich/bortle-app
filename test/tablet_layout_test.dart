// Phone, tablet upright, tablet on its side (lib/layout.dart): the navigation the width
// asks for, list and detail side by side only where there is room, and a tab's state kept
// across a turn of the device.

import 'package:bortle_app/api/bortle_client.dart';
import 'package:bortle_app/api/session_store.dart';
import 'package:bortle_app/framing/framing_screen.dart';
import 'package:bortle_app/main.dart';
import 'package:bortle_app/screens/gallery_screen.dart';
import 'package:bortle_app/screens/run_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_server.dart';

const phone = Size(400, 800);
const tabletUpright = Size(800, 1280);
const tabletLandscape = Size(1280, 800);

Widget app(FakeServer server) => BortleApp(
  store: MemorySessionStore()..session = const StoredSession('https://bortle.eu', FakeServer.token),
  clientFor: (url, token) => BortleClient(baseUrl: url, token: token, http_: server.client),
);

void size(WidgetTester tester, Size logical) {
  tester.view.physicalSize = logical * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

Future<void> openTab(WidgetTester tester, String label) async {
  final nav = find.byType(NavigationBar).evaluate().isNotEmpty
      ? find.byType(NavigationBar)
      : find.byType(NavigationRail);
  await tester.tap(find.descendant(of: nav, matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  for (final (logical, bar, rail, extended) in [
    (phone, true, false, false),
    (tabletUpright, false, true, false),
    (tabletLandscape, false, true, true),
  ]) {
    testWidgets('${logical.width.round()}×${logical.height.round()}: '
        '${bar ? 'bottom bar' : 'rail${extended ? ', extended' : ''}'}', (tester) async {
      size(tester, logical);
      await tester.pumpWidget(app(FakeServer()));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), bar ? findsOneWidget : findsNothing);
      expect(find.byType(NavigationRail), rail ? findsOneWidget : findsNothing);
      if (rail) expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended, extended);
      // the same five places either way
      for (final label in ['Heute', 'Planen', 'Teleskop', 'Galerie', 'Mehr']) {
        expect(find.text(label), findsWidgets);
      }
    });
  }

  testWidgets('gallery on a tablet on its side: the run opens beside the list', (tester) async {
    size(tester, tabletLandscape);
    await tester.pumpWidget(app(FakeServer()));
    await tester.pumpAndSettle();
    await openTab(tester, 'Galerie');
    expect(find.byKey(const Key('nothing-chosen')), findsOneWidget);

    await tester.tap(find.text('Läufe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('M33_galaxy'));
    await tester.pumpAndSettle();
    expect(find.byType(RunScreen), findsOneWidget);
    expect(find.byType(GalleryScreen), findsOneWidget); // still there, not pushed away
    expect(find.text('NGC7000_emission'), findsWidgets); // the list beside it
    expect(Navigator.of(tester.element(find.byType(RunScreen))).canPop(), isFalse);
  });

  testWidgets('gallery on a phone: the run is pushed over the list', (tester) async {
    size(tester, phone);
    await tester.pumpWidget(app(FakeServer()));
    await tester.pumpAndSettle();
    await openTab(tester, 'Galerie');
    expect(find.byKey(const Key('nothing-chosen')), findsNothing);

    await tester.tap(find.text('Läufe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('M33_galaxy'));
    await tester.pumpAndSettle();
    expect(find.byType(RunScreen), findsOneWidget);
    expect(find.byType(GalleryScreen), findsNothing); // offstage under the pushed run
    expect(Navigator.of(tester.element(find.byType(RunScreen))).canPop(), isTrue);
  });

  testWidgets('plan on a tablet on its side: recommendations stay, the target opens beside them', (tester) async {
    size(tester, tabletLandscape);
    await tester.pumpWidget(app(FakeServer()));
    await tester.pumpAndSettle();
    await openTab(tester, 'Planen');
    expect(find.byKey(const Key('nothing-chosen')), findsOneWidget);

    await tester.tap(find.byKey(const Key('rec-Pacman Nebula')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan-detail')), findsOneWidget);
    expect(find.text('Höhe heute Nacht'), findsOneWidget);
    expect(find.byKey(const Key('rec-North America Nebula')), findsOneWidget);
    expect(find.byKey(const Key('nothing-chosen')), findsNothing);

    // turned upright: one pane again, the chosen target kept, still on the Plan tab
    tester.view.physicalSize = tabletUpright * 2;
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Höhe heute Nacht'), findsOneWidget);
    expect(find.byKey(const Key('rec-North America Nebula')), findsNothing);

    // and down to a phone: the bottom bar, still Plan, still the target
    tester.view.physicalSize = phone * 2;
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 1);
    expect(find.text('Höhe heute Nacht'), findsOneWidget);
  });

  testWidgets('plan on a phone: the target takes the recommendations’ place', (tester) async {
    size(tester, phone);
    await tester.pumpWidget(app(FakeServer()));
    await tester.pumpAndSettle();
    await openTab(tester, 'Planen');
    await tester.ensureVisible(find.byKey(const Key('rec-North America Nebula')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rec-North America Nebula')));
    await tester.pumpAndSettle();
    expect(find.text('Höhe heute Nacht'), findsOneWidget);
    expect(find.byKey(const Key('rec-Pacman Nebula')), findsNothing);
    expect(find.byKey(const Key('plan-detail')), findsNothing);
  });

  testWidgets('telescope on a tablet on its side: live overview beside the controls', (tester) async {
    size(tester, tabletLandscape);
    await tester.pumpWidget(app(FakeServer()));
    await tester.pumpAndSettle();
    await openTab(tester, 'Teleskop');
    expect(find.text('Guiding RMS'), findsOneWidget); // the overview, on the left
    expect(find.byKey(const Key('rig-control')), findsOneWidget); // the controls, on the right
    final bar = tester.widget<ListView>(find.byKey(const Key('rig-device-bar')));
    expect(bar.scrollDirection, Axis.vertical); // the devices down the side
    expect(find.text('Übersicht'), findsNothing); // no segment for what is always shown

    // a phone: the overview first, the controls a segment away
    tester.view.physicalSize = phone * 2;
    await tester.pumpAndSettle();
    expect(find.text('Guiding RMS'), findsOneWidget);
    expect(find.byKey(const Key('rig-control')), findsNothing);
    await tester.tap(find.text('Steuern'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rig-control')), findsOneWidget);
    expect(tester.widget<ListView>(find.byKey(const Key('rig-device-bar'))).scrollDirection, Axis.horizontal);
  });

  testWidgets('telescope on an upright large tablet: one view at a time, devices at the side', (tester) async {
    size(tester, const Size(1032, 1376)); // iPad 13″ upright
    await tester.pumpWidget(app(FakeServer()));
    await tester.pumpAndSettle();
    await openTab(tester, 'Teleskop');
    expect(find.text('Übersicht'), findsOneWidget); // the overview is a view of its own again
    expect(find.text('Guiding RMS'), findsOneWidget);
    expect(find.byKey(const Key('rig-control')), findsNothing);
    await tester.tap(find.text('Steuern'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rig-control')), findsOneWidget);
    final bar = tester.widget<ListView>(find.byKey(const Key('rig-device-bar')));
    expect(bar.scrollDirection, Axis.vertical);
  });

  testWidgets('More on a wide screen keeps its text at a readable width', (tester) async {
    size(tester, tabletLandscape);
    await tester.pumpWidget(app(FakeServer()));
    await tester.pumpAndSettle();
    await openTab(tester, 'Mehr');
    final card = tester.getRect(find.byType(Card).first);
    expect(card.width, lessThanOrEqualTo(720));
    expect(card.width, greaterThan(600));
  });

  for (final (logical, sideBySide) in [(phone, false), (tabletLandscape, true), (const Size(800, 400), true)]) {
    testWidgets('framing at ${logical.width.round()}×${logical.height.round()}: '
        '${sideBySide ? 'picture beside the controls' : 'controls below the picture'}', (tester) async {
      size(tester, logical);
      final server = FakeServer();
      await tester.pumpWidget(
        MaterialApp(
          home: FramingScreen(
            client: BortleClient(baseUrl: 'https://bortle.eu', token: FakeServer.token, http_: server.client),
            target: 'NGC 7000',
            raDeg: 314.75,
            decDeg: 44.33,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('framing')), findsOneWidget);
      final picture = tester.getRect(find.byKey(const Key('framing-picture')));
      final rotation = tester.getRect(find.byKey(const Key('framing-rotation')));
      if (sideBySide) {
        expect(rotation.left, greaterThan(picture.right)); // beside it
      } else {
        expect(rotation.top, greaterThan(picture.bottom)); // below it
      }
    });
  }
}
