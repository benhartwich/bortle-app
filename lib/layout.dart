// Phone, tablet, landscape: the Material 3 window size classes the app lays itself out by.
//
// compact  (< 600 dp)  a phone upright: bottom navigation, one page at a time, push.
// medium   (600–840)   a tablet upright, a foldable, a phone on its side: a navigation rail.
// expanded (≥ 840)     a tablet on its side: the rail, and list and detail side by side.
//
// The class is the window's width, not the pane's: a screen inside the shell asks the same
// question the shell does and gets the same answer.

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'design.dart';

enum WindowClass { compact, medium, expanded }

const double mediumMinWidth = 600;
const double expandedMinWidth = 840;

/// From this width on the rail shows its labels beside the icons.
const double extendedRailMinWidth = 1200;

/// What a line of running text is allowed to grow to: about 80 characters.
const double readableMaxWidth = 720;

WindowClass windowClassFor(double width) => width >= expandedMinWidth
    ? WindowClass.expanded
    : width >= mediumMinWidth
    ? WindowClass.medium
    : WindowClass.compact;

extension WindowClassOf on BuildContext {
  WindowClass get windowClass => windowClassFor(MediaQuery.sizeOf(this).width);

  /// List and detail side by side instead of pushing the detail.
  bool get twoPane => windowClass == WindowClass.expanded;
}

/// [base] widened on both sides so the content between stays at most [maxWidth], centred.
/// The scrollable keeps the whole width, so it scrolls from anywhere on a tablet.
class Readable extends StatelessWidget {
  const Readable({required this.base, required this.builder, this.maxWidth = readableMaxWidth, super.key});

  final EdgeInsets base;
  final double maxWidth;
  final Widget Function(BuildContext context, EdgeInsets padding) builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final extra = box.maxWidth.isFinite ? math.max(0.0, (box.maxWidth - base.horizontal - maxWidth) / 2) : 0.0;
      return builder(context, base.copyWith(left: base.left + extra, right: base.right + extra));
    },
  );
}

/// A list on the left at a fixed width, its detail on the right in the rest.
class TwoPane extends StatelessWidget {
  const TwoPane({required this.list, required this.detail, this.listWidth = 400, super.key});

  final Widget list;
  final Widget detail;
  final double listWidth;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(width: listWidth, child: list),
      VerticalDivider(width: 1, thickness: 1, color: context.tones.line),
      Expanded(child: detail),
    ],
  );
}

/// The detail pane before anything is chosen in the list.
class NothingChosen extends StatelessWidget {
  const NothingChosen({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    key: const Key('nothing-chosen'),
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: context.tones.muted),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.tones.muted),
          ),
        ],
      ),
    ),
  );
}
