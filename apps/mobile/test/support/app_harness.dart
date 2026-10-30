// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

/// Widget-test harness for the real WattByte app.
///
/// Pumps the REAL `WattByteApp` (real MaterialApp builder, theme, l10n, start
/// gate, shell, dashboard) - or a single screen inside the same theme/l10n -
/// at any text scale, screen size, brightness, locale and platform, on top of
/// realistic seeded data, with every native/network edge replaced by a fake:
///
/// | edge                         | replaced by                                  |
/// |------------------------------|----------------------------------------------|
/// | SQLite                       | in-memory `sqflite_common_ffi` [WattByteDb]  |
/// | SharedPreferences            | `setMockInitialValues`                       |
/// | `wattbyte/system` channel    | [FakeSystem] (iOS or Android personality)    |
/// | Keychain / Keystore          | `InMemoryTokenStore`                         |
/// | auth backend                 | `MockAuthRepository` (password: `password`)  |
/// | HTTP (`ApiFactory`)          | [FakeBackend] (`MockClient`, no network)     |
/// | local notifications          | [FakeAppNotifier]                            |
/// | home-screen widget publisher | [FakeWidgetPublisher]                        |
///
/// ## Usage
///
/// ```dart
/// import '../support/app_harness.dart';
///
/// testWidgets('dashboard fits at every text scale', (tester) async {
///   final h = await pumpApp(tester, device: kIPhoneSE);   // signed in, seeded
///   for (final scale in kTextScales) {
///     await h.setTextScale(tester, scale);                // re-lays out in place
///     expectNoFlutterErrors(tester, screen: 'Dashboard'); // all 4 tabs checked
///   }
/// });
///
/// testWidgets('every device x scale x brightness', (tester) async {
///   final h = await pumpApp(tester, signedIn: false);     // Welcome
///   await sweepViews(tester, h, () async {
///     expectNoFlutterErrors(tester, screen: 'Welcome');
///   }, brightnesses: Brightness.values);                  // lists ALL failures
/// });
///
/// testWidgets('welcome is accessible at 2x', (tester) async {
///   await pumpApp(tester, signedIn: false, textScale: 2.0, semantics: true);
///   await expectAccessibleTargets(tester, screen: 'Welcome');
///   expect(semanticsWithLabel(tester, 'Sign in').single.tappable, isTrue);
/// });
///
/// testWidgets('a screen in isolation, Android, dark, Polish', (tester) async {
///   await pumpScreen(tester, const StatisticsScreen(),
///       textScale: 3.0, platform: HarnessPlatform.android,
///       brightness: Brightness.dark, locale: const Locale('pl'));
///   expectNoFlutterErrors(tester, screen: 'Statistics');
/// });
/// ```
///
/// Knobs of [pumpApp] / [pumpScreen]: `textScale`, `device` (a [ScreenSpec];
/// [kScreenSizes] has four) or a plain `size`, `brightness`, `locale`,
/// `platform`, `signedIn`, `onboarded`, `apiConfigured`, `appConfig` (`pumpApp`
/// only: any [AppConfig] instead of the one `apiConfigured` derives), `settings`,
/// `historyDays` (0 = fresh install), `now` (default [harnessNow]), `chargingNow`, `plan`,
/// `accessibilityFeatures` (bold text, reduce motion, ...), `semantics`.
/// Change them later, in place, with [AppHarness.configure] and its `set*`
/// shortcuts. Reach the fakes through the returned [AppHarness]: `h.system`
/// (what the native side answers and was asked), `h.backend` (HTTP routes and
/// requests), `h.db`, `h.prefs`, `h.notifier`, `h.widgets`, `h.container(tester)`.
///
/// Battery capacity has two separate faces (docs/BATTERY_CAPACITY.md): the
/// DESIGN capacity of the model is a setting ([AppHarness.defaultSettings]:
/// the catalog figure, e.g. 4575 mAh for the Pixel 8); the ESTIMATED full-charge
/// capacity of this battery is not a setting but a reading the collector keeps
/// in the database. Put one there with [seedFullChargeEstimate], or let the real
/// `Collector` produce it from [FakeSystem.setReading] (the charge counter is
/// the charge stored in the battery, not a capacity).
///
/// ## Things that matter
///
/// * **Fonts.** `flutter test` renders every glyph as a 1em square (the Ahem
///   font), which overflows far more than any real device: the real Dashboard
///   "overflows" at text scale 1.0 on an iPhone SE in Ahem and fits in Roboto.
///   The harness therefore loads Roboto from the Flutter SDK cache under the
///   families Material and Cupertino ask for, so text metrics are realistic
///   (iOS' SF Pro is a few percent wider than Roboto; treat a margin below ~5%
///   as a coin flip). `realFonts: false` gives Ahem back on purpose.
/// * **Text scale, size, brightness, locale** are driven through
///   `tester.platformDispatcher.*TestValue` and `tester.view.*`, i.e. through
///   the same inputs a real device gives Flutter. The harness never touches
///   the app's own scaling code, so it behaves the same with or without the
///   clamp in `lib/app.dart` (`pumpScreen` never has the clamp).
/// * **Overflow detection** ([expectNoFlutterErrors]) combines the errors
///   Flutter reported with a scan of the render tree for layouts that overflow
///   right now. Flutter reports an overflow once per render object, so the
///   report alone misses overflows that appear after an in-place text-scale
///   change and ones you check twice. The scan also sees tabs that are not
///   visible (offstage children are laid out). Painting-based checks - the
///   accessibility guidelines, [semanticsNodes] - only see what is visible:
///   [AppHarness.tapTab] to each tab first.
/// * **Platform.** `flutter test` reports `defaultTargetPlatform == android`;
///   the harness sets it to the chosen [HarnessPlatform] (default iOS) so the
///   Flutter side agrees with the fake native side, and undoes it when the tree
///   is unmounted.
/// * **Time.** Screen periods and seed data share [AppHarness.now], defaulting
///   to [harnessNow] through [clockProvider]. No test data or date label depends
///   on the host clock, including when a suite runs across midnight. Pass `now`
///   to exercise another time; sessions are still only seeded once completed.
/// * **Async.** SQLite runs through `databaseFactoryFfiNoIsolate`, so
///   `pump()` is enough to complete database work; no `runAsync` is needed.
///   [settle] pumps until the app is quiet. `databaseFactory` is a
///   process-wide setting; the harness sets it once.
/// * **One database at a time.** In-memory SQLite is one database per
///   process, so creating a second harness in the same test disposes the first
///   (its database is closed; using the old object afterwards fails loudly).
///   Pass `harness: h` to keep state across pumps.
/// * **Cleanup.** Everything the harness changes (test values, platform
///   override, semantics handle, DB, channel handler, FlutterError.onError) is
///   undone when the widget tree is unmounted or in `addTearDown`; no state
///   leaks between tests or test files. (The platform override and the
///   semantics handle are flutter_test invariants, checked before `addTearDown`
///   runs, which is why they are released from a widget's `dispose`.)
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wattbyte/analytics/dashboard_model.dart';
import 'package:wattbyte/analytics/notification_rules.dart';
import 'package:wattbyte/api/api_config.dart';
import 'package:wattbyte/api/api_factory.dart';
import 'package:wattbyte/app.dart';
import 'package:wattbyte/background/app_notifier.dart';
import 'package:wattbyte/background/refresh_service.dart';
import 'package:wattbyte/background/widget_publisher.dart';
import 'package:wattbyte/cloud_providers.dart';
import 'package:wattbyte/config/app_config.dart';
import 'package:wattbyte/config/config_providers.dart';
import 'package:wattbyte/core/periods.dart';
import 'package:wattbyte/core/units.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/features/auth/data/auth_repositories.dart';
import 'package:wattbyte/features/auth/data/secure_token_store.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/features/auth/presentation/auth_controller.dart';
import 'package:wattbyte/l10n/generated/app_localizations.dart';
import 'package:wattbyte/providers.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/storage/database.dart';
import 'package:wattbyte/ui/theme.dart';

import 'fake_backend.dart';
import 'fake_system.dart';

export 'fake_backend.dart' show FakeBackend;
export 'fake_system.dart' show FakeSystem, HarnessPlatform;

// ---------------------------------------------------------------------------
// Matrices: text scales and screens
// ---------------------------------------------------------------------------

/// Text scale factors to sweep: default, iOS "Extra Large" (the old app clamp),
/// Android large font, iOS accessibility sizes up to the maximum.
const kTextScales = <double>[1.0, 1.35, 1.6, 2.0, 3.0];

/// A device screen in logical pixels, with the system insets that SafeArea sees.
class ScreenSpec {
  const ScreenSpec(
    this.name,
    this.size,
    this.devicePixelRatio, {
    this.safeArea = EdgeInsets.zero,
  });

  /// A screen of exactly [size] with no insets (3x).
  const ScreenSpec.custom(Size size)
      : this('custom', size, 3, safeArea: EdgeInsets.zero);

  final String name;

  /// Logical pixels.
  final Size size;
  final double devicePixelRatio;

  /// Status bar / home indicator / notch insets, logical pixels.
  final EdgeInsets safeArea;

  Size get physicalSize => size * devicePixelRatio;

  @override
  String toString() =>
      '$name ${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)}';
}

const kIPhoneSE = ScreenSpec('iPhone SE', Size(375, 667), 3,
    safeArea: EdgeInsets.only(top: 20));
const kIPhone17Pro = ScreenSpec('iPhone 17 Pro', Size(402, 874), 3,
    safeArea: EdgeInsets.only(top: 62, bottom: 34));
const kIPhone17ProLandscape = ScreenSpec(
    'iPhone 17 Pro landscape', Size(874, 402), 3,
    safeArea: EdgeInsets.only(left: 62, right: 62, bottom: 21));
const kTablet = ScreenSpec('tablet', Size(820, 1180), 2,
    safeArea: EdgeInsets.only(top: 24, bottom: 20));

/// The screens to sweep: smallest phone, current phone, landscape, tablet.
const kScreenSizes = <ScreenSpec>[
  kIPhoneSE,
  kIPhone17Pro,
  kIPhone17ProLandscape,
  kTablet,
];

// ---------------------------------------------------------------------------
// Fakes the harness owns
// ---------------------------------------------------------------------------

/// Records notifications instead of talking to the OS.
class FakeAppNotifier implements AppNotifier {
  /// What `requestPermission` answers.
  bool permissionGranted = true;
  int permissionRequests = 0;
  final List<PendingNotification> shown = [];

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permissionGranted;
  }

  @override
  Future<void> showAll(
    List<PendingNotification> pending, {
    required SettingsStore store,
    required AppLocalizations l10n,
    required Units units,
    required String currency,
  }) async {
    for (final n in pending) {
      shown.add(n);
      await store.markSent(n.key);
    }
  }
}

/// Records what would be pushed to the home-screen widgets.
class FakeWidgetPublisher implements WidgetPublisher {
  int publishCount = 0;
  DashboardModel? lastModel;

  @override
  Future<void> publish({
    required DashboardModel model,
    required Units units,
    required AppLocalizations l10n,
    required String currency,
    required bool hasPrice,
  }) async {
    publishCount++;
    lastModel = model;
  }
}

/// `MockAuthRepository` whose `me()` answers the signed-in harness user instead
/// of a fixed `mock@example.com`, so the account screen stays consistent.
///
/// A session this repository issued (sign-in, sign-up) is answered with the user
/// it was issued to, as the real API does: the same account keeps one id, which
/// matters now that the account-bound settings are stored per account.
class HarnessAuthRepository extends MockAuthRepository {
  HarnessAuthRepository({this.user = harnessUser});

  User user;
  final Map<String, User> _issued = {};

  AuthSession _remember(AuthSession s, String email) {
    // The harness account signing in again is the same account.
    final session = email == user.email
        ? AuthSession(
            accessToken: s.accessToken,
            refreshToken: s.refreshToken,
            expiresAt: s.expiresAt,
            user: user)
        : s;
    _issued[session.accessToken] = session.user;
    return session;
  }

  @override
  Future<AuthSession> signInWithEmail(
          {required String email, required String password}) async =>
      _remember(
          await super.signInWithEmail(email: email, password: password), email);

  @override
  Future<AuthSession> signUpWithEmail(
          {required String email, required String password}) async =>
      _remember(
          await super.signUpWithEmail(email: email, password: password), email);

  @override
  Future<User> me(String accessToken) async {
    final f = meFailure;
    if (f != null) throw AuthException(f);
    return _issued[accessToken] ?? user;
  }
}

const harnessUser = User(
    id: 'harness-user', email: 'tester@example.com', displayName: 'Tester');

AuthSession harnessSession({User user = harnessUser}) => AuthSession(
      accessToken: 'harness-access',
      refreshToken: 'harness-refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      user: user,
    );

// ---------------------------------------------------------------------------
// Seed data
// ---------------------------------------------------------------------------

/// What [seedHistory] wrote.
class SeededHistory {
  const SeededHistory(this.days, this.sessions);

  final List<DailyData> days;
  final List<ChargingSession> sessions;
}

/// Default local time for app data and screen periods in widget tests.
final harnessNow = DateTime(2026, 10, 13, 12);

const _mb = 1024 * 1024;

/// Writes `days` days of plausible usage and charging sessions.
///
/// Deterministic: the numbers of "N days ago" depend only on [seed] and N, never
/// on the calendar date or the wall clock. Today's overnight session is included
/// only after its seeded end time (06:50-07:29, 07:07 for the default seed).
/// [now] defaults to [harnessNow], so the default fixture always includes it.
///
/// * Data: 0.2-0.9 GB mobile and 1.4-4.6 GB Wi-Fi per day, more on every 6th
///   and 7th offset ("weekend"); today holds ~45% of a normal day.
/// * Charging: one overnight charge (00:20 -> ~06:50, from ~6-36% to 100%) per
///   day and a short afternoon top-up on about 40% of days. Always in the past.
/// * [estimated] flags rows as iOS-style estimates and marks ~15% of sessions
///   `sparse`; [measuredEnergy] adds Android charge/energy counter deltas
///   (`capacityMah` is what they are derived from).
/// * [chargingNow] adds three plugged samples ending now (an open session).
Future<SeededHistory> seedHistory(
  WattByteDb db, {
  int days = 45,
  DateTime? now,
  int seed = 7,
  bool estimated = true,
  bool measuredEnergy = false,
  double capacityMah = 3988,
  bool chargingNow = false,
}) async {
  final at = now ?? harnessNow;
  final today = dayOf(at);
  final rows = <DailyData>[];
  final sessions = <ChargingSession>[];

  for (var offset = days - 1; offset >= 0; offset--) {
    final rng = Random(seed * 1009 + offset);
    final day = DateTime(today.year, today.month, today.day - offset);
    final weekend = offset % 7 >= 5;
    final scale = offset == 0 ? 0.45 : 1.0;

    int bytes(int minMb, int spanMb) =>
        ((minMb + rng.nextInt(spanMb)) * _mb * scale).round();
    final mobile = bytes(weekend ? 260 : 180, 640);
    final wifi = bytes(weekend ? 2600 : 1400, 2100);
    final rxShare = 0.88 + rng.nextDouble() * 0.05;
    rows.add(DailyData(
      day: day,
      mobileRx: (mobile * rxShare).round(),
      mobileTx: mobile - (mobile * rxShare).round(),
      wifiRx: (wifi * rxShare).round(),
      wifiTx: wifi - (wifi * rxShare).round(),
      estimated: estimated,
    ));

    ChargingSession session(DateTime start, Duration length, int from, int to) {
      final added = to - from;
      final uah = measuredEnergy ? (added * capacityMah * 10).round() : null;
      return ChargingSession(
        start: start,
        end: start.add(length),
        startLevel: from,
        endLevel: to,
        chargeDeltaUah: uah,
        energyDeltaNwh: uah == null ? null : uah * 3850,
        avgVoltageMv: measuredEnergy ? 3800 + rng.nextInt(300) : null,
        sparse: estimated && rng.nextDouble() < 0.15,
      );
    }

    final overnightEnd =
        DateTime(day.year, day.month, day.day, 6, 50 + rng.nextInt(40));
    final overnightFrom = 6 + rng.nextInt(30);
    final overnightIsPast = !overnightEnd.isAfter(at);
    if (overnightIsPast) {
      sessions.add(session(
          DateTime(day.year, day.month, day.day, 0, 20),
          overnightEnd
              .difference(DateTime(day.year, day.month, day.day, 0, 20)),
          overnightFrom,
          100));
    }
    if (offset > 0 && rng.nextDouble() < 0.4) {
      final from = 40 + rng.nextInt(20);
      sessions.add(session(
          DateTime(day.year, day.month, day.day, 13, 5 + rng.nextInt(90)),
          Duration(minutes: 25 + rng.nextInt(30)),
          from,
          from + 15 + rng.nextInt(20)));
    }
  }

  await db.replaceDaily(rows);
  await db.insertSessions(sessions);
  if (chargingNow) {
    await db.insertSamples([
      for (final (i, level) in const [48, 57, 66].indexed)
        BatterySample(
          time: at.subtract(Duration(minutes: 50 - i * 20)),
          level: level,
          plugged: true,
          chargeUah: measuredEnergy ? (level * capacityMah * 10).round() : null,
          voltageMv: measuredEnergy ? 4000 : null,
        ),
    ]);
  }
  return SeededHistory(rows, await db.allSessions());
}

/// Stores an estimated full-charge capacity the way the collector keeps it (the
/// meta table, read back by `Collector.fullChargeCapacity`) and returns it.
///
/// The estimate comes from the real [FullChargeCapacityEstimator]: a battery
/// that holds [mah] when full, read at battery [level], reports a charge
/// counter of `mah * level / 100`, which extrapolates back to [mah] with the
/// confidence of that level (95 % and up high, 75-94 % medium, 40-74 % low).
/// [wh] is the same for the energy counter. This is an ESTIMATE of this
/// battery; it never touches the design capacity in [Settings].
Future<EstimatedFullChargeCapacity> seedFullChargeEstimate(
  WattByteDb db, {
  double mah = 3600,
  int level = 100,
  double? wh,
  DateTime? measuredAt,
}) async {
  final estimate = FullChargeCapacityEstimator.estimate(
    chargeUah: mah * level / 100 * 1000,
    energyNwh: wh == null ? null : wh * level / 100 * 1e9,
    level: level,
    measuredAt: measuredAt ?? DateTime.now(),
  );
  if (!estimate.isAvailable) {
    throw ArgumentError('$mah mAh at $level % is not an available estimate');
  }
  for (final e in estimate.toMeta().entries) {
    await db.setMeta(e.key, e.value);
  }
  return estimate;
}

// ---------------------------------------------------------------------------
// The harness
// ---------------------------------------------------------------------------

/// Everything a test needs around the app: the fakes, the database, the
/// preferences, and the knobs to change the environment while the app runs.
///
/// Created by [pumpApp] / [pumpScreen]; create one yourself with
/// [AppHarness.create] only when a test needs it before the first pump.
class AppHarness {
  AppHarness._({
    required this.platform,
    required this.appConfig,
    required this.db,
    required this.prefs,
    required this.system,
    required this.backend,
    required this.authRepository,
    required this.tokenStore,
    required this.history,
    required this.now,
  }) {
    overrides = [
      clockProvider.overrideWithValue(() => now),
      prefsProvider.overrideWithValue(prefs),
      dbProvider.overrideWithValue(db),
      systemProvider.overrideWithValue(system.system),
      appConfigProvider.overrideWithValue(appConfig),
      apiConfigProvider.overrideWithValue(apiConfig),
      apiFactoryProvider
          .overrideWithValue(ApiFactory(apiConfig, httpClient: backend.client)),
      authRepositoryProvider.overrideWithValue(authRepository),
      tokenStoreProvider.overrideWithValue(tokenStore),
      notifierProvider.overrideWithValue(notifier),
      // `refreshServiceProvider` builds its own `WidgetPublisher()`; there is no
      // provider for it, so the whole service is rebuilt from the same parts.
      refreshServiceProvider.overrideWith((ref) => RefreshService(
            collector: ref.watch(collectorProvider),
            db: ref.watch(dbProvider),
            widgets: widgets,
            notifier: ref.watch(notifierProvider),
            sync: ref.watch(syncServiceProvider),
          )),
    ];
  }

  /// Opens the in-memory database, loads the fonts and builds every fake.
  ///
  /// * [onboarded] null = whatever [settings] says (default settings: true).
  /// * [apiConfigured] true = the normal build (`API_BASE_URL` set, account
  ///   required); false = the explicit debug-only `LOCAL_ONLY_DEV` mode
  ///   (no API, no accounts).
  /// * [signedIn] only matters with [apiConfigured]: in local-only mode the
  ///   build has no accounts and starts at setup/dashboard (as `startDestination`).
  /// * [appConfig], when given, is the build configuration the app runs with
  ///   INSTEAD of the one derived from [apiConfigured] - for tests of
  ///   configurations the harness never builds on its own (an invalid one, a
  ///   release-mode one). [signedIn] still stores a session when
  ///   [apiConfigured] is true (its default), whatever [appConfig] says.
  /// * [historyDays] 0 = a fresh install without any data.
  static Future<AppHarness> create(
    WidgetTester tester, {
    HarnessPlatform platform = HarnessPlatform.ios,
    bool signedIn = true,
    bool? onboarded,
    bool apiConfigured = true,
    AppConfig? appConfig,
    Settings? settings,
    int historyDays = 45,
    bool chargingNow = false,
    Plan plan = Plan.free,
    Locale locale = const Locale('en'),
    bool realFonts = true,
    Map<String, Object> prefsValues = const {},
    FakeSystem? system,
    AuthRepository? authRepository,
    bool installErrorLog = true,
    DateTime? now,
  }) async {
    final at = now ?? harnessNow;
    // In-memory SQLite is one database per process: a second harness would
    // silently share the first one's data. The previous harness is therefore
    // disposed first (its database closed), and using it afterwards fails loudly.
    await _current?._dispose();
    // rootBundle memoizes the Future of every asset it loaded (e.g. the device catalog). A Future created inside the
    // previous test's FakeAsync zone is never completed in this test's zone and the second test of a file would hang
    // in 'Setting up WattByte...'. Evicting the entry gives every harness a fresh load.
    rootBundle.evict('assets/device_specs/devices.json');
    if (realFonts) await loadRealFonts(tester);

    if (!_factoryReady) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfiNoIsolate;
      _factoryReady = true;
    }
    final db = await WattByteDb.open(path: inMemoryDatabasePath);
    final fake = system ??
        FakeSystem(
          platform: platform,
          clock: () => at,
          chargeCounterMah: platform.isIos ? null : 4575 * 0.78,
        );
    final AppHarness harness;
    try {
      final device = fake.platform;
      if (chargingNow) fake.plugged = true;

      SharedPreferences.setMockInitialValues(prefsValues);
      final prefs = await SharedPreferences.getInstance();
      final store = SettingsStore(prefs);
      final base = settings ??
          ((onboarded ?? true)
              ? defaultSettings(device, now: at)
              : const Settings());
      await store.save(base.copyWith(onboarded: onboarded ?? base.onboarded));
      await store.setLocale(_tag(locale));

      final user = User(
          id: harnessUser.id,
          email: harnessUser.email,
          displayName: harnessUser.displayName,
          plan: plan);
      final tokens = InMemoryTokenStore();
      if (signedIn && apiConfigured) {
        await tokens.write(harnessSession(user: user));
      }

      final backend = FakeBackend();
      _defaultRoutes(backend);

      final seeded = historyDays <= 0
          ? const SeededHistory([], [])
          : await seedHistory(db,
              days: historyDays,
              now: at,
              estimated: device.isIos,
              measuredEnergy: !device.isIos,
              capacityMah: device.isIos ? 3988 : 4575,
              chargingNow: chargingNow);

      harness = AppHarness._(
        platform: device,
        appConfig: appConfig ??
            AppConfig.fromDefines(
              buildMode: BuildMode.debug,
              apiBaseUrl: apiConfigured ? 'http://api.harness.test' : '',
              localOnlyDev: apiConfigured ? '' : 'true',
            ),
        db: db,
        prefs: prefs,
        system: fake,
        backend: backend,
        authRepository: authRepository ?? HarnessAuthRepository(user: user),
        tokenStore: tokens,
        history: seeded,
        now: at,
      );
    } catch (_) {
      await db.close();
      fake.dispose();
      rethrow;
    }
    if (installErrorLog) _errorLog = _FlutterErrorLog._install();
    _current = harness;
    addTearDown(() async {
      await harness._dispose();
      _errorLog?._uninstall();
      _errorLog = null;
      tester.view.reset();
      tester.platformDispatcher.clearAllTestValues();
    });
    return harness;
  }

  /// The live harness (at most one: see [create]).
  static AppHarness? _current;
  bool _disposed = false;

  /// `databaseFactory` is a process-wide setting and warns on every change.
  static bool _factoryReady = false;

  final HarnessPlatform platform;

  /// The build configuration the app under test runs with: normal online
  /// (`apiConfigured`) or the explicit local-only development mode.
  final AppConfig appConfig;
  ApiConfig get apiConfig => appConfig.api;
  final WattByteDb db;
  final SharedPreferences prefs;
  final FakeSystem system;

  /// All HTTP traffic of the app; add routes with `backend.routes['GET /path']`.
  final FakeBackend backend;
  final AuthRepository authRepository;
  final InMemoryTokenStore tokenStore;
  final SeededHistory history;

  /// Fixed app-data clock, also used by the screens through [clockProvider].
  final DateTime now;
  final FakeAppNotifier notifier = FakeAppNotifier();
  final FakeWidgetPublisher widgets = FakeWidgetPublisher();

  /// The provider overrides every pump uses (stable: same list each time).
  late final List<Override> overrides;

  SemanticsHandle? _semantics;
  _Environment _env = const _Environment();

  /// Realistic, fully configured settings (what a finished setup leaves behind):
  /// Poland, PLN, the average household price, the catalog battery.
  static Settings defaultSettings(HarnessPlatform platform, {DateTime? now}) =>
      Settings(
        currency: 'PLN',
        countryCode: 'PL',
        regionSource: SettingSource.detected,
        pricePerKwh: 1.15,
        autoPrice: AutoPrice(
          pricePerKwh: 1.15,
          currency: 'PLN',
          countryCode: 'PL',
          period: '2026-S1',
          source: 'eurostat',
          // Fresh: the app only refetches after 24 h.
          updatedAt: now ?? harnessNow,
        ),
        // The DESIGN capacity of the model (catalog figure); the estimated
        // full-charge capacity of this battery is not a setting (see
        // [seedFullChargeEstimate]).
        designCapacityMah: platform.isIos ? 3988 : 4575,
        designCapacitySource: DesignCapacitySource.localDeviceDatabase,
        deviceModel: platform.isIos ? 'iPhone 17 Pro' : 'Pixel 8',
        deviceModelIdentifier: platform.isIos ? 'iPhone18,1' : 'Pixel 8',
        onboarded: true,
      );

  static void _defaultRoutes(FakeBackend b) {
    b.routes['GET /api/v1/region'] = (r) =>
        FakeBackend.json({'countryCode': 'PL', 'source': 'backendCountry'});
    b.routes['GET /api/v1/electricity-price'] = (r) => FakeBackend.json({
          'countryCode': 'PL',
          'currency': 'PLN',
          'pricePerKwh': 1.15,
          'period': '2026-S1',
          'source': 'eurostat',
          'includesTaxes': true,
          'includesNetworkCosts': true,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
          'stale': false,
        });
    b.routes['POST /api/v1/devices'] =
        (r) => FakeBackend.json(FakeBackend.device('harness-device'), 201);
    b.routes['POST /api/v1/usage/sync'] = (r) {
      final days = (r.body!['days'] as List).cast<Map<String, dynamic>>();
      return FakeBackend.json({
        'accepted': days.length,
        'dates': days.map((d) => d['date']).toList(),
      });
    };
  }

  // ----------------------------------------------------------- environment

  /// Applies [textScale], [screen], [brightness], [locale], [platform] and
  /// accessibility features to the test view, then settles.
  ///
  /// This is the one place that writes the test values; [pumpApp] calls it, and
  /// so do the `set*` shortcuts below. Unspecified arguments keep their value.
  Future<void> configure(
    WidgetTester tester, {
    double? textScale,
    ScreenSpec? device,
    Brightness? brightness,
    Locale? locale,
    FakeAccessibilityFeatures? accessibilityFeatures,
    bool andSettle = true,
  }) async {
    _env = _env.copyWith(
      textScale: textScale,
      device: device,
      brightness: brightness,
      locale: locale,
      accessibilityFeatures: accessibilityFeatures,
    );
    final e = _env;
    final view = tester.view;
    view
      ..devicePixelRatio = e.device.devicePixelRatio
      ..physicalSize = e.device.physicalSize
      ..padding = _padding(e.device)
      ..viewPadding = _padding(e.device)
      ..viewInsets = FakeViewPadding.zero;
    tester.platformDispatcher
      ..textScaleFactorTestValue = e.textScale
      ..platformBrightnessTestValue = e.brightness
      ..localesTestValue = [e.locale]
      ..localeTestValue = e.locale
      ..accessibilityFeaturesTestValue = e.accessibilityFeatures;
    debugDefaultTargetPlatformOverride = platform.targetPlatform;
    if (andSettle) await settle(tester);
  }

  static FakeViewPadding _padding(ScreenSpec s) => FakeViewPadding(
        left: s.safeArea.left * s.devicePixelRatio,
        top: s.safeArea.top * s.devicePixelRatio,
        right: s.safeArea.right * s.devicePixelRatio,
        bottom: s.safeArea.bottom * s.devicePixelRatio,
      );

  Future<void> setTextScale(WidgetTester tester, double scale) =>
      configure(tester, textScale: scale);

  Future<void> setDevice(WidgetTester tester, ScreenSpec device) =>
      configure(tester, device: device);

  Future<void> setBrightness(WidgetTester tester, Brightness brightness) =>
      configure(tester, brightness: brightness);

  Future<void> setLocale(WidgetTester tester, Locale locale) =>
      configure(tester, locale: locale);

  /// What the view looks like now, for failure messages.
  String describe() => _env.describe(platform);

  /// Turns semantics on for the rest of the test (disposed automatically when
  /// the widget tree is unmounted). Idempotent.
  SemanticsHandle enableSemantics(WidgetTester tester) =>
      _semantics ??= tester.ensureSemantics();

  /// The Riverpod container of the pumped app (for reading/overriding state).
  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(_HarnessRoot)),
          listen: false);

  /// Taps bottom-navigation destination [index] (0 dashboard, 1 history,
  /// 2 insights, 3 settings) and settles. Only the visible tab is painted, so
  /// overflow in a tab is reported only after it was shown.
  Future<void> tapTab(WidgetTester tester, int index) async {
    await tester.tap(find.byType(NavigationDestination).at(index));
    await settle(tester);
  }

  /// Closes the database and the fake native side. Idempotent.
  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (identical(_current, this)) _current = null;
    _release();
    await db.close();
    system.dispose();
  }

  void _release() {
    _semantics?.dispose();
    _semantics = null;
    debugDefaultTargetPlatformOverride = null;
  }
}

class _Environment {
  const _Environment({
    this.textScale = 1.0,
    this.device = kIPhone17Pro,
    this.brightness = Brightness.light,
    this.locale = const Locale('en'),
    this.accessibilityFeatures = const FakeAccessibilityFeatures(),
  });

  final double textScale;
  final ScreenSpec device;
  final Brightness brightness;
  final Locale locale;
  final FakeAccessibilityFeatures accessibilityFeatures;

  _Environment copyWith({
    double? textScale,
    ScreenSpec? device,
    Brightness? brightness,
    Locale? locale,
    FakeAccessibilityFeatures? accessibilityFeatures,
  }) =>
      _Environment(
        textScale: textScale ?? this.textScale,
        device: device ?? this.device,
        brightness: brightness ?? this.brightness,
        locale: locale ?? this.locale,
        accessibilityFeatures:
            accessibilityFeatures ?? this.accessibilityFeatures,
      );

  String describe(HarnessPlatform platform) =>
      'textScale ${textScale}x, $device @${device.devicePixelRatio.toStringAsFixed(0)}x, '
      '${brightness.name}, locale ${_tag(locale)}, ${platform.name}';
}

String _tag(Locale l) => l.countryCode == null
    ? l.languageCode
    : '${l.languageCode}_${l.countryCode}';

/// Sits at the root of every pump. Its `dispose` runs when the post-test
/// `runApp` unmounts the tree - before flutter_test verifies its invariants
/// (`addTearDown` runs after them, too late for the platform override and the
/// semantics handle, which are invariants).
class _HarnessRoot extends StatefulWidget {
  const _HarnessRoot({required this.harness, required this.child});

  final AppHarness harness;
  final Widget child;

  @override
  State<_HarnessRoot> createState() => _HarnessRootState();
}

class _HarnessRootState extends State<_HarnessRoot> {
  @override
  void dispose() {
    widget.harness._release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ---------------------------------------------------------------------------
// Pumping
// ---------------------------------------------------------------------------

/// Pumps the real [WattByteApp].
///
/// Start destination follows the app's own rule: [signedIn] false -> Welcome,
/// signed in but [onboarded] false -> device setup, both -> Dashboard (inside
/// the real shell with its four tabs). [home], when given, is pushed on top of
/// that destination as a full-screen route (the real app's `home` is fixed to
/// the start gate), still inside the real MaterialApp builder.
///
/// Creation arguments ([platform], [signedIn], [onboarded], [apiConfigured],
/// [appConfig], [settings], [historyDays], [now], [chargingNow], [plan], [realFonts])
/// are ignored when an existing [harness] is passed. Returns the harness (pass
/// it back to pump again, or use its fakes).
///
/// [appConfig], when given, is the build configuration the app runs with
/// instead of the one [apiConfigured] derives (see [AppHarness.create]).
///
/// [size], when given, replaces [device] with a plain 3x screen without insets.
Future<AppHarness> pumpApp(
  WidgetTester tester, {
  AppHarness? harness,
  Widget? home,
  double textScale = 1.0,
  ScreenSpec device = kIPhone17Pro,
  Size? size,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('en'),
  FakeAccessibilityFeatures accessibilityFeatures =
      const FakeAccessibilityFeatures(),
  HarnessPlatform platform = HarnessPlatform.ios,
  bool signedIn = true,
  bool? onboarded,
  bool apiConfigured = true,
  AppConfig? appConfig,
  Settings? settings,
  int historyDays = 45,
  bool chargingNow = false,
  Plan plan = Plan.free,
  bool realFonts = true,
  bool semantics = false,
  bool andSettle = true,
  DateTime? now,
}) async {
  final h = await _prepare(tester,
      harness: harness,
      textScale: textScale,
      device: device,
      size: size,
      brightness: brightness,
      locale: locale,
      accessibilityFeatures: accessibilityFeatures,
      platform: platform,
      signedIn: signedIn,
      onboarded: onboarded,
      apiConfigured: apiConfigured,
      appConfig: appConfig,
      settings: settings,
      historyDays: historyDays,
      chargingNow: chargingNow,
      plan: plan,
      realFonts: realFonts,
      semantics: semantics,
      now: now);
  await tester.pumpWidget(ProviderScope(
    // A new harness must never inherit the previous one's provider state.
    key: ObjectKey(h),
    overrides: h.overrides,
    child: _HarnessRoot(harness: h, child: const WattByteApp()),
  ));
  if (andSettle) await settle(tester);
  if (home != null) {
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(MaterialPageRoute<void>(builder: (_) => home));
    if (andSettle) await settle(tester);
  }
  return h;
}

/// Pumps one [screen] inside the same providers, theme and l10n as the app,
/// without the start gate, shell or the app's MediaQuery builder.
///
/// Set [scaffold] for widgets that are only a body (the dashboard, for one,
/// returns a `SafeArea`/`ListView` and relies on the shell's `Scaffold`).
/// Everything else is as in [pumpApp].
Future<AppHarness> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  AppHarness? harness,
  bool scaffold = false,
  double textScale = 1.0,
  ScreenSpec device = kIPhone17Pro,
  Size? size,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('en'),
  FakeAccessibilityFeatures accessibilityFeatures =
      const FakeAccessibilityFeatures(),
  HarnessPlatform platform = HarnessPlatform.ios,
  bool signedIn = true,
  bool? onboarded,
  bool apiConfigured = true,
  Settings? settings,
  int historyDays = 45,
  bool chargingNow = false,
  Plan plan = Plan.free,
  bool realFonts = true,
  bool semantics = false,
  bool andSettle = true,
  DateTime? now,
}) async {
  final h = await _prepare(tester,
      harness: harness,
      textScale: textScale,
      device: device,
      size: size,
      brightness: brightness,
      locale: locale,
      accessibilityFeatures: accessibilityFeatures,
      platform: platform,
      signedIn: signedIn,
      onboarded: onboarded,
      apiConfigured: apiConfigured,
      settings: settings,
      historyDays: historyDays,
      chargingNow: chargingNow,
      plan: plan,
      realFonts: realFonts,
      semantics: semantics,
      now: now);
  await tester.pumpWidget(ProviderScope(
    key: ObjectKey(h),
    overrides: h.overrides,
    child: _HarnessRoot(
      harness: h,
      child: _ScreenApp(child: scaffold ? Scaffold(body: screen) : screen),
    ),
  ));
  if (andSettle) await settle(tester);
  return h;
}

/// Everything both pump functions do before mounting: build (or re-use) the
/// harness, apply the environment, switch semantics on.
Future<AppHarness> _prepare(
  WidgetTester tester, {
  required AppHarness? harness,
  required double textScale,
  required ScreenSpec device,
  required Size? size,
  required Brightness brightness,
  required Locale locale,
  required FakeAccessibilityFeatures accessibilityFeatures,
  required HarnessPlatform platform,
  required bool signedIn,
  required bool? onboarded,
  required bool apiConfigured,
  required Settings? settings,
  required int historyDays,
  required bool chargingNow,
  required Plan plan,
  required bool realFonts,
  required bool semantics,
  AppConfig? appConfig,
  DateTime? now,
}) async {
  final h = harness ??
      await AppHarness.create(tester,
          platform: platform,
          signedIn: signedIn,
          onboarded: onboarded,
          apiConfigured: apiConfigured,
          appConfig: appConfig,
          settings: settings,
          historyDays: historyDays,
          chargingNow: chargingNow,
          plan: plan,
          locale: locale,
          realFonts: realFonts,
          now: now);
  await h.configure(tester,
      textScale: textScale,
      device: size == null ? device : ScreenSpec.custom(size),
      brightness: brightness,
      locale: locale,
      accessibilityFeatures: accessibilityFeatures,
      andSettle: false);
  if (semantics) h.enableSemantics(tester);
  return h;
}

/// The app's MaterialApp minus start gate and MediaQuery builder.
class _ScreenApp extends ConsumerWidget {
  const _ScreenApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(settingsProvider).theme;
    return MaterialApp(
      title: 'WattByte',
      debugShowCheckedModeBanner: false,
      theme: wbTheme(Brightness.light),
      darkTheme: wbTheme(Brightness.dark),
      themeMode: switch (theme) {
        AppTheme.system => ThemeMode.system,
        AppTheme.light => ThemeMode.light,
        AppTheme.dark => ThemeMode.dark,
      },
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
  }
}

/// Pumps frames until nothing is scheduled any more: database reads, provider
/// rebuilds and short animations finish; an endless animation (a spinner that
/// never resolves) stops the loop at [timeout] instead of failing, so a test can
/// assert on it.
///
/// Always pumps at least [minimum] of fake time so timers of a few hundred
/// milliseconds (the fake auth repository's latency, route transitions) fire.
Future<void> settle(
  WidgetTester tester, {
  Duration minimum = const Duration(milliseconds: 600),
  Duration step = const Duration(milliseconds: 50),
  Duration timeout = const Duration(seconds: 5),
}) async {
  var elapsed = Duration.zero;
  while (elapsed < timeout) {
    await tester.pump(step);
    elapsed += step;
    if (elapsed >= minimum && !tester.binding.hasScheduledFrame) return;
  }
}

/// Runs [check] for every combination of device, brightness and text scale,
/// re-using one running app, and fails once at the end listing every failing
/// combination (each with the check's own message). A check signals failure by
/// throwing a `TestFailure` - `expectNoFlutterErrors` and
/// `expectAccessibleTargets` do.
///
/// ```dart
/// await sweepViews(tester, h, () async {
///   expectNoFlutterErrors(tester, screen: 'Dashboard');
/// });
/// ```
Future<void> sweepViews(
  WidgetTester tester,
  AppHarness harness,
  Future<void> Function() check, {
  List<double> textScales = kTextScales,
  List<ScreenSpec> devices = kScreenSizes,
  List<Brightness> brightnesses = const [Brightness.light],
}) async {
  final failures = <String>[];
  for (final device in devices) {
    for (final b in brightnesses) {
      for (final scale in textScales) {
        await harness.configure(tester,
            textScale: scale, device: device, brightness: b);
        try {
          await check();
        } on TestFailure catch (e) {
          failures.add('${harness.describe()}\n${e.message}');
        }
      }
    }
  }
  if (failures.isNotEmpty) {
    fail('${failures.length} failing view configuration(s):\n\n'
        '${failures.join('\n\n')}');
  }
}

// ---------------------------------------------------------------------------
// Errors (overflow, exceptions)
// ---------------------------------------------------------------------------

_FlutterErrorLog? _errorLog;

/// Every error Flutter reported since the harness was created. flutter_test
/// keeps only the first (and, with several, replaces them all with
/// "Multiple exceptions (N)"); this keeps each one, then forwards it so the
/// binding still fails the test when nobody takes it.
class _FlutterErrorLog {
  _FlutterErrorLog._(this._previous);

  final FlutterExceptionHandler? _previous;
  late final FlutterExceptionHandler _handler;
  final List<FlutterErrorDetails> _errors = [];

  static _FlutterErrorLog _install() {
    _errorLog?._uninstall();
    final log = _FlutterErrorLog._(FlutterError.onError);
    log._handler = (details) {
      log._errors.add(details);
      log._previous?.call(details);
    };
    FlutterError.onError = log._handler;
    return log;
  }

  bool get _installed => identical(FlutterError.onError, _handler);

  void _uninstall() {
    if (_installed) FlutterError.onError = _previous;
  }

  List<FlutterErrorDetails> _drain() {
    final copy = List.of(_errors);
    _errors.clear();
    return copy;
  }
}

/// One overflowing layout, whether it came from a reported error or from
/// scanning the render tree.
class _Overflow {
  _Overflow(this.kind, this.location, this.amount, this.edge);

  /// `Row`, `Column`, or the render object's type.
  final String kind;

  /// `lib/ui/dashboard/dashboard_screen.dart:353:15`, when the creator is known.
  final String? location;
  final double? amount;
  final String? edge;
  int count = 1;

  String get key => location ?? kind;

  @override
  String toString() => '$kind${location == null ? '' : ' created at $location'}'
      ' overflows${amount == null ? '' : ' by ${amount!.toStringAsFixed(amount! >= 10 ? 0 : 1)} px'}'
      '${edge == null ? '' : ' on the $edge'}'
      '${count > 1 ? '  [x$count]' : ''}';
}

final _overflowLine = RegExp(r'overflowed by ([\d.]+) pixels on the (\w+)');
final _fileLocation = RegExp(r'file://(/\S+?:\d+:\d+)');

/// `lib/ui/x.dart:12:3` from the first `file:///.../x.dart:12:3` in [text].
String? _locationIn(String text) {
  final path = _fileLocation.firstMatch(text)?.group(1);
  if (path == null) return null;
  final root = '${Directory.current.path}/';
  return path.startsWith(root) ? path.substring(root.length) : path;
}

/// Render objects that are laid out with content that does not fit, right now
/// (`OVERFLOWING` in their debug description), in every tab - also the ones
/// that are not painted, because layout is what decides.
List<_Overflow> _scanOverflows(WidgetTester tester) {
  final out = <_Overflow>[];
  void visit(RenderObject r) {
    if (r.toStringShort().contains(' OVERFLOWING')) {
      String? location;
      final creator = r.debugCreator;
      if (creator != null) {
        final text =
            debugTransformDebugCreator([DiagnosticsDebugCreator(creator)])
                .map((n) => n.toStringDeep())
                .join('\n');
        location = _locationIn(text);
      }
      // How far the children stick out (exact when none of them flexes).
      double? amount;
      if (r is RenderFlex) {
        final horizontal = r.direction == Axis.horizontal;
        var used = 0.0;
        r.visitChildren((c) {
          if (c is RenderBox) used += horizontal ? c.size.width : c.size.height;
        });
        final over = used - (horizontal ? r.size.width : r.size.height);
        if (over > 0) amount = over;
      }
      final kind = r is RenderFlex
          ? (r.direction == Axis.horizontal ? 'Row' : 'Column')
          : r.runtimeType.toString();
      out.add(_Overflow(kind, location, amount, null));
    }
    r.visitChildren(visit);
  }

  for (final view in tester.binding.renderViews) {
    visit(view);
  }
  return out;
}

/// Fails (with a [TestFailure]) when anything overflows or Flutter reported an
/// error since the last check, and clears the reported errors so a failure is
/// told once. The failure names the [screen] you pass and the current text
/// scale / size / brightness / locale, and for every overflow its widget and
/// source location (`lib/ui/dashboard/dashboard_screen.dart:353:15`).
///
/// Two sources are combined, because neither alone is reliable:
///
/// * errors Flutter reported (overflow, layout assertions, exceptions in
///   build), collected completely - flutter_test itself keeps one;
/// * a scan of the render tree for layouts that overflow *right now*.
///   Flutter reports an overflow once per render object, so after a text-scale
///   change in place, or on a second check of the same screen, the report
///   alone would say "fine" about a layout that is still broken.
///
/// The scan covers all four tabs of the shell, including the ones that are not
/// visible. Synchronous: `expect(() => expectNoFlutterErrors(tester),
/// throwsA(isA<TestFailure>()))`.
void expectNoFlutterErrors(WidgetTester tester, {String? screen}) {
  // A log left over from an earlier test is no longer installed: ignore it.
  final log = (_errorLog?._installed ?? false) ? _errorLog : null;
  final reported = log?._drain() ?? const <FlutterErrorDetails>[];
  final taken = <Object>[];
  for (Object? e = tester.takeException();
      e != null;
      e = tester.takeException()) {
    taken.add(e);
  }

  final overflows = <String, _Overflow>{};
  void add(_Overflow o) {
    final known = overflows[o.key];
    if (known == null) {
      overflows[o.key] = o;
    } else {
      known.count++;
    }
  }

  final others = <String>[];
  for (final d in reported) {
    final text = d.toString();
    final m = _overflowLine.firstMatch(text);
    if (m != null) {
      final who =
          RegExp(r'A (Render\w+) overflowed').firstMatch(text)?.group(1);
      add(_Overflow(
          who == null || who == 'RenderFlex'
              ? (text.contains('Axis.vertical') ? 'Column' : 'Row')
              : who,
          _locationIn(text),
          double.tryParse(m.group(1)!),
          m.group(2)));
    } else {
      others.add(_describeError(d));
    }
  }
  // Scanned overflows that a reported error already described are the same
  // layout: keep the reported one (it knows the exact amount and edge).
  final scanned = _scanOverflows(tester);
  final reportedKeys = overflows.keys.toSet();
  for (final o in scanned) {
    if (reportedKeys.contains(o.key)) continue;
    add(o);
  }
  // Without the log (a test that never pumped through the harness) the binding's
  // single pending exception is all there is; with it, that exception is a
  // duplicate of what the log holds.
  if (log == null) {
    for (final e in taken) {
      others.add(e.toString().split('\n').first);
    }
  }
  if (overflows.isEmpty && others.isEmpty) return;

  final context =
      [if (screen != null) screen, describeView(tester)].join(' | ');
  final buffer = StringBuffer('Layout problems at [$context]\n');
  if (overflows.isNotEmpty) {
    buffer.writeln('\n${overflows.length} overflowing layout(s):');
    for (final o in overflows.values) {
      buffer.writeln('  - $o');
    }
  }
  if (others.isNotEmpty) {
    buffer.writeln('\n${others.length} other Flutter error(s):');
    for (final o in others) {
      buffer.writeln('  - $o');
    }
  }
  fail(buffer.toString());
}

String _describeError(FlutterErrorDetails d) {
  final summary = d.exceptionAsString().split('\n').first.trim();
  final where = _locationIn(d.toString());
  return '$summary${where == null ? '' : '  ($where)'}';
}

/// "textScale 1.6x, 375x667 @3x, dark, locale en, android" from the test view.
String describeView(WidgetTester tester) {
  final view = tester.view;
  final size = view.physicalSize / view.devicePixelRatio;
  return 'textScale ${tester.platformDispatcher.textScaleFactor}x, '
      '${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)} '
      '@${view.devicePixelRatio.toStringAsFixed(0)}x, '
      '${tester.platformDispatcher.platformBrightness.name}, '
      'locale ${_tag(tester.platformDispatcher.locale)}, '
      '${defaultTargetPlatform.name}';
}

// ---------------------------------------------------------------------------
// Accessibility
// ---------------------------------------------------------------------------

/// Checks the tap-target and label guidelines on whatever is on screen and
/// fails once, listing every violation with [screen] and the view settings.
///
/// Turns semantics on for the duration of the call (or uses the handle
/// [AppHarness.enableSemantics] / `pumpApp(semantics: true)` already holds).
///
/// * [android]  every tappable node is at least 48x48.
/// * [ios]      every tappable node is at least 44x44.
/// * [labeled]  every tappable node has a label.
/// * [contrast] WCAG text contrast (renders the frame; slower, off by default).
Future<void> expectAccessibleTargets(
  WidgetTester tester, {
  String? screen,
  bool android = true,
  bool ios = true,
  bool labeled = true,
  bool contrast = false,
}) async {
  final handle = tester.ensureSemantics();
  try {
    await tester.pump();
    final guidelines = <String, AccessibilityGuideline>{
      if (android) 'Android tap target (48x48)': androidTapTargetGuideline,
      if (ios) 'iOS tap target (44x44)': iOSTapTargetGuideline,
      if (labeled) 'Labeled tap targets': labeledTapTargetGuideline,
      if (contrast) 'Text contrast': textContrastGuideline,
    };
    final failures = <String>[];
    for (final e in guidelines.entries) {
      final result = await e.value.evaluate(tester);
      if (!result.passed) failures.add('${e.key}:\n${result.reason}');
    }
    if (failures.isEmpty) return;
    final context =
        [if (screen != null) screen, describeView(tester)].join(' | ');
    fail('Accessibility guideline(s) violated at [$context]\n\n'
        '${failures.join('\n\n')}');
  } finally {
    handle.dispose();
  }
}

/// One semantics node, flattened for assertions and debugging.
class SemanticsInfo {
  const SemanticsInfo(
      this.label, this.value, this.hint, this.size, this.tappable);

  final String label;
  final String value;
  final String hint;

  /// Logical pixels.
  final Size size;
  final bool tappable;

  @override
  String toString() =>
      '${tappable ? '[tap] ' : ''}"$label"${value.isEmpty ? '' : ' = "$value"'} '
      '${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)}';
}

/// Every semantics node of the screen that has a label, value or tap action.
/// Needs semantics on (`pumpApp(semantics: true)` or `h.enableSemantics`).
List<SemanticsInfo> semanticsNodes(WidgetTester tester) {
  final root =
      tester.binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
  if (root == null) {
    throw StateError('Semantics are off: pumpApp(semantics: true) or '
        'h.enableSemantics(tester) first, then pump a frame.');
  }
  final out = <SemanticsInfo>[];
  void visit(SemanticsNode n) {
    final d = n.getSemanticsData();
    final tappable = d.hasAction(SemanticsAction.tap);
    if (d.label.isNotEmpty || d.value.isNotEmpty || tappable) {
      out.add(SemanticsInfo(d.label, d.value, d.hint, n.rect.size, tappable));
    }
    n.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  visit(root);
  return out;
}

/// Nodes whose label matches [label] (`String` = contains, `RegExp` = matches).
List<SemanticsInfo> semanticsWithLabel(WidgetTester tester, Pattern label) => [
      for (final n in semanticsNodes(tester))
        if (label.allMatches(n.label).isNotEmpty) n,
    ];

// ---------------------------------------------------------------------------
// Fonts
// ---------------------------------------------------------------------------

bool _fontsLoaded = false;

/// Registers the SDK's Roboto under every family name Material/Cupertino text
/// styles ask for, so layout uses real glyph widths instead of the 1em-square
/// Ahem font. Loaded once per process.
///
/// (Deliberately a flag, not a memoized Future: a Future created inside one
/// test's fake-async zone can never be awaited from another test's zone.)
Future<void> loadRealFonts(WidgetTester tester) async {
  if (_fontsLoaded) return;
  await _loadRealFonts(tester);
  _fontsLoaded = true;
}

const _fontFamilies = <String>[
  'Roboto',
  'CupertinoSystemText',
  'CupertinoSystemDisplay',
  '.AppleSystemUIFont',
  '.SF UI Text',
  '.SF UI Display',
  '.SF Pro Text',
  '.SF Pro Display',
];

Future<void> _loadRealFonts(WidgetTester tester) async {
  final dir = _materialFontsDir();
  if (dir == null) {
    throw StateError(
        'Roboto not found in the Flutter SDK cache (looked at FLUTTER_ROOT and '
        'above ${Platform.resolvedExecutable}). Run through `flutter test`, or '
        'pass realFonts: false to accept the Ahem test font.');
  }
  final files = [
    for (final name in const [
      'Roboto-Thin.ttf',
      'Roboto-Light.ttf',
      'Roboto-Regular.ttf',
      'Roboto-Medium.ttf',
      'Roboto-Bold.ttf',
      'Roboto-Black.ttf',
    ])
      File('${dir.path}/$name').readAsBytesSync(),
  ];
  await tester.runAsync(() async {
    for (final family in _fontFamilies) {
      final loader = FontLoader(family);
      for (final bytes in files) {
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    }
  });
}

Directory? _materialFontsDir() {
  const rel = 'bin/cache/artifacts/material_fonts';
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && Directory('$root/$rel').existsSync()) {
    return Directory('$root/$rel');
  }
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.path != dir.parent.path) {
    final candidate = Directory('${dir.path}/$rel');
    if (candidate.existsSync()) return candidate;
    dir = dir.parent;
  }
  return null;
}
