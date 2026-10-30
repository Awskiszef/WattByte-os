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
| `src/config/operator.ts` | the business that operates the site (name, tax and registry ids, postal address) and the person named on /about. The legal pages print it. In the public repository every value is a placeholder: replace them before you deploy |
| `src/config/navigation.ts` | navbar, footer columns, the list of public routes (sitemap + link tests) |
| `src/config/pricing.ts` | the plans; a plan without `price` renders "Pricing announced at launch" |
| `src/config/features.ts` | every product claim shown on the site, with `comingSoon` flags |
| `src/config/faq.ts` | the FAQ |
| `src/config/demo-data.ts` | the numbers in the mockups (labelled as example data everywhere) |
| `src/components/sections/*` | one file per section; pages compose them |
| `src/fonts/` | Latin subsets of Geist Sans / Geist Mono (OFL), loaded with `next/font/local`; see its README |
| `src/lib/electricity-price.ts` | Eurostat `nrg_pc_204` fetch (same query as the API), cached one day, `null` on failure |
| `src/app/api/launch-list/route.ts` | launch-list sign-up, forwarded to `LAUNCH_LIST_WEBHOOK_URL` |
| `src/lib/campaign.ts` | the `utm_*` campaign tag of a sign-up (read on landing, kept in session storage, validated by the route) |
| `integrations/launch-list-sheet.gs` | the Google Apps Script that receives the launch list into a Google Sheet (see below) |

## Environment

See `.env.example`. `NEXT_PUBLIC_SITE_URL` sets canonical/Open Graph URLs (default `https://wattbyte.app`);
`LAUNCH_LIST_WEBHOOK_URL` (+ optional `LAUNCH_LIST_WEBHOOK_TOKEN`) opens the launch list. Unset, the form
reports that the list is closed.

## Campaign tags

To see which ad brought a sign-up, tag the ad's link, for example
`https://wattbyte.app/download?utm_source=tiktok&utm_medium=paid&utm_campaign=launch-test&utm_content=hook-a`.
The tag of the page the visitor lands on is kept in session storage for that tab (no cookie, no third party) and is
sent with the launch-list form as `utm_source`, `utm_medium`, `utm_campaign` and `utm_content`. The route forwards a
tag only if it is at most 100 characters of letters, digits, space, `.`, `_` and `-` (starting with a letter or
digit) and silently drops it otherwise; the sign-up itself never fails because of a tag. A later landing through
another tagged link replaces the tag; untagged pages keep it.

## Launch-list receiver (Google Sheet)

Production sends sign-ups to a private Google Sheet through `integrations/launch-list-sheet.gs`, one row per
sign-up with the columns `at, email, platform, source, utm_source, utm_medium, utm_campaign, utm_content`.

1. Create the spreadsheet in the Google account that should own the list, then Extensions → Apps Script and
   replace `Code.gs` with `integrations/launch-list-sheet.gs`.
2. Project Settings → Script properties: add `KEY` with a long random value (`openssl rand -hex 24`).
3. Deploy → New deployment → Web app, Execute as: Me, Who has access: Anyone; authorize, copy the URL ending
   in `/exec`. After a later script edit, Manage deployments → Edit → New version keeps the same URL.
4. `pnpm --filter @wattbyte/web exec wrangler secret put LAUNCH_LIST_WEBHOOK_URL` and paste
   `<web app URL>?key=<KEY>`. Leave `LAUNCH_LIST_WEBHOOK_TOKEN` unset: Apps Script cannot read request headers,
   so the key travels in the URL, which stays inside the Worker secret. The secret applies without a redeploy.
5. Sign up once through `https://wattbyte.app/download?utm_source=test&utm_campaign=setup` and check that the
   row arrives with its tags, then delete it. The script answers 200 even to a wrong key, so a missing row is
   the only sign of a bad `KEY` or URL.

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

`/contact` and `/privacy`, measured the same day after the company details were added, score 100 in every
category on mobile and desktop.

`/about` (added 2026-10-20): mobile 98–99 / 100 / 100 / 100 across three warm runs (LCP 2.0–2.5 s, TBT 10 ms,
CLS 0), desktop 100 / 100 / 100 / 100. Its first run scored 92 on Accessibility because the mission and
building cards wrapped each `<li>` in the reveal `<div>`; the reveal now lives inside the `<li>`.

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

## Deployment (Cloudflare Workers, https://wattbyte.app)

The site runs as the Cloudflare Worker `wattbyte-web`, built with the
[OpenNext Cloudflare adapter](https://opennext.js.org/cloudflare) from the normal `next build` output
(`open-next.config.ts`, `wrangler.jsonc`; in the public repository copy `wrangler.example.jsonc` to the git-ignored `wrangler.jsonc` first and put your own hostnames and KV id in it). Static files are served by Workers Static Assets; the home
page is ISR (the Eurostat price is fetched with `revalidate: 86400`), so prerendered pages and the fetch
cache live in the Workers KV namespace `wattbyte-web-cache` (binding `NEXT_INC_CACHE_KV`).

```bash
pnpm --filter @wattbyte/web run preview   # OpenNext build + wrangler dev on http://localhost:8787 (Workers runtime)
```

```bash
pnpm --filter @wattbyte/web run deploy    # OpenNext build + upload + KV cache population (`run` matters: `pnpm deploy` is pnpm's own command)
```

Both need a port, so run them outside any sandbox. `deploy` needs a logged-in Wrangler
(`npx wrangler login`, or `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` in the environment with the
"Edit Cloudflare Workers" template plus Workers KV write and DNS edit for the zone).

### What `wrangler.jsonc` sets

| Key | Value | Why |
|---|---|---|
| `routes` | `wattbyte.app`, `www.wattbyte.app` as custom domains | Cloudflare creates the DNS records and the certificate itself; the zone `wattbyte.app` must be in the same account. `next.config.ts` redirects `www.` to the apex with 308. |
| `workers_dev` | `false` | no `*.workers.dev` hostname for the production Worker |
| `compatibility_flags` | `nodejs_compat` | required by OpenNext (and by the `runtime = 'nodejs'` route handler) |
| `kv_namespaces` | `NEXT_INC_CACHE_KV` → your namespace | ISR and `fetch` cache. The committed id is a placeholder: run `npx wrangler kv namespace create wattbyte-web-cache` once and put the id it prints into `wrangler.jsonc` (keep that edit out of commits to a public fork) |
| `services` | `WORKER_SELF_REFERENCE` → `wattbyte-web` | the revalidation queue calls the Worker back |
| `vars` | `NEXT_PUBLIC_SITE_URL=https://wattbyte.app` | canonical URLs, sitemap, Open Graph |

### Secrets

The launch list is closed until these exist (names and meanings in `.env.example`):

```bash
npx wrangler secret put LAUNCH_LIST_WEBHOOK_URL
```

```bash
npx wrangler secret put LAUNCH_LIST_WEBHOOK_TOKEN
```

Set them in the Cloudflare dashboard (Workers & Pages → wattbyte-web → Settings → Variables and Secrets)
or with the commands above from this directory. Never put them in `vars`.

`public/_headers` gives the content-hashed files under `/_next/static/` a one-year immutable cache; it applies
because those requests are answered by the asset layer, not by the Worker code. Plain-HTTP requests and the
`www.` host are 308-redirected to `https://wattbyte.app` by `next.config.ts`.

The first deploy creates both custom domains and populates the KV cache with the prerendered pages. Note that
`opennextjs-cloudflare deploy` on its own uploads the existing `.open-next/` build; always run the `deploy`
package script with `pnpm run deploy` (build + deploy) after a code change.

### Checklist after a deploy

1. `curl -I https://wattbyte.app` answers 200 with the headers from `next.config.ts`; `http://wattbyte.app/` and
   `https://www.wattbyte.app/` answer 308 to the apex; `/_next/static/...` files carry `max-age=31536000, immutable`.
2. `/robots.txt`, `/sitemap.xml`, `/opengraph-image` and `/api/launch-list` (POST) work.
3. Re-run the Lighthouse audit above against the live site.

### Continuous deployment (optional)

Connect the repository to the Worker under Workers & Pages → wattbyte-web → Settings → Build: root directory
`apps/web`, build command `pnpm --filter @wattbyte/web exec opennextjs-cloudflare build`, deploy command
`npx wrangler deploy`, non-production branches as previews. Nothing in `.github/workflows/ci.yml` deploys;
its `node` job lints, typechecks, tests and builds `apps/web` through `pnpm -r` on every push.
