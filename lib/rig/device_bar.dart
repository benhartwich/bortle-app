// The strip over every rig page, as Touch'N'Stars and the cockpit's rig nav have it: one
// round button per device, the open one filled, and a small red badge on every device
// NINA reports as not connected. It scrolls rather than wraps, for a phone in the dark.

import 'package:material_ui/material_ui.dart';

import '../design.dart';
import '../l10n.dart';
import 'rig_models.dart';

enum RigPage { devices, camera, mount, filter, focus, guiding, sequence, rotator, flat }

extension RigPageInfo on RigPage {
  String get label => switch (this) {
    RigPage.devices => tr('Geräte', 'Devices'),
    RigPage.camera => tr('Kamera', 'Camera'),
    RigPage.mount => tr('Montierung', 'Mount'),
    RigPage.filter => 'Filter',
    RigPage.focus => tr('Fokus', 'Focus'),
    RigPage.guiding => 'Guiding',
    RigPage.sequence => tr('Sequenz', 'Sequence'),
    RigPage.rotator => 'Rotator',
    RigPage.flat => tr('Flatpanel', 'Flat panel'),
  };

  IconData get icon => switch (this) {
    RigPage.devices => Icons.cable_outlined,
    RigPage.camera => Icons.photo_camera_outlined,
    RigPage.mount => Icons.explore_outlined,
    RigPage.filter => Icons.filter_tilt_shift,
    RigPage.focus => Icons.center_focus_strong_outlined,
    RigPage.guiding => Icons.track_changes,
    RigPage.sequence => Icons.playlist_play,
    RigPage.rotator => Icons.rotate_right,
    RigPage.flat => Icons.light_mode_outlined,
  };

  /// Whether the page belongs on this rig's bar: the rotator and the flat panel only
  /// when the rig has one.
  bool shownFor(RigState rig) => switch (this) {
    RigPage.rotator => rig.rotator.present,
    RigPage.flat => rig.flat.present,
    _ => true,
  };

  /// Whether the device behind the page is disconnected; never for the sequence, which
  /// is not a device. "Geräte" carries it while any of the five main devices is off.
  bool disconnectedIn(RigState rig) => switch (this) {
    RigPage.devices => rig.mainConnected < 5,
    RigPage.camera => !rig.camera.connected,
    RigPage.mount => !rig.mount.connected,
    RigPage.filter => !rig.filterwheel,
    RigPage.focus => !rig.focuser.connected,
    RigPage.guiding => !rig.guider,
    RigPage.sequence => false,
    RigPage.rotator => !rig.rotator.connected,
    RigPage.flat => !rig.flat.connected,
  };
}

class RigDeviceBar extends StatelessWidget {
  const RigDeviceBar({required this.rig, required this.selected, required this.onSelect, this.trailing, super.key});

  final RigState rig;
  final RigPage selected;
  final ValueChanged<RigPage> onSelect;

  /// The overflow at the end of the strip.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final pages = [
      for (final p in RigPage.values)
        if (p.shownFor(rig)) p,
    ];
    return SizedBox(
      height: 84,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              key: const Key('rig-device-bar'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final p in pages)
                  _DeviceButton(
                    page: p,
                    selected: p == selected,
                    disconnected: p.disconnectedIn(rig),
                    onTap: () => onSelect(p),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _DeviceButton extends StatelessWidget {
  const _DeviceButton({required this.page, required this.selected, required this.disconnected, required this.onTap});

  final RigPage page;
  final bool selected;
  final bool disconnected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: disconnected ? '${page.label}, ${tr('nicht verbunden', 'not connected')}' : page.label,
      child: InkWell(
        key: Key('rig-${page.name}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? scheme.primary : Colors.transparent,
                      border: Border.all(color: selected ? scheme.primary : tones.line, width: 1.5),
                    ),
                    child: Icon(page.icon, size: 24, color: selected ? scheme.onPrimary : scheme.onSurface),
                  ),
                  if (disconnected)
                    Positioned(
                      right: -1,
                      top: -1,
                      child: Container(
                        key: Key('rig-badge-${page.name}'),
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tones.danger,
                          border: Border.all(color: scheme.surface, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              ExcludeSemantics(
                child: Text(
                  page.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? scheme.primary : tones.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
