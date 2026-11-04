// Store screenshots of the real app against bortle.eu, signed in as the review account
// (Ben, 2026-11-04): Codemagic runs this in an iPhone simulator and an Android emulator
// (codemagic.yaml, store-screenshots); test_driver/screenshots.dart keeps each picture as
// build/screenshots/<store>_<locale>_<NN-name>.png, and the allskyhub hub takes them over
// ("Screenshots übernehmen") for the App Store and Google Play.
//
// The review account's name and password come from Codemagic's secure variables, never
// from this repository:
//
//   flutter drive --driver=test_driver/screenshots.dart \
//     --target=integration_test/store_screenshots_test.dart -d <device> \
//     --dart-define=SHOT_STORE=appstore \
//     --dart-define=SHOT_LOGIN=... --dart-define=SHOT_PASSWORD=...
//
// The account is the one tools/seed_review_account.py (Bortle repository) keeps: a site,
// four finished images and a recorded night, so every tab shows something real.

import 'dart:io';

import 'package:bortle_app/api/bortle_client.dart';
import 'package:bortle_app/api/session_store.dart';
import 'package:bortle_app/l10n.dart';
import 'package:bortle_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const store = String.fromEnvironment('SHOT_STORE', defaultValue: 'appstore');
const login = String.fromEnvironment('SHOT_LOGIN');
const password = String.fromEnvironment('SHOT_PASSWORD');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Pumps for a while: the data and pictures come over the network, and a spinner never
  /// lets pumpAndSettle settle.
  Future<void> wait(WidgetTester tester, [int seconds = 5]) async {
    for (var i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tab(WidgetTester tester, String de, String en) async {
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(tr(de, en))));
    await wait(tester);
  }

  for (final (locale, english) in const [('de-DE', false), ('en-US', true)]) {
    testWidgets('store screenshots $locale', (tester) async {
      if (login.isEmpty || password.isEmpty) fail('SHOT_LOGIN and SHOT_PASSWORD are not set');
      appEnglish = english;
      Future<void> shot(String name) async {
        await wait(tester);
        await binding.takeScreenshot('${store}_${locale}_$name');
      }

      await tester.pumpWidget(
        BortleApp(
          store: MemorySessionStore(),
          clientFor: (url, token) => BortleClient(baseUrl: url, token: token),
        ),
      );
      if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
      // the login screen asks bortle.eu what it is before it shows the fields
      await wait(tester, 6);

      await tester.enterText(find.byKey(const Key('login')), login);
      await tester.enterText(find.byKey(const Key('password')), password);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.tap(find.byKey(const Key('sign-in')));
      await wait(tester, 10);
      await shot('01-tonight');

      await tab(tester, 'Planen', 'Plan');
      await shot('02-plan');
      await tester.enterText(find.byKey(const Key('object')), 'M31');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      FocusManager.instance.primaryFocus?.unfocus();
      await wait(tester, 8);
      await shot('03-object');

      await tab(tester, 'Teleskop', 'Telescope');
      await wait(tester, 5);
      await shot('04-telescope');

      await tab(tester, 'Galerie', 'Gallery');
      await shot('05-gallery');
      await tester.tap(find.byType(InkWell).first);
      await wait(tester, 8);
      await shot('06-image');
      await tester.pageBack();
      await wait(tester, 2);

      // sign this device out again: every run would otherwise leave one on the account
      await tab(tester, 'Mehr', 'More');
      await tester.ensureVisible(find.byKey(const Key('sign-out')));
      await tester.tap(find.byKey(const Key('sign-out')));
      await wait(tester, 3);
    });
  }
}
