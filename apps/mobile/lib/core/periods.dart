// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

/// Calendar periods used by the dashboard, statistics and insights.
enum Period {
  today,
  yesterday,
  last7Days,
  last30Days,
  thisWeek,
  thisMonth,
  lastMonth,
  thisYear,
  allTime,
}

/// A calendar day (year, month, day) with no time and no zone.
///
/// Calendar arithmetic must never go through `Duration`: a local day is 23 or
/// 25 hours long on a daylight-saving change, so `end.difference(start).inDays`
/// loses a day. `LocalDate` counts days on the proleptic Gregorian calendar.
class LocalDate implements Comparable<LocalDate> {
  const LocalDate(this.year, this.month, this.day);

  factory LocalDate.of(DateTime t) => LocalDate(t.year, t.month, t.day);

  final int year;
  final int month;
  final int day;

  /// Day count since 1970-01-01, independent of any time zone.
  int get epochDay =>
      DateTime.utc(year, month, day).millisecondsSinceEpoch ~/ 86400000;

  static LocalDate fromEpochDay(int n) => LocalDate.of(
      DateTime.fromMillisecondsSinceEpoch(n * 86400000, isUtc: true));

  /// Overflowing months and days roll over (`LocalDate(2026, 1, 32)` is 1 Feb).
  LocalDate plusDays(int n) => fromEpochDay(epochDay + n);

  int daysUntil(LocalDate other) => other.epochDay - epochDay;

  /// Local midnight of this day (the first instant of the day in the device zone).
  DateTime get midnight => DateTime(year, month, day);

  String get key => dayKey(midnight);

  @override
  int compareTo(LocalDate other) => epochDay.compareTo(other.epochDay);

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => key;
}

/// Half-open range of local instants: `[start, end)`.
///
/// `start` and `end` are local midnights. Instants answer "is this timestamp
/// inside?" ([contains]); calendar days answer "how many days?" ([days],
/// [eachDay]) and are computed with [LocalDate], so DST never changes them.
class DateRange {
  const DateRange(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);

  /// Calendar days in `[start, end)`; 0 for an empty or inverted range.
  int get days {
    final n = LocalDate.of(start).daysUntil(LocalDate.of(end));
    return n < 0 ? 0 : n;
  }

  /// Every local midnight inside the range, oldest first.
  List<DateTime> get eachDay {
    final first = LocalDate.of(start);
    return [for (var i = 0; i < days; i++) first.plusDays(i).midnight];
  }
}

DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

String _pad(int v, int w) => v.toString().padLeft(w, '0');

/// `yyyy-MM-dd` key for storage and grouping.
String dayKey(DateTime d) =>
    '${_pad(d.year, 4)}-${_pad(d.month, 2)}-${_pad(d.day, 2)}';

DateTime parseDayKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

String monthKey(DateTime d) => '${_pad(d.year, 4)}-${_pad(d.month, 2)}';

DateRange rangeFor(Period p, DateTime now) {
  final today = dayOf(now);
  DateTime shift(int days) =>
      DateTime(today.year, today.month, today.day + days);
  switch (p) {
    case Period.today:
      return DateRange(today, shift(1));
    case Period.yesterday:
      return DateRange(shift(-1), today);
    case Period.last7Days:
      return DateRange(shift(-6), shift(1));
    case Period.last30Days:
      return DateRange(shift(-29), shift(1));
    case Period.thisWeek:
      return DateRange(shift(-(today.weekday - 1)), shift(1));
    case Period.thisMonth:
      return DateRange(DateTime(today.year, today.month),
          DateTime(today.year, today.month + 1));
    case Period.lastMonth:
      return DateRange(DateTime(today.year, today.month - 1),
          DateTime(today.year, today.month));
    case Period.thisYear:
      return DateRange(DateTime(today.year), DateTime(today.year + 1));
    case Period.allTime:
      return DateRange(DateTime(1970), shift(1));
  }
}

/// The 7 days before [Period.last7Days]; used for week-over-week insights.
DateRange previous7Days(DateTime now) {
  final cur = rangeFor(Period.last7Days, now);
  return DateRange(
      DateTime(cur.start.year, cur.start.month, cur.start.day - 7), cur.start);
}
