import '../config/app_environment.dart';
import '../config/url_rules.dart';

/// Where the WattByte API lives. Chosen at build time, never hardcoded:
///
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080          (Android emulator, development only)
///   flutter build appbundle --dart-define-from-file=config/production.json
///
/// The address is validated against the build's [AppEnvironment]
/// (`--dart-define=APP_ENV`): development accepts http or https, staging and
/// production accept only https and refuse placeholder hosts. An address that
/// fails validation is treated as absent ([baseUrl] is empty, [isConfigured] is
/// false, [problem] says why) so no request can ever leave for it; the build
/// itself is then invalid and does not start (`AppConfig.isValid`).
///
/// Without an address no cloud feature exists. Whether that is allowed at all
/// is not decided here: a build without a (valid) address is an invalid
/// configuration, except the explicit debug-only `LOCAL_ONLY_DEV` mode (see
/// `validateBackendConfig` in `config/backend_config.dart`). The address is read
/// from the defines in one place only, `AppConfig.fromEnvironment`.
class ApiConfig {
  const ApiConfig(this._rawBaseUrl,
      {this.environment = AppEnvironment.development});

  final String _rawBaseUrl;

  /// The rule set the address is validated against.
  final AppEnvironment environment;

  static String _trimmed(String raw) {
    var s = raw.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// Why the configured address cannot be used, or `null` when it is absent or
  /// valid for [environment]. Never contains the address itself (it may carry
  /// credentials in a misconfigured build).
  String? get problem {
    final url = _trimmed(_rawBaseUrl);
    if (url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'API_BASE_URL is not an absolute http(s) URL';
    }
    if (url.contains(RegExp(r'\s')) || !isValidHost(uri.host)) {
      return 'API_BASE_URL has an invalid host or contains whitespace';
    }
    if (!isValidPort(uri)) {
      return 'API_BASE_URL has an invalid port';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'API_BASE_URL must use http or https';
    }
    if (environment.requiresHttps && uri.scheme != 'https') {
      return 'API_BASE_URL must use https in ${environment.wireName}';
    }
    if (uri.userInfo.isNotEmpty) {
      return 'API_BASE_URL must not contain credentials';
    }
    if (uri.hasQuery || uri.hasFragment) {
      return 'API_BASE_URL must not contain a query or fragment';
    }
    if (environment.requiresHttps && isPlaceholderHost(uri.host)) {
      return 'API_BASE_URL is a placeholder host (.invalid); '
          'set the real address in config/${environment.wireName}.json';
    }
    return null;
  }

  /// The address requests go to, without trailing slash. Empty when the build
  /// has none or the configured one is not valid for [environment].
  String get baseUrl => problem == null ? _trimmed(_rawBaseUrl) : '';

  bool get isConfigured => baseUrl.isNotEmpty;

  /// Whether requests go over TLS. Always true outside development.
  bool get isSecure => baseUrl.startsWith('https://');
}
