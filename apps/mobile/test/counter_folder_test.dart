import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/collection/counter_folder.dart';

CounterState c(DateTime t, {int wifiRx = 0, int cellRx = 0, int boot = 1000}) =>
    CounterState(
      wifiRx: wifiRx,
      wifiTx: 0,
      cellRx: cellRx,
      cellTx: 0,
      bootTimeMs: boot,
      timeMs: t.millisecondsSinceEpoch,
    );

void main() {
  test('same-day delta lands on that day, flagged estimated', () {
    final out = CounterFolder.fold(
      c(DateTime(2026, 10, 13, 10), wifiRx: 100),
      c(DateTime(2026, 10, 13, 12), wifiRx: 700, cellRx: 50),
    );
    expect(out, hasLength(1));
    expect(out.single.day, DateTime(2026, 10, 13));
    expect(out.single.wifiRx, 600);
    expect(out.single.mobileRx, 50);
    expect(out.single.estimated, isTrue);
  });

  test('spreads across midnight proportionally to time', () {
    final out = CounterFolder.fold(
      c(DateTime(2026, 10, 13, 18), wifiRx: 0),
      c(DateTime(2026, 10, 14, 6), wifiRx: 1200),
    );
    expect(out.map((d) => d.day),
        [DateTime(2026, 10, 13), DateTime(2026, 10, 14)]);
    expect(out[0].wifiRx, 600);
    expect(out[1].wifiRx, 600);
  });

  test('handles a 32-bit wrap and a reboot', () {
    final wrapped = CounterFolder.fold(
      c(DateTime(2026, 10, 13, 10), wifiRx: 4294967000),
      c(DateTime(2026, 10, 13, 11), wifiRx: 1000),
    );
    expect(wrapped.single.wifiRx, 1296);

    final rebooted = CounterFolder.fold(
      c(DateTime(2026, 10, 13, 10), wifiRx: 5000, boot: 1000),
      c(DateTime(2026, 10, 13, 11), wifiRx: 300, boot: 999000),
    );
    expect(rebooted.single.wifiRx, 300);
  });

  test('first sample is a baseline only', () {
    expect(CounterFolder.fold(null, c(DateTime(2026, 10, 13), wifiRx: 10)),
        isEmpty);
  });
}
