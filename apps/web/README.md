# WattByte website (`apps/web`)

The marketing site for https://wattbyte.app: Next.js (App Router), React, TypeScript, Tailwind CSS 4, Geist, Lucide.
No analytics, no tracking cookies, no client-side secrets.

```bash
pnpm --filter @wattbyte/web dev        # http://localhost:3000
pnpm --filter @wattbyte/web lint       # eslint (next/core-web-vitals + the monorepo rules)
pnpm --filter @wattbyte/web typecheck
pnpm --filter @wattbyte/web test       # vitest: config, SEO, Eurostat parsing, launch-list route
pnpm --filter @wattbyte/web build      # next build, then `start`
```

## Where things live

| Path | Holds |
|---|---|
| `src/config/site.ts` | name, URL, support mailbox, store URLs (`null` = "Coming soon"), legal dates |
| `src/config/navigation.ts` | navbar, footer columns, the list of public routes (sitemap + link tests) |
| `src/config/pricing.ts` | the plans; a plan without `price` renders "Pricing announced at launch" |
| `src/config/features.ts` | every product claim shown on the site, with `comingSoon` flags |
| `src/config/faq.ts` | the FAQ |
| `src/config/demo-data.ts` | the numbers in the mockups (labelled as example data everywhere) |
| `src/components/sections/*` | one file per section; pages compose them |
| `src/fonts/` | Latin subsets of Geist Sans / Geist Mono (OFL), loaded with `next/font/local`; see its README |
| `src/lib/electricity-price.ts` | Eurostat `nrg_pc_204` fetch (same query as the API), cached one day, `null` on failure |
| `src/app/api/launch-list/route.ts` | launch-list sign-up, forwarded to `LAUNCH_LIST_WEBHOOK_URL` |

## Environment

See `.env.example`. `NEXT_PUBLIC_SITE_URL` sets canonical/Open Graph URLs (default `https://wattbyte.app`);
`LAUNCH_LIST_WEBHOOK_URL` (+ optional `LAUNCH_LIST_WEBHOOK_TOKEN`) opens the launch list. Unset, the form
reports that the list is closed.

## Content rule

Nothing on the site claims a capability the app, the API or `docs/` does not have. Features that are
planned but not built (custom date ranges, free-form AI questions, WattByte Pro, public API, status page)
are rendered with a "Coming soon" badge from the config files above. Store badges become links only when
`site.stores` holds a URL.

## Lighthouse

Measured on 2026-10-20 with Lighthouse 13.5.0 (headless Chromium, default mobile emulation and
`--preset=desktop`) against `next build` + `next start` on localhost. Target: 95+ in every category.
Scores are Performance / Accessibility / Best Practices / SEO.

| Page | Mobile before | Mobile after | Desktop before | Desktop after |
|---|---|---|---|---|
| `/` | 67¹ / 96 / 100 / 100 | **99** / 100 / 100 / 100 | 100 / 96 / 100 / 100 | 100 / 100 / 100 / 100 |
| `/features` | 95 / 96 / 100 / 100 | **97** / 100 / 100 / 100 | 100 / 96 / 100 / 100 | 100 / 100 / 100 / 100 |
| `/ai` | 98 / 96 / 100 / 100 | **98** / 100 / 100 / 100 | 100 / 96 / 100 / 100 | 100 / 100 / 100 / 100 |
| `/pricing` | 96 / 94 / 100 / 100 | **99** / 100 / 100 / 100 | 100 / 94 / 100 / 100 | 100 / 100 / 100 / 100 |
| `/download` | 99 / 96 / 100 / 100 | **100** / 100 / 100 / 100 | 100 / 96 / 100 / 100 | 100 / 100 / 100 / 100 |

¹ First run of the session (cold browser and server): TBT 770 ms. Three warm re-runs of the same build
scored 93 with TBT 10–20 ms and LCP 3.2 s, so the real "before" for `/` on mobile is 93.

What was blocking the targets, and what changed:

- **Largest Contentful Paint on `/` (3.2 s → 2.1 s mobile).** The hero headline faded in from
  `opacity: 0`, and Chrome never reports an element whose first paint had opacity 0 as an LCP
  candidate, so the LCP fell to the first counter whose text changed after hydration. The headline and
  lead paragraph now use `.rise-solid` (same slide, no fade) and are the LCP at first paint.
- **LCP on every page (2.3–2.9 s → 1.8–2.6 s mobile).** Both Geist variable fonts (70 KB each, full
  character set) were preloaded on every page, which put 140 KB on the simulated critical path. The
  fonts are now Latin subsets (37 KB each, `src/fonts/`) and only Geist Sans is preloaded.
- **Accessibility 94–96 → 100.** `--fg-subtle` (#6b6b75 dark, #71717a light) gave 3.6–4.0:1 against
  the page backgrounds; it is now #85858f / #65656e (≥ 4.75:1 on every surface, WCAG AA). On
  `/pricing` the plan names were `<h3>` under the page `<h1>`; the Pricing section renders them as
  `<h2>` when it has no section heading of its own.

Mobile LCP is now bounded by the HTML document itself (31 KB gzipped on `/`) and React/Next runtime on
the simulated slow-4G link; nothing on the page is render-blocking except the 8 KB stylesheet.

To re-measure (the build and server need a port, so run them outside any sandbox):

```bash
pnpm --filter @wattbyte/web build && pnpm --filter @wattbyte/web start
```

```bash
CHROME_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" npx lighthouse http://localhost:3000/ --preset=desktop --output=html --output-path=./lighthouse-home-desktop.html
```

Drop `--preset=desktop` for the mobile run. Any Chromium build works as `CHROME_PATH`.

## Deployment (Vercel, https://wattbyte.app)

The site deploys as one Vercel project rooted at `apps/web`; `vercel.json` in this directory holds the
commands, so the dashboard only needs the settings below.

1. **Create the project** from the GitHub repository (Vercel → Add New → Project → import `wattbyte`).
2. **Project Settings → General**
   - Root Directory: `apps/web` (tick "Include source files outside of the Root Directory in the
     Build Step" so the workspace lockfile and `pnpm-workspace.yaml` are available).
   - Framework Preset: Next.js (also pinned in `vercel.json`).
   - Node.js Version: 22.x (also pinned by `engines.node` in `package.json`, which Vercel reads; on a
     machine with a newer Node, `pnpm install` prints an "Unsupported engine" warning for `apps/web`
     and carries on, since the workspace does not set `engine-strict`).
   - Install Command: `pnpm install --frozen-lockfile`; Build Command: `pnpm --filter @wattbyte/web build`
     (both from `vercel.json`; Vercel reads `packageManager` from the repository root to pick pnpm 11).
   - Ignored Build Step comes from `vercel.json`: a commit that touches neither `apps/web` nor the
     workspace lockfile is not built.
3. **Environment variables** (Settings → Environment Variables; the names and meanings are in
   `.env.example`):

   | Variable | Production | Preview |
   |---|---|---|
   | `NEXT_PUBLIC_SITE_URL` | `https://wattbyte.app` | leave unset (falls back to `https://wattbyte.app`, which keeps canonical URLs pointing at production) |
   | `LAUNCH_LIST_WEBHOOK_URL` | the HTTPS endpoint that stores sign-ups | unset, or a test endpoint; unset means the form reports the list as closed |
   | `LAUNCH_LIST_WEBHOOK_TOKEN` | the bearer token for that endpoint (mark as Sensitive) | unset |

4. **Domain**: Settings → Domains → add `wattbyte.app` and `www.wattbyte.app` (redirect `www` to the
   apex). At the DNS provider: apex `A` record to Vercel's address (`76.76.21.21` at the time of
   writing; the Domains page shows the current one) and `www` `CNAME` to `cname.vercel-dns.com`.
   Vercel issues the TLS certificate once the records resolve.
5. **Branches**: `main` deploys to production; every pull request gets a preview URL. Nothing is
   deployed from this repository's GitHub Actions: `.github/workflows/ci.yml` (`node` job) already
   lints, typechecks, tests and builds `apps/web` through `pnpm -r`, and Vercel builds independently
   from the same commit.

After the first production deploy, check `https://wattbyte.app/robots.txt`, `/sitemap.xml` and the
security headers from `next.config.ts` (`curl -I https://wattbyte.app`), and re-run the Lighthouse
audit above against the live site.
