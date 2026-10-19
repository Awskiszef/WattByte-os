import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/config/app_config.dart';

// The one link no other test can see: the REAL compile-time defines reach
// AppConfig.fromEnvironment. A plain `flutter test` has no defines, so these two
// tests are skipped there; CI runs this file twice, with defines:
//
//   flutter test --dart-define=API_BASE_URL=https://api.sample-company.io \
//       test/config/define_wiring_test.dart
//   flutter test --dart-define=LOCAL_ONLY_DEV=true test/config/define_wiring_test.dart
const _api = String.fromEnvironment('API_BASE_URL');
const _flag = String.fromEnvironment('LOCAL_ONLY_DEV');

void main() {
  test('API_BASE_URL reaches AppConfig.fromEnvironment', () {
    final c = AppConfig.fromEnvironment;
    expect(c.api.isConfigured, isTrue);
    expect(c.backendMode, BackendMode.online);
    expect(c.isLocalOnlyDev, isFalse);
  },
      skip: _api.isEmpty || _flag.isNotEmpty
          ? 'run with --dart-define=API_BASE_URL=https://...'
          : false);

  test('LOCAL_ONLY_DEV=true reaches AppConfig.fromEnvironment (debug build)',
      () {
    final c = AppConfig.fromEnvironment;
    expect(kBuildMode, BuildMode.debug);
    expect(c.isLocalOnlyDev, isTrue);
    expect(c.backendMode, BackendMode.localOnlyDev);
  },
      skip: _api.isNotEmpty || _flag != 'true'
          ? 'run with --dart-define=LOCAL_ONLY_DEV=true'
          : false);
}
