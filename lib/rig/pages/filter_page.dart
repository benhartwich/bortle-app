// Rig › Filter: the wheel's own names, the current one not a choice, empty slots left out.

import 'package:material_ui/material_ui.dart';

import '../../api/bortle_client.dart';
import '../../l10n.dart';
import '../rig_models.dart';
import '../rig_session.dart';
import 'common.dart';

class FilterPage extends StatefulWidget {
  const FilterPage({required this.session, required this.rig, super.key});

  final RigSession session;
  final RigState rig;

  @override
  State<FilterPage> createState() => _FilterPageState();
}

class _FilterPageState extends State<FilterPage> {
  FilterWheel? _filters;

  RigSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _loadFilters();
  }

  Future<void> _loadFilters() async {
    try {
      final wheel = FilterWheel.fromJson(await _s.client.rigFilters());
      if (mounted) setState(() => _filters = wheel);
    } on BortleError catch (e) {
      if (mounted) RigSession.say(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wheel = _filters;
    return RigPageList(
      session: _s,
      children: [
        RigStatus(
          wheel?.current ??
              (widget.rig.filterwheel ? tr('verbunden', 'connected') : tr('nicht verbunden', 'not connected')),
        ),
        const SizedBox(height: 8),
        if (wheel == null)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (!wheel.connected)
          RigNote(tr('Das Filterrad ist nicht verbunden.', 'The filter wheel is not connected.'))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in wheel.names)
                SizedBox(
                  height: 52,
                  child: name == wheel.current
                      ? FilledButton(key: Key('filter-$name'), onPressed: null, child: Text(name))
                      : OutlinedButton(
                          key: Key('filter-$name'),
                          onPressed: _s.busy != null || wheel.moving
                              ? null
                              : () => _s.run(
                                  context,
                                  'filter-$name',
                                  'filter',
                                  params: {'filter': name},
                                  ask: (
                                    tr('Filter wechseln?', 'Change the filter?'),
                                    tr(
                                      'Das Filterrad dreht auf „$name“. Läuft eine Sequenz, wechselt sie den Filter vielleicht gleich zurück.',
                                      'The wheel turns to “$name”. If a sequence runs, it may change the filter right back.',
                                    ),
                                    tr('Wechseln', 'Change'),
                                  ),
                                  after: _loadFilters,
                                ),
                          child: Text(name),
                        ),
                ),
            ],
          ),
      ],
    );
  }
}
