// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

/// The text of the development banner and of the debug startup log line.
/// Developer-facing on purpose: not localised, and never shown to a user
/// because the banner exists only in a debug build started with
/// `--dart-define=LOCAL_ONLY_DEV=true` (see `WattByteApp`).
///
/// The text is a constant that is empty outside debug builds, so the compiler
/// drops the literal itself from profile and release binaries, whatever the
/// tree shaker does with the code around it (`tool/check_release_guard.sh
/// --builds` greps a release binary for it).
const String kLocalOnlyDevBannerText =
    kDebugMode ? 'LOCAL ONLY DEVELOPMENT MODE' : '';

/// A thin, always-visible strip above the whole app that says this build has
/// no backend and no account. It sits inside the status-bar inset, so nothing
/// under it moves except by the strip's own height.
class LocalOnlyDevBanner extends StatelessWidget {
  const LocalOnlyDevBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: const Color(0xFFB3261E),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Semantics(
                  container: true,
                  child: const Text(
                    kLocalOnlyDevBannerText,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // The strip already covers the status bar: the app below must not
        // inset for it a second time.
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}
