// The orchestrator's timeline in words a person reads: a title per kind, the detail with
// the machine parts taken out, runs of the same kind folded into one line, days as headings.
//
// The raw messages are written for the log ("QC accept: 2025-04-28_23-27-24_IR Block_…
// _0038.fits — rule: optical corner aberration"); on a phone that is a wall of filenames.

import 'api/models.dart';
import 'l10n.dart';

/// One line of the list: one event, or several of the same kind in a row. Built from a
/// newest-first list, so [first] is the newest and [last] the oldest.
class EventGroup {
  EventGroup(this.first);

  final BortleEvent first;
  BortleEvent? _last;
  int count = 1;

  BortleEvent get last => _last ?? first;
  String get type => first.type;
  String get severity => first.severity;

  void add(BortleEvent e) {
    _last = e;
    count++;
  }

  String get title => eventTitle(type, count);

  /// What the newest of them said.
  String? get detail => eventDetail(first);

  /// "21:07" or, for a run, "19:23–19:24" (oldest first).
  String get time {
    final a = last.at, b = first.at;
    if (a == null || b == null) return '';
    final from = clock(a.isBefore(b) ? a : b), to = clock(a.isBefore(b) ? b : a);
    return from == to ? from : '$from–$to';
  }
}

/// A day and its lines, newest day first.
class EventDay {
  EventDay(this.day, this.groups);

  final DateTime day;
  final List<EventGroup> groups;

  String label(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return tr('Heute', 'Today');
    if (diff == 1) return tr('Gestern', 'Yesterday');
    final wd = appEnglish
        ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day.weekday - 1]
        : const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'][day.weekday - 1];
    return '$wd, ${dayMonth(day)}';
  }
}

/// Newest first in, days newest first out; within a day consecutive events of one kind
/// share a line. At most [maxLines] lines in all.
List<EventDay> groupEvents(List<BortleEvent> newestFirst, {int maxLines = 8}) {
  final days = <EventDay>[];
  var lines = 0;
  for (final e in newestFirst) {
    final at = e.at?.toLocal();
    if (at == null) continue;
    final day = DateTime(at.year, at.month, at.day);
    if (days.isEmpty || days.last.day != day) {
      if (lines >= maxLines) break;
      days.add(EventDay(day, []));
    }
    final groups = days.last.groups;
    if (groups.isNotEmpty && groups.last.type == e.type) {
      groups.last.add(e);
    } else {
      if (lines >= maxLines) break;
      groups.add(EventGroup(e));
      lines++;
    }
  }
  return days;
}

String eventTitle(String type, int count) {
  final many = count > 1;
  String n(String de, String en) => many ? tr('$count $de', '$count $en') : tr(de, en);
  return switch (type) {
    'frame_captured' => many ? n('Bilder aufgenommen', 'frames captured') : tr('Bild aufgenommen', 'Frame captured'),
    'frame_ingested' => many ? n('Bilder eingelesen', 'frames read in') : tr('Bild eingelesen', 'Frame read in'),
    'frame_accepted' => many ? n('Bilder angenommen', 'frames accepted') : tr('Bild angenommen', 'Frame accepted'),
    'frame_borderline' =>
      many ? n('Bilder grenzwertig', 'frames borderline') : tr('Bild grenzwertig', 'Frame borderline'),
    'frame_rejected' => many ? n('Bilder verworfen', 'frames rejected') : tr('Bild verworfen', 'Frame rejected'),
    'plate_solved' => many ? n('Plate-Solves', 'plate solves') : tr('Position gelöst', 'Plate solved'),
    'autofocus' => many ? n('Autofokus-Läufe', 'autofocus runs') : tr('Autofokus', 'Autofocus'),
    'guiding' => tr('Guiding', 'Guiding'),
    'meridian_flip' => tr('Meridian-Flip', 'Meridian flip'),
    'state_change' => tr('Nacht: neuer Zustand', 'Night: new state'),
    'decision' => many ? n('Entscheidungen', 'decisions') : tr('Entscheidung', 'Decision'),
    'weather_pause' => tr('Wetterpause', 'Weather pause'),
    'target_switch' => tr('Zielwechsel', 'Target switch'),
    'error' => many ? n('Fehler', 'errors') : tr('Fehler', 'Error'),
    _ => type.replaceAll('_', ' '),
  };
}

final _qcPrefix = RegExp(r'^QC (accept|reject|borderline)\s*:\s*', caseSensitive: false);
final _frameNumber = RegExp(r'_(\d{3,5})\.(?:fits?|fit|xisf)\b', caseSensitive: false);
final _fileName = RegExp(r'\S+\.(?:fits?|xisf)\b', caseSensitive: false);

/// The message without what only a log needs: "Bild 0038 · optical corner aberration".
String? eventDetail(BortleEvent e) {
  final message = e.message;
  if (message == null) return null;
  var text = message.replaceFirst(_qcPrefix, '');
  final parts = text.split(' — ');
  final number = _frameNumber.firstMatch(parts.first)?.group(1);
  var head = parts.first.contains(_fileName) || parts.first.contains('.fits')
      ? (number == null ? '' : tr('Bild $number', 'Frame $number'))
      : parts.first;
  var reason = parts.length > 1 ? parts.sublist(1).join(' — ') : '';
  reason = reason.replaceFirst(RegExp(r'^rule:\s*'), '');
  if (reason == 'all checks within thresholds') reason = tr('alle Werte im Rahmen', 'all within limits');
  head = head.trim();
  text = [if (head.isNotEmpty) head, if (reason.isNotEmpty) reason].join(' · ');
  return text.isEmpty ? null : text;
}
