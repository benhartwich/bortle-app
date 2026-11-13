// Touch'N'Stars: NINA's own web interface, a plugin inside NINA. Bortle does not embed
// or proxy it – the phone's browser opens it on the LAN, at the address the user gave.
// There is no default: an address is the user's rig, never Bortle's guess.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/session_store.dart';
import '../l10n.dart';
import 'rig_session.dart';

/// Opens [url] outside the app; false when nothing could. Tests replace it.
Future<bool> Function(Uri url) openExternalUrl = (url) async {
  try {
    return await launchUrl(url, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
};

/// Where the address is kept (SessionStore.setting).
const touchNStarsKey = 'touchnstars_url';

/// What was typed, as a URL to open: http(s) with a host, `http://` added when no scheme
/// was given. Null for anything else.
Uri? touchNStarsUri(String text) {
  var t = text.trim();
  if (t.isEmpty) return null;
  if (!t.contains('://')) t = 'http://$t';
  final uri = Uri.tryParse(t);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) return null;
  return uri;
}

class TouchNStars {
  TouchNStars(this.store);

  /// Null in tests and before sign-in: then the address lives as long as the page.
  final SessionStore? store;
  String? _memory;

  Future<String?> url() async => store == null ? _memory : await store!.setting(touchNStarsKey);

  Future<void> _save(String? value) async {
    if (store == null) {
      _memory = value;
    } else {
      await store!.setSetting(touchNStarsKey, value);
    }
  }

  /// Opens Touch'N'Stars; asks for the address first when there is none.
  Future<void> open(BuildContext context) async {
    var text = await url();
    if (text == null || text.isEmpty) {
      if (!context.mounted) return;
      text = await edit(context);
      if (text == null || text.isEmpty) return;
    }
    final uri = touchNStarsUri(text);
    if (uri == null) return;
    final opened = await openExternalUrl(uri);
    if (opened || !context.mounted) return;
    // no browser to hand it to: the address goes to the clipboard instead
    await Clipboard.setData(ClipboardData(text: '$uri'));
    if (context.mounted) {
      RigSession.say(
        context,
        tr(
          'Kein Browser hat die Adresse geöffnet – sie liegt jetzt in der Zwischenablage: $uri',
          'No browser opened the address – it is on the clipboard now: $uri',
        ),
      );
    }
  }

  /// Asks for the address; returns what was saved (empty when cleared), null when cancelled.
  Future<String?> edit(BuildContext context) async {
    final current = await url() ?? '';
    if (!context.mounted) return null;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _AddressDialog(initial: current),
    );
    if (result == null) return null;
    final uri = touchNStarsUri(result);
    final value = uri?.toString() ?? '';
    await _save(value.isEmpty ? null : value);
    return value;
  }
}

class _AddressDialog extends StatefulWidget {
  const _AddressDialog({required this.initial});

  final String initial;

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  // the dialog's own: it outlives the call that opened it by the closing animation
  late final _controller = TextEditingController(text: widget.initial);
  String? _problem;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text;
    if (text.trim().isNotEmpty && touchNStarsUri(text) == null) {
      setState(() => _problem = tr('Keine http(s)-Adresse.', 'Not an http(s) address.'));
      return;
    }
    Navigator.pop(context, text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('Adresse von Touch’N’Stars', 'Touch’N’Stars address')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(
            'Touch’N’Stars läuft als Plugin in NINA auf dem Rechner am Teleskop. Die Adresse zeigt das Plugin in NINA an.',
            'Touch’N’Stars runs as a plugin in NINA on the computer at the telescope. The plugin shows its address in NINA.',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('touchnstars-url'),
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: tr('Adresse', 'Address'),
            hintText: tr(
              'z. B. http://astro-remote:5000/ (Touch’N’Stars-Plugin in NINA)',
              'e.g. http://astro-remote:5000/ (Touch’N’Stars plugin in NINA)',
            ),
            hintMaxLines: 2,
            errorText: _problem,
          ),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Zurück', 'Back'))),
      FilledButton(key: const Key('touchnstars-save'), onPressed: _submit, child: Text(tr('Speichern', 'Save'))),
    ],
  );
}
