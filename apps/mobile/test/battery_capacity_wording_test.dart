// The words the user reads decide whether an estimate is mistaken for the
// nominal capacity. These tests pin the literal English and Polish wording
// (other tests build their expectations from the same l10n getters, so they
// could not notice a copy edit that drops "Estimated").
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/l10n/generated/app_localizations_pl.dart';
import 'package:wattbyte/ui/settings/setup_editors.dart';

import 'accessibility/flow_matrix_support.dart' show resetAssetCache;
import 'support/app_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  setUp(resetAssetCache);

  final en = AppLocalizationsEn();
  final pl = AppLocalizationsPl();

  test('the estimate is always called an estimate, in both languages', () {
    expect(en.estimatedFullChargeCapacity, 'Estimated full charge capacity');
    expect(
        en.estimatedFullChargeCapacityBody('high'), startsWith('Estimated '));
    expect(en.estimatedFullChargeCapacityBody('high'), contains('high'));
    expect(pl.estimatedFullChargeCapacity,
        'Szacowana pojemność przy pełnym naładowaniu');
    expect(pl.estimatedFullChargeCapacityBody('wysoka'),
        startsWith('Oszacowano '));
    expect(pl.estimatedFullChargeCapacityBody('wysoka'), contains('wysoka'));
    // And it is never named like the nominal capacity.
    for (final text in [
      en.estimatedFullChargeCapacity,
      pl.estimatedFullChargeCapacity,
    ]) {
      expect(text, isNot(equals(en.batteryCapacity)));
      expect(text, isNot(equals(pl.batteryCapacity)));
    }
  });

  test(
      'the unavailable wording does not promise a number the system could give',
      () {
    expect(en.capacityUnavailable, 'Battery capacity unavailable');
    expect(en.capacityUnavailableBody,
        'This model is not in the device database.');
    expect(en.capacityUnavailableBody.toLowerCase(), isNot(contains('system')));
    expect(pl.capacityUnavailableBody.toLowerCase(), isNot(contains('system')));
  });

  testWidgets(
      'every design source has its own label; only "manual" says chosen '
      'manually', (tester) async {
    late BuildContext context;
    await pumpScreen(
      tester,
      Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }),
      scaffold: true,
    );
    final labels = {
      for (final s in DesignCapacitySource.values)
        s: capacitySourceText(context, s),
    };
    expect(labels[DesignCapacitySource.localDeviceDatabase],
        'Detected from device specifications');
    expect(labels[DesignCapacitySource.backendDeviceDatabase],
        'From the WattByte device database');
    expect(labels[DesignCapacitySource.manufacturerSpecification],
        "From the manufacturer's specification");
    expect(labels[DesignCapacitySource.manual], 'Chosen manually');
    expect(labels[DesignCapacitySource.unknown],
        'This model is not in the device database.');
    expect(labels.values.toSet(), hasLength(DesignCapacitySource.values.length),
        reason: 'no two sources share a label');
  });
}
