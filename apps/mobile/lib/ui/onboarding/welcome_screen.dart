// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../../app.dart';
import '../settings/flow_widgets.dart';
import '../theme.dart';
import '../widgets/privacy_policy_link.dart';
import '../widgets/wb_widgets.dart';
import 'auth_screen.dart';

/// First screen without a session: nothing is configured before an account exists.
///
/// Scrolls when the content is taller than the screen (accessibility text
/// sizes, small phones, landscape) and spreads out when it is not.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 48, 28, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    const ExcludeSemantics(child: WattByteMark(size: 96)),
                    const SizedBox(height: 32),
                    // One word: scaled down as a whole rather than wrapped.
                    // (A FittedBox, unlike a LayoutBuilder, can sit inside the
                    // intrinsic-height measuring of SliverFillRemaining.)
                    Semantics(
                      header: true,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(l.appName,
                            maxLines: 1, style: theme.textTheme.headlineMedium),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(l.welcomeTagline,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: mutedOf(context), height: 1.4)),
                    const Spacer(flex: 2),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => _open(context, register: true),
                      child: Text(l.signUp, textAlign: TextAlign.center),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      style: flowOutlinedStyle(context),
                      onPressed: () => _open(context, register: false),
                      child: Text(l.signIn, textAlign: TextAlign.center),
                    ),
                    const SizedBox(height: 16),
                    Text(l.welcomePrivacyNote,
                        style: theme.textTheme.labelMedium,
                        textAlign: TextAlign.center),
                    const PrivacyPolicyLink(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, {required bool register}) =>
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AuthScreen(register: register)));
}
