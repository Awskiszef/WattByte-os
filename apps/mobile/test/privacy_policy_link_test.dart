// The privacy policy is one tap away where an account is created and in Settings, when the build has an address for it
// (audit F-09, G-05). Without an address nothing is shown: a dead link is worse than none.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/config/app_config.dart';
import 'package:wattbyte/ui/onboarding/welcome_screen.dart';
import 'package:wattbyte/ui/settings/settings_screen.dart';

import 'support/app_harness.dart';

AppConfig _config({String policy = ''}) => AppConfig.fromDefines(
      appEnv: 'development',
      apiBaseUrl: 'http://api.test',
      privacyPolicyUrl: policy,
    );

void main() {
  const url = 'https://wattbyte.app/privacy';

  testWidgets('Welcome: the link opens the configured address in the browser',
      (tester) async {
    final system = FakeSystem(platform: HarnessPlatform.ios);
    final h = await AppHarness.create(tester,
        platform: HarnessPlatform.ios,
        appConfig: _config(policy: url),
        system: system);
    await pumpScreen(tester, const WelcomeScreen(), harness: h, scaffold: true);
    await tester.tap(find.text('Privacy policy'));
    await tester.pump();
    expect(system.openedUrls, [url]);
  });

  testWidgets('Welcome: no address configured, no link', (tester) async {
    final h = await AppHarness.create(tester,
        platform: HarnessPlatform.ios, appConfig: _config());
    await pumpScreen(tester, const WelcomeScreen(), harness: h, scaffold: true);
    expect(find.text('Privacy policy'), findsNothing);
  });

  testWidgets(
      'Settings > Privacy has the row only when the build has an address',
      (tester) async {
    final system = FakeSystem(platform: HarnessPlatform.android);
    final h = await AppHarness.create(tester,
        platform: HarnessPlatform.android,
        appConfig: _config(policy: url),
        system: system);
    await pumpScreen(tester, const SettingsScreen(),
        harness: h, platform: h.platform, scaffold: true);
    await tester.scrollUntilVisible(find.text('Privacy policy'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Privacy policy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Privacy policy'));
    await tester.pumpAndSettle();
    expect(system.openedUrls, [url]);

    final without = await AppHarness.create(tester,
        platform: HarnessPlatform.android, appConfig: _config());
    await pumpScreen(tester, const SettingsScreen(),
        harness: without, platform: without.platform, scaffold: true);
    expect(find.text('Privacy policy'), findsNothing);
  });

  test('only https addresses are ever handed to the system', () async {
    final system = FakeSystem(platform: HarnessPlatform.ios);
    for (final bad in [
      'http://example.org/p',
      'javascript:alert(1)',
      'file:///etc/passwd',
      'https:///nohost'
    ]) {
      expect(await system.system.openExternalUrl(Uri.parse(bad)), isFalse,
          reason: bad);
    }
    expect(system.openedUrls, isEmpty);
    expect(await system.system.openExternalUrl(Uri.parse(url)), isTrue);
    system.dispose();
  });
}
