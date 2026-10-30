// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';

import '../core/error_log.dart';
import 'app_config.dart';
import 'local_only_banner.dart';

/// The app is portrait-only on both platforms (iPhone `Info.plist`
/// `UISupportedInterfaceOrientations`, Android `screenOrientation="portrait"`);
/// the Dart side states the same so a rotated simulator or a foldable cannot
/// lay the screens out sideways.
const List<DeviceOrientation> kAppOrientations = [
  DeviceOrientation.portraitUp,
];

/// Must complete before `runApp`.
Future<void> lockOrientation() =>
    SystemChrome.setPreferredOrientations(kAppOrientations);

/// Debug builds only: one line with the effective configuration (no values),
/// then one line per configuration problem, and the development banner text
/// when the build runs without a backend. Release builds print nothing.
void logStartupConfiguration(AppConfig config) {
  debugLog(config.diagnostics, where: 'config');
  for (final problem in config.problems) {
    debugLog(problem, where: 'config');
  }
  if (kBuildMode == BuildMode.debug && config.isLocalOnlyDev) {
    debugLog(kLocalOnlyDevBannerText, where: 'config');
  }
}
