// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Building blocks of the flow screens (Welcome, Auth, Setup, Permissions,
/// Settings, Account): layouts that stay readable from the design size up to the
/// largest accessibility text size, and semantics helpers.
///
/// Three rules every widget here follows:
///  * a value or a button that does not fit beside its text moves below it
///    (never ellipsized, never squeezed so that a word breaks in the middle);
///  * a word that is wider than its line shrinks just enough to fit
///    ([FlowFitText]) instead of being cut in half;
///  * nothing is hidden from a screen reader: merged rows carry one label.

/// From about iOS "Extra Large" on: pills become rounded rectangles that can
/// hold several lines, side-by-side rows start to stack.
bool isLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(16) / 16 > 1.3;

/// An outlined button that stays a pill at the design size and becomes a
/// rounded rectangle once its label can run over several lines (a stadium
/// border would cut into multi-line text).
ButtonStyle flowOutlinedStyle(BuildContext context, {Color? color}) {
  final scheme = Theme.of(context).colorScheme;
  final base = color ?? scheme.onSurface;
  return OutlinedButton.styleFrom(
    foregroundColor: base,
    side: BorderSide(color: base.withValues(alpha: 0.35)),
    shape: isLargeText(context)
        ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
        : const StadiumBorder(),
    minimumSize: const Size(48, 48),
  );
}

/// An email address with invisible break opportunities after `@` and `.`, so a
/// long address wraps there instead of being cut mid-name. Display only: keep
/// the original for semantics and copying.
String breakableEmail(String email) =>
    email.replaceAllMapped(RegExp(r'[@.]'), (m) => '${m[0]}\u200B');

// ------------------------------------------------------------------ measuring

/// Text measurement at the current text scale.
class TextFit {
  const TextFit._();

  /// Pieces of [text] a line can break between: words, and the parts of a
  /// hyphenated word. Zero-width spaces (see [breakableEmail]) separate too.
  static List<String> pieces(String text) => [
        for (final word in text.split(RegExp(r'[\s\u200B]+')))
          ...word.split(RegExp(r'(?<=-)')),
      ].where((p) => p.isNotEmpty).toList();

  /// Width of [text] on a single line.
  static double width(BuildContext context, String text, TextStyle? style) =>
      _measure(context, text, style);

  /// Width of the widest unbreakable piece of [text].
  static double longestWord(
      BuildContext context, String? text, TextStyle? style) {
    if (text == null || text.isEmpty) return 0;
    var widest = 0.0;
    for (final piece in pieces(text)) {
      final w = _measure(context, piece, style);
      if (w > widest) widest = w;
    }
    return widest;
  }

  static double _measure(BuildContext context, String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(
          text: text, style: DefaultTextStyle.of(context).style.merge(style)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = painter.width;
    painter.dispose();
    return w;
  }
}

/// True when [sideWidth] fits beside a main part that needs at least
/// [minMain] and is not more than [maxSideFraction] of the line.
bool fitsBeside({
  required double available,
  required double sideWidth,
  required double minMain,
  double gap = 12,
  double maxSideFraction = 0.5,
}) =>
    sideWidth <= available * maxSideFraction &&
    available - sideWidth - gap >= minMain;

/// [main] with [side] next to it when both fit; otherwise [side] below [main].
///
/// [sideWidth] is the width [side] needs on one line and [minMainWidth] the
/// widest word of [main] (see [TextFit]); the decision is made from them, so
/// the layout never has to squeeze text.
class BesideOrBelow extends StatelessWidget {
  const BesideOrBelow({
    super.key,
    required this.main,
    required this.side,
    required this.sideWidth,
    required this.minMainWidth,
    this.gap = 12,
    this.belowGap = 8,
    this.maxSideFraction = 0.5,
    this.belowAlignment = AlignmentDirectional.centerStart,
  });

  final Widget main;
  final Widget side;
  final double sideWidth;
  final double minMainWidth;
  final double gap;
  final double belowGap;
  final double maxSideFraction;
  final AlignmentGeometry belowAlignment;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final beside = fitsBeside(
              available: constraints.maxWidth,
              sideWidth: sideWidth,
              minMain: minMainWidth,
              gap: gap,
              maxSideFraction: maxSideFraction);
          if (beside) {
            return Row(
              children: [
                Expanded(child: main),
                SizedBox(width: gap),
                side,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              main,
              SizedBox(height: belowGap),
              Align(alignment: belowAlignment, child: side),
            ],
          );
        },
      );
}

/// A [Text] that shrinks just enough for its longest word to fit the line:
/// a slightly smaller word reads better than one broken in the middle. Never
/// shrinks below the design size, and does nothing when everything fits.
///
/// Same idea as the shared `WordFitText` (`wb_widgets.dart`), except that the
/// word is fitted to 98% of the line: fitting it to exactly 100% still broke
/// "Synchronizacja" by one pixel (glyph advances are not linear in the font
/// size). Prefer the shared widget once it has the same slack.
class FlowFitText extends StatelessWidget {
  const FlowFitText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          var scaler = MediaQuery.textScalerOf(context);
          final available = constraints.maxWidth;
          if (available.isFinite) {
            final word = TextFit.longestWord(context, text, style);
            if (word > available + 0.5) {
              final fontSize =
                  (style ?? DefaultTextStyle.of(context).style).fontSize ?? 14;
              final scale = scaler.scale(fontSize) / fontSize;
              // 2% slack: glyph advances are not exactly linear in the size.
              final fitted = scale * available * 0.98 / word;
              scaler = TextScaler.linear(fitted < 1 ? 1 : fitted);
            }
          }
          return Text(text,
              style: style, textAlign: textAlign, textScaler: scaler);
        },
      );
}

/// A heading: announced as one by screen readers, fitted by [FlowFitText]. With
/// [liveRegion] a screen reader announces it when it appears or changes (a
/// screen that is replaced in place, such as the setup review).
class FlowHeading extends StatelessWidget {
  const FlowHeading(
    this.text, {
    super.key,
    this.style,
    this.liveRegion = false,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final bool liveRegion;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        header: true,
        liveRegion: liveRegion,
        child: FlowFitText(text, style: style, textAlign: textAlign),
      );
}

/// A dialog whose content scrolls (large text, small screens), whose title is
/// announced as a heading and whose buttons stack when they do not fit in a row.
///
/// The title scales with the system text size up to 2x (a 24 sp headline at 3x
/// is wider than the longest Polish word that fits on a phone). It is a plain
/// `Text` on purpose: `AlertDialog` measures its intrinsic width, which a
/// `LayoutBuilder` (see [FlowFitText]) cannot answer.
AlertDialog flowDialog(
  BuildContext context, {
  required String title,
  required String body,
  required List<Widget> actions,
}) =>
    AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Semantics(
        container: true,
        header: true,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 2,
          child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
        ),
      ),
      content: Text(body),
      actions: actions,
    );

/// A label with a switch: the same merged node a `SwitchListTile` gives (name,
/// state and the toggle action together), with the switch moving below the text
/// when the text needs the whole line.
class FlowSwitchTile extends StatelessWidget {
  const FlowSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle =
        theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600);
    final subtitleStyle = theme.textTheme.labelMedium;
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: padding,
            child: BesideOrBelow(
              sideWidth: 64,
              minMainWidth: math.max(
                  TextFit.longestWord(context, title, titleStyle),
                  TextFit.longestWord(context, subtitle, subtitleStyle)),
              belowAlignment: AlignmentDirectional.centerEnd,
              main: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FlowFitText(title, style: titleStyle),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: subtitleStyle),
                  ],
                ],
              ),
              side: Switch(value: value, onChanged: onChanged),
            ),
          ),
        ),
      ),
    );
  }
}
