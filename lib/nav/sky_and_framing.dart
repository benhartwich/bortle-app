// The ways into the sky map and the framing, so every screen opens them the
// same way: the sky map's "Einrahmen" leads into the framing.

import 'package:material_ui/material_ui.dart';

import '../api/bortle_client.dart';
import '../l10n.dart';
import '../framing/framing_screen.dart';
import '../sky/sky_map_screen.dart';

void openSkyMap(BuildContext context, BortleClient client, {String? highlight}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (ctx) => SkyMapScreen(
        client: client,
        highlightTarget: highlight,
        onFrame: (name, ra, dec) => openFraming(ctx, client, name, ra, dec),
      ),
    ),
  );
}

/// An app-bar button that opens the sky map.
Widget skyMapButton(BuildContext context, BortleClient client) => IconButton(
  key: const ValueKey('open-sky-map'),
  tooltip: tr('Himmelskarte', 'Sky map'),
  onPressed: () => openSkyMap(context, client),
  icon: const Icon(Icons.travel_explore),
);
