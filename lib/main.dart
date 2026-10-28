import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/bortle_client.dart';
import 'api/models.dart';
import 'api/session_store.dart';
import 'design.dart';
import 'l10n.dart';
import 'screens/gallery_screen.dart';
import 'screens/login_screen.dart';
import 'screens/more_screen.dart';
import 'screens/plan_screen.dart';
import 'screens/telescope_screen.dart';
import 'screens/today_screen.dart';

void main() {
  runApp(
    BortleApp(
      store: SecureSessionStore(),
      clientFor: (url, token) => BortleClient(baseUrl: url, token: token),
    ),
  );
}

class BortleApp extends StatefulWidget {
  const BortleApp({super.key, required this.store, required this.clientFor});

  final SessionStore store;
  final ClientFactory clientFor;

  @override
  State<BortleApp> createState() => _BortleAppState();
}

class _BortleAppState extends State<BortleApp> {
  BortleClient? _client;
  Me? _me;
  bool _red = false;
  bool _loading = true;
  String? _lastServer;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final session = await widget.store.load();
    final red = await widget.store.redLight();
    BortleClient? client;
    Me? me;
    if (session != null) {
      client = widget.clientFor(session.serverUrl, session.token);
      if (session.token != null) {
        try {
          me = await client.me();
        } on BortleError catch (e) {
          // Revoked here or on the profile page, or the password changed: sign in again.
          // Offline is not a reason to forget the login.
          if (e.unauthorized) {
            await widget.store.clear();
            client = null;
          }
        }
      }
    }
    final store = widget.store;
    setState(() {
      _client = client;
      _me = me;
      _red = red;
      _lastServer = session?.serverUrl;
      _loading = false;
    });
    if (store is SecureSessionStore && session == null) {
      final last = await store.lastServer();
      if (mounted) setState(() => _lastServer = last);
    }
  }

  Future<void> _signedIn(BortleClient client, Me? me) async {
    await widget.store.save(StoredSession(client.baseUrl, client.token));
    setState(() {
      _client = client;
      _me = me;
      _lastServer = client.baseUrl;
    });
  }

  Future<void> _signOut() async {
    try {
      if (_client?.token != null) await _client!.logout();
    } on BortleError {
      // Offline or already revoked: forget it locally anyway.
    }
    await widget.store.clear();
    setState(() {
      _client = null;
      _me = null;
    });
  }

  Future<void> _setRed(bool on) async {
    await widget.store.setRedLight(on);
    setState(() => _red = on);
  }

  @override
  Widget build(BuildContext context) {
    final client = _client;
    return MaterialApp(
      title: 'Bortle',
      debugShowCheckedModeBanner: false,
      theme: bortleTheme(red: _red),
      locale: appLocale,
      supportedLocales: const [Locale('de'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : client == null
          ? LoginScreen(clientFor: widget.clientFor, onSignedIn: _signedIn, lastServer: _lastServer)
          : HomeShell(
              key: ValueKey(client),
              client: client,
              me: _me,
              redLight: _red,
              onRedLight: _setRed,
              onSignOut: _signOut,
            ),
    );
  }
}

/// The five tabs at the bottom (docs/CONCEPT.md, "Navigation").
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.client,
    required this.me,
    required this.redLight,
    required this.onRedLight,
    required this.onSignOut,
  });

  final BortleClient client;
  final Me? me;
  final bool redLight;
  final ValueChanged<bool> onRedLight;
  final VoidCallback onSignOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayScreen(client: widget.client, onRedLight: () => widget.onRedLight(!widget.redLight)),
      PlanScreen(client: widget.client, me: widget.me),
      TelescopeScreen(
        client: widget.client,
        me: widget.me,
        active: _tab == 2,
        onRedLight: () => widget.onRedLight(!widget.redLight),
      ),
      GalleryScreen(client: widget.client),
      MoreScreen(
        client: widget.client,
        me: widget.me,
        redLight: widget.redLight,
        onRedLight: widget.onRedLight,
        onSignOut: widget.onSignOut,
      ),
    ];
    return SkyBackground(
      child: Scaffold(
        body: IndexedStack(index: _tab, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: tr('Heute', 'Tonight'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.event_outlined),
              selectedIcon: const Icon(Icons.event),
              label: tr('Planen', 'Plan'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.radio_button_checked_outlined),
              selectedIcon: const Icon(Icons.radio_button_checked),
              label: tr('Teleskop', 'Telescope'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.photo_library_outlined),
              selectedIcon: const Icon(Icons.photo_library),
              label: tr('Galerie', 'Gallery'),
            ),
            NavigationDestination(icon: const Icon(Icons.more_horiz), label: tr('Mehr', 'More')),
          ],
        ),
      ),
    );
  }
}
