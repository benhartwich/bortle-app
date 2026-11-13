// The pieces every rig page is built from: big, gloved-finger buttons that wait while
// another action runs, rows, notes, number fields, and the page's scrolling list.

import 'package:material_ui/material_ui.dart';

import '../../design.dart';
import '../rig_session.dart';

/// A big, gloved-finger target. Disabled while any action of the session runs.
Widget rigButton(
  RigSession session,
  String key,
  String label,
  VoidCallback? onPressed, {
  bool primary = false,
  Color? color,
}) {
  final style = ButtonStyle(minimumSize: WidgetStateProperty.all(const Size.fromHeight(52)));
  final text = Text(
    session.busy == key ? '…' : label,
    style: TextStyle(fontSize: 15, color: onPressed == null ? null : color),
  );
  final enabled = session.busy == null ? onPressed : null;
  return primary
      ? FilledButton(key: Key(key), style: style, onPressed: enabled, child: text)
      : OutlinedButton(key: Key(key), style: style, onPressed: enabled, child: text);
}

Widget rigRow(List<Widget> children) => Padding(
  padding: const EdgeInsets.only(top: 8),
  child: Row(
    children: [
      for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: c)],
    ],
  ),
);

class RigNote extends StatelessWidget {
  const RigNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(text, style: TextStyle(color: context.tones.muted, fontSize: 12)),
  );
}

class RigHeading extends StatelessWidget {
  const RigHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
  );
}

Widget rigNumberField(TextEditingController c, String label, String key, {String? suffix}) => TextField(
  key: Key(key),
  controller: c,
  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
  decoration: InputDecoration(labelText: label, suffixText: suffix, isDense: true),
);

/// A number as typed, with either decimal separator.
double? parseNumber(String text) => double.tryParse(text.trim().replaceAll(',', '.'));

/// In red light a full-colour picture would undo the whole mode.
Widget redAware(Tones tones, Widget child) => !tones.red
    ? child
    : ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          .3, .4, .1, 0, 0, //
          0, 0, 0, 0, 0,
          0, 0, 0, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: child,
      );

/// One page's content: a pull-to-refresh list, the same padding everywhere.
class RigPageList extends StatelessWidget {
  const RigPageList({required this.session, required this.children, super.key});

  final RigSession session;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: session.poll,
    child: ListView(key: const Key('rig-page'), padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: children),
  );
}

/// A page's first line: what the device says right now.
class RigStatus extends StatelessWidget {
  const RigStatus(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 4),
    child: Text(text, style: const TextStyle(fontSize: 16)),
  );
}

/// Shown on a page whose device NINA reports as not connected.
class RigNotConnected extends StatelessWidget {
  const RigNotConnected(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 4),
    child: Row(
      children: [
        Icon(Icons.link_off, size: 18, color: context.tones.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: context.tones.danger)),
        ),
      ],
    ),
  );
}
