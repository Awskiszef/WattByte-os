// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Machine-readable data is never locale-formatted: the API client, the sync
/// queue and bodies, local storage and the CSV/JSON export build their numbers
/// with plain Dart (`toStringAsFixed`, `jsonEncode`: decimal point, no
/// grouping). `Units`, `NumberFormat` and `DateFormat` are for screens,
/// notifications and widgets only, so none of these layers may use them.
void main() {
  const dataLayers = [
    'lib/api',
    'lib/export',
    'lib/storage',
    'lib/sync',
  ];

  final forbidden = <String, RegExp>{
    "import of core/units.dart":
        RegExp(r'''import\s+['"][^'"]*core/units\.dart'''),
    'NumberFormat': RegExp(r'\bNumberFormat\b'),
    'DateFormat': RegExp(r'\bDateFormat\b'),
    "package:intl": RegExp(r'''import\s+['"]package:intl/'''),
  };

  for (final dir in dataLayers) {
    test('$dir does not use locale formatting', () {
      final root = Directory(dir);
      expect(root.existsSync(), isTrue,
          reason: '$dir missing: update the list');
      final hits = <String>[];
      for (final f in root.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          // Comments may name the rule; code may not break it.
          final code = lines[i].split('//').first;
          forbidden.forEach((what, pattern) {
            if (pattern.hasMatch(code)) hits.add('${f.path}:${i + 1} $what');
          });
        }
      }
      expect(hits, isEmpty,
          reason: 'locale-dependent formatting in a data layer:\n'
              '${hits.join('\n')}');
    });
  }
}
