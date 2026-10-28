// Store screenshots, rendered from the real app against a scripted cockpit with real fonts.
// Skipped unless asked for:
//
//   SCREENSHOT_IMAGES=<dir with images.json + jpgs> SCREENSHOT_OUT=store/screenshots \
//     flutter test test/screenshots_test.dart
//
// images.json lists the finished pictures the gallery shows ([{title, recipe, file, hours}]).
// They are the maintainer's own images and stay out of the repository; the screenshots made
// from them are what goes in.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bortle_app/api/bortle_client.dart';
import 'package:bortle_app/api/session_store.dart';
import 'package:bortle_app/l10n.dart';
import 'package:bortle_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _images = Platform.environment['SCREENSHOT_IMAGES'];
final _out = Platform.environment['SCREENSHOT_OUT'];

/// Store sizes: Play phone 1080×2400, App Store 6.9" 1320×2868.
const _devices = {'android': Size(360, 800), 'ios': Size(440, 956)};

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/sdks/flutter';
  final material = '$root/bin/cache/artifacts/material_fonts';
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  final roboto = [
    for (final w in ['Regular', 'Medium', 'Bold']) '$material/Roboto-$w.ttf',
  ];
  await family('Roboto', roboto);
  // Text without a family falls back to the test font (boxes); on a phone it is the
  // platform's own, so Roboto stands in for it here.
  await family('FlutterTest', roboto);
  await family('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
  await family('SpaceGrotesk', ['assets/fonts/SpaceGrotesk.ttf']);
}

/// A cockpit in the middle of a good night.
MockClient _showcase(List<Map<String, dynamic>> pictures, String dir) {
  final now = DateTime.now().toUtc();
  String ago(int minutes) => now.subtract(Duration(minutes: minutes)).toIso8601String();
  final events = <Map<String, Object?>>[
    for (var i = 0; i < 6; i++)
      {
        'type': 'frame_accepted',
        'severity': 'info',
        'timestamp': ago(2 + i * 4),
        'message': 'QC accept: NGC7000_Ha_${(42 - i).toString().padLeft(4, '0')}.fits — all checks within thresholds',
      },
    {
      'type': 'frame_borderline',
      'severity': 'warning',
      'timestamp': ago(27),
      'message': 'QC borderline: NGC7000_Ha_0036.fits — star count −38 % (thin cloud)',
    },
    {'type': 'autofocus', 'severity': 'info', 'timestamp': ago(41), 'message': 'Fokus 11 820 · Kurve gültig'},
    {'type': 'plate_solved', 'severity': 'info', 'timestamp': ago(44), 'message': 'NGC 7000 · 0,4′ neben der Mitte'},
    {'type': 'meridian_flip', 'severity': 'info', 'timestamp': ago(46), 'message': 'NINA: Flip auf West'},
  ].reversed.toList();
  final pipeline = {
    'id': 'p1',
    'source': 'nina',
    'subject': 'IC 1318 · Gamma Cygni',
    'owner': 'ben',
    'level': 'guarded',
    'state': 'waiting',
    'hold': {
      'point': 'stacking',
      'reason': 'Eine der drei Nächte weicht ab: Bortle fragt, bevor es kombiniert.',
      'findings': [
        'Nacht 2: Gradient 4,1 % (die anderen 1,2 %)',
        '43 von 455 Frames verworfen (Wolken)',
        'FWHM gleichmäßig 2,9″',
      ],
      'details': {},
      'since': ago(12),
    },
    'history': [],
    'runs': ['IC_1318_RGBHSO'],
    'created_at': ago(90),
    'updated_at': ago(12),
  };
  return MockClient((request) async {
    final path = request.url.path;
    http.Response json(Object body) =>
        http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    if (path.startsWith('/api/bortle/data/')) {
      return http.Response.bytes(File('$dir/${path.split('/').last}').readAsBytesSync(), 200);
    }
    return switch (path) {
      '/api/app/info' => json({'name': 'bortle', 'version': '2026.10', 'api': 1, 'auth': 'password'}),
      '/api/app/session' => json({
        'user': {'name': 'ben', 'admin': false},
      }),
      '/api/app/devices' => json({
        'devices': [
          {'id': 'a', 'label': 'Bortle App (Android)', 'createdAt': ago(3000), 'lastUsedAt': ago(1)},
          {'id': 'b', 'label': 'Bortle App (iOS)', 'createdAt': ago(9000), 'lastUsedAt': ago(800)},
        ],
      }),
      '/api/bortle/night' => json({'active_session_id': 'NGC 7000', 'frame_session_id': 'NGC 7000'}),
      '/api/bortle/events' => json(events),
      '/api/bortle/develop/pipelines' => json([pipeline]),
      '/api/bortle/develop/pipelines/p1' => json(pipeline),
      '/api/bortle/develop/runs' => json([
        {
          'name': 'M101 · Feuerradgalaxie',
          'recipe': 'galaxy',
          'status': 'running',
          'steps_done': 6,
          'total_steps': 10,
          'current_op': 'colour_calibrate',
          'eta_s': 840,
          'worker': 'GPU (A100)',
        },
        for (final p in pictures) {'name': p['title'], 'recipe': p['recipe'], 'status': 'done'},
      ]),
      _ when path.startsWith('/api/bortle/develop/runs/') => json({
        'name': 'M101 · Feuerradgalaxie',
        'title': 'M101 · Feuerradgalaxie',
        'recipe': 'galaxy',
        'status': 'running',
        'total_steps': 10,
        'current_op': 'colour_calibrate',
        'worker': 'GPU (A100)',
        'steps': [
          for (final (op, st) in [
            ('calibrate', 'ok'),
            ('register', 'ok'),
            ('stack_per_session', 'ok'),
            ('gradient_per_session', 'ok'),
            ('combine', 'ok'),
            ('denoise', 'ok'),
            ('colour_calibrate', 'pending'),
            ('stretch', 'pending'),
            ('star_core_protect', 'pending'),
            ('finish', 'pending'),
          ])
            {'op': op, 'status': st},
        ],
        'final_previews': {'full': pictures[1]['file']},
      }),
      '/api/bortle/gallery' => json([
        for (final (i, p) in pictures.indexed)
          {
            'kind': 'developed',
            'name': p['title'],
            'title': p['title'],
            'session': p['title'],
            'recipe': p['recipe'],
            'modified': now.millisecondsSinceEpoch / 1000 - i * 86400,
            'previews': {'full': p['file']},
            'integration': {'total_hours': p['hours']},
          },
      ]),
      _ => http.Response('{}', 404),
    };
  });
}

void main() {
  final skip = _images == null || _out == null ? 'set SCREENSHOT_IMAGES and SCREENSHOT_OUT' : null;

  for (final MapEntry(key: platform, value: size) in _devices.entries) {
    testWidgets('store screenshots: $platform', (tester) async {
      appEnglish = false;
      await _loadFonts();
      final pictures = (jsonDecode(File('$_images/images.json').readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();
      final server = _showcase(pictures, _images!);
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final boundary = GlobalKey();
      var n = 0;
      Future<void> shot(String name) async {
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
          await tester.pump(const Duration(milliseconds: 300));
        }
        final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final bytes = await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 3);
          return (await image.toByteData(format: ui.ImageByteFormat.png))!;
        });
        n++;
        final file = File('$_out/$platform/${n.toString().padLeft(2, '0')}-$name.png')..createSync(recursive: true);
        file.writeAsBytesSync(bytes!.buffer.asUint8List());
      }

      Widget app(MemorySessionStore store) => RepaintBoundary(
        key: boundary,
        child: BortleApp(
          store: store,
          clientFor: (url, token) => BortleClient(baseUrl: url, token: token, http_: server),
        ),
      );

      // 1 the login, against bortle.eu
      await tester.pumpWidget(app(MemorySessionStore()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('login')), 'ben@sternwarte-nord.de');
      await tester.enterText(find.byKey(const Key('password')), 'geheim-genug');
      FocusManager.instance.primaryFocus?.unfocus();
      await shot('anmelden');

      // signed in from here on
      final store = MemorySessionStore()..session = const StoredSession('https://bortle.eu', 'bat_x');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(store));
      await tester.pumpAndSettle();
      await shot('heute');

      await tester.tap(find.textContaining('Wartet auf dich'));
      await tester.pumpAndSettle();
      await shot('freigabe');
      Navigator.of(tester.element(find.text('Freigabe'))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Galerie').last);
      await tester.pumpAndSettle();
      await shot('galerie');

      await tester.tap(find.text('Läufe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('M101 · Feuerradgalaxie').first);
      await tester.pumpAndSettle();
      await shot('entwicklung');
      Navigator.of(tester.element(find.text('Lauf'))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mehr').last);
      await tester.pumpAndSettle();
      await shot('mehr');
      await tester.tap(find.byKey(const Key('red-light')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Heute').last);
      await tester.pumpAndSettle();
      await shot('rotlicht');
    }, skip: skip != null);
  }
}
