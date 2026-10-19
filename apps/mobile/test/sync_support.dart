// Shared fixtures for the sync tests (ownership, frequency, retry, e2e).
//
// Not a test file (no `_test.dart`): it is imported by test/sync_*.dart.
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wattbyte/api/api_config.dart';
import 'package:wattbyte/api/api_factory.dart';
import 'package:wattbyte/api/retry_policy.dart';
import 'package:wattbyte/api/session_manager.dart';
import 'package:wattbyte/core/periods.dart';
import 'package:wattbyte/features/auth/data/secure_token_store.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/storage/database.dart';
import 'package:wattbyte/sync/daily_aggregate.dart';
import 'package:wattbyte/sync/sync_models.dart';
import 'package:wattbyte/sync/sync_service.dart';

import 'support/fake_backend.dart';

var _ffiReady = false;

/// SQLite on the host: `databaseFactory` is a process-wide setting, set once.
void ensureSqliteFfi() {
  if (_ffiReady) return;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  _ffiReady = true;
}

/// One day's aggregate; [date] is `yyyy-MM-dd`.
DailyAggregate agg(String date,
        {int mobile = 100, double wh = 10, double cost = 0.01}) =>
    DailyAggregate(
      date: date,
      mobileBytes: mobile,
      wifiBytes: 200,
      chargedWh: wh,
      wallWh: wh * 1.2,
      chargingSessions: 1,
      estimatedCost: cost,
      currency: 'PLN',
    );

/// A session of [userId]. Tokens are `access-<userId>` / `refresh-<userId>`, so the
/// fake server can tell whose token a request carries.
AuthSession sessionOf(String userId,
        {DateTime? expiresAt, String tokenSuffix = ''}) =>
    AuthSession(
      accessToken: 'access-$userId$tokenSuffix',
      refreshToken: 'refresh-$userId$tokenSuffix',
      expiresAt: expiresAt ?? DateTime.now().add(const Duration(hours: 4)),
      user: User(id: userId, email: '$userId@example.test'),
    );

/// An auth backend whose refresh keeps the user of the refresh token it was given.
class UserAwareRepo implements AuthRepository {
  int refreshCalls = 0;
  AuthError? refreshFailure;
  int _n = 0;

  @override
  Future<AuthSession> refresh(String refreshToken) async {
    refreshCalls++;
    final f = refreshFailure;
    if (f != null) throw AuthException(f);
    final userId = userOfToken(refreshToken);
    _n++;
    return sessionOf(userId, tokenSuffix: '-r$_n');
  }

  /// The e-mail is used as the user id: `signInWithEmail('user-b', ...)` signs in `user-b`.
  @override
  Future<AuthSession> signInWithEmail(
          {required String email, required String password}) async =>
      sessionOf(email);

  @override
  Future<AuthSession> signUpWithEmail(
          {required String email, required String password}) async =>
      sessionOf(email);

  @override
  Future<AuthSession> signInWithApple() => throw UnimplementedError();

  @override
  Future<AuthSession> signInWithGoogle() => throw UnimplementedError();

  @override
  Future<void> signOut(String refreshToken) async {}

  @override
  Future<User> me(String accessToken) async {
    final id = userOfToken(accessToken);
    return User(id: id, email: '$id@example.test');
  }

  @override
  Future<void> deleteAccount(String accessToken) async {}
}

/// The user a fake token belongs to (`access-user-a-r2`, `refresh-user-a` -> `user-a`).
String userOfToken(String? token) => (token ?? '')
    .replaceFirst(RegExp(r'^(access|refresh)-'), '')
    .replaceFirst(RegExp(r'-r\d+$'), '');

/// Counts every request that is attempted, including those the fake network
/// refuses (`FakeBackend` does not record requests it fails as "offline").
class CountingClient extends http.BaseClient {
  CountingClient(this._inner);

  final http.Client _inner;
  int attempts = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    attempts++;
    return _inner.send(request);
  }
}

/// A scriptable API with a tiny in-memory "server": rows per user and device, like
/// `daily_usage (user_id, device_id, date)`.
class FakeCloud {
  FakeCloud(this.backend) {
    backend.routes['POST /api/v1/devices'] = (r) {
      final user = userOfToken(r.bearer);
      // Server-issued ids are opaque: they never contain the user id.
      final id =
          deviceIds.putIfAbsent(user, () => 'device-${deviceIds.length + 1}');
      devices
          .putIfAbsent(user, () => <String>{})
          .add(r.body!['installationId'] as String);
      // The device table answers like the real server: battery groups stored
      // atomically, the rules of `POST /devices` enforced (400 otherwise).
      return deviceTable.register(user, r.body!, id);
    };
    backend.routes['POST /api/v1/usage/sync'] = (r) {
      final user = userOfToken(r.bearer);
      final days = (r.body!['days'] as List).cast<Map<String, dynamic>>();
      final rows = rowsByUser.putIfAbsent(user, () => {});
      for (final d in days) {
        rows[d['date'] as String] = d;
      }
      uploads.add(
          (user: user, dates: [for (final d in days) d['date'] as String]));
      return FakeBackend.json({
        'accepted': days.length,
        'dates': days.map((d) => d['date']).toList()..sort(),
      });
    };
  }

  final FakeBackend backend;

  /// What `POST /devices` stored, per user and installation.
  final FakeDeviceTable deviceTable = FakeDeviceTable();

  /// user -> date -> row as received.
  final Map<String, Map<String, Map<String, dynamic>>> rowsByUser = {};
  final Map<String, Set<String>> devices = {};
  final Map<String, String> deviceIds = {};

  /// Every accepted upload, in order.
  final List<({String user, List<String> dates})> uploads = [];

  List<String> datesOf(String user) =>
      (rowsByUser[user]?.keys.toList() ?? <String>[])..sort();

  /// How many usage-sync requests were made (accepted or not).
  int get requestCount => backend.where('POST', '/api/v1/usage/sync').length;
}

/// A SyncService on an isolated in-memory database with a controllable clock.
class SyncRig {
  SyncRig._(this.db, this.backend, this.cloud, this.repo, this.store,
      this.sessions, this.sync, this._clock, this.net);

  final WattByteDb db;
  final FakeBackend backend;
  final FakeCloud cloud;
  final UserAwareRepo repo;
  final InMemoryTokenStore store;
  final SessionManager sessions;
  final SyncService sync;
  final _Clock _clock;
  final CountingClient net;

  /// HTTP requests attempted so far (answered, failed or refused as offline).
  int get httpAttempts => net.attempts;

  DateTime get now => _clock.now;
  set now(DateTime v) => _clock.now = v;

  void advance(Duration d) => _clock.now = _clock.now.add(d);

  static Future<SyncRig> create({
    String? signedInAs = 'user-a',
    DateTime? now,
    RetryPolicy policy = const RetryPolicy(),
    int seed = 1,
    Duration minInterval = const Duration(minutes: 5),
    WattByteDb? db,
  }) async {
    ensureSqliteFfi();
    final database = db ?? await WattByteDb.openInMemory();
    final backend = FakeBackend();
    final cloud = FakeCloud(backend);
    final repo = UserAwareRepo();
    final store = InMemoryTokenStore();
    final sessions = SessionManager(store: store, repository: repo);
    final clock = _Clock(now ?? DateTime(2026, 10, 13, 12));
    final counting = CountingClient(backend.client);
    final sync = SyncService(
      db: database,
      apis: ApiFactory(const ApiConfig('http://api.test'),
          httpClient: counting, clock: () => clock.now),
      sessions: sessions,
      platform: 'android',
      clock: () => clock.now,
      random: Random(seed),
      policy: policy,
      minInterval: minInterval,
    );
    final rig = SyncRig._(
        database, backend, cloud, repo, store, sessions, sync, clock, counting);
    if (signedInAs != null) await rig.signIn(signedInAs);
    return rig;
  }

  Future<void> close() => db.close();

  /// What AuthController does on sign-in.
  Future<void> signIn(String userId) => sessions.adopt(sessionOf(userId));

  /// What AuthController does on sign-out.
  Future<void> signOut() => sessions.clear();

  /// A new service over the same database (an app restart): new in-memory state,
  /// the same persisted ledger.
  SyncService restart({int seed = 7}) => SyncService(
        db: db,
        apis: ApiFactory(const ApiConfig('http://api.test'),
            httpClient: net, clock: () => _clock.now),
        sessions: sessions,
        platform: 'android',
        clock: () => _clock.now,
        random: Random(seed),
      );

  /// Puts a day into the device-local queue (what `SyncQueue.enqueueRecent` does).
  Future<void> queue(DailyAggregate a) => db.upsertSyncItem(
      SyncQueueItem(day: parseDayKey(a.date), payload: a, updatedAt: now));

  Future<void> queueDays(Iterable<String> dates, {int mobile = 100}) async {
    for (final d in dates) {
      await queue(agg(d, mobile: mobile));
    }
  }

  Future<List<SyncReceipt>> receiptsOf(String userId) async {
    final key = await sync.ownership.accountKey(userId);
    return (await db.receipts(key)).values.toList()
      ..sort((a, b) => a.day.compareTo(b.day));
  }

  Future<String> keyOf(String userId) => sync.ownership.accountKey(userId);
}

class _Clock {
  _Clock(this.now);

  DateTime now;
}

/// `2026-10-07` .. `2026-10-13`: seven consecutive days, the last one "today" of [SyncRig].
List<String> sevenDays() =>
    [for (var d = 7; d <= 13; d++) '2026-10-${d.toString().padLeft(2, '0')}'];

/// A response with a `Retry-After` header.
http.Response rateLimited(int status, String retryAfter,
        {String code = 'rate_limited'}) =>
    http.Response(
        jsonEncode({
          'error': {'code': code, 'message': code}
        }),
        status,
        headers: {
          'content-type': 'application/json',
          'retry-after': retryAfter,
        });
