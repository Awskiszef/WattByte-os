# Logo with name

Status: **derived, provisional**, like the launcher icons in `apps/mobile/assets/branding/README.md`. No designer has approved a final logo.

Use: the name "WattByte" and these logo files are marks of the copyright holder and are **not** licensed with the source code. The Apache License
does not grant permission to use them (section 6, see `NOTICE` and the trademark paragraph of the README); a fork uses its own name and artwork.

Two horizontal lockups, each for a light and a dark background (SVG, and a transparent 4x PNG):

| Files | Mark | Text |
|---|---|---|
| `wattbyte-logo-web.svg` / `.png` | website: black square, white bolt | `#0A0A0A` |
| `wattbyte-logo-web-on-dark.svg` / `.png` | website, dark theme: light square, black bolt | `#F4F4F5` |
| `wattbyte-logo-app.svg` / `.png` | mobile app: blue gradient square, yellow bolt | `#0F1115` |
| `wattbyte-logo-app-on-dark.svg` / `.png` | mobile app, for dark backgrounds | `#F3F4F6` |

* **web** copies `LogoMark` and `Logo` from `apps/web/src/components/layout/logo.tsx` (same mark, 24 px mark : 17 px text : 10 px gap) with the `--fg` / `--bg` tokens of `apps/web/src/app/globals.css`. The favicon (`apps/web/src/app/icon.svg`) is the same shape with an amber bolt.
* **app** copies `WattByteMark` from `apps/mobile/lib/ui/widgets/wb_widgets.dart` with the colours of `WbColors`, flat, without the in-app drop shadow.
* The name is Geist SemiBold with -0.02 em tracking, converted to outlines, so the SVGs need no font.

## Regenerate

From the repo root, after `pnpm install`:

```bash
node docs/brand/tool/build.mjs
```

`tool/outline.mjs` is a small TrueType outliner (no kerning) used to turn the text into paths; `tool/build.mjs` writes the eight files.
