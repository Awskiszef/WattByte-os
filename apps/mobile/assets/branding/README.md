# Branding assets

Status: **IMPLEMENTED (derived, provisional)**. The launcher icons and launch screens are derived from the mark the app already
draws, `WattByteMark` in `lib/ui/widgets/wb_widgets.dart` (blue gradient rounded square, yellow bolt) with the colours of `WbColors`
in `lib/ui/theme.dart`. They are **not** a final brand asset: no designer has created or approved a logo. The owner has to supply or
approve the final artwork before a store release. Nothing here invents a new logo; if the in-app mark changes, regenerate.

## What is generated, and from what

`tool/generate_brand_assets.sh` (from `apps/mobile`, needs the Flutter SDK) renders every file below with `dart:ui` from the same
gradient and the same six bolt points the app uses. `tool/generate_brand_assets.sh --check` fails when a committed file differs
from the renderer, or when the numbers copied into `tool/brand/brand_assets.dart` no longer match `theme.dart` / `wb_widgets.dart`
(it greps both). The renderer lives in `tool/brand/`.

| Output | Used for |
|---|---|
| `assets/branding/icon.png` (1024, RGB, **no alpha**) | master / App Store marketing icon |
| `assets/branding/icon_foreground.png`, `icon_background.png`, `icon_monochrome.png` (1024) | store listings, other tools; the same layers as the Android vectors |
| `assets/branding/launch_logo.png` (720 = 240 pt @3x) | master of the iOS launch logo |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset` | iPhone icons 20/29/40/60 pt @2x @3x + the 1024 marketing icon, all opaque, full-bleed |
| `ios/Runner/Assets.xcassets/LaunchLogo.imageset`, `LaunchBackground.colorset` | iOS launch screen (`Base.lproj/LaunchScreen.storyboard`) |
| `android/app/src/main/res/drawable/ic_launcher_{foreground,background,monochrome}.xml` | adaptive icon layers (vector) |
| `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher{,_round}.xml` | adaptive icon, with the monochrome layer for themed icons (Android 13+) |
| `android/app/src/main/res/mipmap-*dpi/ic_launcher{,_round}.png` | legacy bitmaps for all five densities (also the notification fallback icon) |
| `android/app/src/main/res/drawable/{splash_icon,launch_logo}.xml` | Android 12+ splash icon and the pre-12 launch window |

Hand-written files that use them: `LaunchScreen.storyboard`, `values{,-night}/colors.xml` (`launch_background`),
`values{,-night}/styles.xml`, `values-v31/styles.xml`, `values-night-v31/styles.xml`, `drawable/launch_background.xml`.

## Design decisions

* **iOS**: the icon is the full-bleed gradient square with the bolt; the OS applies its own mask, so no corners are pre-rounded and
  the marketing icon has no alpha channel (verified: `actool` reports every `AppIcon` image as opaque). iPad sizes are absent
  because v1 is iPhone only (`docs/PLATFORM_SUPPORT.md`). iOS 18 dark and tinted variants are the system's rendering of this one
  icon; no custom variants are shipped.
* **Android**: the 108 dp adaptive canvas shows 72 dp through any launcher mask. The mark is laid out inside that 72 dp window, so
  the bolt keeps the in-app proportions and stays inside the 66 dp safe zone. The gradient spans the visible window. The monochrome
  layer is the bolt alone.
* **Launch screens** show the mark at 96 dp / pt, the size of the in-app splash (`lib/app.dart`), on the theme's page background
  (`WbColors.lightBg` / `darkBg`, light and dark) with the same drop shadow, so the hand-over to Flutter does not jump.
  Android 12+ uses the system splash (background colour + `splash_icon`, 132 dp mark inside the 192 dp circle).
* The in-app mark's drop shadow is not part of any launcher icon.

## Verification actually run

`tool/generate_brand_assets.sh --check` passes; `xcrun actool` compiles the catalog without warnings and `assetutil` lists nine
`AppIcon` images all `Opaque: true`, the `LaunchBackground` colour with its dark appearance and `LaunchLogo` @1x/@2x/@3x;
`xcrun ibtool` compiles `LaunchScreen.storyboard` without warnings; the Android resources compile in `flutter build apk --debug`
(aapt2). The PNGs were opened and looked at. **Not done**: a real launcher (iOS home screen, Android adaptive masks, themed icon),
the iOS 27 simulator, and App Store Connect / Play Console icon validation.

## Before a store release

Supply or approve the final artwork (a designer's mark; replace the constants in `tool/brand/brand_assets.dart` or the generated
files), then also prepare what the stores need and this repo does not contain: screenshots, the Play feature graphic (1024x500) and
the Play 512x512 icon (`icon.png` downscaled is fine for a draft).
