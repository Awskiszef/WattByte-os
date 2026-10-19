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

  test('splits on a long gap or a level drop between plugged samples', () {
    final r = builder.build([
      s(0, 10), s(5, 15),
      s(100, 16), s(105, 20), // gap > 30 min -> new session
      s(106, 10), s(110, 14), // drop > 3 points -> new session
      s(111, 14, plugged: false),
    ]);
    expect(r.closed, hasLength(3));
    expect(r.closed.map((c) => c.startLevel), [10, 16, 10]);
    expect(r.open, isEmpty);
  });

  test('ignores single-sample runs and sub-minute blips', () {
    final r = builder.build([
      s(0, 50), s(1, 50, plugged: false), // single sample: no duration known
      s(2, 50), s(2, 51), s(3, 51, plugged: false), // two samples, 0 min apart
    ]);
    expect(r.closed, isEmpty);
  });
}
