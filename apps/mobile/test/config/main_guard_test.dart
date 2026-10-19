import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/app.dart';
import 'package:wattbyte/config/app_config.dart';
import 'package:wattbyte/config/config_error_app.dart';
import 'package:wattbyte/main.dart' as app;

// Runs the REAL main(). A plain `flutter test` has no dart-defines, so the build
// is a debug build without API_BASE_URL and without LOCAL_ONLY_DEV: invalid.
// main() must stop at the controlled configuration error, before any storage
// or platform channel is touched (no channel is mocked here: a call would throw).
void main() {
  testWidgets('main() of an invalid build runs ConfigErrorApp and nothing else',
      (tester) async {
    expect(AppConfig.fromEnvironment.isValid, isFalse,
        reason: 'precondition: flutter test has no dart-defines');
    final channelCalls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/shared_preferences'),
        (call) async {
      channelCalls.add(call.method);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/shared_preferences'),
            null));

    await tester.runAsync(app.main);
    await tester.pump();

    expect(find.byType(ConfigErrorScreen), findsOneWidget);
    expect(find.byType(WattByteApp), findsNothing);
    expect(find.byType(StartGate), findsNothing);
    expect(channelCalls, isEmpty, reason: 'no storage before the guard');
  }, timeout: const Timeout(Duration(seconds: 20)));
}
