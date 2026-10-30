// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart' show WbContext;
import '../../features/auth/presentation/auth_controller.dart';
import '../../providers.dart';

/// Shown instead of the app when the settings of the signed-in account could not be loaded (the settings of the previous
/// user of the phone are still the live ones): a way to try again or to leave, never the previous user's values (F-21).
class SettingsLoadFailedScreen extends ConsumerWidget {
  const SettingsLoadFailedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
          children: [
            Icon(Icons.sync_problem_outlined,
                size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Semantics(
                header: true,
                child: Text(l.settingsLoadFailedTitle,
                    style: theme.textTheme.headlineSmall)),
            const SizedBox(height: 12),
            Text(l.settingsLoadFailedBody, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 24),
            FilledButton(
                onPressed: () =>
                    ref.read(settingsProvider.notifier).retryBind(),
                child: Text(l.settingsLoadFailedRetry)),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).signOut(),
                child: Text(l.signOut)),
          ],
        ),
      ),
    );
  }
}
