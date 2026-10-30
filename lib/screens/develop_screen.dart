// A new develop from the phone, as the cockpit's /develop: how much the person wants to
// have a say, then a project from their Nextcloud. A ZIP upload stays in the browser –
// a session is gigabytes, not something to push over a phone's data plan.

import 'package:flutter/material.dart';

import '../api/bortle_client.dart';
import '../api/models.dart';
import '../design.dart';
import '../l10n.dart';
import '../widgets.dart';

/// How far a run may go on its own (PLAN.md Phase 10), in words.
const _levels = ['stepwise', 'guarded', 'auto'];

String levelName(String level) => switch (level) {
  'stepwise' => tr('Schrittweise', 'Step by step'),
  'guarded' => tr('Mit Leitplanken', 'With guard rails'),
  _ => tr('Automatisch', 'Automatic'),
};

String _levelText(String level) => switch (level) {
  'stepwise' => tr(
    'Hält an jeder Phase – Eingang, Stacking, Kombinieren, Rezept, Galerie – und wartet auf dich.',
    'Stops at every phase – intake, stacking, combining, recipe, gallery – and waits for you.',
  ),
  'guarded' => tr(
    'Läuft allein, hält aber, wenn etwas auffällt, und vor der Galerie.',
    'Runs on its own, but stops when something stands out, and before the gallery.',
  ),
  _ => tr(
    'Bis in die Galerie, ohne anzuhalten. Danach kannst du jedes Bild neu entwickeln.',
    'All the way to the gallery. Afterwards you can develop any image again.',
  ),
};

class DevelopScreen extends StatefulWidget {
  const DevelopScreen({required this.client, super.key});

  final BortleClient client;

  @override
  State<DevelopScreen> createState() => _DevelopScreenState();
}

class _DevelopScreenState extends State<DevelopScreen> {
  String? _level;
  String _path = '';
  late Future<NextcloudFolder?> _folder = widget.client.nextcloudBrowse(_path);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.client.developLevel().then(
      (l) {
        if (mounted) setState(() => _level ??= l);
      },
      onError: (Object _) {
        if (mounted) setState(() => _level ??= 'auto');
      },
    );
  }

  void _open(String path) => setState(() {
    _path = path;
    _folder = widget.client.nextcloudBrowse(path);
  });

  Future<void> _start(String project) async {
    final tier = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                tr(
                  '„$project“ in Produktion · ${levelName(_level!)}',
                  '“$project” into production · ${levelName(_level!)}',
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              key: const Key('tier-slow'),
              leading: const Icon(Icons.memory),
              title: Text(tr('CPU-Pool (kostenlos)', 'CPU pool (free)')),
              subtitle: Text(tr('Rechnet, wenn ein Knoten frei ist.', 'Computes when a node is free.')),
              onTap: () => Navigator.of(context).pop('slow'),
            ),
            ListTile(
              key: const Key('tier-fast'),
              leading: const Icon(Icons.bolt),
              title: Text(tr('Burst (bezahlt)', 'Burst (paid)')),
              subtitle: Text(
                tr('Eine GPU-Maschine, deutlich schneller, kostet Geld.', 'A GPU machine, much faster, costs money.'),
              ),
              onTap: () => Navigator.of(context).pop('fast'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (tier == null || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final said = await widget.client.developFromNextcloud(project, tier: tier, level: _level!);
      messenger.showSnackBar(SnackBar(content: Text(said)));
      if (mounted) Navigator.of(context).pop();
    } on BortleError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), duration: const Duration(seconds: 8)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final level = _level;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Neue Entwicklung', 'New develop'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            tr('Wie viel willst du mitreden?', 'How much do you want to have a say?'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (level == null)
            const LinearProgressIndicator()
          else
            for (final l in _levels)
              Card(
                key: Key('level-$l'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Sky.radius / 2),
                  side: BorderSide(color: l == level ? Theme.of(context).colorScheme.primary : tones.line),
                ),
                child: ListTile(
                  leading: Icon(l == level ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                  title: Text(levelName(l)),
                  subtitle: Text(_levelText(l)),
                  onTap: () => setState(() => _level = l),
                ),
              ),
          SectionTitle(tr('Projekt aus deiner Nextcloud', 'A project from your Nextcloud')),
          FutureBuilder<NextcloudFolder?>(
            future: _folder,
            builder: (context, snap) {
              if (snap.hasError) return LoadError(snap.error!, onRetry: () => _open(_path));
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final folder = snap.data;
              if (folder == null) {
                return Text(
                  tr(
                    'Noch keine Nextcloud verbunden. Das geht im Browser-Cockpit unter Profil → Nextcloud-Verbindung (Adresse, Nutzer, App-Passwort); danach erscheinen deine Projektordner hier.',
                    'No Nextcloud connected yet. Connect it in the browser cockpit under Profile → Nextcloud connection (address, user, app password); your project folders then appear here.',
                  ),
                  style: TextStyle(color: tones.muted),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr(
                      'Ordner mit Lights tragen das Zeichen „Projekt“. Ein Rechen-Knoten zieht die Rohframes, stackt, entwickelt und lädt nur die fertigen Bilder zurück.',
                      'Folders with lights carry the “Project” tag. A compute node pulls the raw frames, stacks, develops and uploads only the finished images.',
                    ),
                    style: TextStyle(color: tones.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  if (folder.path.isNotEmpty)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.arrow_upward),
                      title: Text('/${folder.path}'),
                      subtitle: Text(tr('Eine Ebene höher', 'One level up')),
                      onTap: () => _open(folder.parent ?? ''),
                    ),
                  if (folder.dirs.isEmpty)
                    Text(tr('Keine Unterordner.', 'No subfolders.'), style: TextStyle(color: tones.muted)),
                  for (final d in folder.dirs)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(d.project ? Icons.auto_awesome : Icons.folder_outlined),
                      title: Text(d.name),
                      subtitle: d.project ? Text(tr('Projekt', 'Project'), style: TextStyle(color: tones.good)) : null,
                      trailing: d.project
                          ? FilledButton.tonal(
                              key: Key('start-${d.name}'),
                              onPressed: _busy || level == null
                                  ? null
                                  : () => _start(folder.path.isEmpty ? d.name : '${folder.path}/${d.name}'),
                              child: Text(tr('Starten', 'Start')),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: () => _open(folder.path.isEmpty ? d.name : '${folder.path}/${d.name}'),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            tr(
              'Eine Session als ZIP hochladen geht im Browser-Cockpit unter Entwickeln → Neue Entwicklung – Gigabytes über die Mobilverbindung schicken wir nicht.',
              'Uploading a session as a ZIP is in the browser cockpit under Develop → New develop – gigabytes over a mobile connection we leave alone.',
            ),
            style: TextStyle(color: tones.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
