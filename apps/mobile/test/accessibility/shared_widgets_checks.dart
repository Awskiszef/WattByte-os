/// Checks shared by the accessibility tests of the data screens.
///
/// On top of the harness (`expectNoFlutterErrors`, `expectAccessibleTargets`)
/// this adds what the harness does not look at:
///
/// * [textProblems]: text that is cut off (ellipsis / maxLines) or broken inside
///   a word (a column narrower than its longest word), found in the render tree;
/// * [semanticsTree]: the REAL semantics tree with flags (header, button,
///   selected, live region) and global rectangles;
/// * [tappableProblems]: tappable nodes that are partly off screen or that
///   overlap another tappable node;
/// * [fittedScales]: how far every `FittedBox` shrank its content;
/// * [sweepLayouts] / [sweepScrolled]: the device x brightness x locale x text
///   scale matrix, reporting EVERY failing combination at once.
library;

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';

/// The phones of the matrix (portrait).
const kPhones = <ScreenSpec>[kIPhoneSE, kIPhone17Pro];

/// Android 16 ignores the portrait lock on large screens: these must not throw.
const kWideScreens = <ScreenSpec>[kIPhone17ProLandscape, kTablet];
const kWideScales = <double>[1.0, 2.0];

const kLocales = <Locale>[Locale('en'), Locale('pl')];
const kBrightnesses = <Brightness>[Brightness.light, Brightness.dark];

// ---------------------------------------------------------------------------
// Semantics
// ---------------------------------------------------------------------------

/// One node of the semantics tree, flattened.
class SemNode {
  const SemNode({
    required this.label,
    required this.value,
    required this.hint,
    required this.tooltip,
    required this.rect,
    required this.header,
    required this.button,
    required this.selected,
    required this.liveRegion,
    required this.image,
    required this.tappable,
  });

  final String label;
  final String value;
  final String hint;
  final String tooltip;

  /// Logical pixels, in the coordinates of the screen.
  final Rect rect;
  final bool header;
  final bool button;
  final bool selected;
  final bool liveRegion;
  final bool image;
  final bool tappable;

  /// Label, value and tooltip, as a screen reader would read them (a node with
  /// no label of its own, such as an icon button, is read as its tooltip;
  /// newlines are pauses).
  String get spoken => [label, value, if (label.isEmpty) tooltip]
      .where((s) => s.isNotEmpty)
      .join(' ')
      .replaceAll('\u00A0', ' ')
      .replaceAll('\n', ', ');

  @override
  String toString() => '${tappable ? '[tap] ' : ''}${header ? '[header] ' : ''}'
      '${button ? '[button] ' : ''}${selected ? '[selected] ' : ''}'
      '${liveRegion ? '[live] ' : ''}"${label.replaceAll('\n', ' | ')}"'
      '${value.isEmpty ? '' : ' = "$value"'} '
      '${rect.width.toStringAsFixed(0)}x${rect.height.toStringAsFixed(0)}'
      '@${rect.left.toStringAsFixed(0)},${rect.top.toStringAsFixed(0)}';
}

/// Every node with a label, a value, a tap action or a role, of the real tree.
/// Needs semantics on (`pumpScreen(semantics: true)`).
List<SemNode> semanticsTree(WidgetTester tester) {
  final root =
      tester.binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
  if (root == null) {
    throw StateError('Semantics are off: pumpScreen(semantics: true) first.');
  }
  final dpr = tester.view.devicePixelRatio;
  final out = <SemNode>[];
  void visit(SemanticsNode n) {
    if (!n.isMergedIntoParent) {
      final d = n.getSemanticsData();
      final flags = d.flagsCollection;
      final tappable = d.hasAction(SemanticsAction.tap);
      if (!flags.isHidden &&
          (d.label.isNotEmpty ||
              d.value.isNotEmpty ||
              tappable ||
              flags.isHeader ||
              flags.isImage)) {
        final global = _globalRect(n);
        out.add(SemNode(
          label: d.label,
          value: d.value,
          hint: d.hint,
          tooltip: d.tooltip,
          rect: Rect.fromLTRB(global.left / dpr, global.top / dpr,
              global.right / dpr, global.bottom / dpr),
          header: flags.isHeader,
          button: flags.isButton,
          selected: flags.isSelected == Tristate.isTrue,
          liveRegion: flags.isLiveRegion,
          image: flags.isImage,
          tappable: tappable,
        ));
      }
    }
    n.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  visit(root);
  return out;
}

/// [n]'s rectangle in the coordinates of the screen in physical pixels: its own
/// rectangle moved through the transforms of every ancestor.
Rect _globalRect(SemanticsNode n) {
  var rect = n.rect;
  for (SemanticsNode? cur = n; cur != null; cur = cur.parent) {
    final transform = cur.transform;
    if (transform != null) rect = MatrixUtils.transformRect(transform, rect);
  }
  return rect;
}

/// The nodes whose label (or value) contains [text] (case-insensitive).
List<SemNode> nodesContaining(List<SemNode> tree, String text) => [
      for (final n in tree)
        if (n.spoken.toLowerCase().contains(text.toLowerCase())) n,
    ];

/// The one node that contains ALL of [parts] (case-insensitive); fails with the
/// whole tree when there is none or several.
SemNode oneNodeWith(List<SemNode> tree, List<String> parts, {String? why}) {
  final hits = [
    for (final n in tree)
      if (parts.every((p) => n.spoken.toLowerCase().contains(p.toLowerCase())))
        n,
  ];
  if (hits.length != 1) {
    fail('${why ?? 'Expected exactly one semantics node'} containing $parts, '
        'found ${hits.length}: $hits\n\nsemantics tree:\n${tree.join('\n')}');
  }
  return hits.single;
}

/// Tappable nodes that stick out of the screen sideways or overlap another
/// tappable node (neither containing the other). Empty = fine.
List<String> tappableProblems(WidgetTester tester, List<SemNode> tree) {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  final tappables = [
    for (final n in tree)
      if (n.tappable) n
  ];
  final out = <String>[];
  for (final n in tappables) {
    if (n.rect.left < -0.5 || n.rect.right > size.width + 0.5) {
      out.add(
          'off screen sideways: $n (screen ${size.width.toStringAsFixed(0)} wide)');
    }
  }
  for (var i = 0; i < tappables.length; i++) {
    for (var j = i + 1; j < tappables.length; j++) {
      final a = tappables[i].rect;
      final b = tappables[j].rect;
      final hit = a.intersect(b);
      // Touching is not overlapping.
      if (hit.width <= 1 || hit.height <= 1) continue;
      final nested = _contains(a, b) || _contains(b, a);
      if (!nested) out.add('overlap: ${tappables[i]}  with  ${tappables[j]}');
    }
  }
  return out;
}

bool _contains(Rect outer, Rect inner) =>
    outer.inflate(1).contains(inner.topLeft) &&
    outer.inflate(1).contains(inner.bottomRight);

// ---------------------------------------------------------------------------
// Render tree: text and FittedBox
// ---------------------------------------------------------------------------

/// Text that is cut off or broken inside a word, below [within] (default: the
/// whole screen). Text drawn on one line by design (`softWrap: false`, such as
/// the number of a [BigNumber] inside its `FittedBox`) is not "broken": it is
/// as wide as it needs to be.
List<String> textProblems(WidgetTester tester, {Finder? within}) {
  final roots = within == null
      ? tester.binding.renderViews.cast<RenderObject>().toList()
      : [tester.renderObject(within.first)];
  final out = <String>[];
  void visit(RenderObject r) {
    if (r is RenderParagraph && r.hasSize) {
      final text = r.text.toPlainText(includePlaceholders: false);
      if (r.didExceedMaxLines) {
        out.add('"$text" is cut off (maxLines / ellipsis)');
      }
      final longestWord = r.getMinIntrinsicWidth(double.infinity);
      if (r.size.width + 0.5 < longestWord) {
        out.add('"$text" is broken inside a word '
            '(${r.size.width.toStringAsFixed(1)} px wide, longest word '
            '${longestWord.toStringAsFixed(1)} px)');
      }
    }
    r.visitChildren(visit);
  }

  for (final root in roots) {
    visit(root);
  }
  return out;
}

/// Layouts below [within] (default: the whole screen) that overflow right now.
/// The harness' `expectNoFlutterErrors` looks at every tab of the shell; this
/// looks at one part of it.
List<String> overflowProblems(WidgetTester tester, {Finder? within}) {
  final roots = within == null
      ? tester.binding.renderViews.cast<RenderObject>().toList()
      : [tester.renderObject(within.first)];
  final out = <String>[];
  void visit(RenderObject r) {
    if (r.toStringShort().contains(' OVERFLOWING')) {
      out.add('${r.runtimeType} overflows (${r.toStringShort()})');
    }
    r.visitChildren(visit);
  }

  for (final root in roots) {
    visit(root);
  }
  return out;
}

/// For every `FittedBox` below [within]: how much it scaled its child
/// (1.0 = not at all, 0.5 = half the size), with the text it contains.
List<(String, double)> fittedScales(WidgetTester tester, {Finder? within}) {
  final finder = find.descendant(
      of: within ?? find.byType(Directionality).first,
      matching: find.byType(FittedBox));
  final out = <(String, double)>[];
  for (final element in finder.evaluate()) {
    final box = element.renderObject;
    if (box is! RenderFittedBox || !box.hasSize || box.child == null) continue;
    final child = box.child!;
    if (!child.hasSize || child.size.width == 0) continue;
    final scale = (box.size.width / child.size.width).clamp(0.0, 1.0);
    final text = element.widget is FittedBox ? _plainTextBelow(element) : '';
    out.add((text, scale));
  }
  return out;
}

String _plainTextBelow(Element element) {
  final buffer = StringBuffer();
  void visit(Element e) {
    final w = e.widget;
    if (w is Text) buffer.write(w.data ?? w.textSpan?.toPlainText() ?? '');
    e.visitChildren(visit);
  }

  visit(element);
  return buffer.toString();
}

// ---------------------------------------------------------------------------
// Contrast
// ---------------------------------------------------------------------------

/// Is [element] inside a tab (or anything) that is laid out but not shown?
bool _isOffstage(Element element) {
  var hidden = false;
  element.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Offstage && w.offstage) hidden = true;
    return !hidden;
  });
  return hidden;
}

/// WCAG contrast ratio of two opaque colours.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// What is behind a text: the decorations of its ancestors, composited from the
/// outermost opaque one inwards, with gradients evaluated at [at].
Color _backgroundBehind(Element element, Rect textRect, List<Offset> at,
    Color fallback, int sample) {
  // Outermost last.
  final layers = <Object>[];
  element.visitAncestorElements((ancestor) {
    final w = ancestor.widget;
    Object? layer;
    if (w is Ink) {
      final d = w.decoration;
      if (d is BoxDecoration) layer = (d, ancestor);
    } else if (w is DecoratedBox) {
      final d = w.decoration;
      if (d is BoxDecoration) layer = (d, ancestor);
    } else if (w is ColoredBox) {
      layer = w.color;
    } else if (w is Material && w.color != null) {
      layer = w.color!;
    } else if (w is Scaffold && w.backgroundColor != null) {
      layer = w.backgroundColor!;
    }
    if (layer != null) layers.add(layer);
    // An opaque flat colour hides everything further out.
    final opaque = layer is Color && layer.a >= 0.999;
    return !opaque;
  });

  Color base = fallback;
  for (final layer in layers.reversed) {
    if (layer is Color) {
      base = Color.alphaBlend(layer, base);
    } else if (layer is (BoxDecoration, Element)) {
      final (decoration, owner) = layer;
      final box = owner.findRenderObject();
      final color = decoration.color;
      if (color != null) base = Color.alphaBlend(color, base);
      final gradient = decoration.gradient;
      if (gradient is LinearGradient && box is RenderBox && box.hasSize) {
        final origin = box.localToGlobal(Offset.zero);
        final local = at[sample] - origin;
        base = Color.alphaBlend(_gradientAt(gradient, box.size, local), base);
      }
    }
  }
  return base;
}

Color _gradientAt(LinearGradient g, Size size, Offset p) {
  final rect = Offset.zero & size;
  final a = g.begin.resolve(TextDirection.ltr).withinRect(rect);
  final b = g.end.resolve(TextDirection.ltr).withinRect(rect);
  final d = b - a;
  final t = d.distanceSquared == 0
      ? 0.0
      : (((p - a).dx * d.dx + (p - a).dy * d.dy) / d.distanceSquared)
          .clamp(0.0, 1.0);
  final stops = g.stops ??
      [for (var i = 0; i < g.colors.length; i++) i / (g.colors.length - 1)];
  for (var i = 1; i < g.colors.length; i++) {
    if (t <= stops[i]) {
      final span = stops[i] - stops[i - 1];
      final f = span == 0 ? 1.0 : (t - stops[i - 1]) / span;
      return Color.lerp(g.colors[i - 1], g.colors[i], f)!;
    }
  }
  return g.colors.last;
}

/// Text (and icons) whose colour does not reach WCAG AA against what is drawn
/// behind it: 4.5:1 for text, 3:1 for large text (24 px, or 18.7 px bold, at the
/// size it is drawn) and for icons. Exact, unlike `textContrastGuideline`, which
/// guesses the two colours from a histogram of the pixels and mistakes a gradient
/// card (the accent washes) for a low-contrast text.
///
/// Only text that is on screen is looked at. Decorations that are painted by a
/// custom painter (the charts) are not known to this check.
List<String> contrastProblems(WidgetTester tester) {
  final screen =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  final pageColor = tester.binding.renderViews.isEmpty
      ? Colors.white
      : Theme.of(tester.element(find.byType(Directionality).first))
          .scaffoldBackgroundColor;
  final problems = <String>{};
  for (final element in find.byType(RichText).evaluate()) {
    final render = element.renderObject;
    if (render is! RenderParagraph || !render.hasSize || !render.attached) {
      continue;
    }
    if (_isOffstage(element)) continue;
    final origin = render.localToGlobal(Offset.zero);
    final rect = origin & render.size;
    if (!screen.overlaps(rect) || rect.isEmpty) continue;
    final style = render.text.style;
    final color = style?.color;
    if (color == null) continue;
    final text = render.text.toPlainText(includePlaceholders: false).trim();
    if (text.isEmpty) continue;
    // Icons are glyphs of an icon font: one code point in a private use area
    // (Material Icons live in U+E000.. and U+F0000..).
    final rune = text.runes.length == 1 ? text.runes.first : 0;
    final icon = (rune >= 0xE000 && rune <= 0xF8FF) ||
        (rune >= 0xF0000 && rune <= 0xFFFFD);
    final fontSize = render.textScaler.scale(style?.fontSize ?? 14);
    final bold = (style?.fontWeight?.value ?? 400) >= 600;
    final large = icon || fontSize >= 24 || (bold && fontSize >= 18.66);
    final needed = large ? 3.0 : 4.5;

    // Worst case over the corners and the centre of the text.
    final points = [
      rect.center,
      rect.topLeft + const Offset(1, 1),
      rect.topRight + const Offset(-1, 1),
      rect.bottomLeft + const Offset(1, -1),
      rect.bottomRight + const Offset(-1, -1),
    ];
    for (var i = 0; i < points.length; i++) {
      final background = _backgroundBehind(element, rect, points, pageColor, i);
      final foreground = Color.alphaBlend(color, background);
      final ratio = contrastRatio(foreground, background);
      if (ratio + 0.005 < needed) {
        problems.add('"$text" ${fontSize.toStringAsFixed(0)} px: '
            'contrast ${ratio.toStringAsFixed(2)}:1, needs $needed:1 '
            '(text #${foreground.toARGB32().toRadixString(16)} on '
            '#${background.toARGB32().toRadixString(16)})');
        break;
      }
    }
  }
  return problems.toList();
}

/// Fails with [contrastProblems], naming [screen] and the view.
void expectTextContrast(WidgetTester tester, {String? screen}) {
  final problems = contrastProblems(tester);
  if (problems.isEmpty) return;
  fail('Text contrast at [${[
    if (screen != null) screen,
    describeView(tester)
  ].join(' | ')}]\n'
      '${problems.map((p) => '  - $p').join('\n')}');
}

// ---------------------------------------------------------------------------
// Sweeps
// ---------------------------------------------------------------------------

/// Applies one configuration cheaply: no full settle (that pumps 600+ ms of
/// fake time per call), just enough frames for layout, the locale and the
/// theme animation to finish.
Future<void> applyView(
  WidgetTester tester,
  AppHarness h, {
  required double textScale,
  required ScreenSpec device,
  required Brightness brightness,
  required Locale locale,
  bool settleFully = false,
}) async {
  await h.configure(tester,
      textScale: textScale,
      device: device,
      brightness: brightness,
      locale: locale,
      andSettle: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  if (settleFully) await settle(tester);
}

/// Runs [check] (which signals failure with a `TestFailure`, as the harness
/// checks do) for every combination, and fails ONCE at the end naming every
/// failing combination. [positions] > 1 scrolls the main list to that many
/// evenly spaced offsets, so lazily built rows further down are checked too.
Future<void> sweepLayouts(
  WidgetTester tester,
  AppHarness h, {
  required String screen,
  required Future<void> Function() check,
  List<double> scales = kTextScales,
  List<ScreenSpec> devices = kPhones,
  List<Brightness> brightnesses = kBrightnesses,
  List<Locale> locales = kLocales,
  int positions = 1,

  /// Wait for every animation (theme change, ink, count-up) before checking:
  /// needed for the checks that look at pixels (contrast).
  bool settleFully = false,

  /// The list to scroll (default: the first vertical one on screen).
  Finder? scrollable,
}) async {
  final failures = <String>[];
  var combinations = 0;
  for (final device in devices) {
    for (final brightness in brightnesses) {
      for (final locale in locales) {
        for (final scale in scales) {
          combinations++;
          await applyView(tester, h,
              textScale: scale,
              device: device,
              brightness: brightness,
              locale: locale,
              settleFully: settleFully);
          try {
            await _atPositions(tester, positions, check,
                settleFully: settleFully, scrollable: scrollable);
          } on TestFailure catch (e) {
            failures.add('${h.describe()}\n${e.message}');
          }
        }
      }
    }
  }
  if (failures.isNotEmpty) {
    fail('$screen: ${failures.length} of $combinations view configuration(s) '
        'failed:\n\n${failures.join('\n\n')}');
  }
}

/// [check] at the top and at [positions] - 1 further evenly spaced scroll
/// offsets of the first vertical scrollable (back to the top afterwards).
Future<void> _atPositions(
    WidgetTester tester, int positions, Future<void> Function() check,
    {bool settleFully = false, Finder? scrollable}) async {
  await check();
  if (positions <= 1) return;
  final scrollables =
      (scrollable ?? find.byType(Scrollable)).evaluate().where((e) {
    final state = (e as StatefulElement).state as ScrollableState;
    return state.position.axis == Axis.vertical;
  }).toList();
  if (scrollables.isEmpty) return;
  final state = (scrollables.first as StatefulElement).state as ScrollableState;
  final failures = <String>[];
  try {
    final max = state.position.maxScrollExtent;
    for (var i = 1; i < positions; i++) {
      state.position.jumpTo(max * i / (positions - 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      if (settleFully) await settle(tester);
      try {
        await check();
      } on TestFailure catch (e) {
        failures.add('scrolled to ${(100 * i / (positions - 1)).round()}%:\n'
            '${e.message}');
      }
    }
  } finally {
    state.position.jumpTo(0);
    await tester.pump();
  }
  if (failures.isNotEmpty) fail(failures.join('\n'));
}

/// The standard layout check of a screen: no overflow or Flutter error, no
/// text cut off or broken inside a word, no tappable thing off screen or on top
/// of another.
Future<void> expectLayoutHealthy(WidgetTester tester, String screen,
    {bool semantics = false}) async {
  final problems = <String>[];
  try {
    expectNoFlutterErrors(tester, screen: screen);
  } on TestFailure catch (e) {
    problems.add(e.message ?? 'layout problems');
  }
  problems.addAll(textProblems(tester));
  if (semantics) {
    problems.addAll(tappableProblems(tester, semanticsTree(tester)));
  }
  if (problems.isNotEmpty) {
    fail(problems.map((p) => '  - $p').join('\n'));
  }
}
