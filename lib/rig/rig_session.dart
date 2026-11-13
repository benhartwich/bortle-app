// What every rig page shares: the live snapshot, the one action that runs right now,
// and how an action is run (ask first, say what NINA answered, read the rig again).
//
// The rules the cockpit follows, kept here:
// - anything that moves hardware asks first; a refusal is shown in NINA's or Bortle's
//   own words and never retried behind the user's back;
// - the same bounds: a test exposure 0–120 s, nudges of 1–30′, focuser steps of at most
//   1000 and never below position 0, no focuser move while an autofocus runs;
// - disconnecting is not the reversible twin of connecting (the Lacerta focuser had to
//   be power-cycled on 2026-08-13), so it says so and sends confirm=true only then.

import 'package:material_ui/material_ui.dart';

import '../api/bortle_client.dart';
import '../l10n.dart';
import '../widgets.dart';
import 'rig_models.dart';

class RigSession extends ChangeNotifier {
  RigSession(this.client);

  final BortleClient client;

  RigState? rig;
  Object? error;

  /// The action running right now; every other button waits for it.
  String? _busy;
  String? get busy => _busy;
  set busy(String? key) {
    _busy = key;
    notifyListeners();
  }

  bool _disposed = false;

  Future<void> poll() async {
    try {
      final next = RigState.fromJson(await client.rigLive());
      if (_disposed) return;
      rig = next;
      error = null;
    } on BortleError catch (e) {
      if (_disposed) return;
      error = e;
    }
    notifyListeners();
  }

  /// The newest answer replaces the last one at once instead of queueing behind it.
  static void say(BuildContext context, String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// One of NINA's operations: ask first (unless [ask] is null), run it, say what NINA
  /// answered, read the rig again. A refusal is the server's words, never retried.
  Future<Map?> run(
    BuildContext context,
    String key,
    String action, {
    Map<String, Object?> params = const {},
    (String, String, String)? ask,
    Duration? timeout,
    Future<void> Function()? after,
  }) async {
    if (ask != null) {
      final ok = await confirm(context, ask.$1, ask.$2, ask.$3);
      if (!ok || !context.mounted) return null;
    }
    busy = key;
    try {
      final result = await client.rigControl(action, params, timeout: timeout);
      if (context.mounted) say(context, tr('NINA hat es angenommen.', 'NINA accepted it.'));
      return result;
    } on BortleError catch (e) {
      if (context.mounted) say(context, e.message);
      return null;
    } finally {
      if (!_disposed) busy = null;
      await poll();
      if (after != null && context.mounted) await after();
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
