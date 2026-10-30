// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/background/foreground_refresh.dart';
import 'package:wattbyte/core/error_log.dart';

/// A timer that only fires when the test says so, and remembers whether it was
/// cancelled: the loop's rules are checked without real or even fake time.
class FakeTimer implements Timer {
  FakeTimer(this.period, this._callback);

  final Duration period;
  final void Function(Timer) _callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;

  /// Delivers one period, like the scheduler would (never to a cancelled timer).
  void fire() {
    if (_active) _callback(this);
  }
}

class FakeTimers {
  final List<FakeTimer> created = [];

  Timer create(Duration period, void Function(Timer) callback) {
    final t = FakeTimer(period, callback);
    created.add(t);
    return t;
  }

  int get alive => created.where((t) => t.isActive).length;

  /// One period of every live timer.
  void fireAll() {
    for (final t in List.of(created)) {
      t.fire();
    }
  }
}

void main() {
  late FakeTimers timers;
  late int ticks;
  late ForegroundRefresh loop;

  ForegroundRefresh make({Future<void> Function()? onTick}) =>
      ForegroundRefresh(
        onTick: onTick ??
            () async {
              ticks++;
            },
        timerFactory: timers.create,
      );

  setUp(() {
    timers = FakeTimers();
    ticks = 0;
    loop = make();
  });

  tearDown(() => loop.dispose());

  Future<void> settle() => pumpEventQueue();

  group('start, stop', () {
    test('a started loop owns exactly one 60-second timer', () {
      loop.start();
      expect(timers.alive, 1);
      expect(timers.created.single.period, const Duration(seconds: 60));
      expect(loop.isRunning, isTrue);
    });

    test('starting again, from anywhere, never creates a second timer', () {
      loop
        ..start()
        ..start()
        ..start()
        ..resume()
        ..didChangeAppLifecycleState(AppLifecycleState.resumed)
        ..onAccountChanged('a')
        ..onAccountChanged('a');
      expect(timers.alive, 1);
    });

    test('each period is one refresh', () async {
      loop.start();
      for (var i = 1; i <= 5; i++) {
        timers.fireAll();
        await settle();
        expect(ticks, i);
      }
    });

    test('starting does not tick by itself (the caller refreshes once)',
        () async {
      loop.start();
      await settle();
      expect(ticks, 0);
    });

    test('stop cancels the timer; a late period delivers nothing', () async {
      loop.start();
      final t = timers.created.single;
      loop.stop();
      expect(timers.alive, 0);
      t.fire();
      loop.resume(); // a lifecycle event while stopped must not revive it
      await settle();
      expect(ticks, 0);
      expect(timers.alive, 0);
    });

    test('stopped loops can be started again', () {
      loop
        ..start()
        ..stop()
        ..start();
      expect(timers.alive, 1);
      expect(timers.created, hasLength(2));
    });
  });

  group('lifecycle', () {
    test('paused, hidden and detached cancel the timer', () {
      for (final s in [
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.detached,
      ]) {
        loop
          ..start()
          ..didChangeAppLifecycleState(AppLifecycleState.resumed);
        expect(timers.alive, 1, reason: 'before $s');
        loop.didChangeAppLifecycleState(s);
        expect(timers.alive, 0, reason: s.name);
        expect(loop.isRunning, isFalse);
      }
    });

    test('inactive (the app is still on screen) keeps the timer', () {
      loop.start();
      loop.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(timers.alive, 1);
    });

    test(
        'nothing is delivered while backgrounded; resumed ticks at once and restarts',
        () async {
      loop.start();
      timers.fireAll();
      await settle();
      expect(ticks, 1);
      final old = timers.created.single;
      loop.didChangeAppLifecycleState(AppLifecycleState.paused);
      old.fire(); // a straggler of the cancelled timer
      timers.fireAll();
      await settle();
      expect(ticks, 1);

      loop.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();
      expect(ticks, 2, reason: 'resume refreshes immediately');
      expect(timers.alive, 1);
      timers.fireAll();
      await settle();
      expect(ticks, 3);
    });

    test(
        'a pause before start is respected: the timer starts only when resumed',
        () {
      loop
        ..pause()
        ..start();
      expect(timers.alive, 0);
      loop.resume();
      expect(timers.alive, 1);
    });

    test('100 pause/resume cycles never leave more than one timer alive', () {
      loop.start();
      var maxAlive = 0;
      for (var i = 0; i < 100; i++) {
        loop.didChangeAppLifecycleState(AppLifecycleState.paused);
        loop.didChangeAppLifecycleState(AppLifecycleState.inactive);
        loop.didChangeAppLifecycleState(AppLifecycleState.resumed);
        loop.didChangeAppLifecycleState(AppLifecycleState.resumed);
        maxAlive = timers.alive > maxAlive ? timers.alive : maxAlive;
      }
      expect(maxAlive, 1);
      expect(timers.alive, 1);
    });
  });

  group('account', () {
    test('sign-out stops the loop and nothing is refreshed afterwards',
        () async {
      loop.onAccountChanged('user-a');
      expect(timers.alive, 1);
      timers.fireAll();
      await settle();
      expect(ticks, 1);

      loop.onAccountChanged(null);
      expect(timers.alive, 0);
      expect(loop.accountId, isNull);
      timers.created.single.fire();
      loop.resume();
      await settle();
      expect(ticks, 1);
    });

    test('sign-in starts it, the same account again is a no-op', () {
      loop.onAccountChanged('user-a');
      final first = timers.created.single;
      loop.onAccountChanged('user-a');
      expect(timers.created.single, same(first));
      expect(timers.alive, 1);
    });

    test(
        'an account switch restarts the loop with a fresh timer, the old one is dead',
        () async {
      loop.onAccountChanged('user-a');
      final a = timers.created.single;
      loop.onAccountChanged('user-b');
      expect(a.isActive, isFalse);
      expect(timers.alive, 1);
      expect(loop.accountId, 'user-b');
      a.fire();
      await settle();
      expect(ticks, 0,
          reason: 'the previous account\'s timer delivers nothing');
      timers.fireAll();
      await settle();
      expect(ticks, 1);
    });

    test('switching through signed-out never has two timers', () {
      var maxAlive = 0;
      for (final id in ['a', null, 'b', 'b', null, null, 'c', 'a']) {
        loop.onAccountChanged(id);
        maxAlive = timers.alive > maxAlive ? timers.alive : maxAlive;
      }
      expect(maxAlive, 1);
      expect(timers.alive, 1);
    });
  });

  group('dispose', () {
    test('cancels the timer and delivers nothing afterwards', () async {
      loop.start();
      final t = timers.created.single;
      loop.dispose();
      expect(timers.alive, 0);
      t.fire();
      await settle();
      expect(ticks, 0);
    });

    test('a disposed loop cannot be revived by any call', () async {
      loop.dispose();
      loop
        ..start()
        ..resume()
        ..onAccountChanged('a')
        ..didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();
      expect(timers.created, isEmpty);
      expect(ticks, 0);
      expect(loop.isWanted, isFalse);
    });

    test('is idempotent', () {
      loop
        ..start()
        ..dispose()
        ..dispose();
      expect(timers.alive, 0);
    });
  });

  group('ticks', () {
    test('a slow refresh is not overtaken by the next period', () async {
      final gate = Completer<void>();
      var started = 0;
      loop.dispose();
      loop = make(onTick: () async {
        started++;
        await gate.future;
      })
        ..start();
      timers.fireAll();
      timers.fireAll();
      timers.fireAll();
      await settle();
      expect(started, 1, reason: 'no pile-up behind a refresh in progress');
      gate.complete();
      await settle();
      timers.fireAll();
      await settle();
      expect(started, 2);
    });

    test('a failing refresh is reported and does not stop the loop', () async {
      var calls = 0;
      loop.dispose();
      loop = make(onTick: () async {
        calls++;
        if (calls == 1) throw StateError('collector exploded');
      })
        ..start();
      timers.fireAll();
      await settle();
      expect(recentErrors.last, contains('foreground refresh'));
      expect(recentErrors.last, contains('collector exploded'));
      timers.fireAll();
      await settle();
      expect(calls, 2);
      expect(timers.alive, 1);
    });
  });

  group('with real (fake-async) time', () {
    testWidgets('ticks every 60 s, pauses in the background, stops on dispose',
        (tester) async {
      var n = 0;
      final real = ForegroundRefresh(onTick: () async => n++)..start();
      await tester.pump(const Duration(seconds: 59));
      expect(n, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(n, 1);
      await tester.pump(const Duration(seconds: 120));
      expect(n, 3);

      real.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 10));
      expect(n, 3);
      real.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(n, 4);
      await tester.pump(const Duration(seconds: 60));
      expect(n, 5);

      real.onAccountChanged(null);
      await tester.pump(const Duration(minutes: 10));
      expect(n, 5);
      real.dispose(); // flutter_test fails the test if a timer is still pending
    });
  });
}
