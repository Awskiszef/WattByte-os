import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/units.dart';
import '../theme.dart';

// ---------------------------------------------------------------------------
// Text scale and screen-reader helpers
// ---------------------------------------------------------------------------

/// The text scale the user asked for: 1.0 at the default size, never clamped
/// (iOS accessibility sizes reach ~3.1x, Android 2.0x).
double systemTextScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(16) / 16;

/// [text] the way a screen reader should say it. The "~" that marks an
/// estimate on screen is dropped (VoiceOver reads it as "tilde"; the word
/// "Estimated" carries the meaning) and non-breaking spaces become spaces.
String spoken(String text) =>
    text.replaceAll('~', '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Joins the non-empty [parts] with ", ": one phrase for a screen reader.
String joinSpoken(Iterable<String?> parts) => [
      for (final p in parts)
        if (p != null && spoken(p).isNotEmpty) spoken(p),
    ].join(', ');

// ---------------------------------------------------------------------------
// Cards
// ---------------------------------------------------------------------------

/// Rounded surface card with a soft shadow (light) or hairline border (dark).
///
/// Accessibility: without [semanticLabel] the card adds nothing, its children
/// speak for themselves (what the account and setup screens rely on). With
/// [semanticLabel] the card is ONE node (a button when [onTap] is set) that
/// reads exactly that text and its children are hidden from the screen reader:
/// use it for stat cards and list rows, so the animated number is never read
/// half way and label, value, sub-line and "Estimated" badge are one phrase.
class WbCard extends StatelessWidget {
  const WbCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.gradient,
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;
  final VoidCallback? onTap;

  /// What a screen reader says for the whole card (see the class comment).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kRadius),
        child: Ink(
          decoration: BoxDecoration(
            color: scheme.surface,
            gradient: gradient,
            borderRadius: BorderRadius.circular(kRadius),
            border: dark
                ? Border.all(color: Colors.white.withValues(alpha: 0.06))
                : null,
            boxShadow: dark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    final label = semanticLabel;
    if (label != null) {
      return Semantics(
        container: true,
        label: label,
        button: onTap != null,
        onTap: onTap,
        excludeSemantics: true,
        child: card,
      );
    }
    return card;
  }
}

/// Subtle accent wash used behind hero cards: [accent] at 16% over the card
/// surface in the top-left corner, fading into the plain surface.
///
/// The first stop is the BLENDED colour, not a translucent one: a gradient
/// interpolates the colour channels without regard to alpha, so a translucent
/// stop draws the accent at full strength where it fades (the corner looked
/// two to three times stronger than 16%, and muted text on it fell below 4:1
/// in dark mode).
Gradient accentWash(BuildContext context, Color accent) {
  final surface = Theme.of(context).colorScheme.surface;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color.alphaBlend(accent.withValues(alpha: 0.16), surface),
      surface,
      surface,
    ],
  );
}

// ---------------------------------------------------------------------------
// Numbers and badges
// ---------------------------------------------------------------------------

/// Large number that counts up when its value changes (not when the system
/// asks for reduced motion).
///
/// * It is ONE line that shrinks (`FittedBox.scaleDown`) instead of truncating
///   or wrapping: "~0.000 ..." hid the currency on narrow cards. That is the
///   only use of `FittedBox` in the app, always around a single numeric value.
///   Callers keep the shrink small by giving the number enough width (see
///   [AdaptiveColumns]); `test/accessibility/shared_widgets_*` asserts the
///   value is never drawn below 75% of the size of the style.
/// * The "~" of an estimate is added only to text that is a number: never to
///   "<0,001 zł" or "—" (see [shown]).
/// * A screen reader gets the FINAL value (with "Estimated"), not the numbers
///   of the animation.
class BigNumber extends StatelessWidget {
  const BigNumber({
    super.key,
    required this.value,
    required this.format,
    this.estimated = false,
    this.style,
  });

  final double value;
  final String Function(double) format;
  final bool estimated;
  final TextStyle? style;

  /// [Units.approx] is the one place that knows when a "~" makes sense; it does
  /// not depend on the locale, so any instance will do.
  static const _approx = Units(locale: 'en');

  /// What is drawn for the formatted number [formatted].
  static String shown(String formatted, {required bool estimated}) =>
      _approx.approx(formatted, estimated: estimated);

  @override
  Widget build(BuildContext context) {
    final textStyle = style ?? Theme.of(context).textTheme.displayLarge;
    final animate = !MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: joinSpoken([format(value), if (estimated) context.l10n.estimated]),
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: animate ? 0 : value, end: value),
        duration: animate ? const Duration(milliseconds: 700) : Duration.zero,
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            shown(format(v), estimated: estimated),
            style: textStyle,
            maxLines: 1,
            softWrap: false,
          ),
        ),
      ),
    );
  }
}

/// Small pill reading "Estimated" / "Szacowane".
class EstimatedBadge extends StatelessWidget {
  const EstimatedBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: WbColors.bolt.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          context.l10n.estimated,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
        ),
      );
}

/// Caption above a value, optionally with a coloured dot.
///
/// The text wraps instead of being cut off ("Estimated cost" must stay
/// readable at the largest text size); the dot stays on the first line.
class Label extends StatelessWidget {
  const Label(this.text, {super.key, this.dot});

  final String text;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    final lineHeight =
        MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 12) *
            (style?.height ?? 1.2);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dot != null) ...[
          Padding(
            padding: EdgeInsets.only(top: math.max(0, (lineHeight - 8) / 2)),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(child: Text(text, style: style)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Layout building blocks that survive any text size
// ---------------------------------------------------------------------------

/// [leading] and [trailing] on one line, [trailing] at the far end, when both
/// fit; otherwise [trailing] wraps below [leading]. Nothing overflows and
/// nothing is squeezed to one letter per line, at any text size. Both children
/// may wrap internally when even alone they are wider than the row.
///
/// Use it instead of `Row(children: [Expanded(label), value])`, which gives a
/// long value all the room and the label none.
class SplitRow extends StatelessWidget {
  const SplitRow({
    super.key,
    required this.leading,
    required this.trailing,
    this.spacing = 12,
    this.runSpacing = 2,
  });

  final Widget leading;
  final Widget trailing;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        // A Wrap is as wide as its content unless it is told otherwise, and
        // only a full-width Wrap can push [trailing] to the far end.
        builder: (context, constraints) => SizedBox(
          width: constraints.hasBoundedWidth ? double.infinity : null,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: spacing,
            runSpacing: runSpacing,
            children: [leading, trailing],
          ),
        ),
      );
}

/// Equal-width columns side by side while each has [minColumnWidth] logical
/// pixels at the default text size, a stack otherwise. The need grows with the
/// text scale, so a pair of cards that fits at 1.0x becomes two full-width
/// cards at 1.35x on a small phone instead of two clipped ones.
class AdaptiveColumns extends StatelessWidget {
  const AdaptiveColumns({
    super.key,
    required this.children,
    this.spacing = 12,
    this.minColumnWidth = 150,
  });

  final List<Widget> children;
  final double spacing;

  /// Width one column needs at text scale 1.0.
  final double minColumnWidth;

  /// Whether [count] columns fit side by side in [maxWidth] at [scale].
  static bool fitsSideBySide({
    required double maxWidth,
    required int count,
    required double minColumnWidth,
    required double scale,
    double spacing = 12,
  }) =>
      maxWidth >=
      count * minColumnWidth * math.max(1.0, scale) + (count - 1) * spacing;

  @override
  Widget build(BuildContext context) {
    final scale = systemTextScale(context);
    return LayoutBuilder(builder: (context, constraints) {
      final sideBySide = fitsSideBySide(
        maxWidth: constraints.maxWidth,
        count: children.length,
        minColumnWidth: minColumnWidth,
        scale: scale,
        spacing: spacing,
      );
      if (sideBySide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: spacing),
              Expanded(child: children[i]),
            ],
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            children[i],
          ],
        ],
      );
    });
  }
}

/// Section title; a screen reader announces it as a heading (and can jump
/// from heading to heading). [trailing] stays beside the title when it fits and
/// moves below it when it does not.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final heading = Semantics(
      header: true,
      container: true,
      // A long Polish title ('Powiadomienia') must shrink instead of breaking inside the word at 3x.
      child: WordFitText(title, style: Theme.of(context).textTheme.titleLarge),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 28, 4, 12),
      child: trailing == null
          ? heading
          : SplitRow(leading: heading, trailing: trailing!, runSpacing: 8),
    );
  }
}

/// Stat card: label, big value, optional sub-line and estimate badge. A screen
/// reader reads it as one phrase: "Data Used, 1.81 MB, Estimated".
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.format,
    this.estimated = false,
    this.accent,
    this.sub,
    this.onTap,
  });

  final String label;
  final double value;
  final String Function(double) format;
  final bool estimated;
  final Color? accent;

  /// Small line under the value ("Measured", "0.0152 kWh").
  final String? sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return WbCard(
      onTap: onTap,
      semanticLabel: joinSpoken([
        label,
        format(value),
        sub,
        if (estimated) context.l10n.estimated,
      ]),
      gradient: accent == null ? null : accentWash(context, accent!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Label(label, dot: accent),
          const SizedBox(height: 10),
          BigNumber(
            value: value,
            format: format,
            estimated: estimated,
            style: theme.textTheme.displayMedium,
          ),
          if (sub != null) ...[
            const SizedBox(height: 6),
            Text(sub!, style: theme.textTheme.labelMedium),
          ],
          if (estimated) ...[
            const SizedBox(height: 10),
            const EstimatedBadge()
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

/// Spinner that a screen reader announces ("Loading").
class WbProgress extends StatelessWidget {
  const WbProgress({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: padding,
          child: CircularProgressIndicator(
              semanticsLabel: context.l10n.a11yLoading),
        ),
      );
}

/// Centered empty-state block. A live region: a screen reader announces it
/// when it appears (data finished loading and there is none, or an error).
class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key,
      required this.title,
      this.body,
      this.icon = Icons.bolt_rounded});

  final String title;
  final String? body;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        liveRegion: true,
        label: joinSpoken([title, body]),
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            children: [
              Icon(icon, size: 40, color: mutedOf(context)),
              const SizedBox(height: 16),
              WordFitText(title,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center),
              if (body != null) ...[
                const SizedBox(height: 8),
                WordFitText(body!,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: mutedOf(context)),
                    textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      );
}

/// An [EmptyState] that fills a bounded area and scrolls when the text (large
/// text size!) is taller than the area. Use it wherever the state is not
/// already inside a scrolling list.
class ScrollableEmptyState extends StatelessWidget {
  const ScrollableEmptyState(
      {super.key,
      required this.title,
      this.body,
      this.icon = Icons.bolt_rounded});

  final String title;
  final String? body;
  final IconData icon;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child:
                Center(child: EmptyState(title: title, body: body, icon: icon)),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Selection
// ---------------------------------------------------------------------------

/// Chips for picking a period. They WRAP onto as many lines as the text size
/// needs (a horizontal scroller hides the last chips at large sizes); each is
/// a button that a screen reader announces with its selected state.
///
/// A chip never breaks a word: when the longest word of a label would be wider
/// than the screen at the system text size (Polish "Poprzedni" at 3.0x on a
/// phone), that one label is drawn at the largest size that still fits.
class ChipRow<T> extends StatelessWidget {
  const ChipRow({
    super.key,
    required this.items,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.tooltip,
  });

  final List<T> items;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  /// What a screen reader adds after the label, when it needs more words.
  final String? Function(T)? tooltip;

  /// Padding of a Material chip around its label (both sides, with the
  /// chip's own padding).
  static const _chipPadding = 36.0;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).chipTheme.labelStyle ??
        Theme.of(context).textTheme.labelLarge;
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final i in items)
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: math.max(
                  1.0,
                  _fittingScale(label(i), style, direction,
                      constraints.maxWidth - _chipPadding)),
              child: ChoiceChip(
                tooltip: tooltip?.call(i),
                // Material draws a chip label on ONE line that fades out at
                // the edge; a long label has to wrap instead.
                label: Builder(builder: (context) {
                  final base = DefaultTextStyle.of(context);
                  return DefaultTextStyle(
                    style: base.style,
                    textAlign: base.textAlign,
                    softWrap: true,
                    maxLines: null,
                    overflow: TextOverflow.visible,
                    child: Text(label(i)),
                  );
                }),
                selected: i == selected,
                onSelected: (_) => onSelected(i),
              ),
            ),
        ],
      ),
    );
  }
}

/// Width of the longest word of [text] in [style] at [scaler].
double longestWordWidth(
    String text, TextStyle? style, TextScaler scaler, TextDirection direction) {
  var widest = 0.0;
  for (final word in text.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final painter = TextPainter(
      text: TextSpan(text: word, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, painter.width);
    painter.dispose();
  }
  return widest;
}

/// The text scale at which the longest word of [text] is exactly [width] wide.
double _fittingScale(
    String text, TextStyle? style, TextDirection direction, double width) {
  final widest = longestWordWidth(text, style, TextScaler.noScaling, direction);
  return widest <= 0 ? double.infinity : width / widest;
}

/// Text that follows the system text size and wraps, but never breaks inside a
/// word: when the longest word would be wider than the line (Polish
/// "przeciągnięciem" at 3x on a phone) it is drawn at the largest size at which
/// that word fits. Everything else is an ordinary [Text].
class WordFitText extends StatelessWidget {
  const WordFitText(this.text, {super.key, this.style, this.textAlign});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final style = this.style ?? DefaultTextStyle.of(context).style;
    final base = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      TextScaler? scaler;
      if (constraints.hasBoundedWidth) {
        final widest = longestWordWidth(text, style, base, direction);
        // Fit as soon as the word would use more than 98% of the line: at an exact fit the glyph advances are
        // not linear and the last letter can still wrap by one pixel.
        if (widest > constraints.maxWidth * 0.98 && widest > 0) {
          final fontSize = style.fontSize ?? 14;
          // 2% to spare: text widths do not scale perfectly linearly.
          final fitted = base.scale(fontSize) *
              (constraints.maxWidth * 0.98) /
              widest /
              fontSize;
          // Never below 75% of the design size; a longer word than that
          // fits nowhere and is the only case left that may break.
          scaler = TextScaler.linear(math.max(0.75, fitted));
        }
      }
      return Text(text, style: style, textAlign: textAlign, textScaler: scaler);
    });
  }
}

/// One option of a [WbSegmented].
class WbSegment<T> {
  const WbSegment(this.value, this.label, {this.tooltip});

  final T value;
  final String label;

  /// What a screen reader adds after the label ("7D" -> "Last 7 Days").
  final String? tooltip;
}

/// A [SegmentedButton] that stays usable at any text size: the segments sit in
/// one row while the widest label fits its share of the width; when it would
/// have to be broken inside a word the options become wrapping chips (a
/// vertical SegmentedButton does not grow with the text: its segments stay
/// 40 px tall and clip a 3x label). Both expose selection to a screen reader
/// and keep a 48 px touch target.
class WbSegmented<T> extends StatelessWidget {
  const WbSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<WbSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Room a segment needs around its label (Material's padding and border).
  static const _padding = 32.0;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .labelLarge
        ?.copyWith(fontWeight: FontWeight.w700);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      var widest = 0.0;
      for (final segment in segments) {
        final painter = TextPainter(
          text: TextSpan(text: segment.label, style: style),
          textDirection: direction,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        widest = math.max(widest, painter.width);
        painter.dispose();
      }
      final fits = widest + _padding <= constraints.maxWidth / segments.length;
      if (!fits) {
        return ChipRow<T>(
          items: [for (final segment in segments) segment.value],
          selected: selected,
          label: (value) =>
              segments.firstWhere((segment) => segment.value == value).label,
          tooltip: (value) =>
              segments.firstWhere((segment) => segment.value == value).tooltip,
          onSelected: onChanged,
        );
      }
      return SegmentedButton<T>(
        segments: [
          for (final segment in segments)
            ButtonSegment<T>(
              value: segment.value,
              label: Text(segment.label),
              tooltip: segment.tooltip,
            ),
        ],
        selected: {selected},
        onSelectionChanged: (s) => onChanged(s.first),
        showSelectedIcon: false,
      );
    });
  }
}

/// The WattByte mark: a bolt over a byte-blue tile.
class WattByteMark extends StatelessWidget {
  const WattByteMark({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: WbColors.byteGradient,
          borderRadius: BorderRadius.circular(size * 0.3),
          boxShadow: [
            BoxShadow(
              color: WbColors.byte.withValues(alpha: 0.35),
              blurRadius: size * 0.4,
              offset: Offset(0, size * 0.15),
            ),
          ],
        ),
        child: CustomPaint(painter: _BoltPainter()),
      );
}

class _BoltPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.56, h * 0.12)
      ..lineTo(w * 0.28, h * 0.56)
      ..lineTo(w * 0.47, h * 0.56)
      ..lineTo(w * 0.42, h * 0.88)
      ..lineTo(w * 0.72, h * 0.44)
      ..lineTo(w * 0.53, h * 0.44)
      ..close();
    canvas.drawPath(path, Paint()..color = WbColors.bolt);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
