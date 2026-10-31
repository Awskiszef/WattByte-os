// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:home_widget/home_widget.dart';
import 'package:wattbyte_system/wattbyte_system.dart';

import '../analytics/dashboard_model.dart';
import '../core/units.dart';
import '../l10n/generated/app_localizations.dart';

/// Pushes pre-formatted, localized strings to the home-screen widgets.
///
/// Android: `WattByteWidgetProvider` reads them from the home_widget prefs.
/// iOS: the `WattByteWidget` extension reads them from the App Group.
class WidgetPublisher {
  WidgetPublisher([WattByteSystem? system])
      : _system = system ?? WattByteSystem();

  final WattByteSystem _system;

  Future<void> publish({
    required DashboardModel model,
    required Units units,
    required AppLocalizations l10n,
    required String currency,
    required bool hasPrice,
  }) async {
    // iOS: the group comes from the build configuration (see ios/Runner Info.plist), not from a literal.
    final group = await _system.appGroupId();
    if (group != null) await HomeWidget.setAppGroupId(group);
    final values = valuesFor(
      model: model,
      units: units,
      l10n: l10n,
      currency: currency,
      hasPrice: hasPrice,
    );
    for (final e in values.entries) {
      await HomeWidget.saveWidgetData<String>(e.key, e.value);
    }
    await HomeWidget.updateWidget(
      androidName: 'WattByteWidgetProvider',
      qualifiedAndroidName: 'pl.wattbyte.app.WattByteWidgetProvider',
      iOSName: 'WattByteWidget',
    );
  }

  /// The strings the widgets display, keyed like the native providers expect.
  ///
  /// Numbers go through [units] (the same locale logic as the app screens, see
  /// `runBackgroundRefresh`); labels come from [l10n]. Wall energy and cost
  /// always carry the efficiency assumption, hence "~"; a missing price shows
  /// [Units.placeholder], never a made-up zero.
  static Map<String, String> valuesFor({
    required DashboardModel model,
    required Units units,
    required AppLocalizations l10n,
    required String currency,
    required bool hasPrice,
  }) =>
      {
        'data_today': units.approx(units.bytes(model.today.total),
            estimated: model.today.estimated),
        'energy_today': units.approx(units.kwh(model.todayEnergy.wallWhShown),
            estimated: true),
        'cost_today': hasPrice
            ? units.approx(units.money(model.todayEnergy.costShown, currency),
                estimated: true)
            : Units.placeholder,
        'data_month': units.approx(units.bytes(model.month.total),
            estimated: model.month.estimated),
        'cost_month': hasPrice
            ? units.approx(units.money(model.monthEnergy.costShown, currency),
                estimated: true)
            : Units.placeholder,
        'label_data_today': l10n.widgetDataToday,
        'label_energy_today': l10n.widgetEnergyToday,
        'label_cost_today': l10n.widgetCostToday,
        'label_data_month': l10n.widgetMonthlyData,
        'label_cost_month': l10n.widgetMonthlyCost,
        'label_data': l10n.widgetData,
        'label_energy': l10n.widgetEnergy,
        'label_cost': l10n.widgetCost,
      };
}
