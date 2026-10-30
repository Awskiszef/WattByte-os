// Shared sweep helpers for the flow-screen accessibility tests (welcome, auth,
// setup, permissions, settings, account). Not a test file itself.
//
// One sweep = one screen checked in every combination of device x brightness x
// locale x text scale: no overflow / layout error (expectNoFlutterErrors) and,
// optionally, every tap target large enough and labelled
// (expectAccessibleTargets). All failing combinations are collected and
// reported together, and a one-line summary is printed so before/after numbers
// can be compared:
//
//   SWEEP Settings: 40 configs, 17 failing, 23 overflow findings
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';

/// `rootBundle` memoizes the device catalog's `Future`. A `Future` created in
/// one test's fake-async zone can never be awaited from another test's zone
/// (its continuation is scheduled in the dead zone), so the second test of a
/// file that runs the automatic setup would hang in "Setting up WattByte...".
/// Call this in `setUp`.
void resetAssetCache() => rootBundle.evict('assets/device_specs/devices.json');

/// Phones: the smallest supported iPhone and the current one.
const kPhones = <ScreenSpec>[kIPhoneSE, kIPhone17Pro];

/// Layouts v1 does not target but must never crash on (Android 16 ignores the
/// orientation lock on large screens): landscape phone, tablet.
const kWide = <ScreenSpec>[kIPhone17ProLandscape, kTablet];

const kLocales = <Locale>[Locale('en'), Locale('pl')];

final _overflowCount = RegExp(r'(\d+) overflowing layout');
final _problemCount = RegExp(r'(\d+) problem\(s\)');

/// What a sweep measured.
class SweepResult {
  const SweepResult(this.configs, this.failing, this.findings);

  final int configs;
  final int failing;

  /// Overflowing layouts + other Flutter errors, summed over all failing configs.
  final int findings;
}

/// Runs the checks for every combination and fails once, at the end, listing
/// every failing combination. [prepare] runs after each `configure` (reopen a
/// sheet, scroll to the bottom, ...); [after] runs after the checks.
///
/// [layout] checks overflow / errors, [targets] the tap-target guidelines.
Future<SweepResult> sweepFlow(
  WidgetTester tester,
  AppHarness h, {
  required String screen,
  List<ScreenSpec> devices = kPhones,
  List<double> scales = kTextScales,
  List<Brightness> brightnesses = Brightness.values,
  List<Locale> locales = kLocales,
  bool layout = true,
  bool targets = true,
  Future<void> Function()? prepare,
  bool scroll = false,
  bool failOnProblems = true,
}) async {
  final failures = <String>[];
  var configs = 0;
  var findings = 0;
  for (final device in devices) {
    for (final b in brightnesses) {
      for (final locale in locales) {
        for (final scale in scales) {
          configs++;
          await h.configure(tester,
              textScale: scale, device: device, brightness: b, locale: locale);
          if (prepare != null) await prepare();
          final problems = <String>[];
          Future<void> check() async {
            if (layout) {
              try {
                expectNoFlutterErrors(tester, screen: screen);
              } on TestFailure catch (e) {
                final m = _overflowCount.firstMatch(e.message ?? '');
                findings += m == null ? 1 : int.parse(m.group(1)!);
                problems.add(e.message ?? 'layout problem');
              }
              try {
                expectNoBrokenText(tester, screen: screen);
              } on TestFailure catch (e) {
                final m = _problemCount.firstMatch(e.message ?? '');
                findings += m == null ? 1 : int.parse(m.group(1)!);
                problems.add(e.message ?? 'broken text');
              }
            }
            if (targets) {
              try {
                await expectAccessibleTargets(tester, screen: screen);
              } on TestFailure catch (e) {
                findings++;
                problems.add(e.message ?? 'accessibility problem');
              }
            }
          }

          if (scroll) {
            await forEachScrollPosition(tester, check);
          } else {
            await check();
          }
          if (problems.isNotEmpty) {
            failures.add('${h.describe()}\n${problems.join('\n')}');
          }
        }
      }
    }
  }
  debugPrint('SWEEP $screen: $configs configs, ${failures.length} failing, '
      '$findings findings');
  if (failOnProblems && failures.isNotEmpty) {
    fail('${failures.length} of $configs view configuration(s) of [$screen] '
        'fail:\n\n${failures.join('\n\n')}');
  }
  return SweepResult(configs, failures.length, findings);
}

/// Text that is cut off or torn apart: a paragraph that hit its line limit
/// (ellipsis or clip), or one whose longest word is wider than the paragraph,
/// which makes the line breaker split the word in the middle. Overflow errors
/// do not show either: a `Text` in an `Expanded` simply wraps inside the word.
///
/// Fails with a [TestFailure] listing each offender once.
void expectNoBrokenText(WidgetTester tester, {String? screen}) {
  final problems = <String>{};
  void visit(RenderObject r) {
    if (r is RenderParagraph && r.hasSize && r.size.width > 0) {
      final text = r.text.toPlainText();
      if (r.didExceedMaxLines) {
        problems.add('cut off at its line limit: "${_short(text)}"');
      }
      if (r.softWrap) {
        final style = _firstStyle(r.text);
        for (final piece in _pieces(text)) {
          final painter = TextPainter(
            text: TextSpan(text: piece, style: style),
            textDirection: r.textDirection,
            textScaler: r.textScaler,
            locale: r.locale,
          )..layout();
          final width = painter.width;
          painter.dispose();
          if (width > r.size.width + 0.5) {
            problems.add('word "$piece" (${width.toStringAsFixed(0)} px) '
                'is wider than its line (${r.size.width.toStringAsFixed(0)} px) '
                'in "${_short(text)}"');
          }
        }
      }
    }
    r.visitChildren(visit);
  }

  for (final view in tester.binding.renderViews) {
    visit(view);
  }
  if (problems.isEmpty) return;
  final context =
      [if (screen != null) screen, describeView(tester)].join(' | ');
  fail('Broken text at [$context]\n\n${problems.length} problem(s):\n'
      '${problems.map((p) => '  - $p').join('\n')}\n');
}

String _short(String t) {
  final one = t.replaceAll('\n', ' ');
  return one.length > 48 ? '${one.substring(0, 48)}...' : one;
}

TextStyle? _firstStyle(InlineSpan span) {
  if (span is TextSpan && span.style != null) return span.style;
  TextStyle? found;
  span.visitChildren((child) {
    if (child is TextSpan && child.style != null) {
      found = child.style;
      return false;
    }
    return true;
  });
  return found;
}

List<String> _pieces(String text) => [
      for (final word in text.split(RegExp(r'[\s\u200B]+')))
        ...word.split(RegExp(r'(?<=-)')),
    ].where((p) => p.length > 1).toList();

/// A lazy list builds only what is near the viewport, so a single check misses
/// every row further down. Runs [check] with the outermost scrollable at the
/// top, then page by page (70% of the viewport per step) to the end, and puts it
/// back on top.
Future<void> forEachScrollPosition(
    WidgetTester tester, Future<void> Function() check) async {
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isEmpty) {
    await check();
    return;
  }
  final position = tester.state<ScrollableState>(scrollables.first).position;
  position.jumpTo(position.minScrollExtent);
  await tester.pump();
  await check();
  var guard = 0;
  while (position.pixels < position.maxScrollExtent && guard++ < 200) {
    position.jumpTo((position.pixels + position.viewportDimension * 0.7)
        .clamp(position.minScrollExtent, position.maxScrollExtent));
    await tester.pump();
    await check();
  }
  position.jumpTo(position.minScrollExtent);
  await tester.pump();
}

/// The text the screen exposes to a screen reader, joined, for assertions that
/// a value is not cut off.
Iterable<String> semanticLabels(WidgetTester tester) =>
    semanticsNodes(tester).map((n) => n.label);

/// A label that matches exactly (labels are compared as plain strings by
/// `find.bySemanticsLabel`, `RegExp` is "contains").
Pattern exactly(String label) => RegExp('^${RegExp.escape(label)}\$');

/// Every distinct semantics node whose label matches [label]. (Several
/// elements, e.g. a `MergeSemantics` and the `IndexedSemantics` of its list
/// slot, can stand for one node.)
List<SemanticsNode> _nodesWithLabel(WidgetTester tester, Pattern label) {
  final nodes = <int, SemanticsNode>{};
  for (final element in find.bySemanticsLabel(label).evaluate()) {
    final node = element.renderObject?.debugSemantics;
    if (node != null) nodes[node.id] = node;
  }
  return nodes.values.toList();
}

/// The one semantics node whose label matches [label]; fails, listing every
/// label on screen, when there is none or several. Semantics must be on.
SemanticsNode semanticsNode(WidgetTester tester, Pattern label) {
  final nodes = _nodesWithLabel(tester, label);
  expect(nodes, hasLength(1),
      reason: 'exactly one semantics node should match $label. On screen:\n'
          '${semanticLabels(tester).map((l) => '  - ${l.replaceAll('\n', ' / ')}').join('\n')}');
  return nodes.single;
}

/// Number of distinct semantics nodes whose label matches [label].
int semanticsCount(WidgetTester tester, Pattern label) =>
    _nodesWithLabel(tester, label).length;

/// The guideline samples the pixels of every text it finds: a row cut by the top or bottom edge of the list is sampled half
/// empty and "fails" for a reason that has nothing to do with the design. Where a row falls at the end of the list depends on the
/// platform's text metrics (a wrapped Polish label sat on the edge on Linux and not on macOS), so from the end of the list the
/// scroll position moves up, in small steps, to the nearest position where no text is cut. Every row is still judged whole.
Future<void> _scrollUpUntilNoTextIsCut(
    WidgetTester tester, ScrollPosition position) async {
  final viewport = tester.getRect(find.byType(Scrollable).first);
  bool anyCut() {
    for (final element in find.byType(RichText).evaluate()) {
      final box = element.renderObject;
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      final visible = rect.intersect(viewport);
      final touches = visible.width > 0 && visible.height > 0;
      if (touches && visible.height < rect.height - 0.5) return true;
    }
    return false;
  }

  final end = position.maxScrollExtent;
  for (var back = 0.0;
      back <= 240 && end - back >= position.minScrollExtent;
      back += 4) {
    position.jumpTo(end - back);
    await tester.pump();
    if (!anyCut()) return;
  }
  position.jumpTo(end); // nothing cleaner within reach: judge the end as it is
  await tester.pump();
}

/// Saves what the test sees to `build/test-failures/<name>.png` (CI uploads that folder when a job fails), so a failure that
/// only happens on one platform can be looked at instead of guessed. Returns the path, or null if nothing could be written.
Future<String?> _saveFailureScreenshot(WidgetTester tester, String name) async {
  try {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first);
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    });
    if (bytes == null) return null;
    final dir = Directory('build/test-failures')..createSync(recursive: true);
    final file = File(
        '${dir.path}/${name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_')}.png');
    file.writeAsBytesSync(bytes);
    return file.path;
  } catch (_) {
    return null;
  }
}

/// WCAG text contrast (4.5:1, 3:1 for large text) of what is on screen, light
/// and dark, English and Polish, at the design text size: with the list at its
/// top and at its end (a row cut by the screen edge would be sampled half
/// blank, so the positions in between are not judged).
Future<void> expectReadableContrast(
  WidgetTester tester,
  AppHarness h, {
  required String screen,
  ScreenSpec device = kIPhone17Pro,
}) async {
  final failures = <String>[];
  for (final b in Brightness.values) {
    for (final locale in kLocales) {
      await h.configure(tester,
          textScale: 1.0, device: device, brightness: b, locale: locale);
      Future<void> check(String where) async {
        try {
          await expectAccessibleTargets(tester,
              screen: screen,
              android: false,
              ios: false,
              labeled: false,
              contrast: true);
        } on TestFailure catch (e) {
          final shot = await _saveFailureScreenshot(
              tester, '$screen-${b.name}-${locale.languageCode}-$where');
          failures.add('${b.name} ${locale.languageCode} ($where)\n'
              '${e.message}${shot == null ? '' : '\nscreenshot: $shot'}');
        }
      }

      final scrollables = find.byType(Scrollable);
      if (scrollables.evaluate().isEmpty) {
        await check('screen');
        continue;
      }
      final position =
          tester.state<ScrollableState>(scrollables.first).position;
      position.jumpTo(position.minScrollExtent);
      await tester.pump();
      await check('top');
      if (position.maxScrollExtent > position.minScrollExtent) {
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        await _scrollUpUntilNoTextIsCut(tester, position);
        await check('end');
        position.jumpTo(position.minScrollExtent);
        await tester.pump();
      }
    }
  }
  if (failures.isNotEmpty) {
    fail('${failures.length} contrast failure(s) on [$screen]:\n\n'
        '${failures.join('\n\n')}');
  }
}
