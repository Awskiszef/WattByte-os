// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wattbyte/api/api_config.dart';
import 'package:wattbyte/api/api_factory.dart';
import 'package:wattbyte/cloud_providers.dart';
import 'package:wattbyte/features/auth/data/secure_token_store.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/features/auth/presentation/auth_controller.dart';
import 'package:wattbyte/providers.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/setup/device_specification.dart';
import 'package:wattbyte/setup/region_detection.dart';
import 'package:wattbyte/setup/setup_controller.dart';
import 'package:wattbyte/storage/database.dart';

import '../sync_support.dart';
import 'app_harness.dart' show FakeAppNotifier, FakeWidgetPublisher;
import 'fake_backend.dart';
import 'fake_system.dart';

/// One PHONE of one or more people: its own preferences, SQLite and token store,
/// the real providers (auth, settings binding, setup, account sync) and a fake
/// network that several phones can share, so two phones talk to ONE account
/// server like two installs of the same user do.
class Phone {
  Phone._(this.name, this.backend, this.prefs, this.db, this.tokens,
      this.system, this._regionCode, this._catalog, this._apiUrl)
      : _wire = _CuttableClient(backend?.client ?? http.Client()) {
    _build();
  }

  final String name;

  /// The fake network, or null when this phone talks to a RUNNING API
  /// ([create] with `apiUrl`): then the real client, the real auth repository
  /// and the real household-price service are used.
  final FakeBackend? backend;
  final String? _apiUrl;
  SharedPreferences prefs;
  final WattByteDb db;
  final InMemoryTokenStore tokens;
  final FakeSystem system;
  final String _regionCode;
  final String _catalog;
  late ProviderContainer c;

  /// The connection of THIS phone, which can be cut like a lost network.
  final _CuttableClient _wire;

  /// Cuts (or restores) this phone's connection, whichever network it uses.
  set offline(bool value) => _wire.offline = value;

  static const _config = ApiConfig('http://api.test');

  /// A phone reporting [regionCode] as its Region setting. [storedPrefs] is what
  /// an earlier version of the app left in the preferences.
  static Future<Phone> create(
    String name,
    FakeBackend? backend, {
    String? apiUrl,
    String regionCode = 'PL',
    String localeTag = 'en-PL',
    String modelIdentifier = 'iPhone16,1',
    Map<String, Object> storedPrefs = const {},
  }) async {
    assert((backend == null) != (apiUrl == null),
        'a phone has a fake network or a running API, not both');
    ensureSqliteFfi();
    // One preferences instance per phone: the static singleton is reset first.
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(storedPrefs);
    final prefs = await SharedPreferences.getInstance();
    final db = await WattByteDb.openInMemory();
    final system = FakeSystem(deviceInfo: {
      'manufacturer': 'Apple',
      'model': 'iPhone',
      'modelIdentifier': modelIdentifier,
      'regionCode': regionCode,
      'localeTag': localeTag,
    });
    final phone = Phone._(
        name,
        backend,
        prefs,
        db,
        InMemoryTokenStore(),
        system,
        regionCode,
        File('assets/device_specs/devices.json').readAsStringSync(),
        apiUrl);
    addTearDown(() async {
      phone.c.dispose();
      system.dispose();
      await db.close();
    });
    return phone;
  }

  /// Extra provider overrides for the next [rebuild] (a store that fails, ...).
  List<Override> extraOverrides = const [];

  /// Starts the app again over the same storage with [extraOverrides] in place.
  void rebuild() {
    c.dispose();
    _build();
  }

  void _build() {
    final live = _apiUrl != null;
    final url = _apiUrl;
    final config = url != null ? ApiConfig(url) : _config;
    c = ProviderContainer(overrides: [
      prefsProvider.overrideWithValue(prefs),
      dbProvider.overrideWithValue(db),
      systemProvider.overrideWithValue(system.system),
      apiConfigProvider.overrideWithValue(config),
      apiFactoryProvider
          .overrideWithValue(ApiFactory(config, httpClient: _wire)),
      if (!live) authRepositoryProvider.overrideWithValue(UserAwareRepo()),
      tokenStoreProvider.overrideWithValue(tokens),
      ...extraOverrides,
      notifierProvider.overrideWithValue(FakeAppNotifier()),
      widgetPublisherProvider.overrideWithValue(FakeWidgetPublisher()),
      // What a finished setup detects here: the region the phone reports, the
      // bundled catalog, and the account of the signed-in user. The household
      // price is asked of the running API only when there is one.
      autoSetupProvider.overrideWith((ref) => AutoSetup(
            region: RegionDetectionService(
                system: system.system, localeTag: () => 'en_$_regionCode'),
            device: DeviceSpecificationService(
                system: system.system, loadCatalog: () async => _catalog),
            account: ref.watch(accountSettingsSyncProvider),
            price: live ? ref.watch(electricityPriceServiceProvider) : null,
          )),
    ]);
  }

  Settings get settings => c.read(settingsProvider);
  SettingsStore get store => SettingsStore(prefs);

  /// The user this phone is signed in as, or null.
  String? get userId {
    final s = c.read(authControllerProvider).valueOrNull;
    return s is SignedIn ? s.user.id : null;
  }

  /// Signs [user] in the way the UI does and waits until the phone's settings
  /// are the ones of that account. Against a running API [user] is the e-mail
  /// of an account that exists ([signUp]) and [userId] is the server's id.
  Future<void> signIn(String user) async {
    await c.read(authControllerProvider.future);
    await c.read(authControllerProvider.notifier).signInWithEmail(
        user, _apiUrl != null ? 'correct horse battery' : 'password');
    expect(userId, isNotNull, reason: '$name signed in as $user');
    if (_apiUrl == null) expect(userId, user);
    await bound();
  }

  /// Creates the account on a running API and signs in as it.
  Future<void> signUp(String email) async {
    await c.read(authControllerProvider.future);
    await c
        .read(authControllerProvider.notifier)
        .signUpWithEmail(email, 'correct horse battery');
    expect(userId, isNotNull, reason: '$name signed up as $email');
    await bound();
  }

  Future<void> signOut() => c.read(authControllerProvider.notifier).signOut();

  /// Waits for `SettingsNotifier` to have swapped in the account's settings.
  Future<void> bound() async {
    c.read(settingsProvider);
    for (var i = 0; i < 500 && !c.read(settingsBoundProvider); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(c.read(settingsBoundProvider), isTrue,
        reason: '$name: settings bound');
    await c.read(syncAccountProvider.notifier).refresh();
  }

  /// The automatic setup of a new install, exactly as `SetupScreen` runs it:
  /// detect (region, device, the account's settings), merge, save, upload what
  /// this phone decided, acknowledge what the account took. Returns the review.
  Future<SetupResult> runSetup({bool expectUpload = true}) async {
    final uploaded = Completer<void>();
    final notifier = c.read(settingsProvider.notifier);
    await c.read(setupControllerProvider.notifier).run(
          setup: c.read(autoSetupProvider),
          current: c.read(settingsProvider),
          save: (s) => notifier.update((_) => s),
          onAccountPushed: (push) async {
            await notifier
                .update((s) => s.markInSyncFrom(push.pushed, push.groups));
            if (!uploaded.isCompleted) uploaded.complete();
          },
        );
    if (expectUpload) {
      await uploaded.future.timeout(const Duration(seconds: 5),
          onTimeout: () => fail('$name: the setup upload never completed'));
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await notifier.update((s) => s.copyWith(onboarded: true));
    return c.read(setupControllerProvider).result!;
  }

  /// An edit made in Settings: the change, then the upload of what is decided.
  Future<void> edit(Settings Function(Settings) change) async {
    await c.read(settingsProvider.notifier).update(change);
    await c.read(accountSettingsControllerProvider)!.push();
  }

  /// What the app does at start and on resume.
  Future<void> reconcile() =>
      c.read(accountSettingsControllerProvider)!.reconcile();

  /// Kills the app and starts it again over the same storage.
  Future<void> restart() async {
    c.dispose();
    // What a process restart finds: the preferences read back from "disk" (this
    // phone's own keys; the mock store behind them is shared by every phone).
    final disk = {for (final k in prefs.getKeys()) k: prefs.get(k)!};
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(disk);
    prefs = await SharedPreferences.getInstance();
    _build();
    await c.read(authControllerProvider.future);
    await bound();
  }
}

/// `http.Client` that fails like a lost connection while [offline].
class _CuttableClient extends http.BaseClient {
  _CuttableClient(this._inner);

  final http.Client _inner;
  bool offline = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (offline) throw const SocketException('offline');
    return _inner.send(request);
  }
}
