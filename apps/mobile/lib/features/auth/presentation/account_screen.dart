// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app.dart';
import '../../../cloud_providers.dart';
import '../../../config/config_providers.dart' show featureFlagsProvider;
import '../../../providers.dart';
import '../../../sync/sync_service.dart';
import '../../../ui/settings/flow_widgets.dart';
import '../../../ui/theme.dart';
import '../../../ui/widgets/wb_widgets.dart';
import '../domain/auth_models.dart';
import 'auth_controller.dart';
import 'auth_form.dart';
import 'cloud_data_section.dart';

/// Account and cloud sync. Local-first: nothing here is needed to use the app.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _register = false;
  String? _syncMessage;

  String _syncText(SyncOutcome? o) {
    final l = context.l10n;
    if (o == null) return l.syncNothing;
    return switch (o.status) {
      SyncStatus.idle => l.syncNothing,
      SyncStatus.synced => l.syncDone(o.uploaded),
      SyncStatus.retryLater => l.syncOffline,
      SyncStatus.authRequired => l.syncAuthRequired,
      SyncStatus.rejected => l.syncRejected,
    };
  }

  Future<void> _deleteAccount() async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => flowDialog(
        context,
        title: l.deleteAccount,
        body: l.deleteAccountBody,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.deleteAccount,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final deleted =
        await ref.read(authControllerProvider.notifier).deleteAccount();
    if (deleted) {
      await ref.read(cloudSyncProvider).disable();
    } else if (mounted) {
      setState(() => _syncMessage = context.l10n.deleteAccountFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final auth = ref.watch(authControllerProvider);
    final configured = ref.watch(apiConfigProvider).isConfigured;
    final state = auth.value;

    Widget body;
    if (!configured) {
      body = _Info(
          title: l.accountUnavailableTitle, body: l.accountUnavailableBody);
    } else if (auth.isLoading || state is AuthUnknown || state == null) {
      body = _Info(title: l.account, body: l.accountRestoring, busy: true);
    } else if (state is SignedIn) {
      body = _signedIn(context, state);
    } else {
      body = _signedOut(context, state);
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.account)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          body,
          const SizedBox(height: 16),
          Text(l.cloudSyncNote, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }

  Widget _signedOut(BuildContext context, AuthState? state) {
    final l = context.l10n;
    return WbCard(
      gradient: accentWash(context, WbColors.byte),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlowHeading(_register ? l.signUp : l.signIn,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          AuthForm(
            register: _register,
            onModeChanged: (v) => setState(() => _register = v),
          ),
        ],
      ),
    );
  }

  Widget _signedIn(BuildContext context, SignedIn state) {
    final l = context.l10n;
    final settings = ref.watch(settingsProvider);
    final summary = ref.watch(syncSummaryProvider).value;
    final user = state.user;
    final fmt = DateFormat.yMMMd(context.localeTag).add_Hm();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WbCard(
          gradient: accentWash(context, WbColors.byte),
          // Each card is its own group for a screen reader (a list otherwise
          // reads the text of neighbouring cards as one block).
          child: _Group(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const ExcludeSemantics(child: WattByteMark(size: 32)),
                  const SizedBox(width: 12),
                  Expanded(
                    // Wraps after "@" and "." rather than inside the name; a
                    // screen reader gets the address as it is.
                    child: Semantics(
                      label: user.email,
                      excludeSemantics: true,
                      child: FlowFitText(breakableEmail(user.email),
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                    '${l.accountPlan}: ${user.plan == Plan.premium ? l.planPremium : l.planFree}',
                    style: Theme.of(context).textTheme.bodyMedium),
                if (state.offline) ...[
                  const SizedBox(height: 8),
                  Text(l.accountOfflineNote,
                      style: Theme.of(context).textTheme.labelMedium),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).signOut(),
                  child: Text(l.signOut, textAlign: TextAlign.center),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        WbCard(
          child: _Group(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FlowSwitchTile(
                  padding: EdgeInsets.zero,
                  title: l.cloudSyncTitle,
                  subtitle: l.cloudSyncBody,
                  value: settings.cloudSync,
                  onChanged: (on) async {
                    if (on && !ref.read(featureFlagsProvider).cloudSync) {
                      // The server (or this build) has cloud sync switched off: it can be turned off, not on (F-04).
                      setState(() => _syncMessage = l.cloudSyncUnavailable);
                      return;
                    }
                    if (on) {
                      final o = await ref.read(cloudSyncProvider).enable();
                      if (mounted) setState(() => _syncMessage = _syncText(o));
                    } else {
                      await ref.read(cloudSyncProvider).disable();
                    }
                  },
                ),
                if (summary != null) ...[
                  Text(
                      l.syncCounts(
                          summary.pending, summary.synced, summary.failed),
                      style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Text(
                      summary.lastSync == null
                          ? l.syncNever
                          : l.syncLast(fmt.format(summary.lastSync!)),
                      style: Theme.of(context).textTheme.labelMedium),
                ],
                if (_syncMessage != null) ...[
                  const SizedBox(height: 8),
                  // The outcome of a sync or a failed delete is announced.
                  Semantics(
                    container: true,
                    liveRegion: true,
                    child: Text(_syncMessage!,
                        style: Theme.of(context).textTheme.labelMedium),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton(
                    style: flowOutlinedStyle(context),
                    onPressed: settings.cloudSync
                        ? () async {
                            final o =
                                await ref.read(cloudSyncProvider).syncNow();
                            if (mounted) {
                              setState(() => _syncMessage = _syncText(o));
                            }
                          }
                        : null,
                    child: Text(l.syncNow),
                  ),
                  if ((summary?.failed ?? 0) > 0)
                    OutlinedButton(
                      style: flowOutlinedStyle(context),
                      onPressed: () async {
                        final o = await ref
                            .read(cloudSyncProvider)
                            .syncNow(retryFailed: true);
                        if (mounted) {
                          setState(() => _syncMessage = _syncText(o));
                        }
                      },
                      child: Text(l.syncRetryFailed),
                    ),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const CloudDataSection(),
        const SizedBox(height: 16),
        _DestructiveTile(label: l.deleteAccount, onTap: _deleteAccount),
      ],
    );
  }
}

/// One group for a screen reader: the texts inside are read together and apart
/// from the neighbouring groups.
class _Group extends StatelessWidget {
  const _Group({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Semantics(container: true, child: child);
}

class _Info extends StatelessWidget {
  const _Info({required this.title, required this.body, this.busy = false});

  final String title;
  final String body;
  final bool busy;

  @override
  Widget build(BuildContext context) => WbCard(
        gradient: accentWash(context, WbColors.byte),
        child: _Group(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const ExcludeSemantics(child: WattByteMark(size: 32)),
                const SizedBox(width: 12),
                Expanded(
                    child: FlowHeading(title,
                        style: Theme.of(context).textTheme.titleMedium)),
              ]),
              const SizedBox(height: 12),
              Text(body,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(height: 1.4)),
              if (busy) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(semanticsLabel: title),
              ],
            ],
          ),
        ),
      );
}

class _DestructiveTile extends StatelessWidget {
  const _DestructiveTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        style: flowOutlinedStyle(context,
            color: Theme.of(context).colorScheme.error),
        onPressed: onTap,
        icon: const ExcludeSemantics(child: Icon(Icons.delete_outline_rounded)),
        label: Text(label, textAlign: TextAlign.center),
      );
}
