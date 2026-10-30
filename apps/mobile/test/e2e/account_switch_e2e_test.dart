// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wattbyte/api/api_config.dart';
import 'package:wattbyte/api/api_factory.dart';
import 'package:wattbyte/cloud_providers.dart';
import 'package:wattbyte/core/periods.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/features/auth/data/secure_token_store.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/features/auth/presentation/auth_controller.dart';
import 'package:wattbyte/generated/api/api.dart' as api;
import 'package:wattbyte/providers.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/storage/database.dart';
import 'package:wattbyte/sync/sync_models.dart';
import 'package:wattbyte/sync/sync_queue.dart';
import 'package:wattbyte/sync/sync_service.dart';

/// Two accounts on ONE phone against a RUNNING WattByte API on PostgreSQL.
///
/// Skipped unless WATTBYTE_E2E_API_URL is set (see test/e2e/api_e2e_test.dart); run
/// the API with AI_MOCK=1 and a high AUTH_RATE_LIMIT_PER_MIN:
///
///   WATTBYTE_E2E_API_URL=http://127.0.0.1:18240 flutter test test/e2e/account_switch_e2e_test.dart
///
/// The whole app wiring is real except the platform: the providers (auth, session,
/// sync service, `CloudSync`, the default account-deleted hook), the generated client,
/// the HTTP stack, the API and PostgreSQL. SQLite is in memory and is the SAME
/// database for both users, like the phone's.
void main() {
  final url = Platform.environment['WATTBYTE_E2E_API_URL'];
  final skip = url == null ? 'set WATTBYTE_E2E_API_URL to run' : null;

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
      'A syncs history, B on the same phone starts at zero, A comes back, '
      'a changed day, A deletes the account', () async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final emailA = 'e2e-switch-a-$stamp@test.wattbyte';
    final emailB = 'e2e-switch-b-$stamp@test.wattbyte';
    const password = 'correct horse battery';

    // ------------------------------------------------------------ the phone
    final db = await WattByteDb.openInMemory();
    addTearDown(db.close);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await SettingsStore(prefs).save(const Settings(
        currency: 'PLN',
        countryCode: 'PL',
        pricePerKwh: 1.1,
        designCapacityMah: 4000,
        designCapacitySource: DesignCapacitySource.manual,
        onboarded: true));
    final wire = _Recording();
    final config = ApiConfig(url ?? 'http://unused');
    final store = InMemoryTokenStore();
    final c = ProviderContainer(overrides: [
      prefsProvider.overrideWithValue(prefs),
      dbProvider.overrideWithValue(db),
      apiConfigProvider.overrideWithValue(config),
      apiFactoryProvider
          .overrideWithValue(ApiFactory(config, httpClient: wire)),
      tokenStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(c.dispose);
    final auth = c.read(authControllerProvider.notifier);
    expect(await c.read(authControllerProvider.future), isA<SignedOut>());
    final sync = c.read(syncServiceProvider)!;
    final cloud = c.read(cloudSyncProvider);
    final apis = c.read(apiFactoryProvider);

    // Seven days of local statistics, with sessions: device-local data, no owner.
    final today = dayOf(DateTime.now());
    final days = [
      for (var i = 6; i >= 0; i--) LocalDate.of(today).plusDays(-i).midnight
    ];
    await db.replaceDaily([
      for (final (i, d) in days.indexed)
        DailyData(
            day: d,
            mobileRx: 10000000 * (i + 1),
            mobileTx: 1000000,
            wifiRx: 50000000 * (i + 1),
            wifiTx: 2000000),
    ]);
    await db.insertSessions([
      for (final d in days)
        ChargingSession(
            start: d.add(const Duration(hours: 22)),
            end: d.add(const Duration(hours: 28)),
            startLevel: 20,
            endLevel: 100,
            chargeDeltaUah: 3200000),
    ]);
    final dates = [for (final d in days) dayKey(d)];
    final todayKey = dates.last;

    Future<List<api.DailyUsageDto>> rowsOf(String email, {String? pass}) async {
      // Reads the account's cloud copy with a FRESH login, independent of the app.
      final repoSession = await c
          .read(authRepositoryProvider)
          .signInWithEmail(email: email, password: pass ?? password);
      final res = await api.UsageApi(apis.bearer(repoSession.accessToken))
          .apiV1UsageDailyGet(dates.first, dates.last);
      return res?.days ?? [];
    }

    int usageSyncs() => wire.log
        .where((r) => r.method == 'POST' && r.path == '/api/v1/usage/sync')
        .length;

    /// The account-bound settings are per account: waits until the phone holds
    /// the signed-in account's own (an account that was never here starts with
    /// none), then gives it the currency a finished setup would have given it.
    /// Sync needs one; an account without one uploads nothing. The price is the
    /// one A has: the queue's payloads are device-local and carry the cost, so
    /// two accounts with different prices on one phone would rewrite each other's
    /// costs (a limitation of the queue, see docs/SETTING_SOURCES.md), which is not
    /// what this test is about.
    Future<void> bindAndConfigure() async {
      final signedIn = c.read(authControllerProvider).value;
      expect(signedIn, isA<SignedIn>());
      c.read(settingsProvider);
      final id = (signedIn as SignedIn).user.id;
      for (var i = 0; i < 500 && c.read(settingsScopeProvider) != id; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(c.read(settingsScopeProvider), id, reason: 'settings bound');
      await c.read(settingsProvider.notifier).update((s) => s.currency.isEmpty
          ? s.copyWith(currency: 'PLN').withManualPrice(1.1)
          : s);
    }

    Future<void> asUser(String email) async {
      await auth.signOut();
      await auth.signInWithEmail(email, password);
      expect(c.read(authControllerProvider).value, isA<SignedIn>(),
          reason: email);
      await c.read(syncAccountProvider.notifier).refresh();
      await bindAndConfigure();
    }

    // -------------------------------------------- 1. A registers, history, 7 rows
    await auth.signUpWithEmail(emailA, password);
    expect(c.read(authControllerProvider).value, isA<SignedIn>());
    final userA = (c.read(authControllerProvider).value as SignedIn).user.id;
    final keyA = (await sync.currentAccountKey())!;
    expect(await sync.isEnabled(), isFalse,
        reason: 'default OFF, even for the owner');
    expect(await cloud.historyBacklog(), 6,
        reason: 'six local days older than today');

    final first = await cloud.enableWith(SyncScope.history);
    expect(first!.status, SyncStatus.synced);
    expect(first.uploaded, 7);
    final aRows = await rowsOf(emailA);
    expect(aRows.map((d) => d.date), dates);
    expect(aRows.every((d) => d.chargingSessions == 1 && d.mobileBytes > 0),
        isTrue);
    expect(await db.receiptCount(keyA), 7);
    final aSnapshot = [for (final d in aRows) d.toJson()];

    // ------------------------------------------- 2. logout; B on the SAME database
    await auth.signOut();
    expect(await db.receiptCount(keyA), 7, reason: 'logout keeps the receipts');
    expect(await db.allDaily(), hasLength(7),
        reason: 'local data survives logout');

    await auth.signUpWithEmail(emailB, password);
    await c.read(syncAccountProvider.notifier).refresh();
    await bindAndConfigure();
    final keyB = (await sync.currentAccountKey())!;
    expect(keyB, isNot(keyA));
    expect(await sync.isEnabled(), isFalse, reason: 'B never opted in');
    final before = usageSyncs();
    final idle = await cloud.syncNow();
    expect(idle!.skip, SyncSkip.notEnabled);
    expect((await sync.syncIfDue()).skip, SyncSkip.notEnabled);
    expect(usageSyncs(), before, reason: 'not one upload for B');
    expect(await db.receiptCount(keyB), 0);
    final bRows0 = await rowsOf(emailB);
    expect(bRows0, isEmpty,
        reason: 'B has NO rows: A\'s history was not uploaded for B');
    expect(await cloud.historyBacklog(), 6,
        reason: 'A\'s receipts do not count for B');

    // B chooses "from now": only today.
    await asUser(emailB);
    final fromNow = await cloud.enableWith(SyncScope.fromNow);
    expect(fromNow!.uploaded, 1);
    expect((await rowsOf(emailB)).map((d) => d.date), [todayKey]);

    // Then the history.
    final bHistory = await cloud.uploadHistory();
    expect(bHistory!.uploaded, 6);
    expect((await rowsOf(emailB)).map((d) => d.date), dates);
    expect(await db.receiptCount(keyB), 7);

    // A's rows are exactly what they were.
    expect([for (final d in await rowsOf(emailA)) d.toJson()], aSnapshot);

    // --------------------------------------------- 3. A signs in again: no uploads
    await asUser(emailA);
    expect(await sync.isEnabled(), isTrue,
        reason: 'A\'s choice was kept per account');
    final again0 = usageSyncs();
    final noop = await cloud.syncNow();
    expect(noop!.uploaded, 0);
    expect(noop.skip, SyncSkip.nothingDue);
    expect(usageSyncs(), again0,
        reason: 'fingerprints match: nothing is uploaded');

    // --------------- 4. one day changes: exactly one upload per account with sync on
    final changedDay =
        days[days.length - 2]; // yesterday: inside the 3-day lookback
    await db.replaceDaily([
      DailyData(
          day: changedDay,
          mobileRx: 777000000,
          mobileTx: 1000000,
          wifiRx: 50000000,
          wifiTx: 2000000),
    ]);
    c.read(refreshTickProvider.notifier).state++; // what every refresh does
    await _enqueueRecent(c, await c.read(appDataProvider.future));

    final beforeChange = usageSyncs();
    final aOne = await cloud.syncNow();
    expect(aOne!.uploaded, 1);
    expect(usageSyncs(), beforeChange + 1);
    await asUser(emailB);
    final bOne = await cloud.syncNow();
    expect(bOne!.uploaded, 1);
    expect(usageSyncs(), beforeChange + 2);
    final bRows = await rowsOf(emailB);
    final aRowsNow = await rowsOf(emailA);
    final changedKey = dayKey(changedDay);
    for (final rows in [aRowsNow, bRows]) {
      expect(
          rows.firstWhere((d) => d.date == changedKey).mobileBytes, 778000000);
      expect(
          rows
              .where((d) => d.date != changedKey)
              .map((d) => d.toJson())
              .toList(),
          [for (final d in aSnapshot.where((j) => j['date'] != changedKey)) d],
          reason: 'every other day is untouched');
    }
    // and no more after that
    await asUser(emailA);
    expect((await cloud.syncNow())!.uploaded, 0);
    await asUser(emailB);
    expect((await cloud.syncNow())!.uploaded, 0);

    // ------------------------------------------------ 5. A deletes the account
    await asUser(emailA);
    final deleted = await auth.deleteAccount();
    expect(deleted, isTrue);
    expect(c.read(authControllerProvider).value, isA<SignedOut>());
    // everything this phone knew about A is gone ...
    expect(await db.receiptCount(keyA), 0);
    expect(await db.rejections(keyA), isEmpty);
    expect(await db.meta('sync_account:$keyA'), isNull);
    expect(await db.meta('server_device_id:$keyA'), isNull);
    expect(await db.meta('server_device_id:$userA'), isNull);
    // ... the local data is intact ...
    expect(await db.allDaily(), hasLength(7));
    expect(await db.allSessions(), hasLength(7));
    expect(await db.syncItems(), hasLength(7));
    // ... B is untouched, on the phone and in the cloud.
    expect(await db.receiptCount(keyB), 7);
    expect((await sync.accountState()), isNull, reason: 'signed out');
    expect(await rowsOf(emailB), hasLength(7));
    // A's cloud copy is gone with the account: it cannot sign in any more.
    await expectLater(
        c
            .read(authRepositoryProvider)
            .signInWithEmail(email: emailA, password: password),
        throwsA(isA<AuthException>()
            .having((e) => e.error, 'error', AuthError.invalidCredentials)));
    // The same address registering again is a new, empty account: sync OFF.
    await auth.signUpWithEmail(emailA, password);
    await c.read(syncAccountProvider.notifier).refresh();
    await bindAndConfigure();
    expect(await sync.isEnabled(), isFalse);
    expect(await cloud.historyBacklog(), 6);
    expect((await rowsOf(emailA)), isEmpty);

    // the ledger holds no user id and no e-mail anywhere
    final dump = [
      for (final t in ['meta', 'sync_receipts', 'sync_rejections'])
        (await db.rawDatabase.query(t)).toString()
    ].join('\n');
    for (final secret in [emailA, emailB, userA]) {
      expect(dump, isNot(contains(secret)));
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 4)));
}

/// What the foreground refresh does after the statistics changed.
Future<void> _enqueueRecent(ProviderContainer c, AppData data) =>
    SyncQueue(c.read(dbProvider)).enqueueRecent(
      days: data.days,
      sessions: data.sessions,
      calc: c.read(energyCalcProvider),
      currency: c.read(settingsProvider).currency,
      now: DateTime.now(),
    );

class _Recording extends http.BaseClient {
  final http.Client _inner = http.Client();
  final List<({String method, String path, int status})> log = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final res = await _inner.send(request);
    log.add((
      method: request.method,
      path: request.url.path,
      status: res.statusCode
    ));
    return res;
  }
}
