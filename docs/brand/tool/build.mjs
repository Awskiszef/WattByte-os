// Regenerates the logo files in docs/brand/ (run from the repo root after `pnpm install`):
//   node docs/brand/tool/build.mjs
// Text is converted to outlines from the Geist SemiBold TTF in the `geist` package; PNGs are rendered with `sharp`.
import { mkdirSync, readdirSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadFont, textPath } from './outline.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const OUT = join(ROOT, 'docs', 'brand');
const store = join(ROOT, 'node_modules', '.pnpm');
const pkg = (prefix) => {
  const d = readdirSync(store).find((n) => n.startsWith(prefix));
  if (!d) throw new Error(`${prefix} not found in node_modules/.pnpm; run pnpm install`);
  return join(store, d, 'node_modules');
};
const font = loadFont(join(pkg('geist@'), 'geist', 'dist', 'fonts', 'geist-sans', 'Geist-SemiBold.ttf'));
const sharp = createRequire(import.meta.url)(join(pkg('sharp@'), 'sharp'));

const PAD = 8;
const f = (n) => +n.toFixed(2);

function lockup({ M, size, gap, mark, textColor }) {
  const capH = Math.max(...font.glyph(font.cmap(87)).flat().map((p) => p.y)) * (size / font.upem); // 'W'
  const baseline = PAD + M / 2 + capH / 2;
  const t = textPath(font, 'WattByte', size, PAD + M + gap, baseline, -0.02);
  const W = Math.ceil(PAD * 2 + M + gap + t.width);
  const H = PAD * 2 + M;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-label="WattByte">
${mark}  <path d="${t.d}" fill="${textColor}"/>
</svg>
`;
}

// App mark: WattByteMark in apps/mobile/lib/ui/widgets/wb_widgets.dart, colours of WbColors (flat, no drop shadow).
const appMark = (() => {
  const M = 96;
  const bolt = [[0.56, 0.12], [0.28, 0.56], [0.47, 0.56], [0.42, 0.88], [0.72, 0.44], [0.53, 0.44]]
    .map(([x, y]) => `${f(x * M)} ${f(y * M)}`).join('L');
  return `  <defs>
    <linearGradient id="byte" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#67D2FF"/>
      <stop offset="1" stop-color="#2A9DF4"/>
    </linearGradient>
  </defs>
  <g transform="translate(${PAD} ${PAD})">
    <rect width="${M}" height="${M}" rx="${M * 0.3}" fill="url(#byte)"/>
    <path d="M${bolt}Z" fill="#FFC53D"/>
  </g>
`;
})();

// Web mark: LogoMark in apps/web/src/components/layout/logo.tsx (32-unit viewBox shown at 24px, text 17px, gap 10px),
// theme tokens --fg / --bg of apps/web/src/app/globals.css. Everything is scaled x4 so the proportions are the site's.
const webMark = (fg, bg) => `  <g transform="translate(${PAD} ${PAD}) scale(3)">
    <rect x="2" y="2" width="28" height="28" rx="8" fill="${fg}"/>
    <path d="M18.5 6.5 10 18h5.2l-1.7 7.5L22 13h-5.3z" fill="${bg}"/>
  </g>
`;

const files = {
  'wattbyte-logo-app': lockup({ M: 96, size: 78, gap: 26, mark: appMark, textColor: '#0F1115' }),
  'wattbyte-logo-app-on-dark': lockup({ M: 96, size: 78, gap: 26, mark: appMark, textColor: '#F3F4F6' }),
  'wattbyte-logo-web': lockup({ M: 96, size: 68, gap: 40, mark: webMark('#0A0A0A', '#FFFFFF'), textColor: '#0A0A0A' }),
  'wattbyte-logo-web-on-dark': lockup({ M: 96, size: 68, gap: 40, mark: webMark('#F4F4F5', '#000000'), textColor: '#F4F4F5' }),
};

mkdirSync(OUT, { recursive: true });
for (const [name, svg] of Object.entries(files)) {
  writeFileSync(join(OUT, `${name}.svg`), svg);
  const w = Number(/viewBox="0 0 (\d+)/.exec(svg)[1]);
  await sharp(Buffer.from(svg), { density: 288 }).resize({ width: w * 4 }).png().toFile(join(OUT, `${name}.png`));
}
console.log(Object.keys(files).join('\n'));
