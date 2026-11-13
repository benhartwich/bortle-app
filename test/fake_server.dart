// A scripted Bortle cockpit for the tests: the shapes are the real ones (see the Bortle
// repository's tests/test_app_login_e2e.py for the same calls against a live cockpit).

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeServer {
  FakeServer({
    this.localMode = false,
    this.admin = true,
    this.ninaUp = true,
    this.demo = false,
    this.hasSite = true,
    this.hasOptics = true,
    this.framingAngle,
  });

  /// Whether the account's profile has focal length and camera (the object preview's field).
  final bool hasOptics;

  /// The framing angle measured from solved frames, if any.
  final double? framingAngle;

  /// The app-review account: the rig's reads answer from a recording.
  final bool demo;

  /// Whether the account's profile has a site; planning answers 400 without one.
  bool hasSite;
  Map<String, Object?>? savedSite;

  final bool localMode;

  // --- Plan tab: recommendations per night and the catalogue search ---------------------

  /// Tonight's forecast covers every target (the night of 2026-11-12, 22:16).
  bool cloudedTonight = false;

  /// The `date` each recommendation request asked for (null: tonight).
  final recommendDates = <String?>[];

  Map<String, Object?> _recommendations(String? date) {
    recommendDates.add(date);
    final clouded = date == null && cloudedTonight;
    Map<String, Object?> target(
      String name, {
      required double score,
      required double hours,
      required String from,
      required String to,
      required double maxAlt,
      required double meanAlt,
      required double airmass,
      required String verdict,
      String filter = 'L-eXtreme',
      int exposure = 300,
      bool favorite = false,
      double already = 0,
      double ra = 314.75,
      double dec = 44.33,
    }) => {
      'name': name,
      'ids': [name],
      'type': 'emission_nebula',
      'ra_deg': ra,
      'dec_deg': dec,
      'score': clouded ? score / 10 : score,
      'visible_hours': clouded ? 0.0 : hours,
      'max_altitude_deg': maxAlt,
      'mean_altitude_deg': meanAlt,
      'airmass': airmass,
      'window_start': clouded ? null : from,
      'window_end': clouded ? null : to,
      'mean_cloud': clouded ? null : 0.05,
      'fov_fill': 0.4,
      'fov_verdict': verdict,
      'recommended_filter': filter,
      'recommended_exposure_s': exposure,
      'favorite': favorite,
      'already_hours': already,
      'status': already > 0 ? 'started' : 'new',
      'blocked_by': clouded ? 'clouds' : null,
      'dark_hours_above_horizon': hours,
      'reasons': ['culminates at ${maxAlt.round()}°'],
    };
    return {
      'night': {
        'start': '2026-11-14T17:20:00+00:00',
        'end': '2026-11-15T04:20:00+00:00',
        'hours': 11.0,
        'clouded_out': clouded,
      },
      'fov_arcmin': {'width': 100.4, 'height': 67.1},
      'clouds_available': true,
      'recommendations': [
        target(
          'North America Nebula',
          score: 81.4,
          hours: 5.2,
          from: '2026-11-14T17:20:00+00:00',
          to: '2026-11-14T22:30:00+00:00',
          maxAlt: 82,
          meanAlt: 61,
          airmass: 1.14,
          verdict: 'larger than the frame — mosaic',
          favorite: true,
          already: 2.5,
        ),
        target(
          'Pacman Nebula',
          score: 94.6,
          hours: 11.0,
          from: '2026-11-14T17:20:00+00:00',
          to: '2026-11-15T04:20:00+00:00',
          maxAlt: 81,
          meanAlt: 70,
          airmass: 1.07,
          verdict: 'fits well',
          filter: 'Antlia H Alpha & OIII',
          exposure: 180,
          ra: 13.2,
          dec: 56.6,
        ),
      ],
    };
  }

  Map<String, Object?> _search(String q) => {
    'query': q,
    'results': [
      if ('ngc 7000 north america nebula'.contains(q.toLowerCase().trim()))
        {
          'id': 'NGC7000',
          'plan_name': 'NGC 7000',
          'name': 'North America Nebula',
          'aliases': ['Nordamerikanebel', 'C 20'],
          'type': 'HII region',
          'catalog': 'NGC',
          'ra_deg': 314.75,
          'dec_deg': 44.33,
          'size_arcmin': 120.0,
        },
      if ('heart nebula herznebel ic 1805'.contains(q.toLowerCase().trim()))
        {
          'id': 'IC1805',
          'plan_name': 'IC 1805',
          'name': 'Heart Nebula',
          'aliases': ['Herznebel', 'Sh2-190'],
          'type': 'HII region',
          'catalog': 'IC',
          'ra_deg': 38.2,
          'dec_deg': 61.45,
          'size_arcmin': 150.0,
        },
    ],
  };

  /// The operator; anyone else gets the cockpit's 403 on the rig.
  final bool admin;

  /// Whether the instance's NINA answers.
  final bool ninaUp;
  final controls = <Map<String, Object?>>[];
  Map<String, Object?>? sentPlan;
  final requests = <http.Request>[];
  bool approved = false;
  bool cancelled = false;
  bool signedOut = false;
  final revoked = <String>[];
  Map<String, Object?>? pushRegistration;

  /// The last answer at the step hold p2, and the last redevelop asked for.
  Map<String, Object?>? stepAnswer;
  Map<String, Object?>? redevelopBody;
  Map<String, Object?>? nextcloudStart;
  bool pushDropped = false;
  bool accountDeleted = false;

  static const token = 'bat_test-token';

  bool _authed(http.Request r) => localMode || (!accountDeleted && r.headers['authorization'] == 'Bearer $token');

  late final client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    http.Response json(Object body, [int status = 200]) =>
        http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

    if (path == '/api/app/info') {
      return json({'name': 'bortle', 'version': '2026.10', 'api': 1, 'auth': localMode ? 'none' : 'password'});
    }
    if (path == '/api/app/login') {
      final body = jsonDecode(request.body) as Map;
      if (body['login'] == 'ben@example.org' && body['password'] == 'right') {
        return json({
          'token': token,
          'device': {'id': 'd1', 'label': body['device'], 'createdAt': '2026-10-28T08:00:00Z', 'lastUsedAt': null},
          'user': {'name': 'ben', 'admin': admin, 'demo': demo},
        });
      }
      return json({'error': 'Name/E-Mail oder Passwort falsch.'}, 401);
    }
    if (!_authed(request)) return json({'error': 'unauthorized'}, 401);

    switch ((request.method, path)) {
      case ('GET', '/api/app/session'):
        return json({
          'user': {'name': 'ben', 'admin': admin, 'demo': demo},
        });
      case ('POST', '/api/auth/delete-account'):
        if ((jsonDecode(request.body) as Map)['password'] != 'right') {
          return json({'error': 'Das Passwort stimmt nicht.'}, 403);
        }
        accountDeleted = true;
        return json({'ok': true, 'removed': <String, int>{}});
      case ('PUT', '/api/app/push-token'):
        pushRegistration = jsonDecode(request.body) as Map<String, Object?>;
        return json({'ok': true});
      case ('DELETE', '/api/app/push-token'):
        pushDropped = true;
        return json({'ok': true});
      case ('DELETE', '/api/app/session'):
        signedOut = true;
        return json({'ok': true});
      case ('GET', '/api/app/devices'):
        return json({
          'devices': [
            {
              'id': 'd1',
              'label': 'Bortle App (Android)',
              'createdAt': '2026-10-28T08:00:00Z',
              'lastUsedAt': '2026-10-28T09:00:00Z',
            },
          ],
        });
      case ('DELETE', '/api/app/devices'):
        revoked.add(request.url.queryParameters['id']!);
        return json({'ok': true});
      case ('GET', '/api/bortle/night'):
        return json({'active_session_id': 'nina-abc', 'frame_session_id': 'nina-abc'});
      case ('GET', '/api/bortle/events'):
        return json([
          {
            'type': 'frame',
            'severity': 'info',
            'timestamp': '2026-10-28T20:07:00Z',
            'session_id': 's',
            'message': 'Frame 38 angekommen',
          },
        ]);
      case ('GET', '/api/bortle/develop/pipelines'):
        return json(approved || cancelled ? [] : [_pipeline]);
      case ('GET', '/api/bortle/develop/pipelines/p1'):
        return json(_pipeline);
      case ('GET', '/api/bortle/develop/pipelines/p2'):
        return json(_stepPipeline);
      case ('POST', '/api/bortle/develop/pipelines/p2/approve'):
        stepAnswer = (jsonDecode(request.body) as Map).cast<String, Object?>();
        return json({'pipeline': 'p2', 'state': 'queued'});
      case ('GET', '/api/bortle/equipment/nextcloud/browse'):
        final at = request.url.queryParameters['path'] ?? '';
        return json(switch (at) {
          '' => {
            'ok': true,
            'path': '',
            'parent': null,
            'dirs': [
              {'name': 'Nebel', 'has_lights': false},
            ],
          },
          _ => {
            'ok': true,
            'path': at,
            'parent': '',
            'dirs': [
              {'name': 'NGC 7000', 'has_lights': true},
              {'name': 'Flats', 'has_lights': false},
            ],
          },
        });
      case ('POST', '/api/bortle/develop/from-nextcloud'):
        nextcloudStart = (jsonDecode(request.body) as Map).cast<String, Object?>();
        return json({'queued': true, 'mode': 'pipeline', 'state': 'running', 'pipeline': 'p3'});
      case ('GET', '/api/bortle/recipes'):
        return json(_recipes);
      case ('GET', '/api/bortle/recipes/docs'):
        return json(_docs);
      case ('GET', '/api/bortle/develop/runs/M33_galaxy'):
        return json(_m33);
      case ('POST', '/api/bortle/develop/runs/M33_galaxy/redevelop'):
        redevelopBody = (jsonDecode(request.body) as Map).cast<String, Object?>();
        return json({'queued': true, 'run': 'M33_galaxy~2'});
      case ('GET', '/api/bortle/develop/runs/M33_galaxy~2'):
        return json({..._m33, 'name': 'M33_galaxy~2', 'status': 'running'});
      case ('POST', '/api/bortle/develop/pipelines/p1/approve'):
        approved = true;
        return json({'pipeline': 'p1', 'state': 'queued'});
      case ('POST', '/api/bortle/develop/pipelines/p1/cancel'):
        cancelled = true;
        return json({'pipeline': 'p1', 'state': 'cancelled'});
      case ('GET', '/api/bortle/develop/runs'):
        return json([
          {
            'name': 'NGC7000_emission',
            'status': 'running',
            'steps_done': 4,
            'total_steps': 10,
            'current_op': 'gradient',
            'current_iterations': 1,
            'eta_s': 840,
            'modified': 1,
          },
          {
            'name': 'M33_galaxy',
            'recipe': 'galaxy',
            'status': 'done',
            'steps_done': 9,
            'total_steps': 9,
            'current_iterations': 0,
            'modified': 1,
          },
        ]);
      case ('GET', '/api/bortle/develop/runs/NGC7000_emission'):
        return json({
          'name': 'NGC7000_emission',
          'recipe': 'emission',
          'version': 3,
          'status': 'running',
          'input_path': '',
          'final_path': '',
          'total_steps': 3,
          'current_op': 'gradient',
          'steps': [
            {'op': 'calibrate', 'status': 'ok', 'iterations': []},
            {'op': 'gradient', 'status': 'pending', 'iterations': []},
          ],
          'final_previews': {},
        });
      case ('GET', '/api/bortle/gallery'):
        return json([
          {
            'kind': 'developed',
            'name': 'M33_galaxy',
            'title': 'M 33',
            'session': 'M33',
            'recipe': 'galaxy',
            'modified': 1761600000,
            'previews': {'full': 'develop/M33/previews/final_full.jpg'},
          },
        ]);
    }
    // the operator's rig, as proxy.ts guards it
    final recorded = demo && request.method == 'GET' && path.startsWith('/api/bortle/nina/');
    if ((path.startsWith('/api/bortle/nina/') || path == '/api/bortle/plan/nina') &&
        !admin &&
        !localMode &&
        !recorded) {
      return json({'detail': 'Das Teleskop dieser Instanz bedient nur der Betreiber.'}, 403);
    }
    final rig = _rig(request);
    if (rig != null) return rig;
    if (!hasSite && (path == '/api/bortle/plan' || path == '/api/bortle/plan/recommend')) {
      return json({'detail': 'Kein Standort: Breite/Länge im Equipment-Profil eintragen'}, 400);
    }
    switch ((request.method, path)) {
      case ('POST', '/api/equipment'):
        savedSite = (jsonDecode(request.body) as Map).cast<String, Object?>();
        hasSite = true;
        return json({'ok': true, 'profile': savedSite});
      case ('GET', '/api/bortle/plan/resolve'):
        return json({
          'object': 'NGC 7000',
          'common': 'North America Nebula',
          'type': 'HII',
          'ra_deg': 314.75,
          'dec_deg': 44.33,
          'epoch': 'J2000',
          'source': 'catalog',
        });
      // object preview: shaped like services/orchestrator/app.py plan_preview
      case ('GET', '/api/bortle/plan/preview'):
        return json({
          'object': 'NGC 7000',
          'common': 'North America Nebula',
          'ra_deg': 314.75,
          'dec_deg': 44.33,
          'epoch': 'J2000',
          'focal_mm': hasOptics ? 800.0 : null,
          'focal_ratio': hasOptics ? 5.0 : null,
          'telescope': hasOptics ? 'Takahashi Epsilon 160ED' : null,
          'camera': hasOptics ? 'ATR2600C' : null,
          'fov_arcmin': hasOptics ? [100.4, 67.1] : null,
          'size_arcmin': 120.0,
          'fill': hasOptics ? 1.79 : null,
          'verdict': hasOptics ? 'larger than the frame — mosaic' : 'unknown (optics incomplete)',
          'position_angle_deg': framingAngle,
          'image': {
            'path': '/plan/preview/image?ra=314.75&dec=44.33&width_deg=2.6773&height_deg=1.7893&survey=dss2',
            'width_deg': hasOptics ? 2.6773 : 6.0,
            'height_deg': hasOptics ? 1.7893 : 6.0,
            'survey': 'dss2',
            'credit': 'DSS2 / SDSS via CDS hips2fits (NASA SkyView when CDS is away)',
          },
        });
      case ('GET', '/api/bortle/plan/preview/image'):
        return http.Response.bytes(_png, 200, headers: {'content-type': 'image/png'});
      case ('GET', '/api/bortle/plan/suggest'):
        return http.Response(fixture('suggest_ngc7.json'), 200, headers: {'content-type': 'application/json'});
      case ('GET', '/api/bortle/plan'):
        return http.Response(fixture('plan_ngc7000.json'), 200, headers: {'content-type': 'application/json'});
      case ('GET', '/api/bortle/plan/recommend'):
        return json(_recommendations(request.url.queryParameters['date']));
      case ('GET', '/api/bortle/plan/search'):
        return json(_search(request.url.queryParameters['q'] ?? ''));
      case ('GET', '/api/bortle/develop/level'):
        return json({'level': 'guarded', 'step_holds': false, 'stored': true});
      case ('POST', '/api/bortle/plan/nina'):
        sentPlan = (jsonDecode(request.body) as Map).cast<String, Object?>();
        return json({'loaded': true});
      case ('GET', '/api/bortle/nina/live'):
        return ninaUp
            ? json(mountParked ? _parkedSnapshot() : liveSnapshot)
            : http.Response(fixture('live_unreachable.json'), 200, headers: {'content-type': 'application/json'});
      case ('GET', '/api/bortle/nina/frames'):
        return json({
          'count': 3,
          'median_hfr': 2.4,
          'bad_factor': 1.5,
          'frames': [
            for (final (i, hfr) in [2.4, 2.3, 4.1].indexed)
              {
                'index': i,
                'time': '2026-10-28T20:${(10 + i * 3).toString()}:00Z',
                'exposure_s': 120,
                'filter': 'L-eXtreme',
                'hfr': hfr,
                'stars': 1200 - i * 100,
                'rms_arcsec': 0.6,
                'temperature': -10.0,
                'focus_position': 11820,
                'type': 'LIGHT',
                'is_bad': hfr > 3.6,
              },
          ],
        });
      case ('GET', '/api/bortle/nina/live/frame'):
        return http.Response.bytes(_png, 200, headers: {'content-type': 'image/png'});
      case ('POST', '/api/bortle/nina/control'):
        controls.add((jsonDecode(request.body) as Map).cast<String, Object?>());
        return json({'ok': true});
    }
    if (path.startsWith('/api/bortle/data/')) return http.Response('', 404);
    return json({'error': 'not found'}, 404);
  });

  static final _stepPipeline = {
    'id': 'p2',
    'source': 'upload',
    'subject': 'M 33',
    'owner': 'ben',
    'level': 'stepwise',
    'step_holds': true,
    'state': 'waiting',
    'hold': {
      'point': 'steps',
      'reason': 'stepwise, holding after every step',
      'findings': [],
      'details': {
        'key': 'M33_galaxy:stretch',
        'run': 'M33_galaxy',
        'recipe': 'galaxy',
        'step': 'stretch',
        'status': 'ok',
        'next': 'finish',
        'params': {'target_background': 0.2, 'linked': true},
        'failed_expectations': [],
        'previews': [
          'develop/M33_galaxy/02_stretch/iter1/previews/result_center.jpg',
          'develop/M33_galaxy/02_stretch/iter1/previews/result_full.jpg',
        ],
      },
      'since': '2026-10-28T21:40:00Z',
    },
    'history': [],
    'runs': ['M33_galaxy'],
  };

  // galaxy, cut down: a step that runs twice with a per-step target, a stretch with a
  // number and a switch, and a knob that does nothing
  static final _recipes = {
    'galaxy': {
      'version': 4,
      'source': 'builtin',
      'steps': [
        {
          'op': 'deconvolve_or_sharpen',
          'params': {
            'strength': {'default': 0.5, 'min': 0.2, 'max': 0.7, 'choices': null},
            'target': {
              'default': 'object',
              'min': null,
              'max': null,
              'choices': ['stellar', 'object'],
            },
          },
        },
        {
          'op': 'deconvolve_or_sharpen',
          'params': {
            'strength': {'default': 0.5, 'min': 0.2, 'max': 0.7, 'choices': null},
            'target': {
              'default': 'stellar',
              'min': null,
              'max': null,
              'choices': ['stellar', 'object'],
            },
          },
        },
        {
          'op': 'stretch',
          'params': {
            'target_background': {'default': 0.2, 'min': 0.08, 'max': 0.28, 'choices': null},
            'linked': {
              'default': true,
              'min': null,
              'max': null,
              'choices': [true, false],
            },
            'target_highlight': {'default': 0.97, 'min': 0.9, 'max': 0.99, 'choices': null},
          },
        },
      ],
    },
  };

  static Map<String, Object?> _w(String de, String en) => {'de': de, 'en': en};

  static final _docs = {
    'deconvolve_or_sharpen': {
      '_op': {'label': _w('Entfalten / Schärfen', 'Deconvolve / sharpen'), 'help': _w('Schärft.', 'Sharpens.')},
      'strength': {
        'label': _w('Stärke', 'Strength'),
        'help': _w('Wie kräftig.', 'How strong.'),
        'low': _w('weniger: weicher', 'lower: softer'),
        'high': _w('mehr: knackiger', 'higher: crisper'),
      },
      'target': {
        'label': _w('Ziel', 'Target'),
        'help': _w('Objekt oder Sterne.', 'Object or stars.'),
        'choices': {'stellar': _w('Sterne', 'Stars'), 'object': _w('Objekt', 'Object')},
      },
    },
    'stretch': {
      '_op': {'label': _w('Strecken', 'Stretch'), 'help': _w('Macht das Bild hell.', 'Brightens the image.')},
      'target_background': {
        'label': _w('Hintergrund-Ziel', 'Background target'),
        'help': _w('Wie hell der Himmel wird.', 'How bright the sky gets.'),
        'low': _w('weniger: dunkler', 'lower: darker'),
        'high': _w('mehr: heller', 'higher: brighter'),
        'percent': true,
      },
      'linked': {
        'label': _w('Kanäle verknüpft', 'Channels linked'),
        'help': _w('Alle Farben gleich strecken.', 'Stretch all colours alike.'),
        'choices': {'true': _w('gemeinsam', 'together'), 'false': _w('je Kanal', 'per channel')},
      },
      'target_highlight': {
        'label': _w('Sternlicht-Grenze', 'Star highlight ceiling'),
        'help': _w('Gedacht als Grenze.', 'Intended as a ceiling.'),
        'low': _w('weniger', 'lower'),
        'high': _w('mehr', 'higher'),
        'inert': true,
        'note': _w('Hat derzeit keine Wirkung.', 'Currently has no effect.'),
      },
    },
  };

  static final _m33 = {
    'name': 'M33_galaxy',
    'recipe': 'galaxy',
    'title': 'M 33',
    'version': 4,
    'status': 'done',
    'total_steps': 3,
    'steps': [
      {
        'op': 'deconvolve_or_sharpen',
        'status': 'ok',
        'duration_s': 30,
        'iterations': [
          {
            'iteration': 1,
            'params': {'strength': 0.5, 'target': 'object', 'workdir': '/x'},
            'metrics_after': {'noise_sigma': 0.00002, 'star_count': 1800.0, 'fwhm_px': 2.9},
          },
        ],
        'previews': [],
      },
      {
        'op': 'deconvolve_or_sharpen',
        'status': 'ok',
        'iterations': [
          {
            'iteration': 1,
            'params': {'strength': 0.5, 'target': 'stellar'},
            'metrics_after': {'noise_sigma': 0.00002, 'star_count': 1700.0, 'fwhm_px': 2.4},
          },
        ],
        'previews': [],
      },
      {
        'op': 'stretch',
        'status': 'ok',
        'iterations': [
          {
            'iteration': 1,
            'params': {'target_background': 0.2, 'linked': true, 'target_highlight': 0.97},
            'metrics_after': {'median': 0.21, 'star_count': 1650.0, 'highlight_clip_fraction': 0.0001},
          },
        ],
        'previews': [],
      },
    ],
    'final_previews': {},
  };

  static final _pipeline = {
    'id': 'p1',
    'source': 'nina',
    'subject': 'NGC 7000',
    'owner': 'ben',
    'level': 'guarded',
    'step_holds': false,
    'state': 'waiting',
    'approved_through': null,
    'hold': {
      'point': 'stacking',
      'reason': 'Eine Nacht weicht im Gradient ab.',
      'findings': ['Gradient 4,1 % in Nacht 2'],
      'details': {},
      'since': '2026-10-28T21:40:00Z',
    },
    'history': [],
    'runs': ['NGC7000_emission'],
    'created_at': '2026-10-28T21:00:00Z',
    'updated_at': '2026-10-28T21:40:00Z',
  };

  static String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

  /// A 1×1 PNG: enough for Image.memory to decode.
  static final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );

  /// /nina/live in the middle of a night, shaped like nina_live.py shapes it.
  static final liveSnapshot = {
    'at': 1793182074.3,
    'devices': {
      for (final d in ['camera', 'mount', 'focuser', 'filterwheel', 'guider'])
        d: {'connected': true, 'reachable': true, 'error': null, 'age_s': 1.0, 'stale': false, ...?rigFields[d]},
      'rotator': {'connected': false, 'reachable': true, 'error': null, 'age_s': 1.0, 'stale': false},
    },
    'guiding': {
      'reachable': true,
      'active': true,
      'state': 'Guiding',
      'steps': [],
      'rms_ra_arcsec': 0.41,
      'rms_dec_arcsec': 0.46,
      'rms_total_arcsec': 0.62,
    },
    'sequence': {
      'reachable': true,
      'running': true,
      'current': 'NGC 7000 > Imaging > Smart Exposure',
      'containers': [],
    },
    'frames': {
      'reachable': true,
      'count': 38,
      'recent': [
        {
          'index': 37,
          'at': '2026-10-28T20:07:00Z',
          'hfr': 2.4,
          'stars': 1284,
          'exposure_s': 120,
          'filter': 'L-eXtreme',
          'type': 'LIGHT',
        },
      ],
      'progress': {'lights': 38, 'usable': 35, 'rejected': 3, 'usable_minutes': 70.0},
    },
  };
  // --- the rig's control surface (Telescope → Control) ------------------------------

  /// Refusals by control action, answered 409 with the server's own words.
  final refusals = <String, String>{};
  final nudges = <Map<String, Object?>>[];
  int tppaPolls = 0;

  // --- framing (lib/framing) -------------------------------------------------------

  /// The mount reports AtPark in /nina/live.
  bool mountParked = false;

  /// The angle NINA's framing assistant reads back after "determine rotation".
  double ninaRotation = 123.4;

  Map<String, Object?> _parkedSnapshot() {
    final devices = Map<String, Object?>.of(liveSnapshot['devices']! as Map<String, Object?>);
    devices['mount'] = {...devices['mount']! as Map, 'AtPark': true};
    return {...liveSnapshot, 'devices': devices};
  }

  bool tppaAvailable = true;
  bool tppaRunning = false;

  /// NINA's own fields per device, as /nina/live passes them through.
  static final rigFields = <String, Map<String, Object?>>{
    'camera': {
      'Temperature': -9.8,
      'TargetTemp': -10.0,
      'CoolerOn': true,
      'CoolerPower': 41.0,
      'Gain': 100,
      'GainMin': 0,
      'GainMax': 10000,
      'IsExposing': false,
    },
    'mount': {'AtPark': false, 'Slewing': false, 'TrackingEnabled': true, 'Altitude': 61.2, 'TimeToMeridianFlip': 1.5},
    'focuser': {'Position': 8150, 'IsMoving': false, 'Temperature': 3.1},
  };

  http.Response? _rig(http.Request request) {
    http.Response json(Object body, [int status = 200]) =>
        http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
    switch ((request.method, request.url.path)) {
      case ('GET', '/api/bortle/nina/devices'):
        return json({
          'devices': [
            {'key': 'camera', 'label': 'Kamera', 'connected': true, 'driver_name': 'ATR2600C (k_0-12b7)'},
            {'key': 'mount', 'label': 'Montierung', 'connected': true, 'driver_name': 'EQMOD'},
            {'key': 'focuser', 'label': 'Fokussierer', 'connected': false, 'driver_name': 'Lacerta MFOC'},
          ],
          'profile': {'id': 'p', 'name': 'Epsilon 160'},
        });
      case ('GET', '/api/bortle/nina/filters'):
        return json({
          'connected': true,
          'moving': false,
          'current': {'id': 2, 'name': 'Optolong L Pro'},
          'filters': [
            {'id': 0, 'name': 'Optlong UV IR Cut'},
            {'id': 2, 'name': 'Optolong L Pro'},
            {'id': 3, 'name': ''},
            {'id': 4, 'name': 'Antlia H Alpha & OIII'},
          ],
        });
      case ('GET', '/api/bortle/nina/cooling'):
        return json({
          'setpoint_c': -15,
          'reason': 'darks on disk at -15 °C',
          'warnings': ['ambient temperature unknown'],
        });
      case ('GET', '/api/bortle/nina/preflight'):
        return json({
          'ok': false,
          'summary': '1 blocking, 1 to look at',
          'checks': [
            {'key': 'device.camera', 'title': 'Camera', 'status': 'pass', 'detail': 'connected'},
            {'key': 'device.focuser', 'title': 'Focuser', 'status': 'block', 'detail': 'not connected'},
            {'key': 'settle', 'title': 'Settle time', 'status': 'warn', 'detail': '10 s, solve needs 20 s'},
          ],
        });
      case ('GET', '/api/bortle/nina/autofocus/live'):
        return json({
          'running': false,
          'points': [],
          'expected_points': 9,
          'last': {
            'points': [
              {'position': 8040, 'hfr': 6.0},
              {'position': 8100, 'hfr': 4.49},
              {'position': 8160, 'hfr': 4.55},
              {'position': 8220, 'hfr': 4.74},
            ],
            'calculated_position': 8150,
            'calculated_hfr': 4.588,
            'r_squared': 0.9962,
            'trustworthy': true,
          },
        });
      case ('GET', '/api/bortle/nina/tppa'):
        tppaPolls++;
        if (!tppaAvailable) {
          return json({
            'available': false,
            'running': false,
            'paused': false,
            'note': 'Das Plugin ist in NINA nicht geladen.',
          });
        }
        return json({
          'available': true,
          'connected': tppaRunning,
          'running': tppaRunning,
          'paused': false,
          'error_arcmin': tppaRunning ? 3.42 : null,
          'last': tppaRunning
              ? {
                  'azimuth_arcmin': -2.1,
                  'altitude_arcmin': 2.7,
                  'total_arcmin': 3.42,
                  'status': 'Solving',
                  'progress': 0.66,
                }
              : null,
        });
      case ('GET', '/api/bortle/plan/framing'):
        // services/planner/framing.py FramingAdvice.as_dict
        return json({
          'target': request.url.queryParameters['target'],
          'known': framingAngle != null,
          'position_angle_deg': framingAngle,
          'measured_at': framingAngle != null ? '2026-10-28T21:14:00+00:00' : null,
          'frames': framingAngle != null ? 12 : 0,
          'note': framingAngle != null ? 'measured' : 'no solved frame for this target yet',
          'warnings': [],
          'measurements': [],
        });
      case ('GET', '/api/bortle/nina/framing'):
        // nina_live.py framing_view
        return json({
          'source': 'SKYATLAS',
          'ra_deg': 314.75,
          'dec_deg': 44.33,
          'rotation_deg': ninaRotation,
          'fov_deg': 1.67,
          'target_name': null,
        });
      case ('GET', '/api/bortle/nina/capture'):
        return http.Response.bytes(_png, 200, headers: {'content-type': 'image/png'});
      case ('POST', '/api/bortle/nina/nudge'):
        nudges.add((jsonDecode(request.body) as Map).cast<String, Object?>());
        return json({'step': {}, 'result': 'ok'});
      case ('POST', '/api/bortle/nina/control'):
        final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
        final refusal = refusals[body['action']];
        if (refusal != null) {
          controls.add(body);
          return json({'detail': refusal}, 409);
        }
        if (body['action'] == 'tppa-start') tppaRunning = true;
        if (body['action'] == 'tppa-stop') tppaRunning = false;
        if (body['action'] == 'capture') {
          controls.add(body);
          return json({
            'action': 'capture',
            'duration_s': body['duration'],
            'result': '5s exposure — a look, not a measurement',
          });
        }
        return null; // the general case below records it
    }
    return null;
  }
}
