import 'dart:convert';
import 'dart:io' show HttpDate;
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wattbyte/api/api_config.dart';
import 'package:wattbyte/api/api_factory.dart';
import 'package:wattbyte/api/api_failure.dart';
import 'package:wattbyte/api/retry_after_client.dart';
import 'package:wattbyte/api/retry_policy.dart';
import 'package:wattbyte/generated/api/api.dart' as api;
import 'package:wattbyte/sync/sync_models.dart';
import 'package:wattbyte/sync/sync_service.dart';

import 'support/fake_backend.dart';
import 'sync_support.dart';

/// The retry table, row by row, at three levels: the pure policy, the
/// `Retry-After` plumbing through a real HTTP client, and the effect on the sync
/// ledger of one account.
void main() {
  const policy = RetryPolicy();
  final random = Random(3);

  group('RetryPolicy.decide', () {
    ApiFailure f(ApiFailureKind kind,
            {int? status, String? code, Duration? retryAfter}) =>
        ApiFailure(kind, status: status, code: code, retryAfter: retryAfter);

    RetryDecision decide(ApiFailure failure,
            {int attempts = 1, int limited = 1}) =>
        policy.decide(failure,
            attempts: attempts, limitedFailures: limited, random: random);

    // (failure, class, retries?)
    final table = <(String, ApiFailure, FailureClass, bool)>[
      (
        'no connection',
        f(ApiFailureKind.network),
        FailureClass.transient,
        true
      ),
      ('timeout', f(ApiFailureKind.timeout), FailureClass.transient, true),
      (
        'HTTP 429',
        f(ApiFailureKind.rateLimited, status: 429),
        FailureClass.transient,
        true
      ),
      (
        'HTTP 429 rate_limited',
        f(ApiFailureKind.rateLimited, status: 429, code: 'rate_limited'),
        FailureClass.transient,
        true
      ),
      (
        'HTTP 401 after the refresh',
        f(ApiFailureKind.unauthorized, status: 401),
        FailureClass.transient,
        true
      ),
      (
        'AI quota 429',
        f(ApiFailureKind.rateLimited, status: 429, code: 'ai_quota_exceeded'),
        FailureClass.quota,
        false
      ),
      (
        'HTTP 400',
        f(ApiFailureKind.badRequest, status: 400, code: 'validation'),
        FailureClass.permanent,
        false
      ),
      (
        'HTTP 500',
        f(ApiFailureKind.server, status: 500),
        FailureClass.limited,
        true
      ),
      (
        'HTTP 502',
        f(ApiFailureKind.server, status: 502),
        FailureClass.limited,
        true
      ),
      (
        'HTTP 503',
        f(ApiFailureKind.server, status: 503),
        FailureClass.limited,
        true
      ),
      (
        'HTTP 504',
        f(ApiFailureKind.server, status: 504),
        FailureClass.limited,
        true
      ),
      (
        'HTTP 404',
        f(ApiFailureKind.notFound, status: 404),
        FailureClass.limited,
        true
      ),
      (
        'HTTP 409',
        f(ApiFailureKind.conflict, status: 409),
        FailureClass.limited,
        true
      ),
      (
        'HTTP 422',
        f(ApiFailureKind.other, status: 422),
        FailureClass.limited,
        true
      ),
      ('unclassified', f(ApiFailureKind.other), FailureClass.limited, true),
    ];

    for (final (label, failure, cls, retries) in table) {
      test('$label -> $cls, ${retries ? 'retried' : 'failed at once'}', () {
        expect(policy.classify(failure), cls);
        final d = decide(failure);
        expect(d.failureClass, cls);
        expect(d.shouldRetry, retries);
        if (retries) {
          expect(d.delay, isNotNull);
          expect(d.delay!, greaterThan(Duration.zero));
        } else {
          expect(d.delay, isNull);
        }
      });
    }

    test('limited failures are retried up to the maximum, then FAIL', () {
      final server = f(ApiFailureKind.server, status: 500);
      for (var n = 1; n < policy.maxLimitedAttempts; n++) {
        expect(decide(server, attempts: n, limited: n).shouldRetry, isTrue,
            reason: 'failure $n');
      }
      expect(
          decide(server,
                  attempts: policy.maxLimitedAttempts,
                  limited: policy.maxLimitedAttempts)
              .action,
          RetryAction.fail);
    });

    test('transient failures are never given up on, however many in a row', () {
      for (final n in [1, 5, 20, 100, 10000]) {
        for (final failure in [
          f(ApiFailureKind.network),
          f(ApiFailureKind.timeout),
          f(ApiFailureKind.rateLimited, status: 429),
          f(ApiFailureKind.unauthorized, status: 401),
        ]) {
          final d = decide(failure, attempts: n, limited: n);
          expect(d.shouldRetry, isTrue, reason: '$failure #$n');
          expect(d.delay!, lessThanOrEqualTo(const Duration(minutes: 72)),
              reason: 'capped at 1 h + 20 % jitter');
        }
      }
    });

    test(
        'Retry-After is honoured: never earlier than asked, never below the own backoff',
        () {
      // (asked seconds, attempt) -> bounds of the delay in seconds
      final rows = <(int, int, num, num)>[
        (120, 1, 120, 132), // own backoff ~30 s is shorter: the server wins
        (5, 1, 24, 36), // asked less than the own floor: the floor wins
        (5, 4, 192, 288), // 4th failure: own backoff ~240 s
        (3600, 1, 3600, 3960),
        (86400, 1, 86400, 95040), // a day is honoured
        (0, 1, 24, 36), // "retry now" still waits the floor
      ];
      for (final (asked, attempt, lo, hi) in rows) {
        final d = decide(
            f(ApiFailureKind.rateLimited,
                status: 429, retryAfter: Duration(seconds: asked)),
            attempts: attempt);
        expect(d.delay!.inMilliseconds / 1000, inInclusiveRange(lo, hi),
            reason: 'Retry-After $asked s, failure #$attempt');
        expect(d.delay!.inSeconds, greaterThanOrEqualTo(asked),
            reason: 'never earlier than the server asked');
      }
    });

    test(
        'an absent or unusable Retry-After falls back to the exponential floor',
        () {
      for (var attempt = 1; attempt <= 6; attempt++) {
        final withNone = policy.delayFor(
            f(ApiFailureKind.rateLimited, status: 429), attempt, Random(5));
        final own = policy.backoff(attempt, Random(5));
        expect(withNone, own);
      }
    });

    test('the AI quota is not a transport retry, whatever Retry-After says',
        () {
      final quota = f(ApiFailureKind.rateLimited,
          status: 429,
          code: 'ai_quota_exceeded',
          retryAfter: const Duration(seconds: 30));
      expect(decide(quota).shouldRetry, isFalse);
      expect(quota.isTransient, isFalse);
      expect(quota.isQuotaExceeded, isTrue);
      // an ordinary 429 is transient
      expect(f(ApiFailureKind.rateLimited, status: 429).isTransient, isTrue);
    });
  });

  group('backoff schedule', () {
    test('doubles from 30 s, capped at 1 h, +-20 % jitter', () {
      const nominal = [30, 60, 120, 240, 480, 960, 1920, 3600, 3600, 3600];
      for (var n = 1; n <= nominal.length; n++) {
        for (var seed = 0; seed < 25; seed++) {
          final d = policy.backoff(n, Random(seed));
          expect(d.inMilliseconds / 1000,
              inInclusiveRange(nominal[n - 1] * 0.8, nominal[n - 1] * 1.2),
              reason: 'attempt $n, seed $seed');
        }
      }
    });

    test('is monotonic in the nominal part and never overflows', () {
      for (final n in [0, -3, 1, 40, 41, 1000, 1 << 30]) {
        final d = policy.backoff(n, Random(1));
        expect(d, greaterThan(Duration.zero));
        expect(d, lessThanOrEqualTo(const Duration(minutes: 72)));
      }
    });

    test('jitter 0 gives the exact schedule', () {
      const exact = RetryPolicy(jitter: 0);
      expect(
          [for (var n = 1; n <= 9; n++) exact.backoff(n, Random(1)).inSeconds],
          [30, 60, 120, 240, 480, 960, 1920, 3600, 3600]);
    });
  });

  group('Retry-After header parsing', () {
    final now = DateTime.utc(2026, 10, 13, 12);
    final rows = <(String?, int?)>[
      ('120', 120),
      ('0', 0),
      (' 7 ', 7),
      ('1.5', 2),
      ('-5', null),
      ('abc', null),
      ('', null),
      (null, null),
      ('99999999', RetryAfterClient.maxSeconds),
      // HTTP dates: relative to the injected clock
      ('Tue, 13 Oct 2026 12:01:30 GMT', 90),
      ('Tue, 13 Oct 2026 11:00:00 GMT', 0),
      ('Wed, 14 Oct 2026 12:00:00 GMT', 86400),
      ('Mon, 01 Jan 2035 00:00:00 GMT', RetryAfterClient.maxSeconds),
      ('not a date', null),
    ];
    for (final (header, expected) in rows) {
      test('${header == null ? 'absent' : '"$header"'} -> $expected', () {
        expect(RetryAfterClient.parse(header, now), expected);
      });
    }
  });

  group('response body rewriting', () {
    test('error envelope: retryAfterSeconds is added inside `error`', () {
      final out = jsonDecode(RetryAfterClient.rewriteBody(
          '{"error":{"code":"rate_limited","message":"slow down"}}', 42));
      expect(out, {
        'error': {
          'code': 'rate_limited',
          'message': 'slow down',
          'retryAfterSeconds': 42
        }
      });
    });

    test('a JSON object without `error` gets it at the top level', () {
      expect(jsonDecode(RetryAfterClient.rewriteBody('{"a":1}', 9)),
          {'a': 1, 'retryAfterSeconds': 9});
    });

    test('an HTML proxy page, plain text or an empty body is replaced', () {
      for (final body in ['<html>503</html>', 'busy', '', '[1,2]', 'null']) {
        expect(
            jsonDecode(RetryAfterClient.rewriteBody(body, 5)),
            {
              'error': {'retryAfterSeconds': 5}
            },
            reason: body);
      }
    });
  });

  group(
      'Retry-After through the real HTTP stack (ApiFactory -> generated client)',
      () {
    Future<ApiFailure> call(http.Client client,
        {String path = '/api/v1/usage/sync'}) async {
      final apis = ApiFactory(const ApiConfig('http://api.test'),
          httpClient: client, clock: () => DateTime.utc(2026, 10, 13, 12));
      try {
        await api.UsageApi(apis.bearer('t')).apiV1UsageSyncPost(
            api.UsageSyncRequest(installationId: 'i' * 8, days: const []));
        fail('expected a failure');
      } catch (e) {
        return ApiFailure.of(e);
      }
    }

    MockClient respond(int status, Map<String, String> headers,
            [String body =
                '{"error":{"code":"rate_limited","message":"x"}}']) =>
        MockClient((r) async => http.Response(body, status, headers: headers));

    test('429 with seconds', () async {
      final failure = await call(respond(429, {'retry-after': '37'}));
      expect(failure.kind, ApiFailureKind.rateLimited);
      expect(failure.retryAfter, const Duration(seconds: 37));
      expect(failure.code, 'rate_limited',
          reason: 'the body is otherwise intact');
      expect(failure.status, 429);
    });

    test('503 with an HTTP date', () async {
      final failure = await call(
          respond(503, {'retry-after': 'Tue, 13 Oct 2026 12:02:00 GMT'}, ''));
      expect(failure.kind, ApiFailureKind.server);
      expect(failure.retryAfter, const Duration(seconds: 120));
    });

    test('429 without the header: retryAfter is null', () async {
      final failure = await call(respond(429, {}));
      expect(failure.retryAfter, isNull);
      expect(failure.code, 'rate_limited');
    });

    test('an unusable header is ignored', () async {
      final failure = await call(respond(429, {'retry-after': 'soon'}));
      expect(failure.retryAfter, isNull);
    });

    test('other statuses are passed through untouched, header or not',
        () async {
      for (final status in [400, 401, 404, 500, 502]) {
        final failure = await call(respond(status, {'retry-after': '30'},
            '{"error":{"code":"c$status","message":"m"}}'));
        expect(failure.retryAfter, isNull, reason: 'HTTP $status');
        expect(failure.code, 'c$status');
        expect(failure.status, status);
      }
    });

    test('a 200 is untouched', () async {
      final client = respond(200, {'retry-after': '30'},
          jsonEncode({'accepted': 0, 'dates': <String>[]}));
      final apis =
          ApiFactory(const ApiConfig('http://api.test'), httpClient: client);
      final res = await api.UsageApi(apis.bearer('t')).apiV1UsageSyncPost(
          api.UsageSyncRequest(installationId: 'i' * 8, days: const []));
      expect(res!.accepted, 0);
    });

    test('AI quota 429 keeps its code and is not a transport retry', () async {
      final failure = await call(respond(429, {'retry-after': '3600'},
          '{"error":{"code":"ai_quota_exceeded","message":"x"}}'));
      expect(failure.code, 'ai_quota_exceeded');
      expect(failure.retryAfter, const Duration(hours: 1));
      expect(failure.isTransient, isFalse);
      expect(policy.classify(failure), FailureClass.quota);
    });

    test('concurrent requests on one client each see their own delay',
        () async {
      // The token carries the delay the fake server answers with; later requests
      // are answered first, so the responses interleave and arrive out of order.
      final client = MockClient((r) async {
        final secs =
            int.parse(r.headers['authorization']!.replaceFirst('Bearer ', ''));
        await Future<void>.delayed(Duration(milliseconds: 60 - secs));
        return http.Response('{"error":{"code":"rate_limited"}}', 429,
            headers: {'retry-after': '$secs'});
      });
      final apis =
          ApiFactory(const ApiConfig('http://api.test'), httpClient: client);
      final results = await Future.wait([
        for (final secs in [11, 22, 33, 44])
          () async {
            try {
              await api.UsageApi(apis.bearer('$secs')).apiV1UsageSyncPost(
                  api.UsageSyncRequest(
                      installationId: 'i' * 8, days: const []));
            } catch (e) {
              return ApiFailure.of(e).retryAfter!.inSeconds;
            }
            return -1;
          }(),
      ]);
      expect(results, [11, 22, 33, 44]);
    });

    test('two factories over one underlying client do not mix delays',
        () async {
      var next = 5;
      final shared = MockClient((r) async {
        final secs = next;
        next += 5;
        return http.Response('{"error":{"code":"x"}}', 429,
            headers: {'retry-after': '$secs'});
      });
      final a = await call(shared);
      final b = await call(shared);
      expect([a.retryAfter!.inSeconds, b.retryAfter!.inSeconds], [5, 10]);
    });

    test('the rewritten response is a well-formed JSON response', () async {
      final wrapper = RetryAfterClient(MockClient((r) async => http.Response(
          '<html>busy</html>', 503,
          headers: {'retry-after': '8', 'content-type': 'text/html'})));
      final res = await http.Response.fromStream(
          await wrapper.send(http.Request('GET', Uri.parse('http://x.test/'))));
      expect(res.statusCode, 503);
      expect(res.headers['content-type'], contains('application/json'));
      expect(res.headers['content-length'], '${res.bodyBytes.length}');
      expect(jsonDecode(res.body), {
        'error': {'retryAfterSeconds': 8}
      });
    });
  });

  group('effect on one account\'s sync (a fresh rig per row)', () {
    late SyncRig current; // the rig of the row that is running
    // (label, responder, status, attempts, delay seconds [lo, hi] or null, halted, rejections)
    final rows = <(
      String,
      http.Response Function(Recorded)?,
      bool offline,
      SyncStatus,
      List<num>? delay,
      int rejected
    )>[
      ('no connection', null, true, SyncStatus.retryLater, [24, 36], 0),
      (
        'HTTP 408',
        (r) => FakeBackend.error(408, 'timeout'),
        false,
        SyncStatus.retryLater,
        [24, 36],
        0
      ),
      (
        'HTTP 429',
        (r) => FakeBackend.error(429, 'rate_limited'),
        false,
        SyncStatus.retryLater,
        [24, 36],
        0
      ),
      (
        'HTTP 429 Retry-After 120',
        (r) => rateLimited(429, '120'),
        false,
        SyncStatus.retryLater,
        [120, 132],
        0
      ),
      (
        'HTTP 503 Retry-After date',
        (r) => rateLimited(
            503,
            HttpDate.format(
                current.now.toUtc().add(const Duration(minutes: 10)))),
        false,
        SyncStatus.retryLater,
        [600, 660],
        0
      ),
      (
        'HTTP 500',
        (r) => FakeBackend.error(500, 'boom'),
        false,
        SyncStatus.retryLater,
        [24, 36],
        0
      ),
      (
        'HTTP 502',
        (r) => FakeBackend.error(502, 'bad_gateway'),
        false,
        SyncStatus.retryLater,
        [24, 36],
        0
      ),
      (
        'HTTP 503',
        (r) => FakeBackend.error(503, 'unavailable'),
        false,
        SyncStatus.retryLater,
        [24, 36],
        0
      ),
      (
        'HTTP 504',
        (r) => FakeBackend.error(504, 'gateway_timeout'),
        false,
        SyncStatus.retryLater,
        [24, 36],
        0
      ),
      (
        'HTTP 409',
        (r) => FakeBackend.error(409, 'conflict'),
        false,
        SyncStatus.retryLater,
        [24, 36],
        0
      ),
      (
        'HTTP 422',
        (r) => FakeBackend.error(422, 'unprocessable'),
        false,
        SyncStatus.retryLater,
        [24, 36],
        0
      ),
      (
        'HTTP 401 (after the one refresh)',
        (r) => FakeBackend.error(401, 'invalid_token'),
        false,
        SyncStatus.authRequired,
        [24, 36],
        0
      ),
      // refused for good: no automatic retry, the payload is recorded as rejected
      (
        'HTTP 400',
        (r) => FakeBackend.error(400, 'validation'),
        false,
        SyncStatus.rejected,
        null,
        1
      ),
      (
        'AI quota 429 (not a transport retry)',
        (r) => FakeBackend.error(429, 'ai_quota_exceeded'),
        false,
        SyncStatus.rejected,
        null,
        1
      ),
    ];

    for (final (label, responder, offline, status, delay, rejected) in rows) {
      test(label, () async {
        final rig = current = await SyncRig.create();
        addTearDown(rig.close);
        await rig.queue(agg('2026-10-13'));
        await rig.sync.enable(SyncScope.history);
        rig.backend.offline = offline;
        if (responder != null) {
          rig.backend.routes['POST /api/v1/usage/sync'] = responder;
        }
        final o = await rig.sync.syncNow();
        expect(o.status, status);
        final st = (await rig.sync.accountState())!;
        final key = await rig.keyOf('user-a');
        expect((await rig.db.rejections(key)).length, rejected);
        expect(await rig.receiptsOf('user-a'), isEmpty);
        if (delay != null) {
          expect(st.attempts, 1);
          expect(st.retryDelayMs / 1000, inInclusiveRange(delay[0], delay[1]));
          expect(
              st.nextRetryMs, rig.now.millisecondsSinceEpoch + st.retryDelayMs);
          // The very next automatic run does not touch the network.
          final before = rig.httpAttempts;
          final again = await rig.sync.syncIfDue();
          expect(again.skip, SyncSkip.backingOff);
          expect(rig.httpAttempts, before);
          // After the delay it tries again.
          rig.advance(Duration(milliseconds: st.retryDelayMs + 1));
          await rig.sync.syncIfDue();
          expect(rig.httpAttempts, greaterThan(before));
        } else {
          expect(st.attempts, 0,
              reason: 'a refusal is not a transient failure');
          expect(st.halted, isFalse);
          // Never retried automatically: the same payload is not sent again.
          final before = rig.httpAttempts;
          rig.advance(const Duration(hours: 1));
          await rig.sync.syncIfDue();
          expect(rig.httpAttempts, before);
        }
      });
    }

    test('the 8th server error in a row gives up (FAIL) and says so', () async {
      final rig = await SyncRig.create();
      addTearDown(rig.close);
      await rig.queue(agg('2026-10-13'));
      await rig.sync.enable(SyncScope.history);
      rig.backend.routes['POST /api/v1/usage/sync'] =
          (r) => FakeBackend.error(503, 'unavailable');
      SyncOutcome? last;
      for (var n = 1; n <= policy.maxLimitedAttempts; n++) {
        last = await rig.sync.syncNow();
        expect(
            last.status,
            n < policy.maxLimitedAttempts
                ? SyncStatus.retryLater
                : SyncStatus.rejected,
            reason: 'attempt $n');
      }
      expect(last!.failed, 1);
      final st = (await rig.sync.accountState())!;
      expect(st.halted, isTrue);
      final snap = (await rig.sync.snapshot())!;
      expect(snap.halted, isTrue);
      expect(snap.failed, 1, reason: 'shown as failed, with a manual retry');
      expect((await rig.sync.syncIfDue()).skip, SyncSkip.halted);
    });

    test('network failures are never given up on', () async {
      final rig = await SyncRig.create();
      addTearDown(rig.close);
      await rig.queue(agg('2026-10-13'));
      await rig.sync.enable(SyncScope.history);
      rig.backend.offline = true;
      for (var n = 1; n <= 30; n++) {
        final o = await rig.sync.syncNow();
        expect(o.status, SyncStatus.retryLater, reason: 'attempt $n');
      }
      final st = (await rig.sync.accountState())!;
      expect(st.halted, isFalse);
      expect(st.attempts, 30);
      expect(st.retryDelayMs, lessThanOrEqualTo(72 * 60 * 1000));
    });

    test(
        'an unexpected error inside the call is retried within bounds and reported',
        () async {
      final rig = await SyncRig.create();
      addTearDown(rig.close);
      await rig.queue(agg('2026-10-13'));
      await rig.sync.enable(SyncScope.history);
      rig.backend.routes['POST /api/v1/usage/sync'] =
          (r) => http.Response('this is not json', 200);
      final o = await rig.sync.syncNow();
      expect(o.status, isNot(SyncStatus.synced));
      expect(await rig.receiptsOf('user-a'), isEmpty);
    });
  });
}
