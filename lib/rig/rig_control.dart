// Telescope → Control: the rig's devices at the telescope, in the dark, with gloves.
// Everything here asks NINA to run one of its own operations through the routes the
// cockpit's /rig pages use (POST /nina/control, /nina/nudge); the app implements none
// of them, and safety (park on loss, aborts, meridian flip) stays NINA's.
//
// Laid out like Touch'N'Stars: a strip of devices on top (lib/rig/device_bar.dart), the
// page of the one chosen below it (lib/rig/pages/), remembered across visits. What the
// pages share – the live snapshot, the one action running, how an action asks and runs –
// is lib/rig/rig_session.dart.

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../api/bortle_client.dart';
import '../api/session_store.dart';
import '../design.dart';
import '../l10n.dart';
import '../widgets.dart';
import 'device_bar.dart';
import 'pages/camera_page.dart';
import 'pages/devices_page.dart';
import 'pages/filter_page.dart';
import 'pages/flat_page.dart';
import 'pages/focus_page.dart';
import 'pages/guiding_page.dart';
import 'pages/mount_page.dart';
import 'pages/rotator_page.dart';
import 'pages/sequence_page.dart';
import 'rig_models.dart';
import 'rig_session.dart';
import 'touchnstars.dart';

export 'pages/mount_page.dart' show FrameCallback;

/// Where the last open page is kept (SessionStore.setting).
const rigPageKey = 'rig_page';

class RigControl extends StatefulWidget {
  const RigControl({required this.client, required this.active, this.store, this.onFrame, super.key});

  final BortleClient client;

  /// Whether the tab is on screen; polling runs only then.
  final bool active;

  /// Keeps the last page and the Touch'N'Stars address; without it both last as long
  /// as the view.
  final SessionStore? store;

  /// Opens the framing view for a target from the mount's slew tab; the button is not
  /// shown without it.
  final FrameCallback? onFrame;

  @override
  State<RigControl> createState() => _RigControlState();
}

class _RigControlState extends State<RigControl> {
  late final RigSession _session = RigSession(widget.client)..addListener(_changed);
  late final TouchNStars _touchNStars = TouchNStars(widget.store);
  Timer? _timer;
  RigPage _page = RigPage.devices;

  @override
  void initState() {
    super.initState();
    _restorePage();
    _session.poll();
    _schedule();
  }

  Future<void> _restorePage() async {
    final name = await widget.store?.setting(rigPageKey);
    final page = RigPage.values.where((p) => p.name == name).firstOrNull;
    if (page != null && mounted) setState(() => _page = page);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(RigControl old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      _schedule();
      if (widget.active) _session.poll();
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = widget.active ? Timer.periodic(const Duration(seconds: 5), (_) => _session.poll()) : null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _session.dispose();
    super.dispose();
  }

  void _select(RigPage page) {
    if (page == _page) return;
    setState(() => _page = page);
    widget.store?.setSetting(rigPageKey, page.name);
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final rig = _session.rig;
    if (rig == null) {
      return _session.error != null
          ? LoadError(_session.error!, onRetry: _session.poll)
          : const Center(child: CircularProgressIndicator());
    }
    if (!rig.reachable) {
      return RefreshIndicator(
        onRefresh: _session.poll,
        child: ListView(
          padding: const EdgeInsets.all(32),
          children: [
            Icon(Icons.nights_stay_outlined, size: 40, color: tones.muted),
            const SizedBox(height: 12),
            Text(
              tr(
                'NINA antwortet gerade nicht – ohne NINA gibt es nichts zu steuern. Sobald NINA läuft, erscheinen die Geräte hier.',
                'NINA is not answering – without NINA there is nothing to control. Once NINA runs, the devices show here.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: tones.muted),
            ),
          ],
        ),
      );
    }
    // a rotator or flat panel that went away takes its page with it
    final page = _page.shownFor(rig) ? _page : RigPage.devices;
    return Column(
      key: const Key('rig-control'),
      children: [
        RigDeviceBar(
          rig: rig,
          selected: page,
          onSelect: _select,
          trailing: PopupMenuButton<String>(
            key: const Key('rig-more'),
            tooltip: tr('Mehr', 'More'),
            icon: const Icon(Icons.more_vert),
            onSelected: (choice) => switch (choice) {
              'open' => _touchNStars.open(context),
              _ => _touchNStars.edit(context),
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                key: const Key('menu-touchnstars'),
                value: 'open',
                child: Text(tr('Touch’N’Stars öffnen', 'Open Touch’N’Stars')),
              ),
              PopupMenuItem(
                key: const Key('menu-touchnstars-address'),
                value: 'address',
                child: Text(tr('Touch’N’Stars-Adresse …', 'Touch’N’Stars address …')),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: tones.line),
        Expanded(
          child: KeyedSubtree(key: ValueKey(page), child: _pageFor(page, rig)),
        ),
      ],
    );
  }

  Widget _pageFor(RigPage page, RigState rig) => switch (page) {
    RigPage.devices => DevicesPage(session: _session, rig: rig, touchNStars: _touchNStars),
    RigPage.camera => CameraPage(session: _session, rig: rig),
    RigPage.mount => MountPage(session: _session, rig: rig, onFrame: widget.onFrame),
    RigPage.filter => FilterPage(session: _session, rig: rig),
    RigPage.focus => FocusPage(session: _session, rig: rig),
    RigPage.guiding => GuidingPage(session: _session, rig: rig),
    RigPage.sequence => SequencePage(session: _session, rig: rig),
    RigPage.rotator => RotatorPage(session: _session, rig: rig),
    RigPage.flat => FlatPage(session: _session, rig: rig),
  };
}
