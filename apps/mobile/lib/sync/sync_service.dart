import 'dart:async';
import 'dart:math';

import '../api/api_factory.dart';
import '../api/api_failure.dart';
import '../api/retry_policy.dart';
import '../api/session_manager.dart';
import '../calc/energy.dart';
import '../core/error_log.dart';
import '../core/periods.dart';
import '../domain/battery_capacity.dart';
import '../features/auth/domain/auth_models.dart';
import '../generated/api/api.dart' as api;
import '../setup/device_specification.dart';
import '../storage/database.dart';
import 'daily_aggregate.dart';
import 'sync_models.dart';
import 'sync_ownership.dart';
import 'sync_queue.dart';

enum SyncStatus {
  /// Nothing was uploaded; see [SyncOutcome.skip] for why.
  idle,

  /// Everything due was accepted by the server.
  synced,

  /// A transient failure (offline, timeout, 5xx, 429); the days stay due, with backoff.
  retryLater,

  /// Not signed in, or the session could not be refreshed. Nothing is lost.
  authRequired,

  /// The server rejected some days for good (HTTP 400), or retrying was given up on.
  rejected,
}

/// Why a run uploaded nothing ([SyncStatus.idle]).
enum SyncSkip {
  none,

  /// This account never enabled cloud sync on this phone.
  notEnabled,

  /// The last successful upload is younger than the interval (automatic runs only).
  throttled,

  /// A failed attempt is waiting out its backoff (automatic runs only).
  backingOff,

  /// Repeated server errors ended the automatic retries; a manual retry continues.
  halted,

  /// Every eligible day already has a receipt for this account.
  nothingDue,

  /// The signed-in account changed while the run was in progress; its result was dropped.
  accountChanged,

  /// Another run is in progress (automatic runs do not queue up behind it).
  inProgress,
}

class SyncOutcome {
  const SyncOutcome(this.status,
      {this.uploaded = 0, this.failed = 0, this.skip = SyncSkip.none});

  final SyncStatus status;
  final int uploaded;
  final int failed;
  final SyncSkip skip;

  @override
  String toString() =>
      'SyncOutcome($status, uploaded: $uploaded, failed: $failed${skip == SyncSkip.none ? '' : ', skip: $skip'})';
}

/// What the Account screen needs to know about the signed-in account's sync.
class SyncSnapshot {
  const SyncSnapshot({
    required this.accountKey,
    required this.enabled,
    this.scope,
    this.enabledOn,
    this.pending = 0,
    this.synced = 0,
    this.failed = 0,
    this.lastSync,
    this.nextRetryAt,
    this.halted = false,
  });

  final String accountKey;
  final bool enabled;
  final SyncScope? scope;

  /// Local day (`yyyy-MM-dd`) sync was enabled.
  final String? enabledOn;

  /// Eligible days that still have to be uploaded.
  final int pending;

  /// Days whose current aggregate is in this account's cloud.
  final int synced;

  /// Days refused for good, plus (when [halted]) the days waiting for a manual retry.
  final int failed;
  final DateTime? lastSync;

  /// When the next automatic retry may happen, while a failure is backing off.
  final DateTime? nextRetryAt;
  final bool halted;
}

/// A response (or the registration it belongs to) arrived for an account that is no
/// longer the signed-in one: nothing may be recorded for it.
class AccountChangedException implements Exception {
  const AccountChangedException();

  @override
  String toString() => 'AccountChangedException';
}

/// Uploads per-day aggregates to `POST /api/v1/usage/sync`.
///
///   SQLite sync_queue -> this service -> generated API client -> backend -> PostgreSQL
///
/// ## Ownership (`docs/SYNC_OWNERSHIP.md`)
/// * Local history is device-local; nothing here changes it.
/// * Sync is an explicit per-account opt-in ([enable], scope required): an account
///   that never enabled it on this phone uploads nothing, whoever signed in before.
/// * A day is uploaded to account X iff it is inside X's scope and has no receipt for
///   X or the receipt's fingerprint differs from the current aggregate's. Receipts
///   are written per (day, account) only after the server accepted the upload.
/// * Every run captures the session epoch and the account key at the start and drops
///   its result (writes nothing) if the account changed or was deleted meanwhile.
///
/// ## Schedule (`syncIfDue`, `syncNow`)
/// * Automatic runs upload at most once per [minInterval] per account (last SUCCESS,
///   persisted), honour the backoff after a failure, and stop after repeated server
///   errors; manual runs ignore all three but are single-flight and bounded.
/// * A clock moved backwards cannot freeze the schedule (see [_rebase]).
///
/// ## Failures
/// The table lives in [RetryPolicy]; this class applies it and records the outcome
/// per account.
///
/// The device is identified by a random per-installation id generated on the phone;
/// the server issues its own device id per account.
class SyncService {
  SyncService({
    required this.db,
    required this.apis,
    required this.sessions,
    required this.platform,
    DateTime Function()? clock,
    Random? random,
    this.policy = const RetryPolicy(),
    this.minInterval = const Duration(minutes: 5),
    this.batchSize = SyncQueue.batchSize,
    this.maxBatchesPerRun = 12,
    this.haltProbeInterval = const Duration(hours: 6),
    SyncOwnership? ownership,
  })  : _clock = clock ?? DateTime.now,
        _random = random ?? Random(),
        ownership = ownership ?? SyncOwnership(db);

  final WattByteDb db;
  final ApiFactory apis;
  final SessionManager sessions;

  /// `android` or `ios`.
  final String platform;
  final RetryPolicy policy;

  /// Automatic uploads happen at most this often per account.
  final Duration minInterval;

  /// Days per request (the API accepts at most 92).
  final int batchSize;

  /// A run sends at most this many requests with days; the rest waits for the next run.
  final int maxBatchesPerRun;

  /// After repeated server trouble the automatic runs stop ([SyncSkip.halted]) but not for ever: one automatic
  /// attempt every [haltProbeInterval] (plus up to 25 % jitter) checks whether the server is back, and a success clears
  /// the halt. The server's kill switch (503 `feature_disabled`) waits the same way instead of counting as a failure.
  final Duration haltProbeInterval;
  final SyncOwnership ownership;
  final DateTime Function() _clock;
  final Random _random;

  Future<SyncOutcome>? _inFlight;
  bool _inFlightManual = false;

  /// Bumped (synchronously) when an account is forgotten: every run in progress
  /// drops its result.
  int _forgetEpoch = 0;

  /// Backoff before attempt number [attempts] (1-based), with +-20 % jitter.
  Duration backoff(int attempts) => policy.backoff(attempts, _random);

  Future<String> installationId() => ownership.installationId();

  // ------------------------------------------------------------ account state

  /// The key of the signed-in account on this phone, or null when signed out.
  Future<String?> currentAccountKey() async {
    final s = await sessions.current();
    return s == null ? null : ownership.accountKey(s.user.id);
  }

  /// The sync state of the signed-in account (sync OFF unless it was enabled here);
  /// null when nobody is signed in.
  Future<AccountSyncState?> accountState() async {
    final key = await currentAccountKey();
    return key == null ? null : ownership.state(key);
  }

  Future<bool> isEnabled() async => (await accountState())?.enabled ?? false;

  /// Switches cloud sync ON for the signed-in account.
  ///
  /// [scope] is required: `history` makes every local day eligible, `fromNow` only
  /// days from today on. There is deliberately no default that uploads a phone's
  /// history to an account. This only records the choice; the caller makes sure the
  /// queue holds the days (`SyncQueue.enqueueAll` for history) and runs [syncNow].
  ///
  /// Throws [AuthException] (`sessionExpired`) when nobody is signed in.
  Future<AccountSyncState> enable(SyncScope scope) async {
    final s = await sessions.current();
    if (s == null) throw const AuthException(AuthError.sessionExpired);
    return ownership.enable(
        await ownership.accountKey(s.user.id), scope, _clock());
  }

  /// Switches cloud sync OFF for the signed-in account (receipts are kept). Does
  /// nothing when signed out.
  Future<void> disable() async {
    final key = await currentAccountKey();
    if (key != null) await ownership.disable(key);
  }

  /// How many of [localDays] (the aggregates of every local day) are older than
  /// [before] (default: the day sync was enabled for this account, else today) and
  /// have no receipt for the signed-in account. The UI asks "Upload this phone's N
  /// days of history to <account>?" only when this is above zero. 0 when signed out.
  Future<int> daysWithoutReceipt(Iterable<DailyAggregate> localDays,
      {DateTime? before}) async {
    final key = await currentAccountKey();
    if (key == null) return 0;
    final st = await ownership.state(key);
    final limit =
        before != null ? dayKey(before) : (st.enabledOn ?? dayKey(_clock()));
    final receipts = await db.receipts(key);
    return localDays
        .where((a) =>
            a.date.compareTo(limit) < 0 &&
            !a.isEmpty &&
            a.isWithinContract &&
            !receipts.containsKey(a.date))
        .length;
  }

  /// Takes the signed-in account's refused days and a halted schedule back to
  /// "try again" (the manual "retry failed").
  Future<void> retryFailed() async {
    final key = await currentAccountKey();
    if (key != null) await _resetFailures(key);
  }

  Future<void> _resetFailures(String key) async {
    await db.clearRejections(key);
    await ownership.update(
        key,
        (s) => s.copyWith(
              attempts: 0,
              limitedFailures: 0,
              permanentFailures: 0,
              nextRetryMs: 0,
              retryDelayMs: 0,
              halted: false,
              clearError: true,
            ));
  }

  /// The account of [userId] was deleted on the server: erase its receipts,
  /// rejections, sync state and cached server device id from this phone (local
  /// statistics stay) and make every run in progress drop its result.
  Future<void> forgetAccount(String userId) async {
    _forgetEpoch++;
    await ownership.forgetUser(userId);
  }

  /// Counts for the Account screen; null when signed out.
  Future<SyncSnapshot?> snapshot() async {
    final session = await sessions.current();
    if (session == null) return null;
    final key = await ownership.accountKey(session.user.id);
    final st = await ownership.state(key);
    final now = _clock();
    final plan = await _plan(key, st, now);
    final receipts = await db.receipts(key);
    final items = await db.syncItems();
    final synced = items
        .where((i) =>
            receipts[dayKey(i.day)]?.fingerprint == i.payload.fingerprint)
        .length;
    return SyncSnapshot(
      accountKey: key,
      enabled: st.enabled,
      scope: st.scope,
      enabledOn: st.enabledOn,
      pending: plan.sendable.length,
      synced: synced,
      failed: plan.rejected + (st.halted ? plan.sendable.length : 0),
      lastSync: st.lastSuccessMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(st.lastSuccessMs!),
      nextRetryAt: st.nextRetryMs > now.millisecondsSinceEpoch
          ? DateTime.fromMillisecondsSinceEpoch(st.nextRetryMs)
          : null,
      halted: st.halted,
    );
  }

  // ------------------------------------------------------------------- running

  /// Automatic entry point (60 s refresh ticks, foreground resume): uploads at most
  /// once per [minInterval] since the last success, waits out a failure's backoff,
  /// and does nothing for an account that did not enable sync.
  Future<SyncOutcome> syncIfDue({Duration? minInterval}) =>
      _run(manual: false, interval: minInterval ?? this.minInterval);

  /// Manual "Sync now": ignores the interval, the backoff and a halt, uploads what is
  /// due (still nothing for an account without sync). Single-flight: a second call
  /// while one runs shares its result. [retryFailed] first takes refused days back.
  Future<SyncOutcome> syncNow({bool retryFailed = false}) =>
      _run(manual: true, interval: Duration.zero, retryFailed: retryFailed);

  Future<SyncOutcome> _run({
    required bool manual,
    required Duration interval,
    bool retryFailed = false,
  }) async {
    while (_inFlight != null) {
      final running = _inFlight!;
      if (!manual) {
        return const SyncOutcome(SyncStatus.idle, skip: SyncSkip.inProgress);
      }
      if (_inFlightManual && !retryFailed) return running;
      try {
        await running;
      } on Object {
        // The failure belongs to the caller that started that run.
      }
    }
    final run =
        _sync(manual: manual, interval: interval, retryFailed: retryFailed)
            .whenComplete(() => _inFlight = null);
    _inFlight = run;
    _inFlightManual = manual;
    return run;
  }

  /// What is due for the account: the eligible days without a matching receipt or
  /// rejection, and how many days are refused.
  Future<_Plan> _plan(String key, AccountSyncState st, DateTime now) async {
    if (!st.enabled) return const _Plan([], 0);
    // A window that starts after today (clock moved back) must not hide today.
    final today = dayKey(now);
    final since = st.scope == SyncScope.fromNow && st.enabledOn != null
        ? (st.enabledOn!.compareTo(today) > 0 ? today : st.enabledOn)
        : null;
    final items = await db.syncItems(sinceDay: since);
    final receipts = await db.receipts(key);
    final rejections = await db.rejections(key);
    final sendable = <_Due>[];
    final invalid = <_Due>[];
    var rejected = 0;
    for (final i in items) {
      final day = dayKey(i.day);
      final fp = i.payload.fingerprint;
      if (receipts[day]?.fingerprint == fp) continue;
      if (rejections[day]?.fingerprint == fp) {
        rejected++;
        continue;
      }
      (i.payload.isWithinContract ? sendable : invalid).add(_Due(i, fp));
    }
    return _Plan(sendable, rejected + invalid.length, invalid: invalid);
  }

  Future<SyncOutcome> _sync({
    required bool manual,
    required Duration interval,
    required bool retryFailed,
  }) async {
    final epoch = sessions.accountEpoch;
    final forgetEpoch = _forgetEpoch;
    bool stale() =>
        sessions.accountEpoch != epoch || _forgetEpoch != forgetEpoch;
    const changed = SyncOutcome(SyncStatus.idle, skip: SyncSkip.accountChanged);

    final session = await sessions.current();
    if (session == null) return const SyncOutcome(SyncStatus.authRequired);
    final userId = session.user.id;
    final key = await ownership.accountKey(userId);
    if (stale()) return changed;

    var st = await ownership.state(key);
    if (!st.enabled) {
      return const SyncOutcome(SyncStatus.idle, skip: SyncSkip.notEnabled);
    }
    var now = _clock();
    st = await _rebase(key, st, now);
    if (retryFailed) {
      await _resetFailures(key);
      st = await ownership.state(key);
    }
    final nowMs = now.millisecondsSinceEpoch;
    if (!manual) {
      if (st.halted) {
        // Refused payloads (HTTP 400 again and again) stay halted until something changes; server trouble is probed.
        final refusals = st.permanentFailures >= policy.maxPermanentFailures;
        if (refusals || st.nextRetryMs > nowMs) {
          return const SyncOutcome(SyncStatus.idle, skip: SyncSkip.halted);
        }
      }
      if (st.nextRetryMs > nowMs) {
        return const SyncOutcome(SyncStatus.idle, skip: SyncSkip.backingOff);
      }
      final last = st.lastSuccessMs;
      if (last != null && nowMs - last < interval.inMilliseconds) {
        return const SyncOutcome(SyncStatus.idle, skip: SyncSkip.throttled);
      }
    }

    var uploaded = 0;
    var failed = 0;
    // Days per request in this run; halved when the server refuses a request with HTTP 400, to find the day that is wrong
    // instead of rejecting the whole chunk for one bad day (F-12).
    var take = batchSize;
    for (var batch = 0; batch < maxBatchesPerRun; batch++) {
      if (batch > 0) {
        st = await ownership.state(key);
        if (!st.enabled) {
          break; // switched off while a long history was going up
        }
        now = _clock();
      }
      final plan = await _plan(key, st, now);
      if (plan.invalid.isNotEmpty) {
        if (stale()) return changed;
        await db.saveRejections([
          for (final d in plan.invalid)
            SyncRejection(
                day: dayKey(d.item.day),
                accountKey: key,
                fingerprint: d.fingerprint,
                error: 'invalid_local',
                rejectedAt: now)
        ]);
        failed += plan.invalid.length;
      }
      if (plan.sendable.isEmpty) break;
      final chunk = plan.sendable.take(take).toList();

      try {
        final res = await _upload(userId, key, chunk);
        if (stale()) {
          return changed; // a response for a previous session: drop it
        }
        final done = _clock();
        // Only what the server confirmed gets a receipt; a date it silently ignored
        // is refused for this payload instead of being resent forever.
        final confirmed = res.dates.isNotEmpty
            ? res.dates.toSet()
            : (res.accepted >= chunk.length
                ? {for (final d in chunk) dayKey(d.item.day)}
                : <String>{});
        final receipts = <SyncReceipt>[];
        final dropped = <SyncRejection>[];
        for (final d in chunk) {
          final day = dayKey(d.item.day);
          if (confirmed.contains(day)) {
            receipts.add(SyncReceipt(
                day: day,
                accountKey: key,
                fingerprint: d.fingerprint,
                syncedAt: done));
          } else {
            dropped.add(SyncRejection(
                day: day,
                accountKey: key,
                fingerprint: d.fingerprint,
                error: 'not_accepted',
                rejectedAt: done));
          }
        }
        await db.saveReceipts(receipts);
        if (dropped.isNotEmpty) await db.saveRejections(dropped);
        await ownership.update(
            key,
            (s) => s.copyWith(
                  lastSuccessMs: done.millisecondsSinceEpoch,
                  attempts: 0,
                  limitedFailures: 0,
                  permanentFailures: 0,
                  nextRetryMs: 0,
                  retryDelayMs: 0,
                  halted: false,
                  clearError: true,
                ));
        uploaded += receipts.length;
        failed += dropped.length;
      } on AccountChangedException {
        return changed;
      } on WrongAccountException {
        return changed;
      } on Object catch (e, st0) {
        if (stale()) return changed;
        if (chunk.length > 1 &&
            ApiFailure.of(e).kind == ApiFailureKind.badRequest) {
          take = (chunk.length + 1) ~/ 2;
          continue;
        }
        return _failure(e, st0,
            key: key,
            st: st,
            batch: chunk,
            plan: plan,
            uploaded: uploaded,
            failed: failed);
      }
    }
    if (uploaded == 0 && failed == 0) {
      return const SyncOutcome(SyncStatus.idle, skip: SyncSkip.nothingDue);
    }
    return SyncOutcome(failed > 0 ? SyncStatus.rejected : SyncStatus.synced,
        uploaded: uploaded, failed: failed);
  }

  /// Records a failed request and answers what the caller should show.
  Future<SyncOutcome> _failure(
    Object error,
    StackTrace trace, {
    required String key,
    required AccountSyncState st,
    required List<_Due> batch,
    required _Plan plan,
    required int uploaded,
    required int failed,
  }) async {
    if (error is AuthException && error.error == AuthError.sessionExpired) {
      // The session ended (SessionManager cleared it); nothing to record.
      return SyncOutcome(SyncStatus.authRequired,
          uploaded: uploaded, failed: failed);
    }
    final ApiFailure f;
    if (error is AuthException) {
      f = ApiFailure(switch (error.error) {
        AuthError.network => ApiFailureKind.network,
        AuthError.rateLimited => ApiFailureKind.rateLimited,
        _ => ApiFailureKind.server,
      });
    } else {
      f = ApiFailure.of(error);
    }
    // The kill switch (503 feature_disabled) is the server saying "not now", not a failure: no error report, no
    // failure count, and the next automatic attempt is a probe later.
    if (f.code == 'feature_disabled') {
      final at = _clock();
      final wait = _probeDelay();
      await ownership.update(
          key,
          (s) => s.copyWith(
                nextRetryMs: at.millisecondsSinceEpoch + wait.inMilliseconds,
                retryDelayMs: wait.inMilliseconds,
                lastError: 'feature_disabled',
              ));
      return SyncOutcome(SyncStatus.retryLater,
          uploaded: uploaded, failed: failed);
    }
    // Offline, timeouts, rate limits and an ended session are everyday events.
    // Anything else (a server error, a refused request, a response the client could
    // not read, a bug) is retried within bounds but never invisible.
    if (const {
      ApiFailureKind.server,
      ApiFailureKind.other,
      ApiFailureKind.badRequest,
      ApiFailureKind.notFound,
      ApiFailureKind.conflict,
    }.contains(f.kind)) {
      reportError(error, trace, 'sync upload');
    }

    final now = _clock();
    final cls = policy.classify(f);
    final limited = st.limitedFailures + (cls == FailureClass.limited ? 1 : 0);
    final decision = policy.decide(f,
        attempts: st.attempts + 1, limitedFailures: limited, random: _random);
    // A machine code, stored in the ledger: bounded, whatever the server sent.
    final raw = f.code ?? f.kind.name;
    final code = raw.length > 64 ? raw.substring(0, 64) : raw;

    if (decision.shouldRetry) {
      final delay = decision.delay!;
      await ownership.update(
          key,
          (s) => s.copyWith(
                attempts: s.attempts + 1,
                limitedFailures: cls == FailureClass.limited
                    ? s.limitedFailures + 1
                    : s.limitedFailures,
                nextRetryMs: now.millisecondsSinceEpoch + delay.inMilliseconds,
                retryDelayMs: delay.inMilliseconds,
                lastError: code,
              ));
      return SyncOutcome(
          f.kind == ApiFailureKind.unauthorized
              ? SyncStatus.authRequired
              : SyncStatus.retryLater,
          uploaded: uploaded,
          failed: failed);
    }

    if (cls == FailureClass.limited) {
      // Retries used up: stop the automatic attempts, keep the data.
      final probe = _probeDelay();
      await ownership.update(
          key,
          (s) => s.copyWith(
                attempts: s.attempts + 1,
                limitedFailures: limited,
                halted: true,
                // The next automatic attempt is a probe, not "never" (F-06). The delay is stored with it: a retry time
                // further away than its own delay is read as a clock set back and pulled in (see _rebase).
                nextRetryMs: now.millisecondsSinceEpoch + probe.inMilliseconds,
                retryDelayMs: probe.inMilliseconds,
                lastError: code,
              ));
      return SyncOutcome(SyncStatus.rejected,
          uploaded: uploaded, failed: failed + plan.sendable.length);
    }

    // Permanent (HTTP 400, ...): these exact payloads are refused for this account.
    // A changed day is a new payload and gets its chance, but not sooner than the
    // normal interval and not after [RetryPolicy.maxPermanentFailures] refusals in a
    // row: no failure may leave an automatic request loop behind.
    await db.saveRejections([
      for (final d in batch)
        SyncRejection(
            day: dayKey(d.item.day),
            accountKey: key,
            fingerprint: d.fingerprint,
            error: code,
            rejectedAt: now)
    ]);
    await ownership.update(
        key,
        (s) => s.copyWith(
              permanentFailures: s.permanentFailures + 1,
              halted: s.permanentFailures + 1 >= policy.maxPermanentFailures,
              nextRetryMs:
                  now.millisecondsSinceEpoch + minInterval.inMilliseconds,
              retryDelayMs: minInterval.inMilliseconds,
              lastError: code,
            ));
    return SyncOutcome(SyncStatus.rejected,
        uploaded: uploaded, failed: failed + batch.length);
  }

  Duration _probeDelay() => Duration(
      milliseconds:
          (haltProbeInterval.inMilliseconds * (1 + _random.nextDouble() * 0.25))
              .round());

  /// Keeps the persisted schedule honest after the clock moved.
  ///
  /// * A "last success" in the future (clock set back) would mean "just synced" for
  ///   hours: it becomes "now", so the next upload is at most one interval away.
  /// * A "next retry" further away than the delay it was computed with (clock set
  ///   back) becomes "now + that delay".
  /// A clock moved forwards needs nothing: everything is simply due.
  Future<AccountSyncState> _rebase(
      String key, AccountSyncState st, DateTime now) async {
    final nowMs = now.millisecondsSinceEpoch;
    bool needs(AccountSyncState s) =>
        (s.lastSuccessMs != null && s.lastSuccessMs! > nowMs) ||
        (s.nextRetryMs > nowMs && s.nextRetryMs - nowMs > s.retryDelayMs);
    if (!needs(st)) return st;
    return ownership.update(key, (s) {
      var next = s;
      if (next.lastSuccessMs != null && next.lastSuccessMs! > nowMs) {
        next = next.copyWith(lastSuccessMs: nowMs);
      }
      if (next.nextRetryMs > nowMs &&
          next.nextRetryMs - nowMs > next.retryDelayMs) {
        next = next.copyWith(nextRetryMs: nowMs + next.retryDelayMs);
      }
      return next;
    });
  }

  // ------------------------------------------------------------------- network

  Future<api.UsageSyncResponse> _upload(
      String userId, String key, List<_Due> items,
      {bool retriedRegistration = false}) async {
    final installation = await ownership.installationId();
    await _ensureRegistered(userId, key, installation);
    final body = api.UsageSyncRequest(
      installationId: installation,
      days: [for (final d in items) _dto(d.item.payload)],
    );
    try {
      return await sessions.authorized(
          userId: userId,
          (token) => guarded(() async {
                final res = await api.UsageApi(apis.bearer(token))
                    .apiV1UsageSyncPost(body);
                if (res == null) throw const ApiFailure(ApiFailureKind.server);
                return res;
              }));
    } on ApiFailure catch (f) {
      // The server forgot this installation (e.g. the device record was deleted).
      if (f.kind == ApiFailureKind.notFound &&
          f.code == 'device_not_registered' &&
          !retriedRegistration) {
        await ownership.clearDeviceId(key);
        return _upload(userId, key, items, retriedRegistration: true);
      }
      rethrow;
    }
  }

  Future<void> _ensureRegistered(
      String userId, String key, String installation) async {
    if (await ownership.deviceId(key) != null) return;
    await _register(userId, key, installation, null, null);
  }

  /// Registers (or refreshes) this installation together with its device-bound
  /// battery facts. They are properties of the phone, so they live on the
  /// device record, not on the account. Safe to repeat. Carries no usage data,
  /// so it does not depend on cloud sync being enabled.
  ///
  /// Two separate groups are sent (see `docs/BATTERY_CAPACITY.md`): the design
  /// capacity of [spec] (always, `unknown` included, which carries no numbers)
  /// and, only when [fullCharge] is an available estimate, the estimated
  /// full-charge capacity of this battery. Without an estimate those four fields
  /// are `null`, which keeps the estimate the server already stores (sending
  /// source `unknown` would erase it).
  Future<void> registerDevice(
    DeviceSpecification spec, {
    EstimatedFullChargeCapacity? fullCharge,
  }) async {
    final session = await sessions.current();
    if (session == null) return;
    final userId = session.user.id;
    try {
      await _register(userId, await ownership.accountKey(userId),
          await ownership.installationId(), spec, fullCharge);
    } on AccountChangedException {
      // The account changed while the request was on the wire: nothing is recorded
      // for it, and the next sign-in of that account registers again.
    } on WrongAccountException {
      // Same, before the request went out.
    }
  }

  Future<void> _register(
      String userId,
      String key,
      String installation,
      DeviceSpecification? spec,
      EstimatedFullChargeCapacity? fullCharge) async {
    final epoch = sessions.accountEpoch;
    final forgetEpoch = _forgetEpoch;
    final design = spec?.design;
    final estimate =
        fullCharge != null && fullCharge.isAvailable ? fullCharge : null;
    // Wh is optional: an implausible value is left out instead of failing the registration.
    final estimateWh = estimate?.wh;
    final sendWh = estimateWh != null &&
        estimateWh.isFinite &&
        estimateWh > 0 &&
        estimateWh <= EnergyCalc.maxCapacityWh;
    final dto = await sessions.authorized(
        userId: userId,
        (token) => guarded(() async {
              final d =
                  await api.DevicesApi(apis.bearer(token)).apiV1DevicesPost(
                api.DeviceRegisterRequest(
                  installationId: installation,
                  platform: platform == 'ios'
                      ? api.DeviceRegisterRequestPlatformEnum.ios
                      : api.DeviceRegisterRequestPlatformEnum.android,
                  model: spec == null || spec.model.isEmpty ? null : spec.model,
                  modelIdentifier: spec?.modelIdentifier,
                  designCapacityMah: design?.mah,
                  designCapacityWh: design?.wh,
                  designCapacitySource:
                      design == null ? null : _designSourceDto(design.source),
                  estimatedFullChargeCapacityMah: estimate?.mah,
                  estimatedFullChargeCapacityWh: sendWh ? estimateWh : null,
                  fullChargeCapacitySource: estimate == null
                      ? null
                      : _fullChargeSourceDto(estimate.source),
                  fullChargeCapacityConfidence: estimate == null
                      ? null
                      : _confidenceDto(estimate.confidence),
                ),
              );
              if (d == null) throw const ApiFailure(ApiFailureKind.server);
              return d;
            }));
    // A response for a session that ended (or an account that was deleted) while the
    // request was in flight must not leave a record behind.
    if (sessions.accountEpoch != epoch || _forgetEpoch != forgetEpoch) {
      throw const AccountChangedException();
    }
    await ownership.saveDeviceId(key, dto.id);
  }

  static api.DeviceRegisterRequestDesignCapacitySourceEnum _designSourceDto(
          DesignCapacitySource s) =>
      switch (s) {
        DesignCapacitySource.manufacturerSpecification => api
            .DeviceRegisterRequestDesignCapacitySourceEnum
            .manufacturerSpecification,
        DesignCapacitySource.localDeviceDatabase =>
          api.DeviceRegisterRequestDesignCapacitySourceEnum.localDeviceDatabase,
        DesignCapacitySource.backendDeviceDatabase => api
            .DeviceRegisterRequestDesignCapacitySourceEnum
            .backendDeviceDatabase,
        DesignCapacitySource.manual =>
          api.DeviceRegisterRequestDesignCapacitySourceEnum.manual,
        DesignCapacitySource.unknown =>
          api.DeviceRegisterRequestDesignCapacitySourceEnum.unknown,
      };

  static api.DeviceRegisterRequestFullChargeCapacitySourceEnum
      _fullChargeSourceDto(FullChargeCapacitySource s) => switch (s) {
            FullChargeCapacitySource.androidChargeCounter => api
                .DeviceRegisterRequestFullChargeCapacitySourceEnum
                .androidChargeCounter,
            FullChargeCapacitySource.unknown =>
              api.DeviceRegisterRequestFullChargeCapacitySourceEnum.unknown,
          };

  /// `none` has no wire value: an absent estimate sends no confidence at all.
  static api.DeviceRegisterRequestFullChargeCapacityConfidenceEnum?
      _confidenceDto(FullChargeCapacityConfidence c) => switch (c) {
            FullChargeCapacityConfidence.none => null,
            FullChargeCapacityConfidence.low =>
              api.DeviceRegisterRequestFullChargeCapacityConfidenceEnum.low,
            FullChargeCapacityConfidence.medium =>
              api.DeviceRegisterRequestFullChargeCapacityConfidenceEnum.medium,
            FullChargeCapacityConfidence.high =>
              api.DeviceRegisterRequestFullChargeCapacityConfidenceEnum.high,
          };

  static api.DailyUsageDto _dto(DailyAggregate a) => api.DailyUsageDto(
        date: a.date,
        mobileBytes: a.mobileBytes,
        wifiBytes: a.wifiBytes,
        chargedWh: a.chargedWh,
        wallWh: a.wallWh,
        chargingSessions: a.chargingSessions,
        estimatedCost: a.estimatedCost,
        currency: a.currency,
        dataEstimated: a.dataEstimated,
        energyEstimated: a.energyEstimated,
      );
}

/// A queued day together with the fingerprint of the payload that will be sent.
class _Due {
  const _Due(this.item, this.fingerprint);

  final SyncQueueItem item;
  final String fingerprint;
}

class _Plan {
  const _Plan(this.sendable, this.rejected, {this.invalid = const []});

  /// Eligible, valid days that still have to be uploaded, oldest first.
  final List<_Due> sendable;

  /// Days refused for their current payload (including [invalid] ones).
  final int rejected;

  /// Eligible days whose payload breaks the API contract: never sent, refused locally.
  final List<_Due> invalid;
}
