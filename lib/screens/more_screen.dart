// "Mehr": who and where you are signed in, the red light mode, this account's signed-in
// devices, and signing out.

import 'package:flutter/material.dart';

import '../api/bortle_client.dart';
import '../api/models.dart';
import '../design.dart';
import '../l10n.dart';
import '../tools/tools_screen.dart';
import '../widgets.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({
    required this.client,
    required this.me,
    required this.redLight,
    required this.onRedLight,
    required this.onSignOut,
    super.key,
  });

  final BortleClient client;

  /// Null on an instance in local mode.
  final Me? me;
  final bool redLight;
  final ValueChanged<bool> onRedLight;
  final VoidCallback onSignOut;

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  late Future<List<AppDevice>>? _devices = widget.me == null ? null : widget.client.devices();

  void _reload() => setState(() {
    _devices = widget.client.devices();
  });

  Future<void> _revoke(AppDevice d) async {
    final ok = await confirm(
      context,
      tr('Gerät abmelden?', 'Sign this device out?'),
      tr('„${d.label}“ muss sich danach neu anmelden.', '“${d.label}” will have to sign in again.'),
      tr('Abmelden', 'Sign out'),
    );
    if (!ok) return;
    try {
      await widget.client.revokeDevice(d.id);
    } on BortleError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final me = widget.me;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Mehr', 'More'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(widget.client.baseUrl.replaceFirst(RegExp(r'^https?://'), '')),
              subtitle: Text(
                me == null
                    ? tr('Lokaler Modus, ohne Anmeldung', 'Local mode, no sign-in')
                    : tr(
                        'Angemeldet als ${me.name}${me.admin ? ' (Betreiber)' : ''}',
                        'Signed in as ${me.name}${me.admin ? ' (operator)' : ''}',
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: SwitchListTile(
              key: const Key('red-light'),
              secondary: Icon(Icons.dark_mode_outlined, color: tones.danger),
              title: Text(tr('Rotlicht-Modus', 'Red light mode')),
              subtitle: Text(
                tr('Schont die Dunkeladaption am Teleskop.', 'Keeps your dark adaptation at the telescope.'),
              ),
              value: widget.redLight,
              onChanged: widget.onRedLight,
            ),
          ),
          if (_devices != null) ...[
            SectionTitle(tr('Angemeldete Geräte', 'Signed-in devices')),
            FutureBuilder<List<AppDevice>>(
              future: _devices,
              builder: (context, snap) {
                if (snap.hasError) {
                  return LoadError(snap.error!, onRetry: _reload);
                }
                final list = snap.data;
                if (list == null) return const LinearProgressIndicator();
                return Card(
                  child: Column(
                    children: [
                      for (final d in list)
                        ListTile(
                          leading: const Icon(Icons.smartphone_outlined),
                          title: Text(d.label),
                          subtitle: Text(
                            d.lastUsedAt == null
                                ? tr('noch nie verbunden', 'never connected')
                                : tr('zuletzt ${when(d.lastUsedAt!)}', 'last ${when(d.lastUsedAt!)}'),
                          ),
                          trailing: IconButton(
                            tooltip: tr('Abmelden', 'Sign out'),
                            icon: const Icon(Icons.logout),
                            onPressed: () => _revoke(d),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
          ListTile(
            key: const Key('tools'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.nights_stay_outlined),
            title: Text(tr('Werkzeuge für die Nacht', 'Tools for the night')),
            subtitle: Text(
              tr('Dämmerung, Mond, Objekthöhen, Optik, Wetter', 'Twilight, moon, altitudes, optics, weather'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ToolsScreen())),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            key: const Key('sign-out'),
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
            label: Text(me == null ? tr('Server wechseln', 'Change server') : tr('Abmelden', 'Sign out')),
          ),
          const SizedBox(height: 16),
          Text(
            tr(
              'Sessions, der ZIP-Upload, die Gerätesteuerung und die Einstellungen (auch die Nextcloud-Verbindung) sind im Browser-Cockpit; die Gerätesteuerung kommt in die App, sobald sie an echter Hardware erprobt ist.',
              'Sessions, the ZIP upload, device control and settings (the Nextcloud connection too) are in the browser cockpit; device control comes to the app once it is proven on real hardware.',
            ),
            style: TextStyle(color: tones.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
