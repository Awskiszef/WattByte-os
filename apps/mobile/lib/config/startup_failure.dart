import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import '../core/error_log.dart';

/// Runs the app's storage initialisation and, if it throws, runs a recovery screen instead of leaving the user on the
/// native launch screen for ever (audit F-07). Any exception before the first frame (a corrupt or unreadable database, a
/// full disk, a failed schema upgrade, unreadable preferences) used to escape `main()`: nothing was mounted, nothing was
/// shown, and the next launch did the same.
///
/// [build] opens everything and returns the root widget. [resetLocalData] must keep the old file (move it aside), never
/// delete it. [run] is `runApp` (a test passes its own).
Future<void> startGuarded({
  required Future<Widget> Function() build,
  required Future<void> Function() resetLocalData,
  void Function(Widget app) run = runApp,
}) async {
  Future<void> attempt() async {
    try {
      run(await build());
    } catch (e, st) {
      reportError(e, st, 'startup');
      run(StartupFailureApp(
        onRetry: attempt,
        onResetLocalData: () async {
          await resetLocalData();
          await attempt();
        },
      ));
    }
  }

  await attempt();
}

/// What the user sees when the local storage cannot be opened. Neutral wording, no error details (they may contain a
/// path); Polish when the phone is set to Polish, English otherwise: the localisation of the app is not loaded yet and a
/// broken start cannot depend on it.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({
    super.key,
    required this.onRetry,
    required this.onResetLocalData,
    this.languageCode,
  });

  final Future<void> Function() onRetry;
  final Future<void> Function() onResetLocalData;

  /// Overrides the phone's language (tests).
  final String? languageCode;

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
        home: StartupFailureScreen(
          onRetry: onRetry,
          onResetLocalData: onResetLocalData,
          texts: StartupTexts.forLanguage(
              languageCode ?? PlatformDispatcher.instance.locale.languageCode),
        ),
      );
}

class StartupTexts {
  const StartupTexts({
    required this.title,
    required this.body,
    required this.retry,
    required this.reset,
    required this.confirmTitle,
    required this.confirmBody,
    required this.cancel,
    required this.confirmReset,
  });

  final String title;
  final String body;
  final String retry;
  final String reset;
  final String confirmTitle;
  final String confirmBody;
  final String cancel;
  final String confirmReset;

  static StartupTexts forLanguage(String code) => code == 'pl' ? pl : en;

  static const en = StartupTexts(
    title: 'WattByte could not open its data',
    body:
        'Your data on this phone could not be read. Try again first. If it keeps failing you can start with an empty '
        'local database: the old file is kept on the phone, not deleted. Your account and cloud data are not affected.',
    retry: 'Try again',
    reset: 'Start with empty local data',
    confirmTitle: 'Start with empty local data?',
    confirmBody:
        'The statistics stored on this phone will no longer be shown. The old file is kept (it is only moved aside).',
    cancel: 'Cancel',
    confirmReset: 'Start empty',
  );

  static const pl = StartupTexts(
    title: 'WattByte nie może otworzyć swoich danych',
    body:
        'Nie udało się odczytać danych zapisanych na tym telefonie. Najpierw spróbuj ponownie. Jeśli to się powtarza, '
        'możesz zacząć od pustej lokalnej bazy: stary plik zostaje na telefonie, nie jest usuwany. Konto i dane w '
        'chmurze nie są dotknięte.',
    retry: 'Spróbuj ponownie',
    reset: 'Zacznij od pustych danych lokalnych',
    confirmTitle: 'Zacząć od pustych danych lokalnych?',
    confirmBody:
        'Statystyki zapisane na tym telefonie nie będą już pokazywane. Stary plik zostaje (jest tylko przeniesiony).',
    cancel: 'Anuluj',
    confirmReset: 'Zacznij od zera',
  );
}

class StartupFailureScreen extends StatefulWidget {
  const StartupFailureScreen({
    super.key,
    required this.onRetry,
    required this.onResetLocalData,
    required this.texts,
  });

  final Future<void> Function() onRetry;
  final Future<void> Function() onResetLocalData;
  final StartupTexts texts;

  @override
  State<StartupFailureScreen> createState() => _StartupFailureScreenState();
}

class _StartupFailureScreenState extends State<StartupFailureScreen> {
  bool _busy = false;

  Future<void> _do(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmReset() async {
    final t = widget.texts;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.confirmTitle),
        content: Text(t.confirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t.confirmReset)),
        ],
      ),
    );
    if (ok == true) await _do(widget.onResetLocalData);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = widget.texts;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          children: [
            Icon(Icons.storage_outlined,
                size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Semantics(
                header: true,
                child: Text(t.title, style: theme.textTheme.headlineSmall)),
            const SizedBox(height: 12),
            Text(t.body, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 24),
            FilledButton(
                onPressed: _busy ? null : () => _do(widget.onRetry),
                child: Text(t.retry)),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: _busy ? null : _confirmReset, child: Text(t.reset)),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
