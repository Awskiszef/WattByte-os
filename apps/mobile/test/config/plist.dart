/// A tiny XML property-list reader for the native-configuration tests
/// (`package:xml` is not a dependency of the app and must not become one).
///
/// Supports what Info.plist, entitlement and privacy-manifest files use:
/// `dict`, `array`, `string`, `integer`, `real`, `true`, `false`, `data`,
/// `date`, comments, the XML declaration and the DOCTYPE. It is strict on
/// purpose: unbalanced or unknown tags, a `dict` with a key but no value, a
/// duplicate key and trailing content all throw a [FormatException], so a
/// malformed file fails the test instead of parsing "mostly".
library;

/// A parsed value: `Map<String, Object?>`, `List<Object?>`, `String`, `int`,
/// `double`, `bool`.
typedef PlistValue = Object?;

PlistValue parsePlist(String source) {
  var text = source;
  text = text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  if (text.contains('<!--') || text.contains('-->')) {
    throw const FormatException('unterminated comment');
  }
  text = text.replaceFirst(RegExp(r'^\s*<\?xml[^>]*\?>'), '');
  text = text.replaceFirst(RegExp(r'^\s*<!DOCTYPE[^>]*>'), '');
  final tokens = _tokenize(text);
  final reader = _Reader(tokens);
  reader.expectOpen('plist');
  final value = reader.value();
  reader.expectClose('plist');
  if (!reader.done) {
    throw FormatException('content after </plist>: ${reader.peek()}');
  }
  return value;
}

/// The root `dict` of a property list.
Map<String, Object?> parsePlistDict(String source) {
  final v = parsePlist(source);
  if (v is! Map<String, Object?>) {
    throw FormatException('the root of the plist is not a dict: $v');
  }
  return v;
}

class _Token {
  _Token(this.kind, this.name, [this.text = '']);

  /// `open`, `close`, `empty` (self-closing) or `text`.
  final String kind;
  final String name;
  final String text;

  @override
  String toString() => '$kind:$name${text.isEmpty ? '' : '($text)'}';
}

List<_Token> _tokenize(String text) {
  final tokens = <_Token>[];
  final tag = RegExp(r'<(/?)([A-Za-z]+)([^<>]*?)(/?)>');
  var pos = 0;
  for (final m in tag.allMatches(text)) {
    final between = text.substring(pos, m.start);
    if (between.trim().isNotEmpty) {
      tokens.add(_Token('text', '', between));
    } else if (between.contains('<') || between.contains('>')) {
      throw FormatException('stray angle bracket near offset $pos');
    }
    final closing = m.group(1)!.isNotEmpty;
    final selfClosing = m.group(4)!.isNotEmpty;
    final name = m.group(2)!;
    if (closing && selfClosing) {
      throw FormatException('</$name/> is not a tag');
    }
    tokens.add(
        _Token(closing ? 'close' : (selfClosing ? 'empty' : 'open'), name));
    pos = m.end;
  }
  final rest = text.substring(pos);
  if (rest.trim().isNotEmpty) {
    throw FormatException('trailing content: ${rest.trim()}');
  }
  return tokens;
}

class _Reader {
  _Reader(this._tokens);

  final List<_Token> _tokens;
  int _i = 0;

  bool get done => _i >= _tokens.length;

  _Token peek() {
    if (done) throw const FormatException('unexpected end of file');
    return _tokens[_i];
  }

  _Token next() {
    final t = peek();
    _i++;
    return t;
  }

  void expectOpen(String name) {
    final t = next();
    if (t.kind != 'open' || t.name != name) {
      throw FormatException('expected <$name>, found $t');
    }
  }

  void expectClose(String name) {
    final t = next();
    if (t.kind != 'close' || t.name != name) {
      throw FormatException('expected </$name>, found $t');
    }
  }

  String _text(String element) {
    final t = peek();
    var text = '';
    if (t.kind == 'text') {
      text = next().text;
    }
    expectClose(element);
    return _decode(text);
  }

  PlistValue value() {
    final t = next();
    switch ((t.kind, t.name)) {
      case ('empty', 'true'):
        return true;
      case ('empty', 'false'):
        return false;
      case ('empty', 'dict'):
        return <String, Object?>{};
      case ('empty', 'array'):
        return <Object?>[];
      case ('empty', 'string'):
        return '';
      case ('open', 'string'):
        return _text('string');
      case ('open', 'integer'):
        final raw = _text('integer').trim();
        return int.tryParse(raw) ??
            (throw FormatException('not an integer: "$raw"'));
      case ('open', 'real'):
        final raw = _text('real').trim();
        return double.tryParse(raw) ??
            (throw FormatException('not a real: "$raw"'));
      case ('open', 'data'):
      case ('open', 'date'):
        return _text(t.name).trim();
      case ('open', 'array'):
        final list = <Object?>[];
        while (!(peek().kind == 'close' && peek().name == 'array')) {
          list.add(value());
        }
        expectClose('array');
        return list;
      case ('open', 'dict'):
        final map = <String, Object?>{};
        while (!(peek().kind == 'close' && peek().name == 'dict')) {
          expectOpen('key');
          final key = _text('key');
          if (map.containsKey(key)) {
            throw FormatException('duplicate key "$key"');
          }
          if (peek().kind == 'close') {
            throw FormatException('key "$key" has no value');
          }
          map[key] = value();
        }
        expectClose('dict');
        return map;
    }
    throw FormatException('unexpected $t');
  }
}

String _decode(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');
