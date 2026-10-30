// The tools without an account, as someone meets them on the login screen: a site from
// the phone, tonight's darkness and moon, an object's night, the optics' arithmetic and
// the weather – everything but the weather computed on the phone.

import 'dart:io';

import 'package:bortle_app/catalog.dart';
import 'package:bortle_app/design.dart';
import 'package:bortle_app/tools/tools_screen.dart';
import 'package:bortle_app/tools/tools_store.dart';
import 'package:bortle_app/tools/weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 2 November 2026, six in the evening (the test runs in UTC)
  final now = DateTime.utc(2026, 11, 2, 18);

  Future<MemoryToolsStore> open(WidgetTester tester, {FetchForecast? forecast, List<(double, double)>? asked}) async {
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryToolsStore();
    await tester.pumpWidget(
      MaterialApp(
        theme: bortleTheme(),
        home: ToolsScreen(
          store: store,
          locate: () async => const Site(48.2, 14.2),
          forecast:
              forecast ??
              (lat, lon) async {
                asked?.add((lat, lon));
                return Forecast(
                  [
                    for (var h = 17; h < 30; h++)
                      WeatherHour(
                        time: DateTime.utc(2026, 11, 2, h),
                        cloud: h < 23 ? 5 : 80,
                        seeing: 3,
                        transparency: 2,
                        temperature: 4,
                        dewPoint: 2.5,
                        wind: 6,
                      ),
                  ],
                  ['Open-Meteo', '7Timer!'],
                );
              },
          // the asset as the app ships it, read here without the engine's asset loader
          catalog: () async => Catalog.parse(File('assets/catalog.json').readAsStringSync()),
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('a site from the phone, and tonight from it', (tester) async {
    final store = await open(tester);
    expect(find.text('Standort des Telefons verwenden'), findsWidgets);
    await tester.tap(find.byKey(const Key('locate')));
    await tester.pumpAndSettle();
    expect(store.stored!.lat, 48.2);
    expect(find.text('48,2° N · 14,2° O'), findsOneWidget);

    // dark from about 17:29, the moon rises about 23:03 (Skyfield, test/astro_test.dart)
    expect(find.textContaining('Dunkel ohne Mond: 17:3'), findsOneWidget);
    expect(find.textContaining('38 % · '), findsOneWidget);
    await tester.tap(find.byKey(const Key('next-night')));
    await tester.pumpAndSettle();
    expect(find.text('Morgen Nacht'), findsOneWidget);
  });

  testWidgets('an object: found by name, its night, and how it fits the optics', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('locate')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Optik'));
    await tester.pumpAndSettle();
    // 530 mm with 3.76 µm pixels and 2.5″ seeing: 1.46″/px, well sampled
    expect(find.text('1,46″/px'), findsOneWidget);
    expect(find.textContaining('Gut abgetastet'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('focal')), '2000');
    await tester.pumpAndSettle();
    expect(find.textContaining('Überabgetastet'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('focal')), '530');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Objekte'));
    await tester.pumpAndSettle();
    expect(find.text('Am besten heute Nacht'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('object-search')), 'andromeda');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Andromeda Galaxy'));
    await tester.pumpAndSettle();
    expect(find.text('M 31 · NGC 224 · Galaxie'), findsOneWidget);
    expect(find.text('Höhe heute Nacht (°)'), findsOneWidget);
    // 190′ against a field of 2.4° × 1.6°: larger than the short side
    expect(find.textContaining('Größer als das Feld'), findsOneWidget);
  });

  testWidgets('the weather is asked for only when opened, with the place rounded', (tester) async {
    final asked = <(double, double)>[];
    await open(tester, asked: asked);
    await tester.tap(find.byKey(const Key('locate')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wetter'));
    await tester.pumpAndSettle();
    expect(asked, isEmpty);
    await tester.tap(find.byKey(const Key('load-weather')));
    await tester.pumpAndSettle();
    expect(asked, [(48.2, 14.2)]);
    expect(find.textContaining('dunklen Stunden klar'), findsOneWidget);
    expect(find.textContaining('Taugefahr'), findsWidgets);
    expect(find.textContaining('Seeing 0,75–1″'), findsWidgets);
  });
}
