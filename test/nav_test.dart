// The sky map's "Einrahmen" leads into the framing, from the Plan tab's button.

import 'package:bortle_app/api/bortle_client.dart';
import 'package:bortle_app/framing/framing_screen.dart';
import 'package:bortle_app/main.dart' show planNightOffset;
import 'package:bortle_app/nav/sky_and_framing.dart';
import 'package:bortle_app/sky/sky_map_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_server.dart';

void main() {
  testWidgets('the sky map button opens the sky map, and its Einrahmen the framing', (tester) async {
    final server = FakeServer();
    final client = BortleClient(baseUrl: 'https://bortle.eu', token: FakeServer.token, http_: server.client);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(appBar: AppBar(actions: [skyMapButton(context, client)])),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-sky-map')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final sky = tester.widget<SkyMapScreen>(find.byType(SkyMapScreen));
    expect(sky.onFrame, isNotNull);
    sky.onFrame!('M 31', 10.68, 41.27);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(FramingScreen), findsOneWidget);
    expect(tester.widget<FramingScreen>(find.byType(FramingScreen)).target, 'M 31');
  });

  test('a push for /plan?night= picks that night', () {
    final evening = DateTime(2026, 11, 13, 20);
    final morning = DateTime(2026, 11, 14, 7);
    expect(planNightOffset('2026-11-13', evening), 0);
    expect(planNightOffset('2026-11-14', evening), 1);
    expect(planNightOffset('2026-11-15', evening), 2);
    expect(planNightOffset('2026-11-20', evening), 2);
    expect(planNightOffset('2026-11-13', morning), 0); // still last night
    expect(planNightOffset('2026-11-14', morning), 1);
    expect(planNightOffset(null, evening), 0);
    expect(planNightOffset('kaputt', evening), 0);
  });
}
