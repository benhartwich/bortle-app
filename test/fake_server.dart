// A scripted Bortle cockpit for the tests: the shapes are the real ones (see the Bortle
// repository's tests/test_app_login_e2e.py for the same calls against a live cockpit).

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeServer {
  FakeServer({this.localMode = false, this.admin = true, this.ninaUp = true});

  final bool localMode;

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

  static const token = 'bat_test-token';

  bool _authed(http.Request r) => localMode || r.headers['authorization'] == 'Bearer $token';

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
          'user': {'name': 'ben', 'admin': admin},
        });
      }
      return json({'error': 'Name/E-Mail oder Passwort falsch.'}, 401);
    }
    if (!_authed(request)) return json({'error': 'unauthorized'}, 401);

    switch ((request.method, path)) {
      case ('GET', '/api/app/session'):
        return json({
          'user': {'name': 'ben', 'admin': admin},
        });
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
    if ((path.startsWith('/api/bortle/nina/') || path == '/api/bortle/plan/nina') && !admin && !localMode) {
      return json({'detail': 'Das Teleskop dieser Instanz bedient nur der Betreiber.'}, 403);
    }
    switch ((request.method, path)) {
      case ('GET', '/api/bortle/plan/suggest'):
        return http.Response(fixture('suggest_ngc7.json'), 200, headers: {'content-type': 'application/json'});
      case ('GET', '/api/bortle/plan'):
        return http.Response(fixture('plan_ngc7000.json'), 200, headers: {'content-type': 'application/json'});
      case ('GET', '/api/bortle/develop/level'):
        return json({'level': 'guarded', 'step_holds': false, 'stored': true});
      case ('POST', '/api/bortle/plan/nina'):
        sentPlan = (jsonDecode(request.body) as Map).cast<String, Object?>();
        return json({'loaded': true});
      case ('GET', '/api/bortle/nina/live'):
        return ninaUp
            ? json(liveSnapshot)
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
        d: {'connected': true, 'reachable': true, 'error': null, 'age_s': 1.0, 'stale': false},
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
}
