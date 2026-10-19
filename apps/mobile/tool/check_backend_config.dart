/// Checks the backend configuration of a build before it is made (CI, release
/// workflow). Usage and rules: lib/config/backend_config_cli.dart.
///
///   dart run tool/check_backend_config.dart --build-mode=release \
///       --dart-define=API_BASE_URL=<https address of the API>
///
/// Exit codes: 0 valid, 1 invalid configuration, 64 unusable arguments.
library;

import 'dart:io';

import 'package:wattbyte/config/backend_config_cli.dart';

void main(List<String> args) {
  exit(runBackendConfigCheck(args));
}
