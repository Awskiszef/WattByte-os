// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `app_en.arb` (the template) and `app_pl.arb`: same keys, same ICU shape,
/// real translations, and honest privacy wording. Reads the ARB files as data;
/// it does not import the app, so a half-finished refactor elsewhere cannot hide
/// a missing translation.
///
/// New strings go in through `tool/arb_add.py`, which keeps both files in step;
/// this test is the net for everything that bypasses it.
void main() {
  final en = _load('lib/l10n/app_en.arb');
  final pl = _load('lib/l10n/app_pl.arb');
  final enKeys = _messageKeys(en);
  final plKeys = _messageKeys(pl);

  /// PL equals EN on purpose: names, units, loan words and labels that are the
  /// same word in Polish. Anything else that is identical is an untranslated copy.
  const sameInBothLanguages = <String, String>{
    'appName': 'the product name',
    'aiTitle': '"AI" is "AI" in Polish',
    'appSystem': '"System" is the same word',
    'accountPlan': '"Plan" is the same word',
    'appTethering': '"Tethering" is used untranslated',
    'setupRegion': '"Region" is the same word',
    'days30': 'unit abbreviation',
    'days7': 'unit abbreviation',
    'pricePerKwh': 'a currency placeholder and a unit',
    'internet': '"Internet" is the same word',
    'planPremium': '"Premium" is the same word',
    'wifi': 'the brand name Wi-Fi',
  };

  /// Identical copies of template metadata that are still in `app_pl.arb`
  /// (harmless: gen-l10n ignores them). Whoever owns the ARB files should delete
  /// them; until then this list keeps the rule strict for everything else.
  const plMetadataCopies = {
    '@syncCounts',
    '@syncLast',
    '@syncDone',
    '@aiRemaining',
  };

  group('keys', () {
    test('both files define exactly the same messages', () {
      expect(enKeys, isNotEmpty);
      expect(plKeys.difference(enKeys), isEmpty,
          reason: 'only in app_pl.arb (not in the template)');
      expect(enKeys.difference(plKeys), isEmpty,
          reason: 'missing a Polish translation');
    });

    test('the locale markers are right', () {
      expect(en['@@locale'], 'en');
      expect(pl['@@locale'], 'pl');
    });

    test('metadata (@key) lives in the template only', () {
      final extra =
          pl.keys.where((k) => k.startsWith('@') && k != '@@locale').toSet();
      expect(extra.difference(plMetadataCopies), isEmpty,
          reason: 'gen-l10n reads placeholders from the template; a copy in '
              'app_pl.arb can only drift. New metadata belongs in app_en.arb');
      // The copies that exist must at least say the same as the template.
      for (final k in extra) {
        expect(pl[k], en[k], reason: '$k differs from the template');
      }
    });

    test('every @key in the template belongs to an existing message', () {
      final orphans = en.keys
          .where((k) => k.startsWith('@') && k != '@@locale')
          .where((k) => !en.containsKey(k.substring(1)))
          .toList();
      expect(orphans, isEmpty);
    });

    test('keys are plain identifiers (they become Dart getters)', () {
      for (final k in enKeys) {
        expect(k, matches(RegExp(r'^[a-z][A-Za-z0-9]*$')), reason: k);
      }
    });

    test('every message is a getter or method of the generated class', () {
      final generated = File('lib/l10n/generated/app_localizations.dart');
      expect(generated.existsSync(), isTrue,
          reason: 'run `flutter gen-l10n` (flutter pub get does it)');
      final source = generated.readAsStringSync();
      final missing = [
        for (final k in enKeys)
          if (!RegExp('String (get $k;|$k\\()').hasMatch(source)) k
      ];
      expect(missing, isEmpty,
          reason:
              'the ARB was edited without regenerating (use tool/arb_add.py)');
    });
  });

  group('values', () {
    test('no message is empty or only whitespace, in either language', () {
      for (final k in enKeys) {
        expect(en[k], isA<String>(), reason: 'en $k');
        expect(pl[k], isA<String>(), reason: 'pl $k');
        expect((en[k] as String).trim(), isNotEmpty, reason: 'en $k');
        expect((pl[k] as String).trim(), isNotEmpty, reason: 'pl $k');
      }
    });

    test('no leading or trailing whitespace', () {
      for (final k in enKeys) {
        for (final lang in [('en', en), ('pl', pl)]) {
          final v = lang.$2[k] as String;
          expect(v, v.trim(), reason: '${lang.$1} $k');
        }
      }
    });

    test('Polish differs from English except for the allow-listed words', () {
      final identical = [
        for (final k in enKeys)
          if (en[k] == pl[k]) k
      ];
      final unexpected =
          identical.where((k) => !sameInBothLanguages.containsKey(k)).toList();
      expect(unexpected, isEmpty,
          reason: 'identical in both languages and not allow-listed: an '
              'English copy-paste? (allow-list: ${sameInBothLanguages.keys})');
      final stale =
          sameInBothLanguages.keys.where((k) => !enKeys.contains(k)).toList();
      expect(stale, isEmpty, reason: 'allow-list entries for removed keys');
    });

    test('Polish text has no English function words and little overlap', () {
      // Words that are not Polish at all ("to" and "by" are, so they are not here).
      const english = {
        'the',
        'your',
        'you',
        'and',
        'of',
        'for',
        'with',
        'this',
        'that',
        'from',
        'not',
        'will',
        'can',
        'is',
        'are',
        'it',
        'in',
        'or',
        'be',
        'at',
        'an',
        'has',
        'have',
        'were',
        'yes',
      };
      for (final k in enKeys) {
        if (sameInBothLanguages.containsKey(k)) continue;
        final plWords = _words(_texts(pl[k] as String));
        final stray = plWords.where(english.contains).toSet();
        expect(stray, isEmpty, reason: 'pl $k: English words $stray');
        final enWords = _words(_texts(en[k] as String)).toSet();
        if (plWords.length >= 4) {
          final shared =
              plWords.where(enWords.contains).length / plWords.length;
          expect(shared, lessThan(0.6),
              reason: 'pl $k shares ${(shared * 100).round()} % of its words '
                  'with the English text');
        }
      }
    });

    test('English text contains no Polish letters', () {
      for (final k in enKeys) {
        expect(_texts(en[k] as String),
            isNot(matches(RegExp('[ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]'))),
            reason: 'en $k');
      }
    });

    test(
        'the translation does not reuse English straight quotes around words '
        'where Polish uses „ ”', () {
      // Hygiene only: a Polish sentence quoting a term uses „…”, not "…".
      for (final k in enKeys) {
        expect(pl[k] as String, isNot(contains('"')),
            reason: 'pl $k uses a straight double quote');
      }
    });
  });

  group('ICU structure', () {
    late Map<String, ({List<Object> en, List<Object> pl})> parsed;

    setUpAll(() {
      parsed = {
        for (final k in enKeys)
          k: (en: _parse(en[k] as String), pl: _parse(pl[k] as String)),
      };
    });

    test('every message parses (balanced braces, well-formed arguments)', () {
      // setUpAll throws on a malformed message: reaching here means all parsed.
      expect(parsed.length, enKeys.length);
    });

    test('the same arguments with the same types in both languages', () {
      for (final k in enKeys) {
        final a = _arguments(parsed[k]!.en);
        final b = _arguments(parsed[k]!.pl);
        expect(b, a, reason: '$k: placeholders differ between en and pl');
      }
    });

    test('plurals: English has one/other, Polish has one/few/many/other', () {
      var seen = 0;
      for (final k in enKeys) {
        for (final p in _plurals(parsed[k]!.en)) {
          seen++;
          expect(p.branches, contains('other'), reason: 'en $k');
          expect(p.branches.any((b) => b == 'one' || b == '=1'), isTrue,
              reason: 'en $k needs a singular');
        }
        for (final p in _plurals(parsed[k]!.pl)) {
          expect(p.branches, containsAll(['few', 'many', 'other']),
              reason: 'pl $k: Polish has the plural classes few and many');
          expect(p.branches.any((b) => b == 'one' || b == '=1'), isTrue,
              reason: 'pl $k needs a singular');
        }
        expect(_plurals(parsed[k]!.pl).length, _plurals(parsed[k]!.en).length,
            reason: '$k: plural count differs');
      }
      expect(seen, greaterThan(0), reason: 'the test found no plural at all');
    });

    test('selects have the same cases in both languages and an "other"', () {
      var seen = 0;
      for (final k in enKeys) {
        final a = _selects(parsed[k]!.en);
        final b = _selects(parsed[k]!.pl);
        expect(b.length, a.length, reason: k);
        for (var i = 0; i < a.length; i++) {
          seen++;
          expect(a[i].branches, contains('other'), reason: 'en $k');
          expect(b[i].branches, contains('other'), reason: 'pl $k');
          expect(b[i].branches.toSet(), a[i].branches.toSet(),
              reason: '$k: a case exists in one language only');
        }
      }
      expect(seen, greaterThan(0));
    });

    test('plurals use the same count in every branch of both languages', () {
      for (final k in enKeys) {
        for (final side in [parsed[k]!.en, parsed[k]!.pl]) {
          for (final p in _plurals(side)) {
            expect(p.name, anyOf('count', 'n'), reason: k);
          }
        }
      }
    });

    test('every placeholder is declared in @key with a type, and only those',
        () {
      for (final k in enKeys) {
        final used =
            _arguments(parsed[k]!.en).map((a) => a.split(':').first).toSet();
        final meta = en['@$k'];
        if (used.isEmpty) continue;
        expect(meta, isA<Map>(), reason: '$k uses $used but has no @$k');
        final declared =
            ((meta as Map)['placeholders'] as Map?)?.keys.toSet() ?? {};
        expect(declared, used, reason: '$k: placeholders vs @$k.placeholders');
        for (final e in ((meta['placeholders']) as Map).entries) {
          expect((e.value as Map)['type'],
              anyOf('String', 'int', 'double', 'num', 'DateTime'),
              reason: '$k.${e.key}');
        }
        for (final p in _plurals(parsed[k]!.en)) {
          expect(((meta['placeholders'] as Map)[p.name] as Map)['type'],
              anyOf('int', 'num'),
              reason: '$k: the plural count must be a number');
        }
      }
    });

    test(
        'a Polish translation does not hard-code a number that is a placeholder',
        () {
      for (final k in enKeys) {
        final used = _arguments(parsed[k]!.en);
        if (used.isEmpty) continue;
        // The percentage sign / unit next to a placeholder survives.
        for (final a in used) {
          final name = a.split(':').first;
          expect(pl[k] as String, contains('{$name'),
              reason: 'pl $k lost {$name}');
        }
      }
    });
  });

  group('privacy wording (what the app says about uploads must be true)', () {
    // Ground truth: docs/privacy.md ("What leaves the phone, and only if the
    // user chooses"), docs/AUTO_SETUP.md (account settings, device registration)
    // and ios/Runner/PrivacyInfo.xcprivacy:
    //
    //  * Without an account / without an API address NOTHING is uploaded.
    //  * With an account: e-mail, installation id, platform; account settings
    //    (country, currency, price mode, manual price) and the device's model
    //    code and battery specification at setup.
    //  * Usage data leaves the phone as DAILY TOTALS, only with cloud sync on.
    //  * AI: this month's totals, only when the user asks for an insight.
    //  * Never: raw battery samples, per-app usage, session timestamps.
    //
    // So a sentence may promise that RAW measurements stay on the phone, and that
    // sync is optional, but it must not claim that nothing ever leaves the phone
    // while an account exists, nor that something is "never uploaded" when daily
    // totals of exactly that thing are.
    const privacyKeys = [
      'aboutBody',
      'dataCollectionBody',
      'cloudSyncTitle',
      'cloudSyncBody',
      'cloudSyncNote',
      'accountUnavailableBody',
      'welcomePrivacyNote',
      'authWhyAccount',
      'aiSignInHint',
      'aiSent',
      'deleteAccountBody',
      'usageAccessBody',
      'permUsageBody',
      'permNotificationsBody',
      'notificationsOptional',
    ];

    String text(Map<String, dynamic> lang, String key) =>
        (lang[key] as String).toLowerCase();

    /// Strings that say "nothing/never uploaded" in absolute terms. None is allowed any more (G-04): the account stores
    /// settings and the phone model, and AI insights send monthly totals, so every such sentence must carry its condition.
    /// A new entry here needs a reason and an owner.
    const knownOverclaims = <String, String>{};

    // 1. Absolute claims: never true once an account exists.
    final absolute = <RegExp>[
      RegExp(r'never leaves?\b'),
      RegExp(r'nothing (ever )?leaves'),
      RegExp(r'\bnever (uploads?|uploaded|sends?|sent|shared?)\b'),
      RegExp(r'nigdy (nie )?(opuszcza|wysyła|wysyłane)'),
      RegExp(r'nigdzie (ich )?nie wysyła'),
    ];
    // 2. "Nothing is uploaded ..." is true only with a condition in the same
    //    sentence ("unless you turn on cloud sync").
    final unlessForm = <RegExp>[
      RegExp(r'\bnothing is (ever )?(uploaded|sent|shared)\b'),
      RegExp(r'nic nie jest (nigdy )?(wysyłane|przesyłane)'),
    ];
    final condition = RegExp(
        r'\bunless\b|\bonly if\b|\buntil\b|dopóki nie|chyba że|tylko jeśli|tylko po\b');
    // 3. Exhaustive claims ("only X can ever be uploaded"): the account also
    //    stores settings and device facts, and AI insights send monthly totals.
    final exhaustive = <RegExp>[
      RegExp(r'\b(can|will|does) ever be uploaded\b'),
      RegExp(r'mogą być wyłącznie dzienne sumy'),
    ];

    /// What is wrong with [message], or nothing.
    List<String> overclaims(String message) {
      final lower = message.toLowerCase();
      final problems = <String>[];
      for (final r in absolute) {
        if (r.hasMatch(lower)) problems.add('absolute claim /$r/');
      }
      for (final sentence in lower.split(RegExp(r'(?<=[.!?])\s+'))) {
        for (final r in unlessForm) {
          if (r.hasMatch(sentence) && !condition.hasMatch(sentence)) {
            problems.add('unconditional "$sentence" /$r/');
          }
        }
      }
      for (final r in exhaustive) {
        if (r.hasMatch(lower)) problems.add('exhaustive claim /$r/');
      }
      return problems;
    }

    // An absolute claim is fine when the build has no server at all.
    const noServerKeys = {'accountUnavailableBody'};

    test('the wording rules do catch what they are meant to catch', () {
      expect(overclaims('Your data never leaves your phone.'), isNotEmpty);
      expect(overclaims('WattByte never uploads them.'), isNotEmpty);
      expect(overclaims('Nothing is uploaded.'), isNotEmpty);
      expect(overclaims('Nothing is uploaded unless you turn on cloud sync.'),
          isEmpty);
      expect(overclaims('Only daily totals can ever be uploaded.'), isNotEmpty);
      expect(overclaims('Nic nie jest wysyłane.'), isNotEmpty);
      expect(
          overclaims('Nic nie jest wysyłane, dopóki nie włączysz.'), isEmpty);
      expect(overclaims('WattByte odczytuje sumy i nigdzie ich nie wysyła.'),
          isNotEmpty);
      expect(
          overclaims(
              'Cloud sync uploads only daily totals, never raw samples.'),
          isEmpty);
      expect(overclaims('Wysyłamy tylko dzienne sumy.'), isEmpty);
    });

    test(
        'no string claims that nothing ever leaves the phone, in either '
        'language (the known exceptions are listed above with their reason)',
        () {
      for (final k in enKeys) {
        if (noServerKeys.contains(k) || knownOverclaims.containsKey(k)) {
          continue;
        }
        for (final lang in [('en', en), ('pl', pl)]) {
          expect(overclaims(lang.$2[k] as String), isEmpty,
              reason: '${lang.$1} $k: "${lang.$2[k]}"');
        }
      }
      for (final k in knownOverclaims.keys) {
        expect(enKeys, contains(k),
            reason: 'knownOverclaims lists a key that no longer exists');
      }
    });

    test(
        'the build without a server may say nothing is uploaded, and says '
        'why', () {
      final s = text(en, 'accountUnavailableBody');
      expect(s, contains('not connected'));
      expect(s, contains('nothing is uploaded'));
      final p = text(pl, 'accountUnavailableBody');
      expect(p, contains('nie jest połączona'));
      expect(p, contains('nic nie jest wysyłane'));
    });

    test(
        'About: measurements stay local unless an account AND cloud sync, and '
        'what sync sends is named', () {
      for (final lang in [en, pl]) {
        final s = text(lang, 'aboutBody');
        expect(s, anyOf(contains('account'), contains('konto')));
      }
      final s = text(en, 'aboutBody');
      expect(s, contains('stay on this device unless'));
      expect(s, contains('cloud sync'));
      expect(s, contains('daily totals'));
      expect(s, contains('estimated'), reason: 'estimates are marked as such');
      final p = text(pl, 'aboutBody');
      expect(p, contains('chyba że'));
      expect(p, contains('synchronizacj'));
      expect(p, contains('dzienne sumy'));
      expect(p, contains('szacowane'));
    });

    test(
        'the account copy names what the account stores besides daily totals (G-04)',
        () {
      for (final key in ['authWhyAccount', 'aboutBody']) {
        expect(text(en, key), contains('phone model'), reason: key);
        expect(text(pl, key), contains('model telefonu'), reason: key);
      }
      expect(text(en, 'aiSent'), contains('ai provider'));
      expect(text(pl, 'aiSent'), contains('dostawcy ai'));
    });

    test('Data collection: uploads are tied to the cloud sync switch', () {
      expect(text(en, 'dataCollectionBody'),
          contains('only if you turn on cloud sync'));
      expect(text(pl, 'dataCollectionBody'),
          contains('tylko po włączeniu synchronizacji'));
    });

    test(
        'Cloud sync: daily totals only, never raw samples or per-app usage, '
        'and only if switched on', () {
      final s = text(en, 'cloudSyncNote');
      expect(s, contains('only daily totals'));
      expect(s, contains('never raw samples'));
      expect(s, contains('per-app'));
      expect(s, contains('only if you turn it on'));
      final p = text(pl, 'cloudSyncNote');
      expect(p, contains('tylko dzienne sumy'));
      expect(p, contains('nigdy surowe próbki'));
      expect(p, contains('tylko jeśli ją włączysz'));
      expect(text(en, 'cloudSyncBody'), contains('daily totals'));
      expect(text(pl, 'cloudSyncBody'), contains('dzienne sumy'));
    });

    test('Welcome: the account is for settings and optional sync', () {
      final s = text(en, 'welcomePrivacyNote');
      expect(s, contains('account'));
      expect(s, contains('settings'));
      expect(s, contains('if you choose'));
      final p = text(pl, 'welcomePrivacyNote');
      expect(p, contains('konto'));
      expect(p, contains('ustawienia'));
      expect(p, contains('jeśli tego chcesz'));
    });

    test('AI: only this month\'s totals, never raw data', () {
      expect(text(en, 'aiSent'), contains("this month's totals only"));
      expect(text(en, 'aiSignInHint'), contains('only totals for this month'));
      expect(text(en, 'aiSignInHint'), contains('never raw data'));
      expect(text(pl, 'aiSent'), contains('tylko sumy z tego miesiąca'));
      expect(text(pl, 'aiSignInHint'), contains('nigdy surowe dane'));
    });

    test('Delete account: permanent, covers the cloud, leaves the phone alone',
        () {
      final s = text(en, 'deleteAccountBody');
      expect(s, contains('permanently'));
      expect(s, contains('cloud'));
      expect(s, contains('data on this phone stays'));
      final p = text(pl, 'deleteAccountBody');
      expect(p, contains('trwale'));
      expect(p, contains('w chmurze'));
      expect(p, contains('na tym telefonie zostają'));
    });

    test('notifications are said to be local', () {
      expect(text(en, 'notificationsOptional'),
          contains('generated on your device'));
      expect(text(pl, 'notificationsOptional'),
          contains('generowane na urządzeniu'));
    });

    test(
        'every privacy key is still a message (a rename must update this test)',
        () {
      final missing = privacyKeys.where((k) => !enKeys.contains(k)).toList();
      expect(missing, isEmpty,
          reason: 'update `privacyKeys` in l10n_parity_test.dart');
    });
  });
}

// ----------------------------------------------------------------- ARB access

Map<String, dynamic> _load(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

Set<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

// ---------------------------------------------------------- ICU message parser

/// A node of a parsed ICU message: [String] text or an [_Arg].
class _Arg {
  _Arg(this.name, this.type, this.branches);

  final String name;

  /// `plain` for `{name}`, otherwise `plural`, `select`, `number`, ...
  final String type;

  /// Branch key -> nested message (plural and select only).
  final Map<String, List<Object>> branches;

  List<String> get branchKeys => branches.keys.toList();

  @override
  String toString() => '$name:$type';
}

List<Object> _parse(String message) {
  final p = _IcuParser(message);
  final nodes = p.message(topLevel: true);
  if (!p.atEnd) throw FormatException('unbalanced "}"', message, p.pos);
  return nodes;
}

class _IcuParser {
  _IcuParser(this.s);

  final String s;
  int pos = 0;

  bool get atEnd => pos >= s.length;

  /// Parses text and arguments until the closing brace of the enclosing branch
  /// (not consumed) or the end of the input.
  List<Object> message({bool topLevel = false}) {
    final out = <Object>[];
    final text = StringBuffer();
    void flush() {
      if (text.isNotEmpty) out.add(text.toString());
      text.clear();
    }

    while (!atEnd) {
      final c = s[pos];
      if (c == '}') {
        if (topLevel) throw FormatException('unbalanced "}"', s, pos);
        break;
      }
      if (c == '{') {
        flush();
        out.add(_argument());
        continue;
      }
      if (c == "'") {
        if (pos + 1 < s.length && s[pos + 1] == "'") {
          text.write("'");
          pos += 2;
          continue;
        }
        if (pos + 1 < s.length && (s[pos + 1] == '{' || s[pos + 1] == '}')) {
          // Quoted literal braces: '{' ... '
          final end = s.indexOf("'", pos + 1);
          if (end == -1) throw FormatException('unterminated quote', s, pos);
          text.write(s.substring(pos + 1, end));
          pos = end + 1;
          continue;
        }
      }
      text.write(c);
      pos++;
    }
    flush();
    return out;
  }

  _Arg _argument() {
    pos++; // {
    final name = _until(',}').trim();
    if (name.isEmpty || !RegExp(r'^\w+$').hasMatch(name)) {
      throw FormatException('bad argument name "$name"', s, pos);
    }
    if (_peek == '}') {
      pos++;
      return _Arg(name, 'plain', const {});
    }
    pos++; // ,
    final type = _until(',}').trim();
    if (type != 'plural' && type != 'select' && type != 'selectordinal') {
      // {n, number} / {d, date, yMd}: no nested messages.
      while (!atEnd && _peek != '}') {
        pos++;
      }
      _expect('}');
      return _Arg(name, type, const {});
    }
    _expect(',');
    final branches = <String, List<Object>>{};
    while (true) {
      _skipSpaces();
      if (_peek == '}') break;
      final key = _until('{ }').trim();
      if (key.isEmpty) throw FormatException('empty branch key', s, pos);
      _skipSpaces();
      _expect('{');
      branches[key] = message();
      _expect('}');
    }
    _expect('}');
    if (branches.isEmpty) throw FormatException('no branches', s, pos);
    return _Arg(name, type, branches);
  }

  String get _peek {
    if (atEnd) throw FormatException('unexpected end of message', s, pos);
    return s[pos];
  }

  void _expect(String c) {
    if (_peek != c) throw FormatException('expected "$c"', s, pos);
    pos++;
  }

  void _skipSpaces() {
    while (!atEnd && ' \t\n\r'.contains(s[pos])) {
      pos++;
    }
  }

  String _until(String stops) {
    final start = pos;
    while (!atEnd && !stops.contains(s[pos])) {
      pos++;
    }
    if (atEnd) throw FormatException('unexpected end of message', s, start);
    return s.substring(start, pos);
  }
}

Iterable<_Arg> _walk(List<Object> nodes) sync* {
  for (final n in nodes) {
    if (n is _Arg) {
      yield n;
      for (final b in n.branches.values) {
        yield* _walk(b);
      }
    }
  }
}

/// `name:type` of every argument anywhere in the message.
Set<String> _arguments(List<Object> nodes) =>
    {for (final a in _walk(nodes)) '${a.name}:${a.type}'};

class _Branches {
  _Branches(this.name, this.branches);

  final String name;
  final List<String> branches;
}

List<_Branches> _plurals(List<Object> nodes) => [
      for (final a in _walk(nodes))
        if (a.type == 'plural') _Branches(a.name, a.branchKeys)
    ];

List<_Branches> _selects(List<Object> nodes) => [
      for (final a in _walk(nodes))
        if (a.type == 'select') _Branches(a.name, a.branchKeys)
    ];

/// The literal text of a message (arguments and branch keys removed).
String _texts(String message) {
  final out = StringBuffer();
  void visit(List<Object> nodes) {
    for (final n in nodes) {
      if (n is String) {
        out.write(n);
      } else if (n is _Arg) {
        out.write(' ');
        for (final b in n.branches.values) {
          visit(b);
          out.write(' ');
        }
      }
    }
  }

  visit(_parse(message));
  return out.toString();
}

List<String> _words(String text) => RegExp(r'\p{L}{2,}', unicode: true)
    .allMatches(text.toLowerCase())
    .map((m) => m.group(0)!)
    .toList();
