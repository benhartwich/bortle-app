// Store screenshots, rendered from the real app against a scripted cockpit with real fonts.
// Skipped unless asked for:
//
//   SCREENSHOT_IMAGES=<dir with images.json + jpgs> SCREENSHOT_OUT=store \
//     flutter test test/screenshots_test.dart
//
// They land where the store listings read them (see _devices): Google Play's phone, 7″ and 10″
// tablet slots under store/play/<language>/, the App Store's 6.9″ iPhone and 13″ iPad slots
// under store/appstore/screenshots/<language>/. At most eight per device, as Play takes.
// SCREENSHOT_DEVICES=tablet7,tablet10,ipad renders only those and leaves the others alone.
//
// images.json lists the finished pictures the gallery shows
// ([{title, title_en, recipe, file, hours}]).
// They are the maintainer's own images and stay out of the repository; the screenshots made
// from them are what goes in.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bortle_app/api/bortle_client.dart';
import 'package:bortle_app/api/session_store.dart';
import 'package:bortle_app/l10n.dart';
import 'package:bortle_app/main.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _images = Platform.environment['SCREENSHOT_IMAGES'];
final _out = Platform.environment['SCREENSHOT_OUT'];

/// One store slot: the logical size the app lays itself out for, the pixel ratio that turns
/// it into the store's size, and the folder under store/ ({lang} is the store's language).
typedef _Device = ({Size size, double ratio, String folder, bool tablet});

/// Play: 24-bit PNG, each side 320–3840 px, the long side at most twice the short one; for
/// tablets and large screens 16:9 and at least 1080 px a side. App Store: the 6.9″ iPhone
/// and 13″ iPad sizes, which every smaller device is scaled down from.
const _devices = <String, _Device>{
  // phones, upright: 1080×2400 and 1320×2868
  'android': (size: Size(360, 800), ratio: 3, folder: 'play/{lang}/screenshots', tablet: false),
  'ios': (size: Size(440, 956), ratio: 3, folder: 'appstore/screenshots/{lang}', tablet: false),
  // tablets on their side, list and detail side by side (≥ 840 dp): 1920×1080 and 2560×1440
  'tablet7': (size: Size(960, 540), ratio: 2, folder: 'play/{lang}/tablet7', tablet: true),
  'tablet10': (size: Size(1280, 720), ratio: 2, folder: 'play/{lang}/tablet10', tablet: true),
  // 13″ iPad upright, 2064×2752: wide enough for two panes as well
  'ipad': (size: Size(1032, 1376), ratio: 2, folder: 'appstore/screenshots/{lang}/ipad', tablet: true),
};
const _languages = {'de-DE': false, 'en-US': true}; // the store's language → appEnglish

/// The devices asked for (SCREENSHOT_DEVICES, comma separated), all without it.
final _only = Platform.environment['SCREENSHOT_DEVICES']?.split(',').map((d) => d.trim()).toSet();

String _title(Map<String, dynamic> picture) =>
    (appEnglish ? picture['title_en'] as String? : null) ?? picture['title'] as String;

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

/// [rgba] as a PNG without an alpha channel: both stores refuse screenshots with one. The
/// app paints an opaque sky behind everything, so nothing is lost.
Uint8List _opaquePng(ByteData rgba, int width, int height) {
  final rows = BytesBuilder(copy: false);
  final pixels = rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
  for (var y = 0; y < height; y++) {
    final line = Uint8List(1 + width * 3); // filter byte 0, then RGB
    for (var x = 0; x < width; x++) {
      final o = (y * width + x) * 4;
      line[1 + x * 3] = pixels[o];
      line[2 + x * 3] = pixels[o + 1];
      line[3 + x * 3] = pixels[o + 2];
    }
    rows.add(line);
  }
  final png = BytesBuilder(copy: false)..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final body = Uint8List.fromList([...type.codeUnits, ...data]);
    png
      ..add(_u32(data.length))
      ..add(body)
      ..add(_u32(_crc32(body)));
  }

  chunk('IHDR', [..._u32(width), ..._u32(height), 8, 2, 0, 0, 0]); // 8 bit, truecolour
  chunk('IDAT', ZLibCodec(level: 6).encode(rows.takeBytes()));
  chunk('IEND', const []);
  return png.takeBytes();
}

Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);

final _crcTable = [
  for (var n = 0; n < 256; n++)
    () {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = c & 1 != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
      }
      return c;
    }(),
];

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >>> 8);
  }
  return c ^ 0xFFFFFFFF;
}

/// A cockpit in the middle of a good night. A [tablet] has the room to show the object's
/// sky picture above its plan; the phone shots leave it out, as they always have.
MockClient _showcase(List<Map<String, dynamic>> pictures, String dir, {bool tablet = false}) {
  final m101 = tr('M101 · Feuerradgalaxie', 'M101 · Pinwheel Galaxy');
  // Tonight at 23:40: a store picture of a night should not read 09:00.
  final today = DateTime.now();
  final now = DateTime(today.year, today.month, today.day, 23, 40).toUtc();
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
    {
      'type': 'autofocus',
      'severity': 'info',
      'timestamp': ago(41),
      'message': tr('Fokus 11 820 · Kurve gültig', 'Focus 11,820 · curve valid'),
    },
    {
      'type': 'plate_solved',
      'severity': 'info',
      'timestamp': ago(44),
      'message': tr('NGC 7000 · 0,4′ neben der Mitte', 'NGC 7000 · 0.4′ off centre'),
    },
    {
      'type': 'meridian_flip',
      'severity': 'info',
      'timestamp': ago(46),
      'message': tr('NINA: Flip auf West', 'NINA: flipped to west'),
    },
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
      'reason': tr(
        'Eine der drei Nächte weicht ab: Bortle fragt, bevor es kombiniert.',
        'One of the three nights stands out: Bortle asks before combining them.',
      ),
      'findings': [
        tr('Nacht 2: Gradient 4,1 % (die anderen 1,2 %)', 'Night 2: gradient 4.1 % (the others 1.2 %)'),
        tr('43 von 455 Frames verworfen (Wolken)', '43 of 455 frames rejected (clouds)'),
        tr('FWHM gleichmäßig 2,9″', 'FWHM even at 2.9″'),
      ],
      'details': {},
      'since': ago(12),
    },
    'history': [],
    'runs': ['IC_1318_RGBHSO'],
    'created_at': ago(90),
    'updated_at': ago(12),
  };
  // A clear night for NGC 7000: the real planner answer, with tonight's window and clouds
  // as a good night has them.
  final plan = jsonDecode(File('test/fixtures/plan_ngc7000.json').readAsStringSync()) as Map<String, dynamic>;
  final nightStart = DateTime.parse(plan['night_start'] as String);
  plan['window_start'] = nightStart.toIso8601String();
  plan['window_end'] = nightStart.add(const Duration(hours: 6, minutes: 40)).toIso8601String();
  plan['window_hours'] = 6.7;
  plan['moon_illumination'] = 0.18;
  plan['warnings'] = <String>[];
  for (final p in plan['points'] as List) {
    (p as Map)['cloud_cover'] = 0.08;
  }
  final start = now.subtract(const Duration(hours: 3));
  final frames = [
    for (var i = 0; i < 46; i++)
      {
        'index': i,
        'time': start.add(Duration(minutes: i * 4)).toIso8601String(),
        'exposure_s': 240,
        'filter': 'L-eXtreme',
        'hfr': i == 17 ? 3.9 : 2.3 + 0.12 * ((i * 7) % 5) / 4 + (i > 24 ? -0.15 : 0),
        'stars': i == 17 ? 610 : 1180 + (i * 37) % 160,
        'rms_arcsec': 0.52 + ((i * 11) % 7) / 40,
        'temperature': -10.0,
        'focus_position': i > 24 ? 11790 : 11820,
        'type': 'LIGHT',
        'is_bad': i == 17,
      },
  ];
  final live = {
    'devices': {
      for (final d in ['camera', 'mount', 'focuser', 'filterwheel', 'guider'])
        d: {'connected': true, 'reachable': true},
    },
    'guiding': {
      'reachable': true,
      'active': true,
      'rms_ra_arcsec': 0.41,
      'rms_dec_arcsec': 0.46,
      'rms_total_arcsec': 0.62,
    },
    'sequence': {'reachable': true, 'running': true, 'current': 'NGC 7000 > Imaging > Smart Exposure'},
    'frames': {
      'reachable': true,
      'recent': [frames.last],
      'progress': {'lights': 46, 'usable': 45, 'rejected': 1, 'usable_minutes': 180.0},
    },
  };
  // Tonight's recommendations, ranked the way the planner ranks them, on the night of the plan.
  final nightEnd = DateTime.parse(plan['night_end'] as String);
  String at(DateTime t) => t.toIso8601String();
  Map<String, Object?> target(
    String name,
    double ra,
    double dec, {
    required double score,
    required DateTime from,
    required DateTime to,
    required double maxAlt,
    required double meanAlt,
    required double airmass,
    required String verdict,
    required String filter,
    required int exposure,
    bool favorite = false,
    double already = 0,
  }) => {
    'name': name,
    'ids': [name],
    'type': 'nebula',
    'ra_deg': ra,
    'dec_deg': dec,
    'score': score,
    'visible_hours': to.difference(from).inMinutes / 60,
    'max_altitude_deg': maxAlt,
    'mean_altitude_deg': meanAlt,
    'airmass': airmass,
    'window_start': at(from),
    'window_end': at(to),
    'mean_cloud': 0.08,
    'fov_verdict': verdict,
    'recommended_filter': filter,
    'recommended_exposure_s': exposure,
    'favorite': favorite,
    'already_hours': already,
    'status': already > 0 ? 'started' : 'new',
    'dark_hours_above_horizon': to.difference(from).inMinutes / 60,
    'reasons': <String>[],
  };
  final windowEnd = DateTime.parse(plan['window_end'] as String);
  final recommended = {
    'site': plan['site'],
    'night': {'start': at(nightStart), 'end': at(nightEnd), 'hours': 10.2, 'clouded_out': false},
    'fov_arcmin': {'width': 100.4, 'height': 67.1},
    'clouds_available': true,
    'recommendations': [
      target(
        'NGC 7000',
        314.75,
        44.33,
        score: 88,
        from: nightStart,
        to: windowEnd,
        maxAlt: 86,
        meanAlt: 62,
        airmass: 1.13,
        verdict: 'larger than the frame — mosaic',
        filter: 'L-eXtreme',
        exposure: 240,
        favorite: true,
        already: 1.9,
      ),
      target(
        'IC 1318',
        305.4,
        40.26,
        score: 81,
        from: nightStart,
        to: nightStart.add(const Duration(hours: 5, minutes: 50)),
        maxAlt: 82,
        meanAlt: 58,
        airmass: 1.18,
        verdict: 'fills the frame',
        filter: 'L-eXtreme',
        exposure: 300,
      ),
      target(
        'IC 1396',
        324.75,
        57.5,
        score: 77,
        from: nightStart,
        to: nightEnd,
        maxAlt: 79,
        meanAlt: 66,
        airmass: 1.09,
        verdict: 'larger than the frame — mosaic',
        filter: 'L-eXtreme',
        exposure: 300,
      ),
      target(
        'NGC 7023',
        315.4,
        68.17,
        score: 72,
        from: nightStart,
        to: nightEnd,
        maxAlt: 70,
        meanAlt: 55,
        airmass: 1.22,
        verdict: 'fits well',
        filter: 'L-Pro',
        exposure: 180,
        already: 2.6,
      ),
      target(
        'M31',
        10.68,
        41.27,
        score: 70,
        from: nightStart.add(const Duration(minutes: 50)),
        to: nightEnd,
        maxAlt: 83,
        meanAlt: 60,
        airmass: 1.15,
        verdict: 'fills the frame',
        filter: 'UV/IR-Cut',
        exposure: 180,
      ),
      target(
        'M45',
        56.75,
        24.12,
        score: 64,
        from: nightStart.add(const Duration(hours: 2, minutes: 30)),
        to: nightEnd,
        maxAlt: 66,
        meanAlt: 50,
        airmass: 1.3,
        verdict: 'fits well',
        filter: 'UV/IR-Cut',
        exposure: 120,
      ),
    ],
  };
  // NINA's own fields per device, for the rig's control pages beside the live frame.
  final rigFields = <String, Map<String, Object?>>{
    'camera': {
      'Temperature': -9.9,
      'TargetTemp': -10.0,
      'CoolerOn': true,
      'CoolerPower': 38.0,
      'Gain': 100,
      'GainMin': 0,
      'GainMax': 10000,
      'IsExposing': true,
    },
    'mount': {
      'AtPark': false,
      'Slewing': false,
      'TrackingEnabled': true,
      'TrackingMode': 'Sidereal',
      'Altitude': 71.4,
      'TimeToMeridianFlip': 2.6,
      'TimeToMeridianFlipString': '02:36:00',
      'SideOfPier': 'pierWest',
      'CanFindHome': true,
      'CanSlew': true,
      'RightAscension': 20.99,
      'Declination': 44.43,
      'SiteLatitude': 48.1,
      'SiteLongitude': 14.4,
    },
    'focuser': {'Position': 11790, 'IsMoving': false, 'Temperature': 3.4},
  };
  if (tablet) {
    live['devices'] = {
      for (final MapEntry(:key, :value) in live['devices']!.entries) key: {...value as Map, ...?rigFields[key]},
    };
  }
  Map<String, Object?>? finished(String name) {
    final p = pictures.where((p) => _title(p) == name).firstOrNull;
    if (p == null || name == m101) return null;
    return {
      'name': name,
      'title': name,
      'recipe': p['recipe'],
      'status': 'done',
      'total_steps': 10,
      'steps': [
        for (final op in [
          'autocrop',
          'remove_gradient',
          'color_calibrate',
          'deconvolve_or_sharpen',
          'deconvolve_or_sharpen',
          'stretch',
          'remove_stars',
          'denoise',
          'recombine',
          'finish',
        ])
          {'op': op, 'status': 'ok'},
      ],
      'final_previews': {'full': p['file']},
    };
  }

  return MockClient((request) async {
    final path = request.url.path;
    if (path == '/api/bortle/nina/live/frame') {
      return http.Response.bytes(File('$dir/${pictures[0]['file']}').readAsBytesSync(), 200);
    }
    http.Response json(Object body) =>
        http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    if (path.startsWith('/api/bortle/data/')) {
      return http.Response.bytes(File('$dir/${path.split('/').last}').readAsBytesSync(), 200);
    }
    // the sky around a target: a DSS2 cutout fetched once into the images folder
    if (path == '/api/bortle/plan/preview/image') {
      final q = request.url.queryParameters;
      final sky = File('$dir/dss_${q['ra']}_${q['dec']}.jpg');
      return sky.existsSync() ? http.Response.bytes(sky.readAsBytesSync(), 200) : http.Response('', 404);
    }
    return switch (path) {
      '/api/app/info' => json({'name': 'bortle', 'version': '2026.10', 'api': 1, 'auth': 'password'}),
      '/api/app/session' => json({
        'user': {'name': 'ben', 'admin': true},
      }),
      '/api/app/devices' => json({
        'devices': [
          {'id': 'a', 'label': 'Bortle App (Android)', 'createdAt': ago(3000), 'lastUsedAt': ago(1)},
          {'id': 'b', 'label': 'Bortle App (iOS)', 'createdAt': ago(9000), 'lastUsedAt': ago(800)},
        ],
      }),
      '/api/bortle/plan/suggest' => json([
        {'name': 'NGC7000', 'type': 'NGC', 'common': tr('Nordamerikanebel', 'North America Nebula')},
      ]),
      '/api/bortle/plan' => json(plan),
      '/api/bortle/plan/recommend' => json(recommended),
      '/api/bortle/plan/preview' when tablet => json({
        'object': 'NGC 7000',
        'common': tr('Nordamerikanebel', 'North America Nebula'),
        'ra_deg': 314.75,
        'dec_deg': 44.33,
        'epoch': 'J2000',
        'focal_mm': 800.0,
        'focal_ratio': 5.0,
        'fov_arcmin': [100.4, 67.1],
        'size_arcmin': 120.0,
        'fill': 1.79,
        'verdict': 'larger than the frame — mosaic',
        'position_angle_deg': 0.0,
        'image': {
          'path': '/plan/preview/image?ra=314.7500&dec=44.3300&width_deg=2.6773&height_deg=1.7893&survey=dss2',
          'width_deg': 2.6773,
          'height_deg': 1.7893,
          'survey': 'dss2',
          'credit': 'DSS2 / SDSS via CDS hips2fits',
        },
      }),
      '/api/bortle/nina/filters' => json({
        'connected': true,
        'moving': false,
        'current': {'id': 2, 'name': 'L-eXtreme'},
        'filters': [
          {'id': 0, 'name': 'UV/IR-Cut'},
          {'id': 1, 'name': 'L-Pro'},
          {'id': 2, 'name': 'L-eXtreme'},
        ],
      }),
      '/api/bortle/nina/cooling' => json({
        'setpoint_c': -10,
        'reason': tr('Darks auf der Platte bei -10 °C', 'darks on disk at -10 °C'),
        'warnings': <String>[],
      }),
      '/api/bortle/nina/devices' => json({
        'devices': [
          {'key': 'camera', 'label': tr('Kamera', 'Camera'), 'connected': true, 'driver_name': 'ATR2600C'},
          {'key': 'mount', 'label': tr('Montierung', 'Mount'), 'connected': true, 'driver_name': 'EQMOD'},
          {'key': 'focuser', 'label': tr('Fokussierer', 'Focuser'), 'connected': true, 'driver_name': 'Lacerta MFOC'},
          {'key': 'filterwheel', 'label': tr('Filterrad', 'Filter wheel'), 'connected': true},
          {'key': 'guider', 'label': 'Guider', 'connected': true, 'driver_name': 'MGEN-3'},
        ],
        'profile': {'id': 'p', 'name': 'Epsilon 160'},
      }),
      '/api/bortle/develop/level' => json({'level': 'guarded'}),
      '/api/bortle/nina/live' => json(live),
      '/api/bortle/nina/frames' => json({'count': frames.length, 'median_hfr': 2.38, 'frames': frames}),
      '/api/bortle/night' => json({'active_session_id': 'NGC 7000', 'frame_session_id': 'NGC 7000'}),
      '/api/bortle/events' => json(events),
      '/api/bortle/develop/pipelines' => json([pipeline]),
      '/api/bortle/develop/pipelines/p1' => json(pipeline),
      '/api/bortle/develop/runs' => json([
        {
          'name': m101,
          'recipe': 'galaxy',
          'status': 'running',
          'steps_done': 6,
          'total_steps': 10,
          'current_op': 'colour_calibrate',
          'eta_s': 840,
          'worker': 'GPU (A100)',
        },
        // M101 is the one computing; it is not in the list twice
        for (final p in pictures)
          if (_title(p) != m101) {'name': _title(p), 'recipe': p['recipe'], 'status': 'done'},
      ]),
      // a finished picture opened from the gallery: the steps its recipe ran
      _
          when path.startsWith('/api/bortle/develop/runs/') &&
              finished(Uri.decodeComponent(path.split('/').last)) != null =>
        json(finished(Uri.decodeComponent(path.split('/').last))!),
      _ when path.startsWith('/api/bortle/develop/runs/') => json({
        'name': m101,
        'title': m101,
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
            'name': _title(p),
            'title': _title(p),
            'session': _title(p),
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

  for (final MapEntry(key: device, value: d) in _devices.entries) {
    if (!(_only?.contains(device) ?? true)) continue;
    for (final MapEntry(key: language, value: english) in _languages.entries) {
      testWidgets('store screenshots: $device $language', (tester) async {
        appEnglish = english;
        addTearDown(() => appEnglish = false);
        await _loadFonts();
        final pictures = (jsonDecode(File('$_images/images.json').readAsStringSync()) as List)
            .cast<Map<String, dynamic>>();
        final server = _showcase(pictures, _images!, tablet: d.tablet);
        tester.view.physicalSize = d.size * d.ratio;
        tester.view.devicePixelRatio = d.ratio;
        addTearDown(tester.view.reset);

        // Only this device's own pictures go: the iPad's folder sits inside the iPhone's.
        final folder = Directory('$_out/${d.folder.replaceAll('{lang}', language)}')..createSync(recursive: true);
        for (final old in folder.listSync().whereType<File>().where((f) => f.path.endsWith('.png'))) {
          old.deleteSync();
        }
        final boundary = GlobalKey();
        var n = 0;
        Future<void> shot(String name) async {
          for (var i = 0; i < 4; i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
            await tester.pump(const Duration(milliseconds: 300));
          }
          final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final png = await tester.runAsync(() async {
            final image = await render.toImage(pixelRatio: d.ratio);
            final rgba = (await image.toByteData())!;
            return _opaquePng(rgba, image.width, image.height);
          });
          n++;
          File('${folder.path}/${n.toString().padLeft(2, '0')}-$name.png').writeAsBytesSync(png!);
        }

        Future<void> tab(String de, String en) async {
          final bar = find.byType(NavigationBar);
          final nav = bar.evaluate().isNotEmpty ? bar : find.byType(NavigationRail);
          await tester.tap(find.descendant(of: nav, matching: find.text(tr(de, en))));
          await tester.pumpAndSettle();
        }

        // Signed in at bortle.eu; Play takes at most eight, so the sign-in and "More" stay out.
        final store = MemorySessionStore()..session = const StoredSession('https://bortle.eu', 'bat_x');
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: BortleApp(
              store: store,
              clientFor: (url, token) => BortleClient(baseUrl: url, token: token, http_: server),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await shot('tonight');

        if (d.tablet) {
          await _tabletScenes(tester, tab, shot);
        } else {
          await _phoneScenes(tester, tab, shot);
        }
      }, skip: skip != null);
    }
  }
}

typedef _Tab = Future<void> Function(String de, String en);
typedef _Shot = Future<void> Function(String name);

Future<void> _phoneScenes(WidgetTester tester, _Tab tab, _Shot shot) async {
  await tab('Planen', 'Plan');
  await tester.enterText(find.byKey(const Key('object')), 'NGC 70');
  await tester.pump(const Duration(milliseconds: 300)); // the search waits for typing to pause
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('hit-NGC7000')));
  await tester.pumpAndSettle();
  await shot('plan');

  await tab('Teleskop', 'Telescope');
  await shot('telescope');
  await tester.tap(find.text(tr('Verlauf', 'History')));
  await tester.pumpAndSettle();
  await shot('history');
  await tester.tap(find.text(tr('Übersicht', 'Overview')));
  await tester.pumpAndSettle();

  await _approval(tester, tab, shot);

  await tab('Galerie', 'Gallery');
  await shot('gallery');

  await tester.tap(find.text(tr('Läufe', 'Runs')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(tr('M101 · Feuerradgalaxie', 'M101 · Pinwheel Galaxy')).first);
  await tester.pumpAndSettle();
  await shot('run');
  Navigator.of(tester.element(find.text(tr('Lauf', 'Run')))).pop();
  await tester.pumpAndSettle();

  await tab('Mehr', 'More');
  await tester.tap(find.byKey(const Key('red-light')));
  await tester.pumpAndSettle();
  await tab('Heute', 'Tonight');
  await shot('red-light');
}

/// List and detail side by side: every detail pane is chosen before it is taken.
Future<void> _tabletScenes(WidgetTester tester, _Tab tab, _Shot shot) async {
  await tab('Planen', 'Plan');
  await tester.tap(find.byKey(const Key('rec-NGC 7000')));
  await tester.pumpAndSettle();
  await shot('plan');

  // on its side: the live frame on the left, the camera controls on the right;
  // upright (the iPad) the telescope shows one view at a time, so the live overview
  await tab('Teleskop', 'Telescope');
  final camera = find.byKey(const Key('rig-camera'));
  if (camera.evaluate().isNotEmpty) {
    await tester.tap(camera);
    await tester.pumpAndSettle();
  }
  await shot('telescope');
  await tester.tap(find.text(tr('Verlauf', 'History')));
  await tester.pumpAndSettle();
  await shot('history');
  await tester.tap(find.text(tr('Steuern', 'Control')));
  await tester.pumpAndSettle();

  await _approval(tester, tab, shot);

  await tab('Galerie', 'Gallery');
  final m42 = find.text(tr('M42 · Orionnebel', 'M42 · Orion Nebula'));
  await tester.ensureVisible(m42);
  await tester.pumpAndSettle();
  await tester.tap(m42);
  await tester.pumpAndSettle();
  // back to the top of the grid, with the picture chosen
  final grid = find.descendant(of: find.byType(GridView), matching: find.byType(Scrollable));
  tester.state<ScrollableState>(grid).position.jumpTo(0);
  await tester.pumpAndSettle();
  await shot('gallery');

  await tester.tap(find.text(tr('Läufe', 'Runs')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(tr('M101 · Feuerradgalaxie', 'M101 · Pinwheel Galaxy')).first);
  await tester.pumpAndSettle();
  await shot('run');

  await tab('Mehr', 'More');
  await tester.tap(find.byKey(const Key('red-light')));
  await tester.pumpAndSettle();
  await tab('Teleskop', 'Telescope');
  await shot('red-light');
}

Future<void> _approval(WidgetTester tester, _Tab tab, _Shot shot) async {
  await tab('Heute', 'Tonight');
  await tester.tap(find.textContaining(tr('Wartet auf dich', 'Waiting for you')));
  await tester.pumpAndSettle();
  await shot('approval');
  Navigator.of(tester.element(find.text(tr('Freigabe', 'Approval')))).pop();
  await tester.pumpAndSettle();
}
