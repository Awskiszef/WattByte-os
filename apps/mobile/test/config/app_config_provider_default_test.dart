import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/config/app_config.dart';
import 'package:wattbyte/config/config_providers.dart';

// main() validates AppConfig.fromEnvironment and then starts the app WITHOUT
// overriding appConfigProvider (lib/main.dart): the provider's default is the only
// link between "the config main() checked" and "the config StartGate / the banner
// use". Every other test overrides this provider, so only this one pins it.
void main() {
  test('appConfigProvider (not overridden) is the AppConfig main() validated',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
        identical(container.read(appConfigProvider), AppConfig.fromEnvironment),
        isTrue);
  });
}
