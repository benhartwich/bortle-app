import 'package:bortle_app/api/models.dart';
import 'package:bortle_app/events.dart';
import 'package:flutter_test/flutter_test.dart';

BortleEvent ev(String type, String at, [String? message, String severity = 'info']) =>
    BortleEvent.fromJson({'type': type, 'severity': severity, 'timestamp': at, 'message': message});

void main() {
  test('a QC message loses its filename and keeps what matters', () {
    final e = ev(
      'frame_accepted',
      '2026-10-12T19:24:50Z',
      'QC accept: 2025-04-28_23-27-24_IR Block_-15.10_180.00s_100g_7368fc_432st_0038.fits — rule: optical corner aberration',
    );
    expect(eventDetail(e), 'Bild 0038 · optical corner aberration');
    final ok = ev('frame_accepted', '2026-10-12T19:24:50Z', 'QC accept: x_0031.fits — all checks within thresholds');
    expect(eventDetail(ok), 'Bild 0031 · alle Werte im Rahmen');
    expect(
      eventDetail(ev('autofocus', '2026-10-12T20:51:00Z', 'Autofokus 11820, Kurve gültig')),
      'Autofokus 11820, Kurve gültig',
    );
  });

  test('runs of one kind fold into one line, days become headings', () {
    // newest first, as the client returns them
    final events = [
      ev('frame_accepted', '2026-10-12T19:24:50Z', 'QC accept: a_0038.fits — ok'),
      ev('frame_accepted', '2026-10-12T19:24:38Z', 'QC accept: a_0037.fits — ok'),
      ev('frame_accepted', '2026-10-12T19:23:05Z', 'QC accept: a_0026.fits — ok'),
      ev('autofocus', '2026-10-12T18:51:00Z', 'done'),
      ev('frame_rejected', '2026-10-11T23:00:00Z', 'QC reject: a_0010.fits — clouds'),
    ];
    final days = groupEvents(events);
    expect(days, hasLength(2));
    final first = days.first.groups;
    expect(first, hasLength(2));
    expect(first.first.count, 3);
    expect(first.first.title, '3 Bilder angenommen');
    expect(first.first.detail, 'Bild 0038 · ok');
    expect(first.first.time, matches(RegExp(r'^\d\d:23–\d\d:24$')));
    expect(days.last.groups.single.title, 'Bild verworfen');
    expect(days.first.label(DateTime(2026, 10, 12, 23)), 'Heute');
    expect(days.last.label(DateTime(2026, 10, 12, 23)), 'Gestern');
    expect(days.last.label(DateTime(2026, 10, 20)), 'So, 11.10.');
  });

  test('the list stops after the given number of lines', () {
    final events = [
      for (var i = 0; i < 20; i++)
        ev(i.isEven ? 'autofocus' : 'plate_solved', '2026-10-12T${(20 - i ~/ 2).toString().padLeft(2, '0')}:00:00Z'),
    ];
    final days = groupEvents(events, maxLines: 5);
    expect(days.expand((d) => d.groups), hasLength(5));
  });
}
