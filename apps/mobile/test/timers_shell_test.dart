// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/features/auth/presentation/auth_controller.dart';

import 'support/app_harness.dart';

/// The refresh loop as the real shell runs it (real `WattByteApp`, fake native
/// side): every period of the 60-second timer is exactly one collection, and no
/// collection, hence no sync, happens once the app is in the background, the
/// account signed out or the shell gone. flutter_test itself fails a test that ends
/// with a timer still pending, so a leaked timer cannot pass silently.
void main() {
  Future<void> elapse(WidgetTester tester, Duration d) async {
    await tester.pump(d);
    await settle(tester, minimum: const Duration(milliseconds: 100));
  }

  int collections(AppHarness h) => h.system.callsTo('interfaceCounters').length;

  testWidgets('one collection per minute while open and signed in',
      (tester) async {
    final h = await pumpApp(tester);
    final base = collections(h);
    expect(base, greaterThan(0),
        reason: 'the first refresh after the first frame');
    await elapse(tester, const Duration(seconds: 61));
    expect(collections(h), base + 1);
    await elapse(tester, const Duration(seconds: 60));
    expect(collections(h), base + 2);
    await elapse(tester, const Duration(seconds: 30));
    expect(collections(h), base + 2, reason: 'nothing between two periods');
  });

  testWidgets(
      'after sign-out nothing refreshes, however long the app stays open',
      (tester) async {
    final h = await pumpApp(tester);
    await elapse(tester, const Duration(seconds: 61));
    await h.container(tester).read(authControllerProvider.notifier).signOut();
    await settle(tester);
    final after = collections(h);
    await elapse(tester, const Duration(minutes: 10));
    expect(collections(h), after, reason: 'the shell is gone, so is its timer');
  });

  testWidgets(
      'in the background nothing refreshes; resuming refreshes once and restarts',
      (tester) async {
    final h = await pumpApp(tester);
    await elapse(tester, const Duration(seconds: 61));
    final before = collections(h);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await elapse(tester, const Duration(minutes: 10));
    expect(collections(h), before, reason: 'paused: no timer, no collection');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester, minimum: const Duration(milliseconds: 100));
    expect(collections(h), before + 1, reason: 'one refresh at once on resume');
    await elapse(tester, const Duration(seconds: 61));
    expect(collections(h), before + 2,
        reason: 'and the periodic loop is back, once');
  });

  testWidgets('sign-out and sign-in again: one loop, not two', (tester) async {
    final h = await pumpApp(tester);
    final auth = h.container(tester).read(authControllerProvider.notifier);
    await auth.signOut();
    await settle(tester);
    await auth.signInWithEmail('tester@example.com', 'password');
    await settle(tester);
    final base = collections(h);
    await elapse(tester, const Duration(seconds: 61));
    expect(collections(h), base + 1);
    await elapse(tester, const Duration(seconds: 60));
    expect(collections(h), base + 2,
        reason: 'two loops would collect twice a minute');
  });
}
