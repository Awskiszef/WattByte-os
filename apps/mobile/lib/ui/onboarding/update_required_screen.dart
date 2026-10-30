// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart' show WbContext;

/// The user chose to carry on with an old version until the app is restarted.
final updateNoticeDismissedProvider = StateProvider<bool>((_) => false);

/// Shown when the server's `minimumAppVersion` is above the installed version (audit F-11). It says what is wrong and that
/// local data is safe; the way on is "Continue without updating" (local statistics keep working, the account features may
/// not). The store address is not known to the app: the text names the store.
class UpdateRequiredScreen extends ConsumerWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
          children: [
            Icon(Icons.system_update_outlined,
                size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Semantics(
                header: true,
                child: Text(l.updateRequiredTitle,
                    style: theme.textTheme.headlineSmall)),
            const SizedBox(height: 12),
            Text(l.updateRequiredBody, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () =>
                  ref.read(updateNoticeDismissedProvider.notifier).state = true,
              child: Text(l.updateRequiredContinue),
            ),
          ],
        ),
      ),
    );
  }
}
