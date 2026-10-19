import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/api/retry_policy.dart';
import 'package:wattbyte/calc/energy.dart';
import 'package:wattbyte/core/periods.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/sync/sync_models.dart';
import 'package:wattbyte/sync/sync_queue.dart';
import 'package:wattbyte/sync/sync_service.dart';

import 'support/fake_backend.dart';
import 'sync_support.dart';

/// How often the sync may talk to the network, over simulated hours.
///
/// The loop under test is the foreground refresh tick (every 60 s):
///
///     collect -> SyncQueue.enqueueRecent (today changes every minute)
///             -> SyncService.syncIfDue -> refresh tick -> next tick
///
/// A counting client records every HTTP request that is attempted (also the ones
/// the fake network refuses), the clock is injected, and the tables printed at the
/// end are the measured request counts.
void main() {
  late SyncRig rig;
  final report = <String>[];

  setUp(() async {
    rig = await SyncRig.create();
    await rig.sync.enable(SyncScope.history);
  });
  tearDown(() => rig.close());
  tearDownAll(() {
    debugPrint(
        '\nREQUEST COUNTS (simulated, 60 s ticks)\n${report.join('\n')}\n');
  });

  final calc = EnergyCalc(
      batteryCapacityMah: 4000,
      nominalVoltage: 3.85,
      efficiency: 0.85,
      pricePerKwh: 1.1);

  /// One refresh pass: today's usage grew a little, the queue is updated, the
  /// automatic sync gets its chance. Returns the HTTP requests it caused.
  var counter = 0;
  Future<int> tick({bool changing = true, SyncService? service}) async {
    final before = rig.httpAttempts;
    if (changing) counter++;
    await SyncQueue(rig.db).enqueueRecent(
      days: [DailyData(day: dayOf(rig.now), mobileRx: 1000 + counter * 4096)],
      sessions: const [],
      calc: calc,
      currency: 'PLN',
      now: rig.now,
    );
    await (service ?? rig.sync).syncIfDue();
    return rig.httpAttempts - before;
  }

  /// Runs [minutes] ticks one minute apart. Returns the elapsed seconds at which a
  /// tick made at least one HTTP request.
  Future<List<int>> run(int minutes,
      {bool changing = true,
      Future<void> Function(int minute)? before,
      SyncService? service}) async {
    final at = <int>[];
    for (var m = 0; m < minutes; m++) {
      if (before != null) await before(m);
      if (await tick(changing: changing, service: service) > 0) at.add(m * 60);
      rig.advance(const Duration(minutes: 1));
    }
    return at;
  }

  group('online, today changes every minute', () {
    test('at most 12 uploads in an hour, never closer than 5 minutes',
        () async {
      final at = await run(60);
      final uploads = rig.cloud.uploads.length;
      report.add('| online, changing day | 60 ticks | $uploads uploads | '
          '${rig.httpAttempts} HTTP requests (1 is the device registration) |');
      expect(uploads, lessThanOrEqualTo(12));
      expect(uploads, 12, reason: 'a tick every minute, one upload every 5');
      expect(rig.httpAttempts, 13);
      for (var i = 1; i < at.length; i++) {
        expect(at[i] - at[i - 1], greaterThanOrEqualTo(300),
            reason: 'uploads at ${at[i - 1]} s and ${at[i]} s');
      }
    });

    test('over 24 hours: 12 uploads an hour at most', () async {
      await run(24 * 60);
      report.add('| online, changing day | 1440 ticks (24 h) | '
          '${rig.cloud.uploads.length} uploads | ${rig.httpAttempts} HTTP requests |');
      expect(rig.cloud.uploads.length, lessThanOrEqualTo(12 * 24 + 1));
      // The history of previous days is uploaded once each, not again.
      final perDay = <String, int>{};
      for (final u in rig.cloud.uploads) {
        for (final d in u.dates) {
          perDay[d] = (perDay[d] ?? 0) + 1;
        }
      }
      expect(perDay['2026-10-13']!, lessThanOrEqualTo(12 * 12 + 2),
          reason: 'the current day is the only one that keeps changing');
      expect(perDay['2026-10-14']!, greaterThan(0));
    });

    test('an unchanged day is uploaded once and then left alone', () async {
      final at = await run(60, changing: false);
      expect(at, [0]);
      expect(rig.cloud.uploads, hasLength(1));
      report.add('| online, nothing changes | 60 ticks | 1 upload | '
          '${rig.httpAttempts} HTTP requests |');
    });

    test('foreground resume (an extra tick) does not add uploads', () async {
      await tick();
      final base = rig.httpAttempts;
      for (var i = 0; i < 20; i++) {
        await tick(); // many resumes within the same minute
      }
      expect(rig.httpAttempts, base, reason: 'inside the 5-minute interval');
    });
  });

  group('offline: attempts follow the backoff schedule', () {
    test('an hour offline: a handful of attempts, each after its backoff',
        () async {
      rig.backend.offline = true;
      final at = <int>[];
      final delays = <int>[];
      for (var m = 0; m < 60; m++) {
        final attemptsBefore = rig.httpAttempts;
        final stateBefore = (await rig.sync.accountState())!;
        await tick();
        final stateAfter = (await rig.sync.accountState())!;
        if (rig.httpAttempts > attemptsBefore) {
          at.add(m * 60);
          delays.add(stateAfter.retryDelayMs);
          // Never before the previous attempt's backoff expired.
          expect(rig.now.millisecondsSinceEpoch,
              greaterThanOrEqualTo(stateBefore.nextRetryMs),
              reason: 'tick $m');
        } else if (stateBefore.nextRetryMs > rig.now.millisecondsSinceEpoch) {
          expect(stateAfter.nextRetryMs, stateBefore.nextRetryMs,
              reason: 'a tick inside the backoff changes nothing (tick $m)');
        }
        rig.advance(const Duration(minutes: 1));
      }
      report.add('| offline, changing day | 60 ticks | ${at.length} attempts '
          'at ${at.map((s) => '${s}s').join(', ')} | 0 uploads |');
      expect(at.length, inInclusiveRange(6, 9));
      expect(rig.cloud.uploads, isEmpty);
      // The backoff doubles (within +-20 % jitter) until the cap.
      for (var k = 0; k < delays.length; k++) {
        final nominal = 30000 * (1 << k);
        final capped = nominal > 3600000 ? 3600000 : nominal;
        expect(delays[k],
            inInclusiveRange((capped * 0.8).floor(), (capped * 1.2).ceil()),
            reason: 'failure ${k + 1}');
      }
      for (var i = 1; i < at.length; i++) {
        expect((at[i] - at[i - 1]) * 1000, greaterThanOrEqualTo(delays[i - 1]),
            reason:
                'attempt ${i + 1} came before the backoff of attempt $i ended');
      }
    });

    test(
        'a changed current day does NOT reset the backoff (enqueue is neutral)',
        () async {
      rig.backend.offline = true;
      await tick();
      final failed = (await rig.sync.accountState())!;
      expect(failed.attempts, 1);
      expect(failed.nextRetryMs, greaterThan(rig.now.millisecondsSinceEpoch));
      // Ten more minutes of "today changed": the ledger entry only moves because of
      // attempts that were really due, never because of an enqueue.
      for (var i = 0; i < 5; i++) {
        counter++;
        await SyncQueue(rig.db).enqueueRecent(
            days: [DailyData(day: dayOf(rig.now), mobileRx: counter * 999)],
            sessions: const [],
            calc: calc,
            currency: 'PLN',
            now: rig.now);
        final s = (await rig.sync.accountState())!;
        expect(s.attempts, 1);
        expect(s.nextRetryMs, failed.nextRetryMs);
      }
    });

    test(
        'back online: the first due attempt succeeds, then the normal schedule',
        () async {
      rig.backend.offline = true;
      final offline = await run(10);
      rig.backend.offline = false;
      final online = await run(20);
      final firstOnline = online.first + 10 * 60;
      expect(offline.length, inInclusiveRange(3, 5));
      expect(rig.cloud.uploads, isNotEmpty);
      final st = (await rig.sync.accountState())!;
      expect(st.attempts, 0, reason: 'a success resets the backoff');
      expect(st.halted, isFalse);
      // After the success the 5-minute rule applies again.
      final ups = rig.cloud.uploads.length;
      expect(ups, lessThanOrEqualTo(1 + 20 ~/ 5));
      report.add(
          '| 10 min offline, then online | 30 ticks | ${offline.length} failed '
          'attempts, first success at ${firstOnline}s, $ups uploads in 20 min |');
    });

    test('a persistent HTTP 500 stops after 8 attempts and waits for a person',
        () async {
      rig.backend.routes['POST /api/v1/usage/sync'] =
          (r) => FakeBackend.error(500, 'boom');
      final at = await run(24 * 60);
      report.add(
          '| HTTP 500 for 24 h | 1440 ticks | ${at.length} attempts, then halted | 0 uploads |');
      // The registration is one request; every attempt is one more (usage).
      final usage = rig.backend.where('POST', '/api/v1/usage/sync');
      expect(usage, hasLength(8));
      final st = (await rig.sync.accountState())!;
      expect(st.halted, isTrue);
      expect(st.lastError, 'boom');
      // A manual retry continues: one more attempt, not a loop.
      final o = await rig.sync.syncNow(retryFailed: true);
      expect(o.status, SyncStatus.retryLater);
      expect(rig.backend.where('POST', '/api/v1/usage/sync'), hasLength(9));
      expect((await rig.sync.accountState())!.halted, isFalse);
    });

    test(
        'HTTP 429 with Retry-After: no attempt before it, whatever the ticks do',
        () async {
      rig.backend.routes['POST /api/v1/usage/sync'] =
          (r) => rateLimited(429, '600');
      final at = await run(30);
      expect(at.first, 0);
      expect(at.length, lessThanOrEqualTo(3));
      for (var i = 1; i < at.length; i++) {
        expect(at[i] - at[i - 1], greaterThanOrEqualTo(600),
            reason: 'the server asked for 10 minutes');
      }
      report.add('| HTTP 429, Retry-After 600 | 30 ticks | attempts at '
          '${at.map((s) => '${s}s').join(', ')} |');
    });

    test('HTTP 400 is not retried at all, however long the app runs', () async {
      rig.backend.routes['POST /api/v1/usage/sync'] =
          (r) => FakeBackend.error(400, 'validation');
      final at = await run(60, changing: false);
      expect(at, [0]);
      expect(rig.backend.where('POST', '/api/v1/usage/sync'), hasLength(1));
    });

    test(
        'HTTP 400 on a day that keeps changing: at most 3 refusals, then it stops',
        () async {
      rig.backend.routes['POST /api/v1/usage/sync'] =
          (r) => FakeBackend.error(400, 'validation');
      final at = await run(60);
      expect(at, [0, 300, 600],
          reason: 'one refusal, one interval, again - then halted');
      final st = (await rig.sync.accountState())!;
      expect(st.halted, isTrue);
      expect(st.permanentFailures, 3);
      report.add(
          '| HTTP 400, day changes | 60 ticks | ${at.length} refusals, then halted |');
      // The person can resume it, once.
      rig.backend.routes['POST /api/v1/usage/sync'] = (r) => FakeBackend.json({
            'accepted': 1,
            'dates': [dayKey(rig.now)]
          });
      final o = await rig.sync.syncNow(retryFailed: true);
      expect(o.status, SyncStatus.synced);
      expect((await rig.sync.accountState())!.halted, isFalse);
    });

    test('a 401 that survives the token refresh backs off instead of looping',
        () async {
      rig.backend.routes['POST /api/v1/usage/sync'] =
          (r) => FakeBackend.error(401, 'invalid_token');
      final at = await run(60);
      final usage = rig.backend.where('POST', '/api/v1/usage/sync');
      // Each attempt = the request + ONE retry after the one refresh.
      expect(usage.length, at.length * 2);
      expect(rig.repo.refreshCalls, at.length);
      expect(at.length, inInclusiveRange(6, 9));
      report.add('| HTTP 401 always | 60 ticks | ${at.length} attempts, '
          '${usage.length} requests, ${rig.repo.refreshCalls} refreshes |');
    });

    test('offline during token refresh keeps the session and backs off',
        () async {
      await rig.sessions.adopt(sessionOf('user-a',
          expiresAt: rig.now.subtract(const Duration(minutes: 5))));
      rig.repo.refreshFailure = AuthError.network;
      var refreshAttempts = 0;
      for (var m = 0; m < 30; m++) {
        final before = rig.repo.refreshCalls;
        await tick();
        if (rig.repo.refreshCalls > before) refreshAttempts++;
        rig.advance(const Duration(minutes: 1));
      }
      expect(refreshAttempts, inInclusiveRange(4, 7));
      expect(await rig.store.read(), isNotNull, reason: 'still signed in');
      expect(rig.httpAttempts, 0, reason: 'no request left the phone');
      rig.repo.refreshFailure = null;
      rig.advance(const Duration(hours: 1));
      await run(2);
      expect(rig.cloud.uploads, isNotEmpty);
    });
  });

  group('manual sync', () {
    test(
        'always uploads what changed, even inside the interval and the backoff',
        () async {
      await tick(); // uploads
      expect(rig.cloud.uploads, hasLength(1));
      await tick(); // changed again, 0 minutes later: throttled
      expect(rig.cloud.uploads, hasLength(1));
      final manual = await rig.sync.syncNow();
      expect(manual.status, SyncStatus.synced);
      expect(rig.cloud.uploads, hasLength(2));

      // Inside a backoff the manual run still goes out.
      rig.backend.offline = true;
      rig.advance(const Duration(minutes: 6));
      await tick();
      expect((await rig.sync.accountState())!.nextRetryMs,
          greaterThan(rig.now.millisecondsSinceEpoch));
      rig.backend.offline = false;
      final after = rig.httpAttempts;
      counter++;
      await tick(); // inside the backoff: nothing
      expect(rig.httpAttempts, after);
      expect((await rig.sync.syncNow()).status, SyncStatus.synced);
      expect(rig.httpAttempts, greaterThan(after));
    });

    test('is bounded and single-flight: 10 taps in a row are 1 request',
        () async {
      await tick();
      counter++;
      await tick(); // a change is waiting
      final before = rig.cloud.requestCount;
      await Future.wait([for (var i = 0; i < 10; i++) rig.sync.syncNow()]);
      expect(rig.cloud.requestCount - before, 1);
      // Nothing changed since: more taps send nothing.
      for (var i = 0; i < 10; i++) {
        await rig.sync.syncNow();
      }
      expect(rig.cloud.requestCount - before, 1);
    });
  });

  group('the clock', () {
    test(
        'moved BACKWARDS by 3 hours: sync resumes within one interval, no loop',
        () async {
      await run(10);
      final before = rig.cloud.uploads.length;
      expect(before, greaterThan(0));
      rig.advance(const Duration(hours: -3));
      final at = await run(30);
      final uploads = rig.cloud.uploads.length - before;
      report.add(
          '| clock back 3 h | 30 ticks after | first request at ${at.first}s, '
          '$uploads uploads |');
      expect(at.first, lessThanOrEqualTo(5 * 60),
          reason: 'due after at most one interval, not after 3 hours');
      expect(uploads, lessThanOrEqualTo(30 ~/ 5 + 1));
    });

    test('moved backwards while a retry is waiting: the wait is not stretched',
        () async {
      rig.backend.offline = true;
      await tick();
      final st = (await rig.sync.accountState())!;
      expect(st.retryDelayMs, lessThanOrEqualTo(36000));
      rig.advance(const Duration(days: -2));
      rig.backend.offline = false;
      // The next ticks are at most one backoff away.
      final at = await run(3);
      expect(at, isNotEmpty,
          reason: 'must not wait 2 days for the old time stamp');
    });

    test('moved FORWARDS by 2 days: due immediately', () async {
      await run(6);
      final before = rig.cloud.uploads.length;
      rig.advance(const Duration(days: 2));
      counter++;
      await tick();
      expect(rig.cloud.uploads.length, before + 1);
    });

    test('a clock set back and forth never produces a burst', () async {
      final at = <int>[];
      for (var m = 0; m < 120; m++) {
        if (await tick() > 0) at.add(m);
        // Wobble: forward 1 minute, every 7th tick back 20 minutes.
        rig.advance(Duration(minutes: m % 7 == 6 ? -20 : 1));
      }
      expect(rig.httpAttempts, lessThanOrEqualTo(40));
    });
  });

  group('restart, accounts', () {
    test(
        'the 5-minute rule survives an app restart (last success is persisted)',
        () async {
      await tick();
      expect(rig.cloud.uploads, hasLength(1));
      rig.advance(const Duration(minutes: 2));
      final restarted = rig.restart();
      final before = rig.httpAttempts;
      await tick(service: restarted);
      expect(rig.httpAttempts, before,
          reason: 'only 2 of 5 minutes have passed');
      rig.advance(const Duration(minutes: 3));
      await tick(service: restarted);
      expect(rig.cloud.uploads, hasLength(2));
    });

    test('a backoff survives an app restart', () async {
      rig.backend.offline = true;
      await tick();
      final restarted = rig.restart();
      final before = rig.httpAttempts;
      rig.advance(const Duration(seconds: 5));
      await tick(service: restarted);
      expect(rig.httpAttempts, before);
    });

    test('an account switch starts a fresh schedule per account', () async {
      await tick(); // A uploads at t=0
      expect(rig.cloud.uploads.map((u) => u.user), ['user-a']);
      await rig.signOut();
      await rig.signIn('user-b');
      await rig.sync.enable(SyncScope.fromNow);
      rig.advance(const Duration(seconds: 30));
      await tick(); // B: not throttled by A's success
      expect(rig.cloud.uploads.map((u) => u.user), ['user-a', 'user-b']);
      await rig.signOut();
      await rig.signIn('user-a');
      rig.advance(const Duration(seconds: 30));
      await tick(); // A: 60 s after its own success, throttled
      expect(rig.cloud.uploads, hasLength(2));
      rig.advance(const Duration(minutes: 5));
      await tick();
      expect(
          rig.cloud.uploads.map((u) => u.user), ['user-a', 'user-b', 'user-a']);
    });

    test('A failing does not slow B down', () async {
      rig.backend.offline = true;
      await tick();
      expect((await rig.sync.accountState())!.attempts, 1);
      rig.backend.offline = false;
      await rig.signOut();
      await rig.signIn('user-b');
      await rig.sync.enable(SyncScope.fromNow);
      rig.advance(const Duration(seconds: 1));
      await tick();
      expect(rig.cloud.datesOf('user-b'), ['2026-10-13']);
      expect((await rig.sync.accountState())!.attempts, 0);
    });

    test('signed out ticks make no request at all', () async {
      await rig.signOut();
      final before = rig.httpAttempts;
      await run(30);
      expect(rig.httpAttempts, before);
    });

    test('an account that never enabled sync makes no request at all',
        () async {
      await rig.sync.disable();
      await run(60);
      expect(rig.httpAttempts, 0);
    });
  });

  test('retry policy knobs are honoured (shorter interval, other base)',
      () async {
    final fast = await SyncRig.create(
        minInterval: const Duration(minutes: 1),
        policy:
            const RetryPolicy(baseBackoff: Duration(seconds: 10), jitter: 0));
    addTearDown(fast.close);
    await fast.sync.enable(SyncScope.history);
    fast.backend.offline = true;
    await fast.queue(agg('2026-10-13'));
    await fast.sync.syncIfDue();
    expect((await fast.sync.accountState())!.retryDelayMs, 10000);
    fast.advance(const Duration(seconds: 11));
    await fast.sync.syncIfDue();
    expect((await fast.sync.accountState())!.retryDelayMs, 20000);
  });
}
