// Small pieces every screen uses.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'api/bortle_client.dart';
import 'design.dart';
import 'l10n.dart';

/// A preview from the server, fetched with this device's token.
class ServerImage extends StatefulWidget {
  const ServerImage({required this.client, required this.path, this.fit = BoxFit.cover, super.key});

  final BortleClient client;
  final String path;
  final BoxFit fit;

  @override
  State<ServerImage> createState() => _ServerImageState();
}

class _ServerImageState extends State<ServerImage> {
  late Future<Uint8List> _bytes = widget.client.dataBytes(widget.path);

  @override
  void didUpdateWidget(ServerImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.client != widget.client) _bytes = widget.client.dataBytes(widget.path);
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) {
          return ColoredBox(
            color: tones.surface,
            child: snap.hasError ? Center(child: Icon(Icons.image_not_supported_outlined, color: tones.muted)) : null,
          );
        }
        final image = Image.memory(bytes, fit: widget.fit, gaplessPlayback: true);
        // In red light a full-colour picture would undo the whole mode.
        if (!tones.red) return image;
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            .3, .4, .1, 0, 0, //
            0, 0, 0, 0, 0,
            0, 0, 0, 0, 0,
            0, 0, 0, 1, 0,
          ]),
          child: image,
        );
      },
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {this.trailing, super.key});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Row(
      children: [
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
        ?trailing,
      ],
    ),
  );
}

/// A failed load, said plainly, with a way to try again.
class LoadError extends StatelessWidget {
  const LoadError(this.error, {required this.onRetry, super.key});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cloud_off_outlined, color: context.tones.muted, size: 36),
        const SizedBox(height: 12),
        Text(
          error is BortleError ? '$error' : tr('Laden fehlgeschlagen', 'Loading failed'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: Text(tr('Erneut versuchen', 'Try again'))),
      ],
    ),
  );
}

/// A small coloured dot that says a state without words; always paired with a label.
class StateDot extends StatelessWidget {
  const StateDot(this.color, {super.key});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Ask before anything that cannot be taken back.
Future<bool> confirm(BuildContext context, String title, String text, String action) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Zurück', 'Back'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
      ],
    ),
  );
  return ok ?? false;
}

/// The readable name of a processing step ("gradient_per_session" → "gradient per session").
String opLabel(String op) => op.replaceAll('_', ' ');
