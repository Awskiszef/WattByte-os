import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/collection/session_builder.dart';
import 'package:wattbyte/domain/models.dart';

BatterySample s(int minute, int level, {bool plugged = true, int? charge}) =>
    BatterySample(
      time: DateTime(2026, 10, 13, 18, 0).add(Duration(minutes: minute)),
      level: level,
      plugged: plugged,
      chargeUah: charge,
      voltageMv: 3900,
    );

void main() {
  const builder = SessionBuilder();

  test('closes a session on unplug and keeps the trailing run open', () {
    final r = builder.build([
      s(0, 20, plugged: false),
      s(1, 21, charge: 1000000),
      s(2, 22, charge: 1050000),
      s(22, 80, charge: 3900000),
      s(23, 80, plugged: false),
      s(120, 40),
      s(121, 41),
    ]);
    expect(r.closed, hasLength(1));
    final c = r.closed.single;
    expect(c.startLevel, 21);
    expect(c.endLevel, 80);
    expect(c.duration, const Duration(minutes: 21));
    expect(c.chargeDeltaUah, 2900000);
    expect(c.avgVoltageMv, 3900);
    expect(c.sparse, isTrue); // 20-minute gap inside the run (> sparseGap)
    expect(r.open, hasLength(2));
  });

  test('splits on a level drop between plugged samples, however short the gap',
      () {
    final r = builder.build([
      s(0, 10), s(5, 15),
      s(6, 10), s(10, 14), // drop > 3 points -> new session
      s(11, 14, plugged: false),
    ]);
    expect(r.closed, hasLength(2));
    expect(r.closed.map((c) => c.startLevel), [10, 10]);
    expect(r.open, isEmpty);
  });

  group('a long gap between plugged samples (G-10)', () {
    test(
        'is bridged when the level and the counters did not fall: one sparse session',
        () {
      final r = builder.build([
        s(0, 10, charge: 1000000), s(5, 15, charge: 1200000),
        s(100, 16, charge: 1250000),
        s(105, 20, charge: 1400000), // 95 min later, still plugged
        s(106, 20, plugged: false),
      ]);
      expect(r.closed, hasLength(1));
      final c = r.closed.single;
      expect(c.startLevel, 10);
      expect(c.endLevel, 20);
      expect(c.chargeDeltaUah, 400000);
      expect(c.sparse, isTrue);
    });

    test(
        'with only two plugged samples hours apart the charge between them is a session',
        () {
      // iOS: one reading when the phone went on the charger, one when the app next ran.
      final r = builder.build([s(0, 30), s(8 * 60 + 30, 100)]);
      expect(r.open, hasLength(2));
      final closed = builder.build([
        s(0, 30),
        s(8 * 60 + 30, 100),
        s(8 * 60 + 31, 100, plugged: false)
      ]).closed;
      expect(closed, hasLength(1));
      expect(closed.single.startLevel, 30);
      expect(closed.single.endLevel, 100);
      expect(closed.single.sparse, isTrue);
    });

    test('is a cut when the level fell in between (it was unplugged and used)',
        () {
      final r = builder.build([
        s(0, 60),
        s(5, 62),
        s(200, 55),
        s(205, 58),
        s(206, 58, plugged: false)
      ]);
      expect(r.closed, hasLength(2));
    });

    test('is a cut when a charge counter fell in between', () {
      final r = builder.build([
        s(0, 50, charge: 2000000),
        s(5, 51, charge: 2050000),
        s(200, 52, charge: 1900000),
        s(205, 53, charge: 1950000),
        s(206, 53, plugged: false),
      ]);
      expect(r.closed, hasLength(2));
    });

    test('is a cut when an unplugged reading lies between the two', () {
      final r = builder.build([
        s(0, 40),
        s(5, 45),
        s(6, 45, plugged: false),
        s(200, 45),
        s(205, 50),
        s(206, 50, plugged: false),
      ]);
      expect(r.closed, hasLength(2));
    });
  });

  group('the unplugged reading that ends a session (G-10)', () {
    test(
        'with a higher level is the end of the session (lower bound), also after a single plugged sample',
        () {
      final r = builder.build([s(0, 20), s(9 * 60, 95, plugged: false)]);
      expect(r.closed, hasLength(1));
      expect(r.closed.single.startLevel, 20);
      expect(r.closed.single.endLevel, 95);
      expect(r.closed.single.sparse, isTrue);
      expect(r.open, isEmpty);
    });

    test('with the same or a lower level only closes the run, as before', () {
      final r = builder.build([s(0, 20), s(10, 30), s(11, 30, plugged: false)]);
      expect(r.closed.single.endLevel, 30);
      final r2 =
          builder.build([s(0, 20), s(10, 30), s(11, 28, plugged: false)]);
      expect(r2.closed.single.endLevel, 30);
    });

    test(
        'a quick plug-unplug with a one-point rise inside a minute is still no session',
        () {
      expect(
          builder.build([s(0, 50), s(0, 51, plugged: false)]).closed, isEmpty);
    });
  });

  test('ignores single-sample runs and sub-minute blips', () {
    final r = builder.build([
      s(0, 50), s(1, 50, plugged: false), // single sample: no duration known
      s(2, 50), s(2, 51), s(3, 51, plugged: false), // two samples, 0 min apart
    ]);
    expect(r.closed, isEmpty);
  });

  group('thinning a long charge in progress (G-18)', () {
    List<BatterySample> minuteByMinute(int minutes,
            {int skipFrom = -1, int skipTo = -1}) =>
        [
          for (var m = 0; m < minutes; m++)
            if (m < skipFrom || m > skipTo)
              s(m, 20 + m ~/ 30, charge: 1000000 + m * 100),
        ];

    test(
        'drops most samples of a multi-day plug-in and the session stays the same',
        () {
      final run = minuteByMinute(3 * 24 * 60);
      final drop = SessionBuilder.redundantSamples(run);
      final kept = run.where((x) => !drop.contains(x)).toList();
      expect(kept.length, lessThan(run.length ~/ 10),
          reason: 'about one sample per 15 minutes');
      expect(kept.first, run.first);
      expect(kept.last, run.last);
      // The last 30 minutes are untouched.
      expect(run.sublist(run.length - 31).every(kept.contains), isTrue);

      final end = s(3 * 24 * 60, 100, plugged: false);
      final full = builder.build([...run, end]).closed.single;
      final thin = builder.build([...kept, end]).closed.single;
      expect(thin.start, full.start);
      expect(thin.end, full.end);
      expect(thin.startLevel, full.startLevel);
      expect(thin.endLevel, full.endLevel);
      expect(thin.chargeDeltaUah, full.chargeDeltaUah);
      expect(thin.sparse, full.sparse);
    });

    test('never opens a gap above the sparse gap that was not there', () {
      final run = minuteByMinute(600);
      final drop = SessionBuilder.redundantSamples(run);
      final kept = run.where((x) => !drop.contains(x)).toList();
      for (var i = 1; i < kept.length; i++) {
        expect(kept[i].time.difference(kept[i - 1].time),
            lessThanOrEqualTo(const Duration(minutes: 15)));
      }
    });

    test('keeps both sides of a real gap, so the session is still sparse', () {
      final run = minuteByMinute(600,
          skipFrom: 200, skipTo: 260); // an hour without samples
      final drop = SessionBuilder.redundantSamples(run);
      final kept = run.where((x) => !drop.contains(x)).toList();
      expect(
          kept.contains(run.firstWhere(
              (x) => x.time == run[0].time.add(const Duration(minutes: 199)))),
          isTrue);
      expect(
          kept.contains(run.firstWhere(
              (x) => x.time == run[0].time.add(const Duration(minutes: 261)))),
          isTrue);
      expect(
          builder
              .build([...kept, s(700, 70, plugged: false)])
              .closed
              .single
              .sparse,
          isTrue);
    });

    test('short runs are left alone', () {
      expect(SessionBuilder.redundantSamples(minuteByMinute(2)), isEmpty);
      expect(SessionBuilder.redundantSamples(minuteByMinute(25)), isEmpty);
    });
  });
}
