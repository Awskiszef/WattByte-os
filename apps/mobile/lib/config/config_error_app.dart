import 'package:flutter/material.dart';

import 'app_config.dart';

/// What `main()` runs instead of the app when the build's configuration is
/// invalid (see [AppConfig.isValid]): a controlled stop. No database, no
/// session store, no network and no account flow are touched, so a build
/// without a valid backend can never behave like a local-only build.
///
/// Developer-facing English on purpose: this is never reached by a build that
/// went through the release guards (`docs/CONFIGURATION_MOBILE.md`), and a
/// broken configuration cannot be expected to bring the localisation along.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key, required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'WattByte',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.teal,
          brightness: Brightness.dark,
        ),
        home: ConfigErrorScreen(config: config),
      );
}

class ConfigErrorScreen extends StatelessWidget {
  const ConfigErrorScreen({super.key, required this.config});

  final AppConfig config;

  /// The one-line summary of the failure.
  static const String title = 'Invalid build configuration';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errors = config.backend.errors;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.headlineSmall),
            ),
            const SizedBox(height: 12),
            Text(
              'This build of WattByte cannot start because its backend '
              'configuration is not valid. Nothing was loaded and no data '
              'was touched.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            for (final error in errors)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SelectableText('• $error',
                    style: theme.textTheme.bodyMedium),
              ),
            const SizedBox(height: 8),
            // The development hints are shown in debug builds only.
            if (kBuildMode == BuildMode.debug) ...[
              const SizedBox(height: 8),
              Text('Online development:', style: theme.textTheme.titleSmall),
              const SelectableText(
                  'flutter run --dart-define=API_BASE_URL=<address of the API>'),
              const SizedBox(height: 12),
              Text('Development without a backend (debug only):',
                  style: theme.textTheme.titleSmall),
              const SelectableText(
                  'flutter run --dart-define=LOCAL_ONLY_DEV=true'),
            ],
          ],
        ),
      ),
    );
  }
}
