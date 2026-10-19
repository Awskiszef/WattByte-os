# Security

## Mobile

- Access and refresh tokens are stored only through `flutter_secure_storage`
  (iOS Keychain, Android Keystore-backed encrypted preferences). SharedPreferences
  holds display settings only.
- The app talks exclusively to the WattByte API over HTTPS; AI provider keys are
  never shipped in the app.
- No private APIs, root or jailbreak detection tricks; capabilities are probed
  through public APIs and the UI adapts.

## API

- Passwords: scrypt (N=2¹⁶, r=8, p=1, 16-byte salt) via Node's crypto, constant-time compare, 8 to 200
  characters. A login for an unknown e-mail runs the same scrypt verification, so timing and answer
  (`401 invalid_credentials`) do not reveal which accounts exist.
- Access tokens: short-lived HS256 JWT (`JWT_SECRET` >= 32 chars, validated at boot; placeholders and
  repeated patterns refused in staging and production, see `docs/CONFIGURATION.md`). Verification pins
  the algorithm to HS256 (an HS384/HS512 token signed with the right key, `alg: none` and a wrong
  `iss`/`aud` are all refused), requires `exp`, `iat` and `sub`, and requires `sub` to be a UUID.
- Refresh tokens: random, hashed at rest, rotated atomically on use. Reuse policy below.
- **Authentication is deny-by-default.** An app-level `preParsing` hook (after the rate limiter,
  before the body is read or validated) requires a valid bearer token on every route that is not
  marked `config: { public: true }`, and checks that the account still exists. An anonymous caller
  therefore always gets `401 unauthorized`: never a `400` describing the schema, never a body parse.
  The public routes are exactly: `GET /health`, `GET /ready`, `GET /openapi.json`,
  `POST /api/v1/auth/{register,login,refresh,logout,apple,google}`,
  `GET /api/v1/devices/specifications/:identifier`, `GET /api/v1/region`, `GET /api/v1/config`
  (`apps/api/tests/security-regression.test.ts` enumerates the route table and fails on any
  other route that answers an anonymous request).
- **A token does not outlive its account.** Each authenticated request reads the user row (one
  primary-key lookup): after `DELETE /me` every access token of that account answers
  `401 account_not_found` at once, not after it expires. The plan used for AI quotas is read from
  that row, not from the token's `plan` claim, so a downgrade applies immediately and a client can
  never present a plan the server did not grant.
- Authorization is always by the token's user id: every query is `WHERE user_id = <token user>`;
  the owner of a row is set **after** the request body is spread, so no body field can choose it.
  Request schemas strip unknown keys, so `plan`, `role`, `isPremium`, `userId` and the like in a
  body are ignored (register, `PATCH /me`, `PUT /me/settings`, `POST /devices`, usage sync, AI
  requests are covered by tests; the AI aggregates schema is strict and rejects them with 400).
- Rate limiting on every route, unknown paths included: 120 per minute per IP by default, 10 per
  minute per IP on each credential route, 20 on AI routes. A blocked client gets `429` with
  `retry-after`, even when its next password is correct. Behind a proxy set `TRUST_PROXY_HOPS`.
- Input validation with Zod on body, query and params; responses are serialized through the same
  schemas, so no unexpected field leaks. Extra guards: JSON only (`text/plain` and forms are `415`),
  1 MiB body limit (`413`), prototype-pollution payloads are `400`, U+0000 in any string, key,
  query or path parameter is `400` (PostgreSQL text cannot store it and would answer `500`),
  battery capacities below the column resolution (0.1 mAh, 0.001 Wh) are `400`.
- `cache-control: no-store`, `x-content-type-options: nosniff` and `x-request-id` on every response.
- PostgreSQL: foreign keys with `ON DELETE CASCADE`, unique constraints on
  email, refresh hash, `(user, installation)`, `(user, device, date)`.

### Error contract

Every failure, whether it comes from a handler, a hook, the router or the body parser, is
`{ "error": { "code": "<machine code>", "message": "<text for people>" } }`. Clients branch on
`code` and on the status; `message` may be reworded and is never a contract. Nothing from inside
leaks: no stack, SQL, constraint name, SQLSTATE, library wording or provider response.

| Status | `code` | When |
|---|---|---|
| 400 | `validation` | body, query or params failed the schema (message lists field and reason, at most 300 characters) |
| 400 | `invalid_json` | malformed or empty JSON body |
| 400 | `bad_request` | malformed URL, bad `content-length`, other client errors without their own code |
| 400 | route codes | `invalid_ai_input`, `manual_price_required`, `invalid_range`, `duplicate_date`, ... |
| 401 | `unauthorized` / `invalid_token` | no or bad bearer token |
| 401 | `account_not_found` | valid token of a deleted account |
| 401 | `invalid_credentials`, `invalid_refresh_token`, `refresh_token_expired`, `refresh_token_reused` | auth routes |
| 403 | `forbidden` | reserved (no route answers it today) |
| 404 | `not_found` | unknown path |
| 404 | route codes | `device_not_found`, `device_not_registered`, `electricity_price_unavailable`, ... |
| 405 | `method_not_allowed` | known path, other method (with an `allow` header) |
| 409 | `email_taken`, `conflict` | duplicate e-mail; a lost unique-key race |
| 413 | `payload_too_large` | body over 1 MiB |
| 415 | `unsupported_media_type` | body that is not `application/json` |
| 429 | `rate_limited`, `ai_quota_exceeded` | per-IP limiter; daily AI quota. Both carry `retry-after` (seconds; for the quota, until the next UTC midnight) |
| 500 | `internal` | anything unexpected; message is always `Internal error` |
| 503 | `ai_unavailable`, `feature_disabled` | the AI provider(s) the policy allowed failed, none is configured, or a spend limit is used up (the log tells which; the client is told nothing more); the feature flag is off |

### Refresh token rotation and reuse (the real policy)

`POST /auth/refresh` consumes the presented token and issues a new pair. The consumed session row
gets `revoked_at` (the rotation time) and `replaced_by` (its successor). Presenting a token whose
row is already revoked is judged by **one rule**, with `gap = presentation time - rotation time`
and `grace = REFRESH_REUSE_GRACE_SEC` (default 10 s):

| Case | Result | Effect |
|---|---|---|
| `gap < grace` and the token was rotated (it has a successor) | `401 refresh_token_reused`, message "Refresh token was already used" | **retry**: nothing else is revoked, the successor and the user's other sessions stay valid |
| `gap >= grace`, or the token was revoked without a successor (logout, earlier theft response) | `401 refresh_token_reused`, message "...all sessions were revoked" | **theft**: every live session of the user is revoked |
| unknown token | `401 invalid_refresh_token` | nothing changes |
| expired token | `401 refresh_token_expired` | nothing changes |

The boundary belongs to theft: with the default grace, **9.9 s is a retry, 10.0 s is theft, 10.1 s
is theft** (1 ms below the grace is still a retry). `REFRESH_REUSE_GRACE_SEC=0` turns the retry
window off. The rule is implemented once in `SessionRepository.rotate({ now, graceMs })` (compare
`now - revoked_at < graceMs`) and decided by the injected clock, so
`apps/api/tests/refresh-boundary.shared.ts` checks it to the millisecond for `MemoryRepositories`
and PostgreSQL, and through `POST /auth/refresh` with a fake clock.

Consequences worth knowing:

* Of N concurrent refreshes with one token exactly one succeeds (row lock); the others are retries.
* A retry is **rejected, not answered**: the server never keeps a token it could replay. A client
  that lost the response of the winning refresh therefore cannot recover with the old token and has
  to sign in again; its other devices stay signed in. Clients must treat `refresh_token_reused` as
  "sign in again".
* A token revoked by **logout** that is presented again is treated as theft (it has no successor):
  a stale background refresh after logout revokes the user's other sessions as well.

### Logging

JSON lines on stdout. A line may contain the request id, method, route pattern and path (no query
string, no client address, e-mail-looking segments masked), status, timings, error type and
SQLSTATE/code with stack frames, and for AI calls only provider id, model, latency, token counts
and status. It never contains `Authorization`/`Cookie` headers, passwords, access or refresh
tokens, request or response bodies, AI prompts or answers, or e-mail addresses: the `req`/`err`
serializers drop them, `redact` censors secret-looking fields of anything logged by hand, and
`apps/api/tests/observability.test.ts` captures the log stream through register, login, refresh,
logout, an AI call, a sync and every error path and asserts that none of the email, password,
token parts or AI text appears. See also `docs/CONFIGURATION.md`.

### Retention

What the server keeps, and for how long. Nothing here is analytics: the server holds accounts and
per-day aggregates, never raw samples, per-app usage, prompts or answers.

| Data | Kept | Removed by |
|---|---|---|
| `users`, `user_settings`, `devices`, `daily_usage` (and the unused-by-default `charging_summaries`, `monthly_summaries`), `subscriptions` | until the account is deleted | `DELETE /api/v1/me` (cascades to everything below); the cloud-data endpoints of the cloud module |
| `sessions` (refresh token hashes) | while live; after they expired or were revoked, 30 more days | `pnpm retention` (expired or revoked more than 30 days ago), account deletion |
| `ai_generations` (task, mode, provider, model, token counts, cost, latency, time; no prompt, no answer) | `AI_HISTORY_RETENTION_DAYS`, default 90 days | `pnpm retention`, account deletion |
| `ai_quota_usage` (per user and UTC day counter) | 7 days | `pnpm retention`, account deletion |
| `ai_spend_daily` (total cost and number of AI answers per UTC day and provider; no user id, no personal data) | kept: a handful of rows a day, and it must survive erasure or a spend limit could be reset by deleting data | – |
| `electricity_prices` | per country, the last fetched value (no personal data) | replaced in place |
| application logs | by the log service's own retention; contain no personal data (see Logging) | – |

`pnpm --filter @wattbyte/api retention` (dry run: `-- --dry-run`) purges the three rows above in
batches, is idempotent and safe to run during traffic, and is meant to run daily
(`docs/CONFIGURATION.md`). The tests seed rows of every age and check each boundary
(`apps/api/tests/db/retention.integration.test.ts`). A new table with user data must be added to
this table and either cascade from `users` or get a purge rule.

### Security regression suite

`apps/api/tests/security-regression.test.ts` (in memory) and `tests/db/security.integration.test.ts`
(PostgreSQL): JWT tampering (alg none, other secret, issuer, audience, expired, no expiry, other
HMAC algorithm, bad subject, truncated, edited payload, flipped signature), malformed
`Authorization` headers, password bounds 7/8/200/201, e-mail normalisation and odd inputs (long,
unicode, control characters, SQL-looking), oversized and anonymous bodies, prototype pollution,
mass assignment on every write route, IDOR on devices, usage, settings and AI quota, the
authenticated-by-default route audit, and rate limiting of the credential routes.

## Not yet done

- Sign in with Apple / Google (routes answer 501 until configured).
- Store receipt verification for subscriptions (table exists, no endpoint).
- Secret management / TLS termination belong to the deployment, not to this repo.
- Clock source of the refresh reuse window: PostgreSQL stamps `sessions.revoked_at` with its own
  `now()` while the comparison uses the API's clock. With skew between the two hosts the effective grace
  shifts by the skew (keep both NTP-synced). The fix is to write the `now` that `rotate()` already
  receives instead of `now()`; the boundary tests pin `revoked_at` explicitly, so they hold either way.
- No per-account login throttle: the credential limiter is per IP, so a distributed guess against one
  account is not slowed beyond scrypt's cost.
- Access tokens cannot be revoked before they expire (default 15 min); a deleted account's token is
  refused at once because the account row is checked, a logged-out device's token is not.
- The AI vendors' API hosts are constructor defaults in `apps/ai` and cannot be overridden from the
  environment.
- AI cost ceilings (`AI_BUDGET_*`) are soft: they are checked before a call and the cost is added after it, and the
  figures are estimates unless prices are configured (`docs/ai.md`, "Spend limits"). A spending limit at the provider is
  the hard one.
