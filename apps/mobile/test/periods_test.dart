import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/core/periods.dart';

/// Run under several zones, e.g.
///   TZ=Europe/Warsaw flutter test test/periods_test.dart
///   TZ=America/New_York flutter test test/periods_test.dart
/// DST must never change how many calendar days a period has.
void main() {
  group('LocalDate', () {
    test('counts calendar days across month, year and leap boundaries', () {
      expect(const LocalDate(2026, 1, 31).plusDays(1),
          const LocalDate(2026, 2, 1));
      expect(const LocalDate(2026, 12, 31).plusDays(1),
          const LocalDate(2027, 1, 1));
      expect(const LocalDate(2024, 2, 28).plusDays(1),
          const LocalDate(2024, 2, 29));
      expect(const LocalDate(2024, 2, 28).plusDays(2),
          const LocalDate(2024, 3, 1));
      expect(const LocalDate(2025, 2, 28).plusDays(1),
          const LocalDate(2025, 3, 1));
      expect(const LocalDate(2026, 3, 1).plusDays(-1),
          const LocalDate(2026, 2, 28));
      expect(const LocalDate(2026, 1, 32), isNot(const LocalDate(2026, 1, 1)));
      expect(const LocalDate(2026, 1, 1).daysUntil(const LocalDate(2027, 1, 1)),
          365);
      expect(const LocalDate(2024, 1, 1).daysUntil(const LocalDate(2025, 1, 1)),
          366);
      expect(const LocalDate(2026, 10, 13).key, '2026-10-13');
    });
    test('round-trips through the epoch day', () {
      for (final d in [
        const LocalDate(1970, 1, 1),
        const LocalDate(2000, 2, 29),
        const LocalDate(2026, 3, 29),
        const LocalDate(2026, 10, 25)
      ]) {
        expect(LocalDate.fromEpochDay(d.epochDay), d);
      }
    });
  });

  // `now` values around the 2026 DST changes in Europe and the US.
  final nows = {
    'ordinary': DateTime(2026, 6, 15, 12),
    'after EU spring forward': DateTime(2026, 4, 5, 12),
    'EU spring forward day': DateTime(2026, 3, 29, 12),
    'before EU spring forward': DateTime(2026, 3, 20, 12),
    'EU fall back day': DateTime(2026, 10, 25, 12),
    'after EU fall back': DateTime(2026, 11, 3, 12),
    'after US spring forward': DateTime(2026, 3, 20, 12),
    'leap day': DateTime(2028, 2, 29, 12),
    'year start': DateTime(2026, 1, 1, 9),
    'year end': DateTime(2026, 12, 31, 23, 30),
  };

  group('day counts never depend on DST', () {
    nows.forEach((name, now) {
      test(name, () {
        expect(rangeFor(Period.today, now).days, 1);
        expect(rangeFor(Period.yesterday, now).days, 1);
        expect(rangeFor(Period.last7Days, now).days, 7);
        expect(rangeFor(Period.last30Days, now).days, 30);
        expect(rangeFor(Period.last7Days, now).eachDay, hasLength(7));
        expect(rangeFor(Period.last30Days, now).eachDay, hasLength(30));
        expect(previous7Days(now).days, 7);

        final month = rangeFor(Period.thisMonth, now);
        expect(month.days, DateTime(now.year, now.month + 1, 0).day);
        final last = rangeFor(Period.lastMonth, now);
        expect(last.days, DateTime(now.year, now.month, 0).day);
        final year = rangeFor(Period.thisYear, now);
        expect(year.days, (now.year % 4 == 0) ? 366 : 365);
        expect(year.eachDay, hasLength(year.days));
      });
    });
  });

  test('eachDay lists consecutive local midnights, today last', () {
    final now = DateTime(2026, 4, 5, 12);
    final days = rangeFor(Period.last30Days, now).eachDay;
    expect(days.first, DateTime(2026, 3, 7));
    expect(days.last, DateTime(2026, 4, 5));
    for (var i = 1; i < days.length; i++) {
      expect(LocalDate.of(days[i]).daysUntil(LocalDate.of(days[i - 1])), -1);
      expect(days[i].hour, 0, reason: 'every entry is a local midnight');
    }
  });

  test('named period boundaries', () {
    final now = DateTime(2026, 3, 31, 12);
    expect(rangeFor(Period.thisMonth, now).start, DateTime(2026, 3, 1));
    expect(rangeFor(Period.thisMonth, now).eachDay.last, DateTime(2026, 3, 31));
    expect(rangeFor(Period.lastMonth, now).days, 28);
    expect(rangeFor(Period.thisYear, now).start, DateTime(2026, 1, 1));
    expect(rangeFor(Period.thisWeek, DateTime(2026, 10, 14)).start,
        DateTime(2026, 10, 12));
  });

  test('an empty or inverted range has zero days', () {
    final a = DateTime(2026, 5, 1);
    expect(DateRange(a, a).days, 0);
    expect(DateRange(a, DateTime(2026, 4, 1)).eachDay, isEmpty);
  });
}
