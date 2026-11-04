// Choosing the place one observes from: the phone's coarse location or typed
// coordinates. The tools keep it on the phone; the Plan tab keeps it in the account's
// profile, where Bortle computes visibility from.

import 'package:flutter/material.dart';

import '../l10n.dart';
import 'tools_store.dart';

/// Latitude and longitude typed in; null when cancelled.
Future<Site?> typeSite(BuildContext context, {Site? initial}) {
  final lat = TextEditingController(text: initial == null ? '' : initial.lat.toStringAsFixed(3));
  final lon = TextEditingController(text: initial == null ? '' : initial.lon.toStringAsFixed(3));
  return showDialog<Site>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Standort eingeben', 'Enter a site')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('lat'),
            controller: lat,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(labelText: tr('Breite (Nord +, Süd −)', 'Latitude (north +, south −)')),
          ),
          TextField(
            key: const Key('lon'),
            controller: lon,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(labelText: tr('Länge (Ost +, West −)', 'Longitude (east +, west −)')),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Abbrechen', 'Cancel'))),
        FilledButton(
          key: const Key('site-ok'),
          onPressed: () {
            final a = double.tryParse(lat.text.replaceAll(',', '.'));
            final b = double.tryParse(lon.text.replaceAll(',', '.'));
            if (a == null || b == null || a.abs() > 90 || b.abs() > 180) return;
            Navigator.of(context).pop(Site(a, b));
          },
          child: Text(tr('Übernehmen', 'Use')),
        ),
      ],
    ),
  );
}

/// The two ways to a site, under a sentence saying what it is for.
class SiteChoice extends StatelessWidget {
  const SiteChoice({required this.explanation, required this.onLocate, required this.onType, super.key});

  final String explanation;
  final VoidCallback? onLocate;
  final VoidCallback? onType;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(explanation),
      const SizedBox(height: 16),
      FilledButton.icon(
        key: const Key('site-locate'),
        onPressed: onLocate,
        icon: const Icon(Icons.my_location),
        label: Text(tr('Standort des Telefons verwenden', "Use the phone's location")),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const Key('site-type'),
        onPressed: onType,
        icon: const Icon(Icons.edit_location_alt_outlined),
        label: Text(tr('Breite und Länge eingeben', 'Enter latitude and longitude')),
      ),
    ],
  );
}
