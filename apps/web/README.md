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
