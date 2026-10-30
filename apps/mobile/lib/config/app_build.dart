import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which build of the app this is: what the server is told in the `X-WattByte-App` header and what is compared with the
/// minimum version the server publishes (`minimumAppVersion` in `GET /api/v1/config`, audit F-11).
class AppBuildInfo {
  const AppBuildInfo(
      {required this.platform, required this.version, this.build = ''});

  /// Nothing known (tests, a native side without the call): no header is sent and nothing is ever "too old".
  static const AppBuildInfo unknown = AppBuildInfo(platform: '', version: '');

  /// `android` or `ios`.
  final String platform;

  /// `MAJOR.MINOR.PATCH` (anything after it, a pre-release or build suffix, is ignored when comparing).
  final String version;
  final String build;

  bool get isKnown => platform.isNotEmpty && parseVersion(version) != null;

  /// The header value: `ios/1.4.0+27`. Contains no identifier of the person or the device.
  String? get header =>
      isKnown ? '$platform/$version${build.isEmpty ? '' : '+$build'}' : null;

  /// True when this build is older than [minimum] (`1.4.0`). An unreadable or missing version on either side is never "older".
  bool isOlderThan(String? minimum) {
    final mine = parseVersion(version);
    final min = minimum == null ? null : parseVersion(minimum);
    if (mine == null || min == null) return false;
    for (var i = 0; i < 3; i++) {
      if (mine[i] != min[i]) return mine[i] < min[i];
    }
    return false;
  }
}

/// `1.4.0`, `1.4.0+27` or `1.4.0-beta` as `[1, 4, 0]`; null for anything else.
List<int>? parseVersion(String text) {
  final m = RegExp(r'^(\d{1,4})\.(\d{1,4})\.(\d{1,4})(?:[-+].*)?$')
      .firstMatch(text.trim());
  if (m == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
}

/// Set once in `main()` from the native side; tests leave the default.
final appBuildProvider = Provider<AppBuildInfo>((_) => AppBuildInfo.unknown);
