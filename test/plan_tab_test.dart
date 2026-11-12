// The Plan tab's recommendations: a night to choose, cards that tell targets apart, the
// catalogue search as you type, and an honest answer when the sky is clouded out.
//
// With PLAN_SHOTS=<dir> the tests also write PNGs of what they show, in the real fonts.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:bortle_app/api/bortle_client.dart';
import 'package:bortle_app/api/session_store.dart';
import 'package:bortle_app/main.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_server.dart';

final _shots = Platform.environment['PLAN_SHOTS'];
final _boundary = GlobalKey();

Widget app(FakeServer server) => RepaintBoundary(
  key: _boundary,
  child: BortleApp(
    store: MemorySessionStore()..session = const StoredSession('https://bortle.eu', FakeServer.token),
    clientFor: (url, token) => BortleClient(baseUrl: url, token: token, http_: server.client),
  ),
);

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340); // a 6.4" Android phone
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/sdks/flutter';
  final material = '$root/bin/cache/artifacts/material_fonts';
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await loader.load();
  }

  final roboto = [
    for (final w in ['Regular', 'Medium', 'Bold']) '$material/Roboto-$w.ttf',
  ];
  await family('Roboto', roboto);
  await family('FlutterTest', roboto);
  await family('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
  await family('SpaceGrotesk', ['assets/fonts/SpaceGrotesk.ttf']);
}

Future<void> shot(WidgetTester tester, String name) async {
  if (_shots == null) return;
  final render = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 3);
    return (await image.toByteData(format: ui.ImageByteFormat.png))!;
  });
  Directory(_shots!).createSync(recursive: true);
  File('$_shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

Future<FakeServer> openPlan(WidgetTester tester, {bool clouded = false}) async {
  phone(tester);
  if (_shots != null) await _loadFonts();
  final server = FakeServer()..cloudedTonight = clouded;
  await tester.pumpWidget(app(server));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Planen')));
  await tester.pumpAndSettle();
  return server;
}

String _day(int ahead) {
  final d = DateTime.now().add(Duration(days: ahead));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

void main() {
  testWidgets('each recommendation says what sets it apart', (tester) async {
    final server = await openPlan(tester);
    await shot(tester, '01-plan-tonight');

    // the window in local time and its length, not one sentence for every target
    final window = tester.widget<Text>(find.byKey(const Key('rec-window-Pacman Nebula'))).data!;
    expect(window, contains('11,0 h'));
    expect(window, matches(RegExp(r'^\d\d:\d\d–\d\d:\d\d')));
    expect(find.textContaining('Luftmasse 1,07'), findsOneWidget);
    expect(find.text('Bildfeld: passt gut'), findsOneWidget);
    expect(find.text('Bildfeld: größer als das Feld – Mosaik'), findsOneWidget);
    expect(find.byKey(const Key('rec-collected-North America Nebula')), findsOneWidget);
    expect(find.byKey(const Key('rec-collected-Pacman Nebula')), findsNothing);
    expect(find.byKey(const Key('rec-favorite')), findsOneWidget);
    // the rank as a bar, its length the score
    final bar = tester.widget<LinearProgressIndicator>(find.byKey(const Key('rec-score-Pacman Nebula')));
    expect(bar.value, closeTo(.946, 1e-6));
    // a sky picture per target, at its own position, small
    final thumbs = server.requests.where((r) => r.url.path == '/api/bortle/plan/preview/image').toList();
    expect(thumbs.map((r) => r.url.queryParameters['ra']), containsAll(['314.7500', '13.2000']));
    expect(thumbs.every((r) => r.url.queryParameters['width_px'] == '240'), isTrue);
    expect(find.byKey(const Key('rec-thumb-Pacman Nebula')), findsOneWidget);
  });

  testWidgets('tomorrow and the day after are a tap away, with the forecast caveat', (tester) async {
    final server = await openPlan(tester);
    expect(server.recommendDates, [null]); // tonight asks without a date
    expect(find.byKey(const Key('forecast-hint')), findsNothing);

    await tester.tap(find.byKey(const Key('night-1')));
    await tester.pumpAndSettle();
    expect(server.recommendDates.last, _day(1));
    expect(find.byKey(const Key('forecast-hint')), findsOneWidget);
    await shot(tester, '02-plan-tomorrow');

    await tester.tap(find.byKey(const Key('night-2')));
    await tester.pumpAndSettle();
    expect(server.recommendDates.last, _day(2));
  });

  testWidgets('a clouded-out night says so and offers the next one', (tester) async {
    final server = await openPlan(tester, clouded: true);
    expect(find.text('Rest der Nacht bewölkt'), findsOneWidget);
    expect(find.byKey(const Key('rec-blocked-Pacman Nebula')), findsOneWidget);
    expect(find.textContaining('bewölkt – sonst 11,0 h dunkel'), findsOneWidget);
    await shot(tester, '03-plan-clouded');

    await tester.tap(find.byKey(const Key('next-night')));
    await tester.pumpAndSettle();
    expect(server.recommendDates.last, _day(1));
    expect(find.byKey(const Key('nothing-usable')), findsNothing);
    expect(find.byKey(const Key('rec-window-Pacman Nebula')), findsOneWidget);
  });

  testWidgets('the search suggests from the catalogue as you type, German names too', (tester) async {
    final server = await openPlan(tester);
    await tester.enterText(find.byKey(const Key('object')), 'herz');
    await tester.pump(const Duration(milliseconds: 100));
    // still typing: nothing asked yet
    expect(server.requests.where((r) => r.url.path == '/api/bortle/plan/search'), isEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(server.requests.where((r) => r.url.path == '/api/bortle/plan/search'), hasLength(1));

    final hit = find.byKey(const Key('hit-IC 1805'));
    expect(hit, findsOneWidget);
    expect(find.text('Heart Nebula'), findsOneWidget);
    expect(find.textContaining('IC 1805 · Herznebel · Sh2-190 · HII region · 150′'), findsOneWidget);
    await shot(tester, '04-plan-search');

    await tester.tap(hit);
    await tester.pumpAndSettle();
    final planned = server.requests.lastWhere((r) => r.url.path == '/api/bortle/plan');
    expect(planned.url.queryParameters['object'], 'IC 1805'); // the designation NINA reads
  });
}
