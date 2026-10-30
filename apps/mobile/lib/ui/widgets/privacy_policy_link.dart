// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart' show WbContext;
import '../../config/config_providers.dart' show appConfigProvider;
import '../../providers.dart' show systemProvider;

/// The address of the privacy policy of this build (`PRIVACY_POLICY_URL`), or null when the build has none configured.
final privacyPolicyUrlProvider =
    Provider<Uri?>((ref) => ref.watch(appConfigProvider).privacyPolicyUrl);

/// Opens the privacy policy in the browser. Nothing is shown when the build has no address: a link that goes nowhere would
/// be worse than none (the address is the owner's to publish).
class PrivacyPolicyLink extends ConsumerWidget {
  const PrivacyPolicyLink({super.key, this.alignment = Alignment.center});

  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(privacyPolicyUrlProvider);
    if (url == null) return const SizedBox.shrink();
    return Align(
      alignment: alignment,
      child: TextButton.icon(
        onPressed: () => ref.read(systemProvider).openExternalUrl(url),
        icon: const Icon(Icons.open_in_new_rounded, size: 18),
        label: Text(context.l10n.privacyPolicy),
      ),
    );
  }
}
