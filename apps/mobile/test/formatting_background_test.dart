// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/analytics/dashboard_model.dart';
import 'package:wattbyte/analytics/notification_rules.dart';
import 'package:wattbyte/background/app_notifier.dart';
import 'package:wattbyte/background/background_tasks.dart';
import 'package:wattbyte/background/widget_publisher.dart';
import 'package:wattbyte/core/units.dart';
import 'package:wattbyte/domain/models.dart';

/// Widget and notification text is produced in the background isolate from the
/// raw device locale tag; it has to read and format exactly like the screens.
const nb = '\u00A0';

PendingNotification pending(NotificationKind k, double v) =>
    PendingNotification(k, 'k:${k.name}', v);

DashboardModel model({
  double todayCost = 0.0052,
  double monthCost = 1.4145,
  double todayWallWh = 4.53,
}) {
  final day = DateTime(2026, 10, 13);
  return DashboardModel(
    today: DailyData(day: day, mobileRx: 1000000000, wifiRx: 1840000000),
    todayEnergy: SessionEnergy(
      mah: 1000,
      mahEstimated: true,
      batteryWh: 3.85,
      whEstimated: true,
      wallWh: todayWallWh,
      cost: todayCost,
    ),
    chargingNow: false,
    inProgress: null,
    last30: const [],
    energyLast30: const [],
    month: DailyData(
        day: DateTime(2026, 10, 1),
        mobileRx: 5000000000,
        wifiRx: 16440000000,
        estimated: true),
    monthEnergy: SessionEnergy(
      mah: 9000,
      mahEstimated: true,
      batteryWh: 34,
      whEstimated: true,
      wallWh: 40,
      cost: monthCost,
    ),
  );
}

void main() {
  group('device tag -> what the background isolate formats with', () {
    test('Polish device', () {
      final t = backgroundText('pl_PL', binaryUnits: false);
      expect(t.l10n.localeName, 'pl');
      expect(t.units.locale, 'pl');
      expect(t.units.money(0.021, 'PLN'), '0,021${nb}zł');
    });

    test('English device with a Polish region reads as English', () {
      final t = backgroundText('en_PL', binaryUnits: false);
      expect(t.l10n.localeName, 'en');
      expect(t.units.locale, 'en');
      expect(t.units.money(0.021, 'PLN'), 'zł${nb}0.021');
      expect(t.units.bytes(2840000000), '2.84 GB');
    });

    test('unsupported language and no recorded tag fall back to English', () {
      for (final tag in ['de_DE', 'fr-FR', '', 'garbage', null]) {
        final t = backgroundText(tag, binaryUnits: false);
        expect(t.l10n.localeName, 'en', reason: '$tag');
        // English text with English separators, never German ones.
        expect(t.units.bytes(2840000000), '2.84 GB', reason: '$tag');
      }
    });

    test('the binary-units setting is carried over', () {
      expect(backgroundText('pl_PL', binaryUnits: true).units.bytes(1073741824),
          '1,00 GiB');
    });

    test('localizationsFor accepts every device tag shape', () {
      expect(localizationsFor('pl').localeName, 'pl');
      expect(localizationsFor('pl_PL').localeName, 'pl');
      expect(localizationsFor('pl-PL').localeName, 'pl');
      expect(localizationsFor('en_PL').localeName, 'en');
      expect(localizationsFor('de_DE').localeName, 'en');
      expect(localizationsFor('').localeName, 'en');
    });
  });

  group('notification text', () {
    final plText = backgroundText('pl_PL', binaryUnits: false);
    final enText = backgroundText('en_PL', binaryUnits: false);

    test('mobile threshold uses the locale for the amount', () {
      final n = pending(NotificationKind.mobileThreshold, 5100000000);
      expect(AppNotifier.textFor(n, plText.l10n, plText.units),
          ('Dane komórkowe', 'Dziś zużyto 5,10 GB danych komórkowych.'));
      expect(AppNotifier.textFor(n, enText.l10n, enText.units),
          ('Mobile data', "You've used 5.10 GB of mobile data today."));
    });

    test('weekly energy uses kWh in the locale', () {
      final n = pending(NotificationKind.weeklyEnergy, 1.23); // kWh
      expect(AppNotifier.textFor(n, plText.l10n, plText.units), (
        'Energia w tym tygodniu',
        'W tym tygodniu telefon zużył około 1,23 kWh.'
      ));
      expect(AppNotifier.textFor(n, enText.l10n, enText.units), (
        'Weekly energy',
        'This week your phone used approximately 1.23 kWh.'
      ));
    });

    test('percent above average is grouped by the locale too', () {
      final n = pending(NotificationKind.aboveWeeklyAverage, 1300);
      expect(AppNotifier.textFor(n, plText.l10n, plText.units)!.$2,
          contains('o 1${nb}300%'));
      expect(AppNotifier.textFor(n, enText.l10n, enText.units)!.$2,
          contains('used 1,300% more'));
      final small = pending(NotificationKind.aboveWeeklyAverage, 34.6);
      expect(AppNotifier.textFor(small, enText.l10n, enText.units)!.$2,
          contains('used 35% more'));
    });

    test('charging done has fixed text in both languages', () {
      final n = pending(NotificationKind.chargingDone, 1234);
      expect(AppNotifier.textFor(n, plText.l10n, plText.units), (
        'Sesja ładowania zakończona',
        'Otwórz WattByte, aby zobaczyć, ile energii dodano.'
      ));
      expect(AppNotifier.textFor(n, enText.l10n, enText.units)!.$1,
          'Charging session completed');
    });

    test('a number that does not exist produces no notification', () {
      for (final kind in [
        NotificationKind.mobileThreshold,
        NotificationKind.weeklyEnergy,
        NotificationKind.aboveWeeklyAverage,
      ]) {
        for (final bad in [double.nan, double.infinity]) {
          expect(
              AppNotifier.textFor(
                  pending(kind, bad), enText.l10n, enText.units),
              isNull,
              reason: '$kind $bad');
        }
      }
    });

    test('Android channel strings exist in both languages', () {
      expect(plText.l10n.notifChannelName, isNotEmpty);
      expect(enText.l10n.notifChannelName, isNotEmpty);
      expect(plText.l10n.notifChannelDescription, isNotEmpty);
      expect(plText.l10n.notifChannelName, isNot(enText.l10n.notifChannelName));
    });
  });

  group('home-widget text', () {
    test('Polish: numbers, labels and "~" for estimates', () {
      final t = backgroundText('pl_PL', binaryUnits: false);
      final v = WidgetPublisher.valuesFor(
        model: model(),
        units: t.units,
        l10n: t.l10n,
        currency: 'PLN',
        hasPrice: true,
      );
      expect(v['data_today'], '2,84 GB'); // measured: no "~"
      expect(v['energy_today'], '~0,0045 kWh');
      expect(v['cost_today'], '~0,005${nb}zł');
      expect(v['data_month'], '~21,44 GB'); // estimated data
      expect(v['cost_month'], '~1,41${nb}zł');
      expect(v['label_data_today'], 'Dane dzisiaj');
      expect(v['label_cost'], 'Koszt');
    });

    test('English device with a Polish region: English text and separators',
        () {
      final t = backgroundText('en_PL', binaryUnits: false);
      final v = WidgetPublisher.valuesFor(
        model: model(),
        units: t.units,
        l10n: t.l10n,
        currency: 'PLN',
        hasPrice: true,
      );
      expect(v['data_today'], '2.84 GB');
      expect(v['energy_today'], '~0.0045 kWh');
      expect(v['cost_today'], '~zł${nb}0.005');
      expect(v['cost_month'], '~zł${nb}1.41');
      expect(v['label_data_today'], 'Data today');
    });

    test('US dollars in English', () {
      final t = backgroundText('en_US', binaryUnits: false);
      final v = WidgetPublisher.valuesFor(
        model: model(),
        units: t.units,
        l10n: t.l10n,
        currency: 'USD',
        hasPrice: true,
      );
      expect(v['cost_today'], '~\$0.005');
      expect(v['cost_month'], '~\$1.41');
    });

    test('no price: a dash, not an invented zero', () {
      final t = backgroundText('pl_PL', binaryUnits: false);
      final v = WidgetPublisher.valuesFor(
        model: model(),
        units: t.units,
        l10n: t.l10n,
        currency: 'PLN',
        hasPrice: false,
      );
      expect(v['cost_today'], Units.placeholder);
      expect(v['cost_month'], Units.placeholder);
      expect(v['energy_today'], '~0,0045 kWh');
    });

    test('a cost below the resolution is "<", never "~0"', () {
      final t = backgroundText('pl_PL', binaryUnits: false);
      final v = WidgetPublisher.valuesFor(
        model: model(todayCost: 0.0001),
        units: t.units,
        l10n: t.l10n,
        currency: 'PLN',
        hasPrice: true,
      );
      expect(v['cost_today'], '<0,001${nb}zł');
    });

    test('every value is a clean string, whatever the inputs', () {
      final t = backgroundText('en_PL', binaryUnits: false);
      final v = WidgetPublisher.valuesFor(
        model: model(
            todayCost: double.nan,
            monthCost: double.infinity,
            todayWallWh: double.nan),
        units: t.units,
        l10n: t.l10n,
        currency: 'PLN',
        hasPrice: true,
      );
      expect(v['cost_today'], Units.placeholder);
      expect(v['cost_month'], Units.placeholder);
      expect(v['energy_today'], Units.placeholder);
      for (final s in v.values) {
        expect(s, isNot(contains('NaN')));
        expect(s, isNot(contains('Infinity')));
        expect(s, isNot(contains('~—')));
      }
    });
  });
}
