// Sign in: pick the server (bortle.eu or an own install), check what it is, then name or
// email + password. The token this returns belongs to this one device.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/bortle_client.dart';
import '../api/models.dart';
import '../design.dart';
import '../l10n.dart';

typedef ClientFactory = BortleClient Function(String baseUrl, String? token);

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.clientFor, required this.onSignedIn, this.lastServer, super.key});

  final ClientFactory clientFor;

  /// Called with the signed-in client and who it is (null in local mode).
  final void Function(BortleClient client, Me? me) onSignedIn;
  final String? lastServer;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late bool _own = widget.lastServer != null && normalizeServerUrl(widget.lastServer!) != defaultServerUrl;
  late final _server = TextEditingController(text: _own ? widget.lastServer : '');
  final _login = TextEditingController();
  final _password = TextEditingController();
  ServerInfo? _info;
  String? _checkedUrl;
  String? _error;
  bool _busy = false;

  String get _url => _own ? normalizeServerUrl(_server.text) : defaultServerUrl;

  String get _deviceLabel => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'Bortle App (iOS)',
    TargetPlatform.android => 'Bortle App (Android)',
    _ => 'Bortle App',
  };

  Future<void> _check() async {
    final url = _url;
    if (url.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final info = await widget.clientFor(url, null).info();
      setState(() {
        _checkedUrl = url;
        _info = info;
        if (info == null) {
          _error = tr(
            'Unter dieser Adresse antwortet kein Bortle (oder eines, das zu alt für die App ist).',
            'No Bortle answers at this address (or one too old for the app).',
          );
        } else if (!info.supported) {
          _error = tr(
            'Dieses Bortle (${info.version}) ist zu alt für die App. Bitte aktualisieren.',
            'This Bortle (${info.version}) is too old for the app. Please update it.',
          );
        }
      });
    } on BortleError {
      setState(() => _error = tr('Server nicht erreichbar.', 'Server not reachable.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    final info = _info;
    final url = _checkedUrl;
    if (info == null || url == null || !info.supported) return;
    if (!info.needsLogin) {
      widget.onSignedIn(widget.clientFor(url, null), null);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.clientFor(url, null).login(_login.text.trim(), _password.text, _deviceLabel);
      widget.onSignedIn(widget.clientFor(url, result.token), result.user);
    } on BortleError catch (e) {
      setState(
        () => _error = switch (e.status) {
          0 => tr('Server nicht erreichbar.', 'Server not reachable.'),
          401 => tr('Name/E-Mail oder Passwort falsch.', 'Name/email or password is wrong.'),
          429 => tr('Zu viele Fehlversuche – bitte kurz warten.', 'Too many failed attempts – please wait a moment.'),
          _ => e.message,
        },
      );
      if (e.status == 401) _password.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    if (!_own) _check();
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final ready = info != null && info.supported && _checkedUrl == _url;
    final tones = context.tones;
    return Scaffold(
      body: SkyBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
            children: [
              Text('Bortle', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 6),
              Text(tr('Planen, aufnehmen, entwickeln – von unterwegs.', 'Plan, capture, develop – on the go.')),
              const SizedBox(height: 28),
              SegmentedButton<bool>(
                segments: [
                  const ButtonSegment(value: false, label: Text('bortle.eu')),
                  ButtonSegment(value: true, label: Text(tr('Eigene Instanz', 'Own install'))),
                ],
                selected: {_own},
                onSelectionChanged: (s) {
                  setState(() {
                    _own = s.first;
                    _info = null;
                    _error = null;
                  });
                  if (!_own) _check();
                },
              ),
              if (_own) ...[
                const SizedBox(height: 16),
                TextField(
                  key: const Key('server'),
                  controller: _server,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: tr('Adresse deiner Bortle-Instanz', 'Address of your Bortle install'),
                    hintText: 'https://bortle.example.org',
                  ),
                  onChanged: (_) => setState(() => _info = null),
                  onSubmitted: (_) => _check(),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(onPressed: _busy ? null : _check, child: Text(tr('Prüfen', 'Check'))),
                ),
                if (isInsecureOutsideHome(_url))
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      tr(
                        'Achtung: http ohne Verschlüsselung außerhalb des Heimnetzes – Passwort und Zugang gingen lesbar übers Netz.',
                        'Careful: plain http outside a home network – password and access would cross the net readable.',
                      ),
                      style: TextStyle(color: tones.warn),
                    ),
                  ),
              ],
              if (ready) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: tones.good, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        info.needsLogin
                            ? tr('Bortle ${info.version} gefunden', 'Found Bortle ${info.version}')
                            : tr(
                                'Bortle ${info.version} im lokalen Modus – keine Anmeldung nötig',
                                'Bortle ${info.version} in local mode – no sign-in needed',
                              ),
                      ),
                    ),
                  ],
                ),
                if (info.needsLogin) ...[
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('login'),
                    controller: _login,
                    autocorrect: false,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email, AutofillHints.username],
                    decoration: InputDecoration(labelText: tr('E-Mail oder Name', 'Email or name')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('password'),
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(labelText: tr('Passwort', 'Password')),
                    onSubmitted: (_) => _signIn(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(
                      'Dieses Gerät erscheint im Profil als „$_deviceLabel“ und lässt sich dort abmelden.',
                      'This device appears in your profile as “$_deviceLabel” and can be signed out there.',
                    ),
                    style: TextStyle(color: tones.muted, fontSize: 13),
                  ),
                ],
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_error!, style: TextStyle(color: tones.danger)),
                ),
              const SizedBox(height: 28),
              FilledButton(
                key: const Key('sign-in'),
                onPressed: ready && !_busy ? _signIn : null,
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(info != null && !info.needsLogin ? tr('Verbinden', 'Connect') : tr('Anmelden', 'Sign in')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
