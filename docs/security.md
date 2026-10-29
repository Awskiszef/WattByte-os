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
- Rate limiting on every route, unknown paths included: 120 per minute per client by default, 10 per
  minute per client for register + login + the OAuth routes **together** (one bucket), 60 on
  `POST /auth/refresh` (its own bucket), 20 on AI routes. A "client" is an IPv4 address or an IPv6
  **/64** (an IPv4-mapped address counts as its IPv4); a blocked client gets `429` with `retry-after`,
  even when its next password is correct. The counters live in the process: with several instances the
  per-client limit is per instance (see docs/CONFIGURATION.md). `/health` and `/ready` are exempt.
- Per-account sign-in throttle (shared by all instances, PostgreSQL): from the 5th consecutive wrong
  password for one e-mail, further attempts are refused with `429` and **without checking the password**
  for 15 s, doubling per further failure up to 15 min; a success clears it, failures older than an hour
  do not count, attempts refused during a lock are not counted. It is keyed on a hash of the e-mail
  whether or not the account exists (no oracle). Trade-off: someone who knows an e-mail can lock that
  account for at most 15 min at a time (an attacker needs about one request per lock period to keep it).
- Client address: `TRUST_PROXY_CIDRS` (preferred) lists the proxies, so `X-Forwarded-For` and
  `COUNTRY_HEADER` are believed only on connections from them; `TRUST_PROXY_HOPS` only counts hops.
  Staging/production must set one of them. Password hashing is bounded (`SCRYPT_CONCURRENCY` running,
  `SCRYPT_MAX_QUEUE` waiting, then `503 busy` + `Retry-After`).
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
| 401 | `invalid_credentials`, `invalid_refresh_token`, `refresh_token_expired`, `refresh_token_reused`, `refresh_token_revoked`, `session_revoked` | auth routes, any signed-out device's access token |
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

### Sessions, refresh token rotation and reuse (the real policy)

A sign-in (register, login, change of password) starts a **session family**: the refresh tokens that descend from it by
rotation. One family is one signed-in device, and it is what logout, "sign out this device" and theft detection act on;
`family_started_at` is the sign-in time. `POST /auth/refresh` consumes the presented token and issues a new pair: the
consumed row gets `revoked_at` (the rotation time) and `replaced_by` (its successor). The successor is a keyed function
of the old token (`TokenService.successorRefreshToken`, HMAC with the server secret), not a fresh random value, so a
retry can be answered with the same one. Presenting a token whose row is already revoked is judged by **one rule**, with
`gap = presentation time - rotation time` and `grace = REFRESH_REUSE_GRACE_SEC` (default **60 s**, longer than the app's
20 s request timeout):

| Case | Result | Effect |
|---|---|---|
| rotated token, `gap < grace`, successor still unused | `200` with **the same refresh token** as the first answer (and a new access token) | **retry after a lost response**: nothing is revoked, the device continues |
| rotated token, `gap >= grace`, or its successor was already used | `401 refresh_token_reused` ("...this session was revoked") | **suspected theft**: the token's **family** (that one device) is revoked; the user's other devices are untouched |
| token revoked without a successor (logout, sign out everywhere, an earlier theft response) | `401 refresh_token_revoked` | nothing else changes (a stale device waking up cannot kill the session the user just created) |
| unknown token | `401 invalid_refresh_token` | nothing changes |
| expired token, or a family older than `SESSION_ABSOLUTE_LIFETIME_DAYS` (default 90) | `401 refresh_token_expired` | nothing changes |

The boundary belongs to theft: with a grace of 10 s, **9.9 s is a retry, 10.0 s is theft, 10.1 s is theft** (1 ms
below the grace is still a retry). `REFRESH_REUSE_GRACE_SEC=0` turns the retry window off. The rule is implemented once in
`SessionRepository.rotate({ now, graceMs, absoluteLifetimeMs })` and decided by the injected clock, so
`apps/api/tests/refresh-boundary.shared.ts` checks it to the millisecond for `MemoryRepositories` and PostgreSQL, and
through `POST /auth/refresh` with a fake clock.

Consequences worth knowing:

* Of N concurrent refreshes with one token exactly one rotates (row lock); the others are retries and receive the same
  successor. Only a presenter of the old token within the grace window can obtain it: that window is the price of making
  a lost response harmless, and a stolen old token used inside it yields the same successor the real client holds (the
  next legitimate refresh by either party continues the chain; a second use of the old token after the window revokes it).
* A device that lost a response and only comes back **after** the grace window cannot recover: its family is revoked and
  it signs in again. Its other devices stay signed in (this used to sign out the whole account).
* **Sign out** revokes the whole family of whichever token the device presents, the sign-in-time one included
  (`POST /auth/logout`); `POST /auth/logout-all` revokes every family of the account and `DELETE /me/sessions/{id}` one device.
* **Access tokens** carry the family id (`sid`) and are checked on every request against the account and the family: a
  token of a signed-out device, and every token issued before "sign out everywhere" or a password change
  (`users.tokens_valid_after`, second resolution), stops working at once instead of living on until it expires. Tokens
  issued before families existed have no `sid` and are accepted until they expire (at most `ACCESS_TOKEN_TTL_SEC`,
  which is capped at one hour).
* `POST /me/password` needs the current password (throttled like a login), signs every device out and returns a fresh
  session for the caller. `GET /me/sessions` lists the live devices.
* Not done: `DELETE /me` still needs only a bearer token (adding a password would break installed apps; it needs a
  coordinated client change), and there is no e-mail verification or password reset (needs an outbound e-mail
  provider, see `docs/remediation/BLOCKERS.md`).

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
- Clock source of the refresh reuse window: `rotate()` stamps `revoked_at` with the `now` it receives (the API's clock), the
  same clock the grace window is compared with; `revoke`/`revokeFamily` (logout) use the database's `now()`, which only
  matters for the retention cut-off.
- No per-account login throttle: the credential limiter is per IP, so a distributed guess against one
  account is not slowed beyond scrypt's cost.
- Access tokens cannot be revoked before they expire (default 15 min); a deleted account's token is
  refused at once because the account row is checked, a logged-out device's token is not.
- The AI vendors' API hosts are constructor defaults in `apps/ai` and cannot be overridden from the
  environment.
- AI cost ceilings (`AI_BUDGET_*`) are soft: they are checked before a call and the cost is added after it, and the
  figures are estimates unless prices are configured (`docs/ai.md`, "Spend limits"). A spending limit at the provider is
  the hard one.
