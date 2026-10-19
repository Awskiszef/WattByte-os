// lib/app.dart honours the system text scale in full. There used to be a
// MediaQuery.withClampedTextScaling(maxScaleFactor: 1.35) around the whole app
// because the Dashboard broke with big text; the layouts now adapt instead
// (see the other tests in this directory), and this file proves the clamp is
// gone, in the REAL app tree.
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/app.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/ui/dashboard/dashboard_screen.dart';

import '../support/app_harness.dart';
import 'shared_widgets_checks.dart';

final _en = AppLocalizationsEn();

/// What a screen inside the real app sees as "10 logical pixels of text".
class _Probe extends StatelessWidget {
  const _Probe(this.onBuild);

  final void Function(TextScaler) onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild(MediaQuery.textScalerOf(context));
    return const Scaffold(body: Text('probe'));
  }
}

void main() {
  testWidgets('at 3.0x a screen inside the real app sees 30, not 13.5',
      (tester) async {
    TextScaler? seen;
    await pumpApp(tester, textScale: 3.0, home: _Probe((s) => seen = s));
    expect(seen, isNotNull);
    expect(seen!.scale(10), closeTo(30, 1e-9));
    expect(tester.platformDispatcher.textScaleFactor, 3.0);
  });

  testWidgets('every size up to the largest iOS accessibility size arrives',
      (tester) async {
    TextScaler? seen;
    final h = await pumpApp(tester, home: _Probe((s) => seen = s));
    for (final scale in [...kTextScales, 2.35, 2.76, 3.12]) {
      await h.setTextScale(tester, scale);
      expect(seen!.scale(10), closeTo(10 * scale, 1e-9),
          reason: 'text scale $scale');
    }
  });

  testWidgets('Android 2.0x arrives too', (tester) async {
    TextScaler? seen;
    await pumpApp(tester,
        textScale: 2.0,
        platform: HarnessPlatform.android,
        home: _Probe((s) => seen = s));
    expect(seen!.scale(10), closeTo(20, 1e-9));
  });

  testWidgets('text never renders smaller than the design size (minimum 1.0)',
      (tester) async {
    TextScaler? seen;
    final h = await pumpApp(tester, home: _Probe((s) => seen = s));
    for (final scale in [0.8, 0.85, 1.0]) {
      await h.setTextScale(tester, scale);
      expect(seen!.scale(10), closeTo(10, 1e-9), reason: 'system $scale');
    }
  });

  testWidgets('the real Dashboard is really three times as large at 3.0x',
      (tester) async {
    final h = await pumpApp(tester);
    double titleHeight() => tester.getSize(find.text(_en.dataUsed)).height;
    final normal = titleHeight();
    await h.setTextScale(tester, 3.0);
    expect(titleHeight(), closeTo(normal * 3, normal * 0.2),
        reason: 'not capped at 1.35x');
    // And nothing broke on the way: the dashboard fits at 3.0x.
    expect(overflowProblems(tester, within: find.byType(DashboardScreen)),
        isEmpty);
    expect(textProblems(tester, within: find.byType(DashboardScreen)), isEmpty);
  });

  testWidgets('WattByteApp(home:) mounts a screen in the real MaterialApp',
      (tester) async {
    final h = await AppHarness.create(tester);
    await h.configure(tester, textScale: 2.0, andSettle: false);
    TextScaler? seen;
    await tester.pumpWidget(ProviderScope(
      overrides: h.overrides,
      child: WattByteApp(home: _Probe((s) => seen = s)),
    ));
    await tester.pump();
    expect(find.text('probe'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing,
        reason: 'the start gate was replaced');
    expect(seen!.scale(10), closeTo(20, 1e-9));
    // flutter_test requires the platform override to be gone when a test ends;
    // the harness only releases it when ITS root widget is unmounted.
    debugDefaultTargetPlatformOverride = null;
  });
}
