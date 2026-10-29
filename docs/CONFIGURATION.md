# Configuration

Everything the API reads from its environment (`apps/api/src/config/env.ts` is the source of
truth; `apps/api/.env.example` is a template). The server validates the environment at boot and
**refuses to start** with a readable list of what is wrong; it never prints a secret value.

Empty variables count as unset. Switches are spelled `0` / `1` (anything else is an error, so a
typo cannot silently turn a feature on or off).

## Environments

`APP_ENV` says which deployment this is: `development`, `staging` or `production`. When it is not
set it is derived from `NODE_ENV` (`production` -> `production`, `development` / `test` -> `development`),
so existing production setups keep their guards without a change.

**At least one of `NODE_ENV` and `APP_ENV` must be set.** A process started with neither is refused
at boot (`NODE_ENV: not set`) instead of being treated as development: a deployment that forgot the
variable would otherwise run with every staging/production guard skipped. Local work asks for the
development profile explicitly (`NODE_ENV=development`; `pnpm --filter @wattbyte/api dev` does it).

| Rule | development | staging | production |
|---|---|---|---|
| `NODE_ENV` | any | must be `production` | must be `production` |
| `JWT_SECRET` at least 32 characters | yes | yes | yes |
| `JWT_SECRET` is not a placeholder (`change-me`, `example`, `placeholder`, `test-secret`, ...) | – | **refused** | **refused** |
| `JWT_SECRET` has at least 10 distinct characters (no `aaaa...`, no repeated pattern) | – | **refused** | **refused** |
| `AI_MOCK=1` | allowed | **refused** | **refused** |
| `DATABASE_URL` | needed to start the server, not validated at load | **required** | **required** |
| `DATABASE_URL` is not the docker-compose credentials (`wattbyte:wattbyte`) | – | **refused** | **refused** |
| `DATABASE_SSL` set explicitly | – | default `0` + warning | **required** (`1` = TLS with certificate verification, `0` = a conscious "private link" choice, logged as a warning) |
| `TRUST_PROXY_HOPS` set explicitly | – | **required** (`0` = deliberately no proxy, logged as a warning) | **required** (same) |
| `ACCESS_TOKEN_TTL_SEC` above one hour | – | warning | warning |

Why staging is held to the production bar: a staging that accepts a placeholder secret or the mock
AI provider hides exactly the mistakes production must not make. Why `DATABASE_SSL` is *required*
in production and only warned about in staging: the default (`0`) would silently send credentials
and data in clear, so production forces the operator to decide; `0` stays legal because private
links, sidecar proxies and unix sockets are common. Contradictions are refused too:
`NODE_ENV=production` with `APP_ENV=development` would switch the production guards off, and
`APP_ENV=staging|production` with another `NODE_ENV` is rejected for the same reason.

Warnings are logged once at boot (`envWarnings`), they do not stop the server.

## Variables

| Variable | Default | Meaning |
|---|---|---|
| `NODE_ENV` | none (required unless `APP_ENV` is set) | `development`, `test` or `production`. `test` turns logging off unless a test asks for it. Unset is refused, not treated as development. |
| `APP_ENV` | derived | `development` / `staging` / `production`, see above. Reported by `GET /api/v1/config`. |
| `PORT` | `8080` | Listen port. |
| `HOST` | `0.0.0.0` | Listen address. Use `127.0.0.1` for local runs. |
| `LOG_LEVEL` | `info` | `fatal` `error` `warn` `info` `debug` `trace` `silent`. |
| `DATABASE_URL` | – | PostgreSQL connection string. |
| `DATABASE_SSL` | `0` | `1` = TLS with `rejectUnauthorized: true`. |
| `READY_DB_TIMEOUT_MS` | `2000` | How long `GET /ready` waits for `SELECT 1` (100 to 30000). |
| `REQUEST_TIMEOUT_MS` | `30000` | A client must deliver a whole request (headers + body) within this time, otherwise the connection is closed (slow-body / slowloris protection). |
| `KEEP_ALIVE_TIMEOUT_MS` | `65000` | Idle keep-alive connections close after this; set it just above the load balancer's idle timeout. |
| `MAX_CONNECTIONS` | `5000` | Open connections accepted at once (0 = no limit). |
| `MAX_REQUESTS_PER_SOCKET` | `1000` | Requests served on one connection before it is recycled (0 = no limit). |
| `SHUTDOWN_DRAIN_MS` | `3000` | On SIGTERM `/ready` answers 503 at once and responses carry `Connection: close`; the process waits this long before it stops accepting connections. |
| `SHUTDOWN_TIMEOUT_MS` | `25000` | Hard deadline of the whole shutdown (then remaining connections are cut and the exit code is 1). Keep it below the orchestrator's grace period. |

Request bodies are limited to 16 KiB (`POST /usage/sync`: 64 KiB), arrays in a body to 1000 elements.
| `JWT_SECRET` | – (required) | HS256 signing key for access tokens, 32+ characters: `openssl rand -base64 48`. |
| `ACCESS_TOKEN_TTL_SEC` | `900` | Access token lifetime. |
| `REFRESH_TOKEN_TTL_DAYS` | `30` | Refresh token lifetime. |
| `REFRESH_REUSE_GRACE_SEC` | `10` | A rotated refresh token presented again **less than** this many seconds after its rotation is a retry (rejected, nothing else touched); **at or after** it, it is theft and every session of the user is revoked. `0` disables the retry window. See `docs/security.md`. |
| `TRUST_PROXY_HOPS` | `0` (development only; **must be set in staging/production**) | Number of reverse proxies in front of the API. `0` ignores `X-Forwarded-For` (clients cannot spoof their IP); behind a proxy set it, or every client shares the proxy's rate-limit bucket. `/health` and `/ready` are exempt from the per-IP limiter. |
| `RATE_LIMIT_PER_MIN` | `120` | Per IP, all routes (unknown paths included). |
| `AUTH_RATE_LIMIT_PER_MIN` | `10` | Per IP, per credential route (register, login, refresh, social sign-in). |
| `AI_RATE_LIMIT_PER_MIN` | `20` | Per IP, per AI route. |
| `AI_FREE_DAILY_LIMIT` | `3` | AI generations per UTC day on the free plan. Published to the app in `GET /api/v1/config`. |
| `AI_PREMIUM_DAILY_LIMIT` | `50` | Same, premium plan. |
| `AI_MOCK` | `0` | `1` = deterministic mock providers, no keys needed. Development only. |
| `OPENAI_API_KEY` `ANTHROPIC_API_KEY` `GOOGLE_AI_API_KEY` `XAI_API_KEY` | – | Provider keys; an unset provider is skipped. Server side only. |
| `OPENAI_FAST_MODEL` `OPENAI_QUALITY_MODEL` `ANTHROPIC_FAST_MODEL` `ANTHROPIC_QUALITY_MODEL` `GEMINI_FAST_MODEL` `GEMINI_QUALITY_MODEL` `XAI_FAST_MODEL` `XAI_QUALITY_MODEL` | – | Model names (insight and roast use `*_FAST_MODEL`, summaries `*_QUALITY_MODEL`; each falls back to the other); a key needs at least one. No model is hardcoded. |
| `AI_DEFAULT_PROVIDER` | unset | `openai`, `anthropic`, `google` or `xai`: tried first for every AI task. It needs its key (boot error otherwise). Unset: each task keeps its own routing order (`docs/ai.md`). |
| `AI_REQUEST_TIMEOUT_MS` | `60000` | The whole AI request: every call, retry pause and the fallback together (1000 to 300000). Nothing runs past it. Above 85000 a warning is logged: the app gives up after 90 s. |
| `AI_ATTEMPT_TIMEOUT_MS` | `20000` | One call to one provider (1000 to 120000); must not exceed `AI_REQUEST_TIMEOUT_MS`. |
| `AI_MAX_RETRIES` | `2` | Extra calls to the same provider after a transient failure (429, 5xx, no connection), 0 to 5, with exponential backoff (500 ms, 1 s, 2 s ...) and jitter. Timeouts, bad requests, bad keys and refusals are never retried. |
| `AI_FALLBACK_ENABLED` | `1` | `0`: a failed provider is never replaced by another one within the same request. |
| `AI_FALLBACK_ON_RATE_LIMIT` | `1` | `0`: a 429 does not send the request to the other provider. |
| `AI_MODEL_PRICES` | unset | JSON, USD per 1M tokens: `{"<model>":{"input":0.4,"output":1.6}}`. Makes cost tracking and budgets exact for those models; otherwise costs are flat per-provider estimates. |
| `AI_BUDGET_DAILY_USD` `AI_BUDGET_MONTHLY_USD` | unset | Spend limits over all providers per UTC day / month. At the limit every AI route answers 503 `ai_unavailable` until the next day / month. |
| `AI_BUDGET_PROVIDER_DAILY_USD` | unset | JSON, per provider and UTC day: `{"openai":5,"xai":2}`. A provider at its limit is skipped; the others keep answering. |
| `FEATURE_AI` | `1` | `0`: every `/api/v1/ai/*` route answers 503 `feature_disabled`. |
| `FEATURE_SUBSCRIPTIONS` | `0` | `0`: subscription routes answer 503 `feature_disabled` (the module is not live yet). |
| `FEATURE_CLOUD_SYNC` | `1` | `0`: `POST /usage/sync` and `GET /usage/daily` answer 503 `feature_disabled`. |
| `AI_HISTORY_RETENTION_DAYS` | `90` | Read by the retention job: rows of `ai_generations` older than this are purged (1 to 3650). |
| `ELECTRICITY_PRICE_CACHE_HOURS` | `168` | How long a fetched household price is reused. |
| `EUROSTAT_BASE_URL` | Eurostat's public dissemination API | Override for the price source (tests, a mirror). |
| `COUNTRY_HEADER` | empty | Request header carrying the caller's country (`cf-ipcountry` behind Cloudflare); empty disables `/region` detection. |

Used by tooling, not by the server: `TEST_DATABASE_URL` (the PostgreSQL integration suites in
`apps/api/tests/db` run only when it is set), `WATTBYTE_E2E_API_URL` (Flutter end-to-end tests),
`WB_PG_PORT` (host port of the docker-compose database).

No WattByte host name is hardcoded anywhere in the code: the Flutter app takes
`--dart-define=API_BASE_URL=...` at build time and the server only knows the hosts it is told about.
The only default hosts in the repository are public third-party APIs (Eurostat, overridable with
`EUROSTAT_BASE_URL`; the AI vendors' API hosts inside `apps/ai`, see "Known limits").

## Running

### Local development

```bash
pnpm db:up && pnpm db:migrate                      # PostgreSQL in Docker, then the schema
cp apps/api/.env.example apps/api/.env              # edit JWT_SECRET
cd apps/api
DATABASE_URL=postgres://wattbyte:wattbyte@localhost:5432/wattbyte \
NODE_ENV=development AI_MOCK=1 JWT_SECRET=$(openssl rand -base64 48) \
PORT=8080 HOST=127.0.0.1 \
node --conditions=development --import tsx src/main.ts      # or: pnpm --filter @wattbyte/api dev
```

`AI_MOCK=1` needs no provider key. If the host port 5432 is taken, `WB_PG_PORT=55432 pnpm db:up`.

### Staging

Same build and same code path as production; only the values differ.

```bash
pnpm install --frozen-lockfile && pnpm build
DATABASE_URL=postgres://app:<password>@<host>:5432/wattbyte pnpm --filter @wattbyte/api migrate
export NODE_ENV=production APP_ENV=staging \
       DATABASE_URL=... DATABASE_SSL=1 JWT_SECRET=<openssl rand -base64 48> \
       TRUST_PROXY_HOPS=1 OPENAI_API_KEY=... OPENAI_FAST_MODEL=... OPENAI_QUALITY_MODEL=...
node apps/api/dist/main.js
```

Use a staging database and a staging `JWT_SECRET` of their own: tokens from one environment must
not be valid in another. `GET /api/v1/config` reports `"environment": "staging"`, so the app can
show a "staging" badge.

### Production

As staging with `APP_ENV=production` (or just `NODE_ENV=production`) and **an explicit
`DATABASE_SSL`**. Secrets come from the deployment's secret store, never from a file in the
repository (`node scripts/secret-scan.mjs` guards that). Terminate TLS at the proxy and set
`TRUST_PROXY_HOPS` to the number of proxies. Run the retention job daily (below).

Migrations are not applied by the server. Run `pnpm --filter @wattbyte/api migrate` (needs the
`.sql` files in `src/database/migrations`, which `tsc` does not copy into `dist/`) as a separate
deploy step before starting the new version.

## Boot, liveness and readiness (what really happens)

1. `loadEnv()` validates everything above. A problem prints the list and exits with code 1; no
   port is opened.
2. `DATABASE_URL` missing (development) also exits with code 1.
3. The PostgreSQL pool is **lazy**: nothing connects at construction. The server starts and listens
   whether or not the database is reachable.
4. After `listen`, one `SELECT 1` is tried and logged: `database reachable at boot` (info) or
   `database NOT reachable at boot; /ready answers 503 until it is` (warn). The result is
   informational only: it neither delays the start nor decides readiness.
5. **`GET /health` (liveness)** answers 200 as long as the process runs. It never touches the
   database, so a database outage does not get healthy instances restarted in a loop.
6. **`GET /ready` (readiness)** runs a real `SELECT 1` through the pool with the
   `READY_DB_TIMEOUT_MS` timeout on every call (the answer is never cached). 200
   `{status:"ok", database:"ok"}` when the query returns, 503 `{status:"degraded",
   database:"unavailable"}` when it fails, is refused, or does not answer in time (a black-holed
   host). Concurrent calls share one probe, and a probe that hangs is not joined once it is half
   the timeout old, so a stuck connection neither queues up probes nor hides a recovery.
7. While the database is down, every route that needs it answers `500 {"error":{"code":"internal",...}}`
   (no database detail), `/health` stays 200 and `/ready` stays 503. When the database comes back
   (or after a restart; the pool replaces dead connections and logs one `postgres pool error`),
   `/ready` is 200 again on the next probe: no restart of the API is needed.

Verified with the real `src/main.ts`: a dead `DATABASE_URL` gave `/health` 200, `/ready` 503, a
login 500 `internal`; and `apps/api/tests/db/ready.integration.test.ts` flips a TCP proxy to
PostgreSQL off and on under one running app.

Point the load balancer's health check at `/ready`, the orchestrator's liveness probe at `/health`.

## Logging and request ids

* Every response carries `x-request-id`. An incoming one is echoed only if it matches
  `^[A-Za-z0-9._-]{8,64}$`; otherwise a UUID is generated. The id is in every log line of the
  request (`reqId`) and on error responses too.
* Logs are one JSON object per line on stdout. They contain: request id, method, route pattern and
  path (no query string; e-mail-looking path segments are masked), status, timing, and for AI calls
  `ai: { task, provider, model, latencyMs, inputTokens, outputTokens, status }`. Errors log type,
  SQLSTATE or error code and stack frames, never the message (database errors echo the offending
  value). They never contain `Authorization` / `Cookie` headers, passwords, tokens, request or
  response bodies, AI prompts or answers, e-mail addresses or client IP addresses.
  `apps/api/tests/observability.test.ts` checks this against a captured log stream.

## Feature flags

`FEATURE_AI`, `FEATURE_SUBSCRIPTIONS`, `FEATURE_CLOUD_SYNC` are read at boot (a restart applies a
change; there is no external flag service). A route behind a disabled flag answers
`503 {"error":{"code":"feature_disabled",...}}` **after** authentication (an anonymous caller gets
401) and before the body is read. Clients read the flags, and the AI limits, from the public
`GET /api/v1/config`:

```json
{ "environment": "staging",
  "features": { "ai": true, "subscriptions": false, "cloudSync": true },
  "ai": { "dailyLimits": { "free": 3, "premium": 50 } } }
```

Routes of new features gate themselves with `requireFeature(features, 'name')`
(`apps/api/src/features/flags.ts`).

`FEATURE_CLOUD_SYNC=0` switches off only the upload and read of per-day aggregates
(`POST /usage/sync`, `GET /usage/daily`). The account-rights routes (`GET /me/export`,
`DELETE /me/cloud-data`, `DELETE /me`) are deliberately **not** gated: a user can always get their
data out and erase it, whatever the deployment has switched off.

## Retention job

`pnpm --filter @wattbyte/api retention` (add `-- --dry-run` to only count; from a build:
`node apps/api/dist/scripts/retention.js`). Needs only `DATABASE_URL` (`DATABASE_SSL`,
`AI_HISTORY_RETENTION_DAYS` optional). Prints one JSON line with the cutoffs and row counts. Deletes
in batches, is idempotent, and takes an advisory lock so two runs never overlap. Schedule it daily.
What it purges and what is kept until the account is deleted: `docs/security.md`, "Retention".

## Known limits

* AI keys: `OPENAI_API_KEY` and `XAI_API_KEY` (and the other two) are secrets. Development: your own untracked
  `apps/api/.env` (git ignores it). Staging and production: the deployment's secret store, one key per environment.
  Nothing in `.env.example` has a value. How the AI layer uses them: `docs/ai.md`.
* `apps/ai` has the AI vendors' public API hosts (`api.openai.com`, `api.anthropic.com`,
  `generativelanguage.googleapis.com`, `api.x.ai`) as constructor defaults and `providersFromEnv`
  does not pass a base URL from the environment, so staging cannot point a provider at a stub
  without code. Use `AI_MOCK` only where it is allowed (development) or run staging against the
  real providers with a separate key.
* A per-account login throttle does not exist: the credential limiter is per IP.
