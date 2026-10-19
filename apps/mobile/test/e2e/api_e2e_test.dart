@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wattbyte/api/api_config.dart';
import 'package:wattbyte/api/api_factory.dart';
import 'package:wattbyte/api/session_manager.dart';
import 'package:wattbyte/features/ai/ai_input_builder.dart';
import 'package:wattbyte/features/ai/ai_service.dart';
import 'package:wattbyte/features/auth/data/api_auth_repository.dart';
import 'package:wattbyte/features/auth/data/secure_token_store.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/features/auth/presentation/auth_controller.dart';
import 'package:wattbyte/generated/api/api.dart' as api;
import 'package:wattbyte/calc/energy.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/storage/database.dart';
import 'package:wattbyte/sync/daily_aggregate.dart';
import 'package:wattbyte/sync/sync_models.dart';
import 'package:wattbyte/sync/sync_service.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/setup/account_settings.dart';
import 'package:wattbyte/setup/device_specification.dart';
import 'package:wattbyte/setup/electricity_price.dart';

/// End to end: the real generated Dart client and the real app code against a
/// RUNNING WattByte API on PostgreSQL. Skipped unless WATTBYTE_E2E_API_URL is set:
///
///   WATTBYTE_E2E_API_URL=http://127.0.0.1:18080 flutter test test/e2e
///
/// The server should run with AI_MOCK=1 (the AI gateway is real, its provider a mock)
/// and AI_FREE_DAILY_LIMIT=4. The three e2e files run in parallel and together send
/// about 190 requests within a few seconds, so also raise the per-IP limits
/// (RATE_LIMIT_PER_MIN=1000, AUTH_RATE_LIMIT_PER_MIN=1000); the default of 120 a
/// minute answers 429. `GET /me/export` has a fixed limit of 6 a minute: run
/// `contract_e2e_test.dart` once a minute.
void main() {
  final url = Platform.environment['WATTBYTE_E2E_API_URL'];
  final skip = url == null ? 'set WATTBYTE_E2E_API_URL to run' : null;

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final email = 'e2e-${DateTime.now().microsecondsSinceEpoch}@test.wattbyte';
  const password = 'correct horse battery';
  late ApiFactory apis;
  late AuthRepository repo;

  setUpAll(() {
    apis = ApiFactory(ApiConfig(url ?? 'http://unused'));
    repo = ApiAuthRepository(apis);
  });

  SessionManager manager(TokenStore store) =>
      SessionManager(store: store, repository: repo);

  test('register -> /me; duplicate email and wrong password are told apart',
      () async {
    final s = await repo.signUpWithEmail(email: email, password: password);
    expect(s.user.email, email);
    expect(s.user.plan, Plan.free);
    expect((await repo.me(s.accessToken)).id, s.user.id);

    await expectLater(
        repo.signUpWithEmail(email: email.toUpperCase(), password: password),
        throwsA(isA<AuthException>()
            .having((e) => e.error, 'error', AuthError.emailTaken)));
    await expectLater(
        repo.signInWithEmail(email: email, password: 'wrong password'),
        throwsA(isA<AuthException>()
            .having((e) => e.error, 'error', AuthError.invalidCredentials)));
    await expectLater(
        repo.signUpWithEmail(email: 'x@y.co', password: 'short'),
        throwsA(isA<AuthException>()
            .having((e) => e.error, 'error', AuthError.invalidInput)));
  }, skip: skip);

  test('login -> refresh rotates the token; the old refresh token is rejected',
      () async {
    final s = await repo.signInWithEmail(email: email, password: password);
    final next = await repo.refresh(s.refreshToken);
    expect(next.refreshToken, isNot(s.refreshToken));
    // Within the server's grace window a replay is rejected without ending the new session.
    await expectLater(
        repo.refresh(s.refreshToken),
        throwsA(isA<AuthException>()
            .having((e) => e.error, 'error', AuthError.sessionExpired)));
    expect((await repo.me(next.accessToken)).email, email);
  }, skip: skip);

  test(
      '5 concurrent calls with an expired token trigger exactly one real refresh',
      () async {
    final login = await repo.signInWithEmail(email: email, password: password);
    final store = InMemoryTokenStore();
    await store.write(AuthSession(
      accessToken: login.accessToken,
      refreshToken: login.refreshToken,
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      user: login.user,
    ));
    final m = manager(store);
    final users = await Future.wait(
        List.generate(5, (_) => m.authorized((t) => repo.me(t))));
    expect(users.map((u) => u.email).toSet(), {email});
    expect(m.refreshCalls, 1);
    expect((await store.read())!.refreshToken, isNot(login.refreshToken));
  }, skip: skip);

  test(
      'session restore: stored expired session -> refresh -> GET /me -> signed in',
      () async {
    final login = await repo.signInWithEmail(email: email, password: password);
    final store = InMemoryTokenStore();
    await store.write(AuthSession(
      accessToken: login.accessToken,
      refreshToken: login.refreshToken,
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      user: const User(id: 'stale', email: 'stale@local'),
    ));
    final c = ProviderContainer(overrides: [
      apiConfigProvider.overrideWithValue(ApiConfig(url!)),
      tokenStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(c.dispose);
    expect(c.read(authControllerProvider).isLoading, isTrue,
        reason: 'initializing first');
    final state = await c.read(authControllerProvider.future);
    expect(state, isA<SignedIn>());
    expect((state as SignedIn).user.email, email,
        reason: 'user comes from the server, not the stale copy');
    expect(state.offline, isFalse);

    await c.read(authControllerProvider.notifier).signOut();
    expect(c.read(authControllerProvider).value, isA<SignedOut>());
    expect(await store.read(), isNull);
    // The refresh token was revoked server-side.
    await expectLater(
        repo
            .refresh(
                (await repo.signInWithEmail(email: email, password: password))
                    .refreshToken)
            .then((_) => null),
        completes);
  }, skip: skip);

  test(
      'cloud sync: SQLite queue -> client -> API -> PostgreSQL, idempotent per day',
      () async {
    final login = await repo.signInWithEmail(email: email, password: password);
    final store = InMemoryTokenStore();
    await store.write(login);
    final m = manager(store);
    final db = await WattByteDb.open(path: inMemoryDatabasePath);
    addTearDown(db.close);
    final sync =
        SyncService(db: db, apis: apis, sessions: m, platform: 'android');
    // Cloud sync is a per-account opt-in (docs/SYNC_OWNERSHIP.md): nothing is
    // uploaded for an account that did not switch it on.
    await sync.enable(SyncScope.history);

    DailyAggregate agg(String date, int mobile) => DailyAggregate(
          date: date,
          mobileBytes: mobile,
          wifiBytes: 5000,
          chargedWh: 12.5,
          wallWh: 14.706,
          chargingSessions: 2,
          estimatedCost: 0.0169,
          currency: 'PLN',
        );
    DateTime day(String k) {
      final p = k.split('-').map(int.parse).toList();
      return DateTime(p[0], p[1], p[2]);
    }

    Future<void> queue(DailyAggregate a) => db.upsertSyncItem(
        SyncQueueItem(day: day(a.date), payload: a, updatedAt: DateTime.now()));

    await queue(agg('2026-10-10', 1000));
    await queue(agg('2026-10-11', 2000));
    await queue(agg('2026-10-12', 3000));
    final first = await sync.syncNow();
    expect(first.status, SyncStatus.synced);
    expect(first.uploaded, 3);

    final client = apis.bearer(login.accessToken);
    var daily = await api.UsageApi(client)
        .apiV1UsageDailyGet('2026-10-01', '2026-10-31');
    expect(daily!.days.map((d) => d.date),
        ['2026-10-10', '2026-10-11', '2026-10-12']);
    expect(daily.days.map((d) => d.mobileBytes), [1000, 2000, 3000]);

    // The day is re-aggregated with new numbers and sent again: replaced, not duplicated.
    await queue(agg('2026-10-11', 9999));
    expect((await sync.syncNow()).status, SyncStatus.synced);
    daily = await api.UsageApi(client)
        .apiV1UsageDailyGet('2026-10-01', '2026-10-31');
    expect(daily!.days, hasLength(3));
    expect(daily.days[1].mobileBytes, 9999);

    // One device, however many syncs.
    final devices = await api.DevicesApi(client).apiV1DevicesGet();
    expect(devices!.devices, hasLength(1));
    expect(devices.devices.single.installationId, await sync.installationId());
    expect(devices.devices.single.model, isNull);
  }, skip: skip);

  test(
      'AI: Flutter -> API -> AI gateway -> provider -> Flutter, with the daily limit enforced',
      () async {
    final login = await repo.signInWithEmail(email: email, password: password);
    final store = InMemoryTokenStore();
    await store.write(login);
    final ai = AiService(apis: apis, sessions: manager(store));
    final stats = AiPeriodStats.thisMonth(
      days: [
        DailyData(
            day: DateTime(2026, 10, 5),
            mobileRx: 4e9.toInt(),
            mobileTx: 1e9.toInt(),
            wifiRx: 3e10.toInt())
      ],
      sessions: [
        ChargingSession(
            start: DateTime(2026, 10, 5, 22),
            end: DateTime(2026, 10, 6, 6),
            startLevel: 20,
            endLevel: 100,
            chargeDeltaUah: 3200000)
      ],
      calc: EnergyCalc(
          batteryCapacityMah: 4000,
          nominalVoltage: 3.85,
          efficiency: 0.85,
          pricePerKwh: 1.1),
      currency: 'PLN',
      now: DateTime(2026, 10, 13, 12),
    );
    expect(stats.isEmpty, isFalse);

    final insight =
        await ai.generate(AiKind.insight, stats, languageCode: 'pl');
    expect(insight.title, isNotEmpty);
    expect(insight.message, isNotEmpty);
    expect(insight.remainingToday, 3);
    final roast = await ai.generate(AiKind.roast, stats, languageCode: 'en');
    expect(roast.remainingToday, 2);
    await ai.generate(AiKind.insight, stats, languageCode: 'en');
    await ai.generate(AiKind.insight, stats, languageCode: 'en');
    await expectLater(
        ai.generate(AiKind.insight, stats, languageCode: 'en'),
        throwsA(isA<AiException>()
            .having((e) => e.error, 'error', AiError.quotaExceeded)));
  }, skip: skip);

  test(
      'automatic setup: Eurostat household price for PL through the API, '
      'account settings round trip, device-bound battery spec on the registration',
      () async {
    final store = InMemoryTokenStore();
    await store
        .write(await repo.signInWithEmail(email: email, password: password));
    final sessions = manager(store);

    // Flutter -> WattByte API -> Eurostat (the app never calls Eurostat itself).
    final prices = ElectricityPriceService(apis: apis, sessions: sessions);
    final pl = await prices.fetch('PL');
    expect(pl, isNotNull, reason: 'Eurostat nrg_pc_204 has PL in band DC');
    expect(pl!.currency, 'PLN');
    expect(pl.pricePerKwh, inInclusiveRange(0.3, 5),
        reason: 'a household PLN/kWh price, not a wholesale MWh price');
    expect(pl.period, matches(RegExp(r'^\d{4}-S[12]$')));
    expect(pl.source, 'eurostat');
    // Second call is served from the API cache: same period and value.
    final again = await prices.fetch('PL');
    expect(again!.pricePerKwh, pl.pricePerKwh);
    expect(again.period, pl.period);
    // A country outside every source: unavailable, never invented.
    expect(await prices.fetch('AQ'), isNull);

    // Account-bound settings follow the account.
    final account = AccountSettingsSync(apis: apis, sessions: sessions);
    const s = Settings(
        countryCode: 'PL',
        currency: 'PLN',
        priceMode: ElectricityPriceMode.manual,
        priceSource: SettingSource.manual,
        manualPricePerKwh: 0.95,
        pricePerKwh: 0.95);
    final pushed = await account.push(s);
    expect(pushed, isNotNull);
    expect(pushed!.groups,
        {SettingGroup.region, SettingGroup.currency, SettingGroup.price});
    final pulled = await account.pull();
    expect(pulled!.countryCode, 'PL');
    expect(pulled.countryCodeSource,
        api.UserSettingsDtoCountryCodeSourceEnum.detected);
    expect(pulled.currencyCode, 'PLN');
    expect(pulled.currencyCodeSource,
        api.UserSettingsDtoCurrencyCodeSourceEnum.detected);
    expect(pulled.electricityPriceMode,
        api.UserSettingsDtoElectricityPriceModeEnum.manual);
    expect(pulled.manualElectricityPrice, 0.95);
    expect(pulled.electricityPriceSource,
        api.UserSettingsDtoElectricityPriceSourceEnum.manual);

    // Device-bound battery facts go with the device registration: the design
    // capacity of the model (here from the bundled catalog) ...
    final db = await WattByteDb.open(path: inMemoryDatabasePath);
    final sync =
        SyncService(db: db, apis: apis, sessions: sessions, platform: 'ios');
    await sync.registerDevice(DeviceSpecification(
      manufacturer: 'Apple',
      model: 'iPhone 15 Pro',
      modelIdentifier: 'iPhone16,1',
      design: DesignCapacity(
          mah: 3274,
          wh: 12.7,
          source: DesignCapacitySource.localDeviceDatabase),
    ));
    final devices = await sessions
        .authorized((t) => api.DevicesApi(apis.bearer(t)).apiV1DevicesGet());
    final mine =
        devices!.devices.firstWhere((d) => d.modelIdentifier == 'iPhone16,1');
    expect(mine.designCapacityMah, 3274);
    expect(mine.designCapacityWh, 12.7);
    expect(mine.designCapacitySource,
        api.DeviceDtoDesignCapacitySourceEnum.localDeviceDatabase);
    expect(mine.estimatedFullChargeCapacityMah, isNull,
        reason: 'no reading, no estimate (iOS has no charge counter)');
    expect(mine.fullChargeCapacitySource, isNull);
    expect(mine.fullChargeCapacityConfidence, isNull);
    // The public catalog endpoint answers the same model with its DESIGN
    // capacity, and 404 for an unknown one.
    final spec = await api.DevicesApi(apis.anonymous())
        .apiV1DevicesSpecificationsIdentifierGet('iPhone16,1');
    expect(spec!.designCapacityMah, 3274);
    expect(spec.designCapacityWh, 12.7);
    await expectLater(
        api.DevicesApi(apis.anonymous())
            .apiV1DevicesSpecificationsIdentifierGet(
                'Acme-Does-Not-Exist-9000'),
        throwsA(isA<api.ApiException>().having((e) => e.code, 'status', 404)));
    await db.close();
  }, skip: skip);

  test(
      'battery capacity through the app: design + estimate registered by '
      'SyncService, read back, atomic per group, charge counter never a design',
      () async {
    final store = InMemoryTokenStore();
    await store
        .write(await repo.signInWithEmail(email: email, password: password));
    final sessions = manager(store);

    Future<api.DeviceDto> readBack(String installation) async {
      final all = await sessions
          .authorized((t) => api.DevicesApi(apis.bearer(t)).apiV1DevicesGet());
      return all!.devices.singleWhere((d) => d.installationId == installation);
    }

    // A fresh in-memory database (`singleInstance: false`) is a fresh installation, so each phone below is its own
    // device record on the account.
    Future<(SyncService, WattByteDb, String)> phone() async {
      final db = await WattByteDb.openInMemory();
      addTearDown(db.close);
      final sync = SyncService(
          db: db, apis: apis, sessions: sessions, platform: 'android');
      return (sync, db, await sync.installationId());
    }

    EstimatedFullChargeCapacity reading(int level, double storedMah,
            {int? energyNwh}) =>
        FullChargeCapacityEstimator.estimate(
            chargeUah: storedMah * 1000,
            energyNwh: energyNwh,
            level: level,
            measuredAt: DateTime.now());

    // 1. A catalog model with a 100 % reading: both groups, high confidence.
    final (sync, _, installation) = await phone();
    const pixel = DeviceSpecification(
        manufacturer: 'Google', model: 'Pixel 8', modelIdentifier: 'Pixel 8');
    final catalog = DesignCapacity(
        mah: 4575, source: DesignCapacitySource.localDeviceDatabase);
    await sync.registerDevice(
        DeviceSpecification(
            manufacturer: pixel.manufacturer,
            model: pixel.model,
            modelIdentifier: pixel.modelIdentifier,
            design: catalog),
        fullCharge: reading(100, 4300, energyNwh: 16500000000));
    var d = await readBack(installation);
    expect(d.designCapacityMah, 4575);
    expect(d.designCapacitySource,
        api.DeviceDtoDesignCapacitySourceEnum.localDeviceDatabase);
    expect(d.estimatedFullChargeCapacityMah, 4300);
    expect(d.estimatedFullChargeCapacityWh, 16.5);
    expect(d.fullChargeCapacitySource,
        api.DeviceDtoFullChargeCapacitySourceEnum.androidChargeCounter);
    expect(d.fullChargeCapacityConfidence,
        api.DeviceDtoFullChargeCapacityConfidenceEnum.high);

    // 2. The same phone registers again with NO estimate (null fields, never
    //    source "unknown"): the stored estimate survives.
    await sync.registerDevice(DeviceSpecification(
        manufacturer: pixel.manufacturer,
        model: pixel.model,
        modelIdentifier: pixel.modelIdentifier,
        design: catalog));
    d = await readBack(installation);
    expect(d.estimatedFullChargeCapacityMah, 4300);
    expect(d.fullChargeCapacityConfidence,
        api.DeviceDtoFullChargeCapacityConfidenceEnum.high);

    // 3. A weaker reading replaces the group as a whole (no stale Wh next to
    //    the new mAh) and leaves the design alone.
    await sync.registerDevice(
        DeviceSpecification(
            manufacturer: pixel.manufacturer,
            model: pixel.model,
            modelIdentifier: pixel.modelIdentifier,
            design: catalog),
        fullCharge: reading(50, 2000));
    d = await readBack(installation);
    expect(d.estimatedFullChargeCapacityMah, 4000);
    expect(d.estimatedFullChargeCapacityWh, isNull);
    expect(d.fullChargeCapacityConfidence,
        api.DeviceDtoFullChargeCapacityConfidenceEnum.low);
    expect(d.designCapacityMah, 4575);

    // 4. The most important rule: Android charge counter != design capacity. A
    //    model no catalog knows stays unknown on the server, however reliable
    //    the reading.
    final (other, _, otherInstallation) = await phone();
    await other.registerDevice(
        const DeviceSpecification(
            manufacturer: 'Acme', model: 'Z1', modelIdentifier: 'Acme Z1'),
        fullCharge: reading(100, 4321));
    d = await readBack(otherInstallation);
    expect(d.designCapacityMah, isNull);
    expect(d.designCapacityWh, isNull);
    expect(
        d.designCapacitySource, api.DeviceDtoDesignCapacitySourceEnum.unknown);
    expect(d.estimatedFullChargeCapacityMah, 4321);
    expect(d.fullChargeCapacitySource,
        api.DeviceDtoFullChargeCapacitySourceEnum.androidChargeCounter);
    expect(d.fullChargeCapacityConfidence,
        api.DeviceDtoFullChargeCapacityConfidenceEnum.high);

    // 5. A manual design capacity, no counter at all (an unsupported counter
    //    leaves the estimate group null).
    final (manual, _, manualInstallation) = await phone();
    await manual.registerDevice(DeviceSpecification(
        manufacturer: 'Acme',
        model: 'Z2',
        modelIdentifier: 'Acme Z2',
        design:
            DesignCapacity(mah: 4800, source: DesignCapacitySource.manual)));
    d = await readBack(manualInstallation);
    expect(d.designCapacityMah, 4800);
    expect(
        d.designCapacitySource, api.DeviceDtoDesignCapacitySourceEnum.manual);
    expect(d.estimatedFullChargeCapacityMah, isNull);
    expect(d.fullChargeCapacitySource, isNull);
  }, skip: skip);

  test('delete account: the account and its sessions are gone', () async {
    final login = await repo.signInWithEmail(email: email, password: password);
    final store = InMemoryTokenStore();
    await store.write(login);
    await manager(store).authorized((t) => repo.deleteAccount(t));
    await expectLater(
        repo.signInWithEmail(email: email, password: password),
        throwsA(isA<AuthException>()
            .having((e) => e.error, 'error', AuthError.invalidCredentials)));
    await expectLater(
        repo.me(login.accessToken),
        throwsA(isA<AuthException>()
            .having((e) => e.error, 'error', AuthError.sessionExpired)));
  }, skip: skip);
}
