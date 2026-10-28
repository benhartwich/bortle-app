// A scripted Bortle cockpit for the tests: the shapes are the real ones (see the Bortle
// repository's tests/test_app_login_e2e.py for the same calls against a live cockpit).

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeServer {
  FakeServer({this.localMode = false});

  final bool localMode;
  final requests = <http.Request>[];
  bool approved = false;
  bool cancelled = false;
  bool signedOut = false;
  final revoked = <String>[];

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
          'user': {'name': 'ben', 'admin': true},
        });
      }
      return json({'error': 'Name/E-Mail oder Passwort falsch.'}, 401);
    }
    if (!_authed(request)) return json({'error': 'unauthorized'}, 401);

    switch ((request.method, path)) {
      case ('GET', '/api/app/session'):
        return json({
          'user': {'name': 'ben', 'admin': true},
        });
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
    if (path.startsWith('/api/bortle/data/')) return http.Response('', 404);
    return json({'error': 'not found'}, 404);
  });

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
}
