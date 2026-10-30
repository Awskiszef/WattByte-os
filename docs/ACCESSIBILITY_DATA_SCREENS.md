# Accessibility and text size of the data screens

Scope: Dashboard, History (+ session sheet), Insights (+ AI card), Statistics, Data by app, the bottom navigation bar and
the shared widgets (`lib/ui/widgets`, `lib/ui/theme.dart`). The onboarding, account and settings screens have their own
building blocks (`lib/ui/settings/flow_widgets.dart`). Statuses follow `docs/VERIFICATION_STATUS.md`: everything below is
IMPLEMENTED and TESTED with widget tests (`apps/mobile/test/accessibility`); nothing is SIMULATOR VERIFIED or DEVICE
VERIFIED by this document, and no screen reader (VoiceOver, TalkBack) was run.

## Text size policy

| What | Policy |
|---|---|
| App | `lib/app.dart` honours the system text scale in full: iOS accessibility sizes up to ~3.1x, Android 2.0x. The old `maxScaleFactor: 1.35` is gone. The only bound is the lower one: text is never drawn smaller than the design size (`minScaleFactor: 1`). |
| Bottom `NavigationBar` | Flutter's own cap applies: labels follow the system size up to **1.3x** (`_kMaxLabelTextScaleFactor`), so the bar keeps its height and four labels stay side by side ("Ustawienia" at 3x would be 190 px). All four labels stay visible and uncut. The full size is available to a screen reader (label, "Tab n of 4", selected) and in the long-press tooltip. Every destination is a 94 x 68 px target on an iPhone SE. |
| `AppBar` title (Statistics, Data by app) | Flutter's own cap applies: **1.34x** (the toolbar has a fixed height). |
| Chart touch tooltip | fl_chart paints it without a text scaler; its sizes are scaled by hand, capped at **1.6x** (it sits inside the chart). |
| Chart axis labels | Follow the system size. Only every n-th label is drawn when they would touch, the newest day always; the strip under the bars grows with them. |
| A single big number (`BigNumber`, the Mobile / Wi-Fi values of the hero card) | The only use of `FittedBox(scaleDown)`. A number is never cut or wrapped: it shrinks to its line. The layouts give it room first (see below); the tests assert it is never drawn below **75%** of the size its style asks for at 1.0x. |
| A word that is wider than its line | `WordFitText` draws it at the largest size at which the word fits (never below 75% of the design size), instead of breaking it in the middle (Polish "przeciągnięciem" at 3x). Used for empty/error states, insight sentences, AI text and app names. `ChipRow` does the same per chip. |

## Layout rules (what the tests enforce)

* No `RenderFlex` overflow, no text cut off (ellipsis / `maxLines`), no word broken in the middle, no tappable node off
  screen or on top of another one, at text scales 1.0 / 1.35 / 1.6 / 2.0 / 3.0 on iPhone SE (375x667) and iPhone 17 Pro
  (402x874), light and dark, English and Polish, for every kind of data (seeded, new install, charging now, Android with
  Data by app, without usage access, no price, unknown battery capacity, empty, loading, error) and with Bold Text.
* Wide screens (874x402 landscape and 820x1180 tablet, scales 1.0 and 2.0) must not overflow or throw: Android 16
  ignores the portrait lock on large screens (`docs/PLATFORM_SUPPORT.md`). They are not designed, only safe.
* Building blocks (`lib/ui/widgets/wb_widgets.dart`):
  * `SplitRow(leading, trailing)`: value at the far end when both fit, below the label when they do not (instead of
    squeezing the label to one letter per line). Replaces `Row(children: [Expanded(label), value])`.
  * `AdaptiveColumns`: equal columns while each has `minColumnWidth` px at 1.0x (the need grows with the text scale),
    a stack of full-width cards otherwise. Energy/Cost, Mobile/Wi-Fi and the link cards use it.
  * `WbSegmented`: a `SegmentedButton` while the widest label fits its share, wrapping chips otherwise (a vertical
    `SegmentedButton` keeps 40 px high segments and clips a 3x label).
  * `ChipRow`: wraps (a horizontal scroller hid the last chips); labels wrap instead of fading out.
  * `Label`: wraps, dot stays on the first line. `SectionHeader`: trailing control drops below the title.
  * `ScrollableEmptyState`: an empty/error state that scrolls when the text is taller than the area.
  * The session sheet scrolls (`isScrollControlled`, `SingleChildScrollView`).

## Semantics (screen readers)

* A stat card, the hero card, a list row, an app row, an insight, a record, a period row is **one node** whose label is
  built from the visible facts: `Data Used, 983.4 MB, Estimated, Mobile ..., Wi-Fi ...`. The animated number and the
  "Estimated" badge are not nodes of their own; the "~" is dropped from the spoken text (it is read as "tilde") and
  "Estimated" is said instead. Cards that open something are buttons.
* A chart is one image node: what, period, total, highest and lowest day, "Estimated". Its painted children (axis
  labels) are excluded. An empty chart says there is no data.
* Section titles and screen titles are headers. The 7D/30D selector and the period chips expose "selected"; "7D" has
  the tooltip "Last 7 Days". Icon-only buttons have tooltips. Loading indicators say "Loading". Empty and error states
  are live regions (announced when they appear), as are the AI answer and the AI error.
* A loose `Text` next to cards gets its own node (`Semantics(container: true)`); otherwise it would be merged into the
  node of the whole list item.
* Reduced motion: the count-up of the numbers and the chart animation are skipped.

## Contrast and theme

`WbColors.lightMuted` (6.1:1 on a card, 5.6:1 on the page), error text (`lightError` / `darkError`), accent-coloured text
(`lightAccentText`), control outlines (`lightOutline` / `darkOutline`) and the series colours (`WbSeries`: chart bars,
legend dots, icons; at least 3:1 on the card in both themes) were chosen to pass WCAG AA. The accent wash behind hero
cards used a translucent first gradient stop, which a gradient interpolates at full colour strength: the corner was two
to three times stronger than the intended 16% and muted text fell to 3.7:1 in dark mode; the first stop is now the
blended colour.

`flutter_test`'s `textContrastGuideline` guesses the two colours from a pixel histogram and reports a false 1.4:1 for
small text on a gradient card. The tests therefore also use `contrastProblems` (`test/accessibility/shared_widgets_checks.dart`),
which computes the text colour against the decorations behind it (gradients evaluated at the text), and run the pixel
guideline only where it agrees (Dashboard, History, Statistics, Data by app).

## Running the tests

    cd apps/mobile
    flutter test test/accessibility

The harness (`test/support/app_harness.dart`) loads Roboto instead of the 1em-square Ahem font; iOS' SF Pro is a few
percent wider, so a margin below ~5% is a coin flip. Material icons render as boxes in tests. A mutation check was done:
putting `maxScaleFactor: 1.35` back into `lib/app.dart` fails `app_text_scale_test.dart`.
