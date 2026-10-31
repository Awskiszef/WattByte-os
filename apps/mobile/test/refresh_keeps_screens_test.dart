// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// Every refresh tick (a minute) re-reads the data. The screens keep what they show while it is read again: no spinner in
// place of the content, the scroll position and the answer on screen survive (audit F-02, G-03).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/providers.dart';
import 'package:wattbyte/ui/dashboard/dashboard_screen.dart';
import 'package:wattbyte/ui/history/history_screen.dart';
import 'package:wattbyte/ui/insights/insights_screen.dart';
import 'package:wattbyte/ui/statistics/statistics_screen.dart';
import 'package:wattbyte/ui/widgets/wb_widgets.dart';

import 'support/app_harness.dart';

void main() {
  final screens = <String, Widget Function()>{
    'Dashboard': () => const DashboardScreen(),
    'History': () => const HistoryScreen(),
    'Insights': () => const InsightsScreen(),
    'Statistics': () => const StatisticsScreen(),
  };

  for (final entry in screens.entries) {
    testWidgets(
        '${entry.key}: a refresh tick shows no spinner and keeps the scroll position',
        (tester) async {
      final h = await AppHarness.create(tester,
          platform: HarnessPlatform.android, historyDays: 45);
      await pumpScreen(tester, entry.value(), harness: h, scaffold: true);
      expect(find.byType(WbProgress), findsNothing, reason: 'loaded');

      final scrollable = find.byType(Scrollable).first;
      double offset() =>
          tester.state<ScrollableState>(scrollable).position.pixels;
      await tester.drag(scrollable, const Offset(0, -300));
      await tester.pumpAndSettle();
      final before = offset();

      final container = h.container(tester);
      for (var tick = 0; tick < 3; tick++) {
        container.read(refreshTickProvider.notifier).state++;
        // Frame by frame: a spinner for even one frame is the bug.
        for (var frame = 0; frame < 6; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(find.byType(WbProgress), findsNothing,
              reason: 'tick $tick, frame $frame');
        }
        await tester.pumpAndSettle();
      }
      expect(find.byType(WbProgress), findsNothing);
      expect(offset(), before, reason: 'the scroll position is kept');
    });
  }
}
