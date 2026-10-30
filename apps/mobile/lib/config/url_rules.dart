// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

/// URL checks shared by the API address and the privacy-policy link.
///
/// Reserved names (RFC 2606 / 6761) are placeholders by definition: they can
/// never resolve on the public internet, so a build that still carries one
/// (for example the `.invalid` hosts of `config/*.example.json`) must not
/// behave as if it were configured.
library;

/// Top-level labels reserved for documentation, tests and private networks.
const Set<String> _reservedTlds = {
  'invalid',
  'example',
  'test',
  'localhost',
  'local',
  'internal',
  'lan',
  'home',
  'corp',
  'intranet',
};

const Set<String> _reservedDomains = {
  'example.com',
  'example.net',
  'example.org',
};

final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

final RegExp _hostLabel =
    RegExp(r'^[A-Za-z0-9_](?:[A-Za-z0-9_\-]*[A-Za-z0-9_])?$');

/// Whether [host] (as `Uri.host` reports it) is a syntactically valid DNS name,
/// IPv4 address or IPv6 address. `Uri.tryParse` alone accepts hosts such as
/// `exa mple.com`; a build must not treat those as configured.
bool isValidHost(String host) {
  if (host.isEmpty || host.length > 253) return false;
  if (host.contains(':')) {
    try {
      Uri.parseIPv6Address(host);
      return true;
    } on FormatException {
      return false;
    }
  }
  return host.split('.').every(_hostLabel.hasMatch);
}

/// Whether an explicit port is in 1..65535 (`Uri.tryParse` accepts any number).
bool isValidPort(Uri uri) =>
    !uri.hasPort || (uri.port >= 1 && uri.port <= 65535);

/// True for hosts that are placeholders and never resolve: `*.invalid`.
bool isPlaceholderHost(String host) {
  final h = host.toLowerCase();
  return h == 'invalid' || h.endsWith('.invalid');
}

/// True when [host] is not a name a stranger's phone could resolve: a
/// single-label name, an IP literal, `localhost`, or a reserved TLD / domain.
bool isNonPublicHost(String host) {
  final h = host.toLowerCase();
  // Single-label names (`intranet`, `localhost`) and IP literals (v4, and v6
  // whose host keeps its colons) are never public hostnames.
  if (h.isEmpty || !h.contains('.') || h.contains(':') || _ipv4.hasMatch(h)) {
    return true;
  }
  final labels = h.split('.');
  if (_reservedTlds.contains(labels.last)) return true;
  return _reservedDomains.any((d) => h == d || h.endsWith('.$d'));
}

/// Why [raw] cannot be a public https URL, or `null` when it can. The value is
/// never echoed back: it may contain credentials.
String? publicHttpsUrlProblem(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return 'is empty';
  if (value.length > 2048) return 'is longer than 2048 characters';
  if (value.contains(RegExp(r'\s'))) return 'contains whitespace';
  final uri = Uri.tryParse(value);
  if (uri == null) return 'is not a valid URL';
  if (uri.scheme != 'https') return 'must use https';
  if (uri.host.isEmpty) return 'has no host';
  if (!isValidHost(uri.host)) return 'has an invalid host';
  if (!isValidPort(uri)) return 'has an invalid port';
  if (uri.userInfo.isNotEmpty) return 'must not contain credentials';
  if (isNonPublicHost(uri.host)) {
    return isPlaceholderHost(uri.host)
        ? 'is a placeholder host (.invalid)'
        : 'is not a public host';
  }
  return null;
}
