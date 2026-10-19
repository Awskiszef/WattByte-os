import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../providers.dart';
import '../settings/flow_widgets.dart';
import '../theme.dart';
import '../widgets/wb_widgets.dart';

/// Explains each permission before any system prompt appears. Only after the
/// account and the automatic setup; the dashboard follows.
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen>
    with WidgetsBindingObserver {
  bool _notificationsGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the system "Usage access" screen: re-read the grant state.
    if (state == AppLifecycleState.resumed) {
      ref.read(refreshTickProvider.notifier).state++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final caps = ref.watch(capabilitiesProvider).value;
    final isAndroid =
        caps?.isAndroid ?? Theme.of(context).platform == TargetPlatform.android;
    final usageGranted = caps?.usageAccessGranted ?? false;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                children: [
                  const ExcludeSemantics(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Icon(Icons.shield_outlined,
                          size: 56, color: WbColors.byte),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FlowHeading(l.permissionsTitle,
                      liveRegion: true,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(l.permissionsBody,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: mutedOf(context), height: 1.4)),
                  const SizedBox(height: 20),
                  if (isAndroid && caps?.usageAccessState != 'unavailable')
                    _PermissionCard(
                      icon: Icons.data_usage_rounded,
                      title: l.permUsageTitle,
                      body: l.permUsageBody,
                      granted: usageGranted,
                      action: l.usageAccessButton,
                      onTap: () =>
                          ref.read(systemProvider).openUsageAccessSettings(),
                    ),
                  if (!isAndroid)
                    _PermissionCard(
                      icon: Icons.phone_iphone_rounded,
                      title: l.permIosTitle,
                      body: l.onboardingPermissionsBodyIos,
                    ),
                  const SizedBox(height: 12),
                  _PermissionCard(
                    icon: Icons.notifications_none_rounded,
                    title: l.permNotificationsTitle,
                    body: l.permNotificationsBody,
                    granted: _notificationsGranted,
                    action: l.enableNotifications,
                    onTap: () async {
                      final ok =
                          await ref.read(notifierProvider).requestPermission();
                      if (ok) {
                        await ref.read(settingsProvider.notifier).update((s) =>
                            s.copyWith(
                                notifyChargingDone: true,
                                notifyWeeklyEnergy: true));
                      }
                      if (mounted) setState(() => _notificationsGranted = ok);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(l.notificationsOptional,
                      style: Theme.of(context).textTheme.labelMedium,
                      textAlign: TextAlign.center),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: FilledButton(
                onPressed: widget.onDone,
                child: FlowFitText(l.getStarted, textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.body,
    this.granted = false,
    this.action,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool granted;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return WbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ExcludeSemantics(child: Icon(icon, color: WbColors.byte)),
            const SizedBox(width: 10),
            Expanded(
                child: FlowHeading(title,
                    style: Theme.of(context).textTheme.titleMedium)),
          ]),
          const SizedBox(height: 8),
          FlowFitText(body,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(height: 1.4)),
          if (action != null) ...[
            const SizedBox(height: 12),
            granted
                // Replaces the button: announced, so the change is not silent.
                ? Semantics(
                    container: true,
                    liveRegion: true,
                    child: Row(children: [
                      const ExcludeSemantics(
                        child: Icon(Icons.check_circle_rounded,
                            color: WbColors.wifi, size: 18),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(l.granted,
                            style: Theme.of(context).textTheme.labelLarge),
                      ),
                    ]),
                  )
                : OutlinedButton(
                    style: flowOutlinedStyle(context),
                    onPressed: onTap,
                    child: FlowFitText(action!, textAlign: TextAlign.center)),
          ],
        ],
      ),
    );
  }
}
