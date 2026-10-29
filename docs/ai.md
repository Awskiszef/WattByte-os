# AI Gateway (`apps/ai`)

One library, four providers, one interface:

```ts
interface AIProvider {
  readonly id: 'openai' | 'anthropic' | 'google' | 'xai';
  generate(request: AIGenerationRequest): Promise<AIGenerationResult>;
  healthCheck(): Promise<ProviderHealthResult>;
}
```

Flow: `Flutter → WattByte API (/api/v1/ai/*) → AIGateway → ProviderRouter → provider`.
Flutter never holds provider keys; keys are read from the API's environment
(`providersFromEnv`). `AI_MOCK=1` swaps in deterministic mock providers for local work.

```
Client (Flutter app, aggregates only)
  ↓  POST /api/v1/ai/insight | weekly-summary | monthly-summary | roast   (bearer token, quota, rate limit)
Backend API (apps/api: AiService)
  ↓  quota slot reserved → AIGateway.generate(task, mode, aggregates, ctx, options?)
AIGateway   spend limits → provider order → retry → at most one fallback → validate output → usage record
  ↓
ProviderRouter  (configured providers, default provider, cooldown of failing ones)
  ├── OpenAIProvider     official `openai` SDK, Responses API, https://api.openai.com/v1
  ├── XAIProvider        official `openai` SDK (its own client), Responses API, https://api.x.ai/v1
  ├── AnthropicProvider  Messages API over fetch
  └── GoogleProvider     generateContent over fetch
```

Status words in this document follow the project convention: TESTED, INTEGRATION VERIFIED,
NOT VERIFIED, BLOCKED. A real provider is only ever called by `smoke:ai` (below); every
other test in this package runs against HTTP doubles.

## What the OpenAI and xAI adapters talk to

Checked against the vendors' documentation on 2026-10-13 (not from memory of older examples):

| | OpenAI | xAI |
|---|---|---|
| Client | official `openai` npm package (7.x), one instance | the same package, **a separate instance** with `baseURL` `https://api.x.ai/v1` (xAI documents this use) |
| Endpoint | Responses API, `POST /v1/responses`. OpenAI: Chat Completions "remains supported", Responses "is recommended for all new projects" | Responses API, `POST /v1/responses`. xAI calls `/v1/chat/completions` a legacy endpoint |
| Instructions / input | `instructions` = system prompt, `input` = the user prompt | same |
| Output limit | `max_output_tokens` = the plan's limit **+ 1024** (reasoning models spend hidden tokens from the same cap; without headroom they can think the answer away) | same |
| Structured output | `text.format` = JSON Schema (strict), the same shape as `AIOutputSchema` | none: its support for the Responses API is not confirmed, so the prompt demands JSON and `parseAIOutput` validates it |
| Storage at the provider | `store: false` (the API stores responses for 30 days by default) | `store: false` |
| Sampling | `temperature` 0.3 (normal) / 0.8 (playful modes), **only where the model accepts it**: reasoning models answer 400 to a custom temperature; the adapter learns that from the 400 (it is not billed), asks again without it, and remembers it per model. No model list to rot | same |
| Usage | `usage.input_tokens`, `usage.output_tokens` | same names (the Chat-Completions names `prompt_tokens` / `completion_tokens` are accepted too) and `usage.cost_in_usd_ticks`, the exact charge (10 000 000 000 ticks = $1) |
| Request id | `x-request-id` header, else the response `id` | same |

What the adapter does around the SDK, because the SDK's defaults would break the repository's rules:

- **No ambient configuration.** The SDK reads `OPENAI_BASE_URL`, `OPENAI_ORG_ID`, `OPENAI_PROJECT_ID`,
  `OPENAI_ADMIN_KEY`, `OPENAI_WEBHOOK_SECRET`, `OPENAI_LOG` and `OPENAI_CUSTOM_HEADERS` from the process
  environment on its own. The adapter passes the key, the base URL and `null` for every other credential
  explicitly, switches the SDK's logging off, and sends only `authorization`, `content-type`, `accept` and
  `user-agent` over the wire, so a variable set for another tool cannot add a header (or an organisation) to
  WattByte's requests, and nothing meant for OpenAI reaches xAI. Covered in `tests/responses.test.ts`.
- **No hidden retries.** The SDK would retry 2 times by default (and retries timeouts). It is set to 0; retries,
  backoff and fallback belong to the gateway, which knows the time budget (below).
- **One hard deadline per call**, raced against the work, plus cancellation by `AbortSignal`.
- **Content-free errors.** A failed call becomes a `ProviderError` made of the provider id, the failure class, the
  HTTP status and one short machine code. The SDK's own `message` and `error` quote the request on some providers
  and are never copied.
- The key lives in an ES private field of the provider (`#apiKey`); `JSON.stringify`, `util.inspect` and structured
  loggers cannot print it.

## Configuration: what is read, and what is not

The gateway reads exactly these variables, from the object handed to `providersFromEnv`
(the API passes its parsed environment); nothing is read from `process.env` inside the
package:

| Provider | Key | Models |
|---|---|---|
| OpenAI | `OPENAI_API_KEY` | `OPENAI_FAST_MODEL`, `OPENAI_QUALITY_MODEL` |
| Anthropic | `ANTHROPIC_API_KEY` | `ANTHROPIC_FAST_MODEL`, `ANTHROPIC_QUALITY_MODEL` |
| Google Gemini | `GOOGLE_AI_API_KEY` | `GEMINI_FAST_MODEL`, `GEMINI_QUALITY_MODEL` |
| xAI | `XAI_API_KEY` | `XAI_FAST_MODEL`, `XAI_QUALITY_MODEL` |

How a request uses them is decided by the API's own variables (`apps/api/src/config/env.ts`, validated by Zod at
boot; the full table with ranges is in `docs/CONFIGURATION.md`):

| Variable | Default | Meaning |
|---|---|---|
| `AI_DEFAULT_PROVIDER` | unset | tried first for every task. Needs its key |
| `AI_REQUEST_TIMEOUT_MS` | `60000` | the whole request: calls, retry pauses and the fallback together |
| `AI_ATTEMPT_TIMEOUT_MS` | `20000` | one call to one provider |
| `AI_MAX_RETRIES` | `2` | extra calls to the same provider after a transient failure |
| `AI_FALLBACK_ENABLED` | `1` | one other provider may take over after a failure that allows it |
| `AI_FALLBACK_ON_RATE_LIMIT` | `1` | a 429 counts as such a failure |
| `AI_MODEL_PRICES` | unset | JSON per-model prices, USD per 1M tokens |
| `AI_BUDGET_DAILY_USD`, `AI_BUDGET_MONTHLY_USD`, `AI_BUDGET_PROVIDER_DAILY_USD` | unset | spend limits |

Conventions that differ from what a generic setup guide would suggest, on purpose:

- **Model names stay `*_FAST_MODEL` / `*_QUALITY_MODEL`**, not one `AI_OPENAI_MODEL`: the app has two kinds of task
  (a short observation and a summary) and picks the cheaper or the better model per task. No model is hardcoded,
  so changing a model is a configuration change. A key without a model is a boot error.
- **Switches are `0` / `1`** like every other switch in this API (`AI_MOCK`, `DATABASE_SSL`, `FEATURE_*`); `true`
  is refused with a message naming the variable.
- **`AI_REQUEST_TIMEOUT_MS=60000` is the whole request**, not one call. One call is `AI_ATTEMPT_TIMEOUT_MS` (20 s,
  as before). The app waits 90 s for an AI answer (`apps/mobile/lib/features/ai/ai_service.dart`), so the request
  budget must stay below that; a warning is logged above 85 s.
- A blank value (`OPENAI_FAST_MODEL=` as in `.env.example`) counts as unset.
- **Ambient variables are ignored on purpose.** `ANTHROPIC_BASE_URL`, `OPENAI_BASE_URL`,
  `OPENAI_API_BASE`, `HTTP(S)_PROXY` and similar belong to other tools on the same machine
  (a developer shell often has `ANTHROPIC_BASE_URL` set for an unrelated CLI). Base URLs are
  constructor options of the adapters (`baseUrl`) and are never taken from the environment, so
  such a variable cannot redirect WattByte traffic or send its keys elsewhere. Covered by
  `tests/env.test.ts` (adapters called with hostile ambient variables hit the default hosts;
  a source scan fails on any `process.env` or `*_BASE_URL` in `src/`).
- Node's own opt-in proxy support (`NODE_USE_ENV_PROXY=1` with `HTTPS_PROXY`) is a property of the
  runtime and would apply to every outbound request of the API process; the package neither reads
  nor sets it. Do not enable it on a host that also runs other tools you do not want proxied.

Choosing the provider:

- **Per request, backend only.** `gateway.generate(task, mode, aggregates, ctx, { provider: 'xai' })`; with
  `model: '<name>'` as well the call uses that model (the name is validated, it is sent to a paid API; the fallback
  keeps its own configured models). The HTTP routes accept neither a provider nor a model: letting a client pick would
  hand it control over the bill.
- **Default.** `AI_DEFAULT_PROVIDER` goes first for every task; the task's own routing order continues behind it.
  Unset, each task keeps its own order (table below). A default that is cooling down sits behind the healthy ones,
  so a dead default does not take every request with it.
- A requested provider that is not configured is an error (`no_provider`), never a silent switch.

## Routing and fallback

| Task | Order | Model tier |
|---|---|---|
| insight | Google → OpenAI → xAI → Anthropic | fast |
| weekly_summary | OpenAI → Google → Anthropic → xAI | quality |
| monthly_summary | Anthropic → OpenAI → Google → xAI | quality |
| roast | xAI → OpenAI → Anthropic → Google | fast |

Only configured providers count. The first one is asked; if it fails in a way that allows it, **exactly one** other
provider (the next in the order) gets the request, and that is the end: a failing request never fans out into a chain
of paid calls. Providers are never asked in parallel. Tier selection happens inside each provider: the tier's model if
configured, otherwise the other tier's model.

### What happens on each failure

| Failure | Category | Retried (same provider) | Other provider asked | Provider demoted |
|---|---|---|---|---|
| timeout (`timeout`) | `timeout` | no (the call spent its whole slice) | yes | yes |
| HTTP 408 | `timeout` | yes | yes | yes |
| connection error (`network`) | `provider_unavailable` | yes | yes | yes |
| HTTP 500 / 502 / 503 / 504 / 529 | `provider_unavailable` | yes | yes | yes |
| HTTP 501 / 505 | `provider_unavailable` | no | yes | yes |
| HTTP 429 | `rate_limit` | yes, unless `insufficient_quota` / `billing_not_active` | yes, unless `AI_FALLBACK_ON_RATE_LIMIT=0` | yes |
| 2xx body that is not JSON (`invalid_response`) | `response` | no | yes | yes |
| HTTP 401 / 403 (bad or revoked key) | `authentication` | no | **no** | yes |
| HTTP 400 / 404 / 409 / 422 (bad request, wrong model name) | `invalid_request` | no | **no** | yes |
| model refused (`refusal`) | `response` | no | **no** | yes |
| empty text, or text that is not JSON / fails the schema (`empty_output`, `invalid_output`) | `response` | no | **no** | yes |
| anything unforeseen inside an adapter (`unexpected`) | `response` | no | **no** | yes |
| the caller cancelled (`aborted`) | `aborted` | no | no | no |

Why the second provider is not asked after "No": a rejected answer is already billed, so asking again pays twice for the
same defect; a revoked key, a wrong model name or a bad prompt is a defect somebody must see, not one to be hidden by
the other vendor. The request fails (503 `ai_unavailable`) and the log says why. The provider is still demoted, so the
**next** request is served by another provider and only one request per cooldown window pays for the defect. This is a
change from the first version of this gateway, which tried every provider after every failure
(and retried none); the rules above are the ones asked for in the cost-control brief.

Demotion (`ProviderRouter`): `cooldownMs` (default 60 s) after the first failure, doubling with each consecutive failure
up to `maxCooldownMs` (default 10 min), at least the provider's `Retry-After` when it sent one (same cap). A success
clears the streak. `cooldownMs: 0` disables the breaker (the API tests use that). A provider that is cooling down is
still the last choice, never dropped: with nothing else configured it is tried, so an outage is never turned into
"no provider". The router state is per process.

### Retry with backoff

Only the failures marked "yes" in the *Retried* column above, and at most `AI_MAX_RETRIES` times (default 2, so three
calls per provider). The wait before retry *n* is 500 ms · 2ⁿ (500, 1000, 2000, ... capped at 8 s) with ±25 % jitter, and
never less than the provider's `Retry-After`. A provider that asks for more than 5 s is not waited for: the request moves
on (the router keeps that provider out for as long as it asked). No pause is taken that, with one more call after it,
would not fit the request budget. The router hears about a provider only when its retries are used up: a retry that
succeeds leaves no trace except the log.

### Time

| Limit | Default | Behaviour |
|---|---|---|
| one call (`AI_ATTEMPT_TIMEOUT_MS`) | 20 s | the call is aborted; a fetch that ignores the abort cannot hold the caller either (the deadline is raced against it) |
| the whole request (`AI_REQUEST_TIMEOUT_MS`) | 60 s | each call gets `min(attempt limit, time left)`; a fallback is only started with at least 1 s left, and nobody is blamed when it is not |
| cancellation | – | `options.signal` ends the request at once; no retry, no fallback, the router is not told |

Worst case for one request is therefore `AI_REQUEST_TIMEOUT_MS`, not providers × timeout (the first version could take
80 s). Every timer is cleared on every path (asserted with fake timers).

### What the caller sees

- Success: `GenerateOutcome` (`output`, `providerId`, `model`, `usage`, `fallbacks`).
- Invalid aggregates or options: `AIGatewayError{code:'invalid_input'}` (the message names the offending fields).
- Nothing configured, or the requested provider is not: `AIGatewayError{code:'no_provider'}`.
- A spend limit is used up: `AIGatewayError{code:'budget_exceeded'}`; nothing was called.
- The provider(s) the policy allowed failed: one `AIGatewayError{code:'all_providers_failed', message:'all AI providers failed'}`.
  The message is generic on purpose. Per-provider detail is limited to the typed, content-free
  `attempts: {providerId, kind, category, status?}[]` (one per provider asked); `causes` carries the sanitized
  `ProviderError`s for operator logs. The API turns every one of these into HTTP 503 `ai_unavailable` (and gives the
  quota slot back); no provider text, status or prompt echo reaches the client.
- `AIGatewayError{code:'aborted'}` when the caller cancelled.

Error categories (`categorize()` in `src/errors.ts`, exported as `AIErrorCategory`): `authentication`, `rate_limit`,
`timeout`, `provider_unavailable`, `invalid_request`, `response`, `aborted`. They are derived from `kind` and `status`, so
they cannot disagree with them, and they are the vocabulary of the logs and of `attempts`. They are a field, not six
exception classes: a `ProviderError` already carries everything an exception class would, and the retry and fallback
policy reads it in one place (`isRetryable`, `allowsFallback`).

`ProviderError.message` is built from the provider id, the failure class and, for HTTP errors,
one short machine code taken from the error body (`invalid_api_key`, `rate_limit_error`,
`RESOURCE_EXHAUSTED`; only values matching `[A-Za-z0-9_.:-]{1,64}`). Error text, response bodies and
request headers are never copied: providers sometimes echo the request in their error messages.

## Structured output

Every answer must be a JSON object matching `AIOutputSchema` (strict):

```json
{ "title": "Heavy data day", "message": "...", "tone": "roast", "severity": "info", "emoji": "💀" }
```

`parseAIOutput(text, mode)` accepts plain JSON, fenced JSON and JSON surrounded by a sentence;
`tone` is forced to the requested mode. It rejects, and the gateway then treats the attempt as a
provider failure (demotion, no second paid call): empty or whitespace-only text, prose without JSON,
truncated or malformed JSON, a missing field, a wrong type or enum value (`severity`), a field
over its limit (title 80, message 600, emoji 8 characters), and any extra key. The rejection
reason lists field paths and Zod issue codes only; the model's text is never quoted. Covered for
every provider through its real adapter and HTTP double. OpenAI is additionally *asked* for this shape
(`text.format`, `AI_OUTPUT_JSON_SCHEMA`, kept in step with the Zod schema by a test); the validation does not depend on it.

## Token usage and cost

Usage fields per provider (extracted by the adapters, covered by `tests/providers.test.ts` and `tests/responses.test.ts`):

| Provider | Input tokens | Output tokens | Charge |
|---|---|---|---|
| OpenAI | `usage.input_tokens` | `usage.output_tokens` | – (estimated) |
| xAI | `usage.input_tokens` (or `prompt_tokens`) | `usage.output_tokens` (or `completion_tokens`) | `usage.cost_in_usd_ticks` |
| Anthropic | `usage.input_tokens` | `usage.output_tokens` | – (estimated) |
| Gemini | `usageMetadata.promptTokenCount` | `candidatesTokenCount + thoughtsTokenCount` (reasoning is billed as output) | – (estimated) |

A count that is missing, negative, not a number or not finite is treated as not reported
(fractions are floored). When either count is not reported, `usageReported` is `false`, both
numbers are 0 and the cost is **unknown**, unless the provider reported the charge itself. It is never presented as a free call.

Cost (`estimateCost`, `UsageRecord.estimatedCostUsd` + `costBasis`):

| `costBasis` | Meaning |
|---|---|
| `provider_reported` | the provider's own figure for this very call (xAI sends it); beats everything below |
| `model_price` | the operator supplied a per-model price (`AI_MODEL_PRICES`, matched by exact model name or a dated `name-…` snapshot) |
| `provider_estimate` | no model price: the flat approximate list price of the provider (`PRICE_PER_MILLION_USD` in `usage.ts`) |
| `unknown` | usage not reported (or no usable price): `estimatedCostUsd` is stored as 0 **and flagged**; 0 here means "no data" |

Decision: model names live only in configuration and change often, so the built-in table is one flat price per
provider, labelled as an estimate, instead of a model list that would rot. **Set `AI_MODEL_PRICES` for every model you
configure** if the numbers are to be trusted (budgets included): the flat OpenAI, Anthropic and Google figures were not
re-checked against current price lists; xAI's was updated from docs.x.ai on 2026-10-13 and is superseded anyway by the
charge xAI reports. An unknown model never crashes and never gets a silent 0: it is priced at the provider figure and
says so. The arithmetic is `(input × in$ + output × out$) / 1 000 000`, rounded to 6 decimals
(the `numeric(12,6)` column); it never yields NaN, Infinity or a negative number. The real invoice comes from the provider.

The API stores every answer in `ai_generations` (provider, model, tokens, cost, `cost_basis`, `usage_reported`, latency,
time; no prompt, no answer) and adds its cost to `ai_spend_daily` in the same statement.

## Spend limits

`AI_BUDGET_DAILY_USD`, `AI_BUDGET_MONTHLY_USD` (all providers together, per UTC day / month) and
`AI_BUDGET_PROVIDER_DAILY_USD` (`{"openai":5,"xai":2}`). Checked before any provider is called, against
`ai_spend_daily`, a table of daily totals per provider written together with each answer's log row (migration 0005).
It holds no user id on purpose: summing `ai_generations` would shrink when users erase their data or the retention job
purges old rows, and a budget that can be reset that way is no budget. Reaching a limit (`>=`):

- daily / monthly: nothing is called, the request is a 503 `ai_unavailable` and the quota slot goes back; the log says
  `budget_exceeded`. It ends at the next UTC day / month.
- one provider's limit: that provider is left out of routing (also as the fallback, and when the backend asked for it);
  the others keep answering, so one spent provider never blocks the app. All of them spent counts as `budget_exceeded`.
- A limit of `0` switches the provider (or everything) off.

Limits to know about: the figures are estimates unless prices are configured or the provider reports the charge; the
check happens before the call and the cost is added after it, so concurrent requests can overshoot a limit by the cost of
the requests in flight; a rejected-but-billed answer (refusal, invalid output) is logged with its tokens but not added to
the spend, since only delivered answers are stored; a spend table that cannot be read fails open and logs
`ai.budget_check_failed`. **Per user** there is no cost limit: the quota (free 3, premium 50 answers per UTC day) and the
per-answer output cap (220 / 400 tokens, plus the reasoning headroom) bound what one user can spend. For a hard ceiling set
a spending limit at the providers too (OpenAI project budget, xAI team spending limit): it is the only guard that does
not depend on this code.

## Status (no request is made to any provider)

`GET /api/v1/ai/status` (bearer token, 20 / minute / IP, not in OpenAPI): which providers are configured, whether one is
cooling down (`inCooldown`, `retryInSec`, `consecutiveFailures`), the default provider, the fallback switches, retries,
timeouts and whether a budget is enforced. No key, no part of a key, no model name. `GET /ready` lists the configured
provider ids too. At boot the API logs one `ai configuration` line with the same summary.

```json
{ "enabled": true,
  "providers": { "openai": { "configured": true, "inCooldown": false, "retryInSec": 0, "consecutiveFailures": 0 },
                 "xai": { "configured": true, "inCooldown": false, "retryInSec": 0, "consecutiveFailures": 0 },
                 "anthropic": { "configured": false, "inCooldown": false, "retryInSec": 0, "consecutiveFailures": 0 },
                 "google": { "configured": false, "inCooldown": false, "retryInSec": 0, "consecutiveFailures": 0 } },
  "defaultProvider": "openai", "fallback": { "enabled": true, "onRateLimit": true }, "maxRetries": 2,
  "timeouts": { "attemptMs": 20000, "requestMs": 60000 }, "budgetEnforced": false }
```

Whether a key is *valid* is only known to the provider: `smoke:ai` (below) is the check, at a cost of a fraction of a cent
per provider.

## Telemetry and privacy

`AIGateway({ logger })` accepts any pino-style logger (`logger.info(obj, msg)`, Fastify's `app.log`
fits; `apps/api/src/main.ts` passes a late-binding wrapper because the gateway exists before the app). It receives
one `ai.attempt` entry per provider call, nothing else:

`event, provider, model, task, outcome, category, httpStatus, attempt, fallback, latencyMs, inputTokens, outputTokens, requestId`

`outcome` is `ok` or the failure kind. `attempt` counts the calls to one provider (1, then 2 for the first retry),
`fallback` is true for the second provider, `requestId` is the provider's own id (for a support ticket). A
rejected-but-billed answer carries its token counts. Prompts, model output, response bodies, request headers, keys and the
user reference are never in an entry (asserted on a captured logger in `tests/gateway.test.ts` with sentinel strings in the
prompt, the model text, the provider error body and the user reference). A usage sink that throws
does not fail the request or trigger another paid call; it is reported as
`ai.usage_record_failed` (or on stderr without a logger). A logger that throws cannot break
generation either. The API adds `ai generation` / `ai generation failed` lines carrying the request id (provider, model,
latency, tokens; for a failure the content-free `attempts` with `kind`, `category`, `httpStatus`).

`AIInputSchema` is `.strict()`: any extra key (email, userId, token, ip, deviceId, name) fails
validation before a prompt exists. The user id is kept only as an opaque `userRef` in the usage
record and never enters a prompt (covered by `apps/api/tests/ai.test.ts` and
`tests/gateway.test.ts`). `store: false` keeps the aggregates from being retained by OpenAI and xAI after the call.

## AI does not calculate

The input schema (`AIInputSchema`) contains finished aggregates only
(GB, kWh, cost, counts, percent change). The system prompt forbids computing,
converting or inventing numbers; tests assert every figure is quoted verbatim.

There is deliberately **no HTTP route that forwards free text to a provider**: the four routes take
aggregates, and the gateway builds the prompt. A generic `POST /ai/generate` taking any text would let every signed-in
user send personal text to third parties (contradicting `docs/privacy.md`) and spend the budget on questions that
have nothing to do with the app. If such a route is ever wanted it is a product and privacy decision, not an
implementation detail.

## Quota and concurrency

Quota per user and day (atomic reserve/release) and rate limiting are enforced by `apps/api`,
before the gateway is called. What the gateway exposes for that: `AIGatewayError.code`
(`invalid_input` → 400, everything else → release the slot, 503), `GenerateOutcome.usage`
(tokens, cost, basis, latency), `ProviderRouter.health()` / `AIGateway.status()` and the `logger` hook.

## Modes

`normal`, `friendly`, `funny`, `roast`. Roast is witty about habits only: never
about the person, intelligence, money, health or appearance; no profanity.

## Development and production

**Local development.** `AI_MOCK=1` needs no key and calls nobody. To try a real provider, put its key and a model name
in an untracked `.env` (`.gitignore` covers `.env`, `.env.*` and `*.env`; only `apps/api/.env.example` is tracked, and it
has no values):

```bash
cd apps/api
cp .env.example .env      # then edit: JWT_SECRET, OPENAI_API_KEY=sk-..., OPENAI_FAST_MODEL=...
NODE_ENV=development node --env-file=.env --conditions=development --import tsx src/main.ts
```

(`sk-...` and `xai-...` anywhere in this repository are placeholders.) Example of a complete provider setup:

```
OPENAI_API_KEY=sk-...
OPENAI_FAST_MODEL=<a model name from your OpenAI account>
OPENAI_QUALITY_MODEL=<another, or the same>
XAI_API_KEY=xai-...
XAI_FAST_MODEL=<a Grok model name>
AI_DEFAULT_PROVIDER=openai
```

**Production.** The API is a plain Node process (`node apps/api/dist/main.js`); the repository does not prescribe a host
and has no `wrangler.toml` or Dockerfile, so these rules are generic:

- The keys are environment variables of that process, supplied by the host's **secret store** (systemd
  `EnvironmentFile` with mode 0600, Docker/Compose `secrets` or `--env-file` from a protected path, the secret manager of
  a PaaS or of Kubernetes). Never a file in the repository, never a build argument that ends up in an image layer.
- Staging and production use **their own keys** (ideally project-scoped keys with a spending limit at the provider), so a
  leak or a runaway in staging cannot touch production's budget, and rotation is independent.
- Rotating a key: create the new key at the provider, deploy it, then revoke the old one. A revoked key shows up as
  `authentication` failures in the log and as that provider sitting in cooldown in `GET /api/v1/ai/status`.
- CI needs no key and has none: every test uses doubles. `node scripts/secret-scan.mjs` fails the build on a real
  provider key anywhere in the tree.
- Keys never reach the app, the logs, the status route or an error response (asserted in the tests of every layer).

## Tests are hermetic

`pnpm --filter @wattbyte/ai test` (vitest, `tests/**/*.test.ts` only):

- `tests/setup.ts` runs before every test file: it deletes every provider, endpoint and proxy
  variable from `process.env` (`OPENAI_*`, `ANTHROPIC_*`, `GOOGLE_*`, `GEMINI_*`, `XAI_*`,
  `*_API_KEY`, `*_BASE_URL`, `*_API_BASE`, `*_ENDPOINT`, `*_PROXY`) and replaces global `fetch`
  with a guard that rejects every host except loopback. A test cannot reach a real provider, and
  a developer's `ANTHROPIC_BASE_URL` cannot change a result.
- Provider behaviour is tested against `fetch` doubles (the SDK is given the double as its transport) and against a real
  HTTP server on `127.0.0.1` (real sockets: headers, `Retry-After`, a server that never answers, a closed port).
- Timeouts, backoff and the request budget use fake timers or an injected clock and sleep, and assert that no timer is left behind.
- What is covered, by file: `providers.test.ts` / `responses.test.ts` (adapters, request mapping, usage, errors, isolation
  from the environment), `policy.test.ts` (categories, retry, fallback, budget, cancellation, status), `gateway.test.ts`
  (routing, cooldown, output validation, telemetry), `router.test.ts`, `usage.test.ts`, `env.test.ts`.
- The API side: `apps/api/tests/ai-policy.test.ts` (status route, spend limits through HTTP, the gateway built from the
  environment), `env.test.ts` (configuration), and, with `TEST_DATABASE_URL`, `tests/db/ai-spend.integration.test.ts`
  (migration 0005 with backfill, atomic spend, survives data erasure).
- The smoke tooling is unit-tested (`tests/smoke.test.ts`) and its compiled CLI is exercised as a
  separate process with a stubbed `fetch` (`tests/smoke-cli.test.ts`).

## Real provider smoke test

Everything above runs against doubles. The only way to learn whether a real provider accepts the
request, honours the output format and returns usage in the shape the adapter expects is to call it.
`smoke:ai` does that, once per provider, and is **not** part of `pnpm test` (a separate script that
compiles `scripts/smoke.ts` and runs it with node; it is not collected by vitest).

```bash
# from the repository root; export only what you want to verify
export OPENAI_API_KEY=...        OPENAI_FAST_MODEL=<model name>
export ANTHROPIC_API_KEY=...     ANTHROPIC_FAST_MODEL=<model name>
export GOOGLE_AI_API_KEY=...     GEMINI_FAST_MODEL=<model name>
export XAI_API_KEY=...           XAI_FAST_MODEL=<model name>
npx pnpm --filter @wattbyte/ai smoke:ai
```

Per provider, in the order openai, anthropic, google, xai:

1. No API key (unset or blank): prints `<provider>: NOT VERIFIED — API KEY MISSING`, no request.
2. Key but no model (neither `*_FAST_MODEL` nor `*_QUALITY_MODEL`): prints
   `<provider>: NOT VERIFIED — MODEL MISSING`, no request.
3. Otherwise ONE request for the `insight` task (fast model, quality as fallback) with a fixed,
   synthetic prompt (invented aggregates for "2026-10", the production system prompt, at most 220
   output tokens plus the reasoning headroom: about 350 input tokens, fractions of a cent). The answer must pass
   `parseAIOutput` (the real output schema) and the response must carry token usage. Then it prints
   one line with provider, model, latency, tokens and the cost with its basis.

The key is never printed: errors are the sanitized `ProviderError` messages, and any configured key
is additionally masked before printing. Raw headers and response bodies are never printed. The
environment is read only for the variables in the table above; `ANTHROPIC_BASE_URL` and friends
are ignored.

Expected output without any key (this is the run on this machine, 2026-10-13):

```
smoke:ai: one minimal request per configured provider (fixed synthetic prompt, no user data)
openai: NOT VERIFIED — API KEY MISSING
anthropic: NOT VERIFIED — API KEY MISSING
google: NOT VERIFIED — API KEY MISSING
xai: NOT VERIFIED — API KEY MISSING
summary: 0 verified, 0 failed, 4 not verified (exit 0)
```

Expected output for a configured provider that works (shape; values vary):

```
openai: OK model=<reported model> latency_ms=612 input_tokens=352 output_tokens=58 est_cost_usd=0.000234 (provider_estimate)
xai: OK model=<reported model> latency_ms=905 input_tokens=340 output_tokens=61 est_cost_usd=0.003776 (provider_reported)
```

and for one that does not:

```
anthropic: FAILED — anthropic: HTTP 401 (authentication_error)
```

Exit code: 0 unless a **configured** provider fails (HTTP error, timeout after 30 s, refusal,
output that does not validate, or a response without token usage). Missing keys and missing
models are never errors.

### How results map to status words

| Smoke result | Status for that provider's real call |
|---|---|
| `OK …` and exit 0 | **INTEGRATION VERIFIED** (real API, structured output validated, usage parsed). Say which model and the date. |
| `NOT VERIFIED — API KEY MISSING` / `MODEL MISSING` | **NOT VERIFIED**. Not BLOCKED: supplying the key is enough. |
| `FAILED — …` (exit 1) | **NOT VERIFIED** and a defect to fix (key, model name, adapter mapping). Never report it as verified or as skipped. |

The unit and HTTP-adapter tests give **TESTED** for the adapter regardless of the smoke result. A
real call proves the provider, not the whole product: Flutter → API → provider on a device stays a
separate status.

### Provider verification status

State as of 2026-10-13, no provider keys exist in this environment:

| Provider | Adapter and gateway behaviour (HTTP doubles + loopback server) | Real call (`smoke:ai`) |
|---|---|---|
| OpenAI | TESTED (Responses API through the official SDK) | NOT VERIFIED — API KEY MISSING |
| Anthropic | TESTED | NOT VERIFIED — API KEY MISSING |
| Google Gemini | TESTED | NOT VERIFIED — API KEY MISSING |
| xAI | TESTED (Responses API through the official SDK) | NOT VERIFIED — API KEY MISSING |

The wire formats are implemented from the providers' public API documentation and the SDK's own type definitions, and have
never been seen against the live services from this repository. Specifically unconfirmed until the smoke run prints `OK`
for that provider: that the configured model accepts `store: false`, `max_output_tokens` and (OpenAI) the strict JSON Schema
format; that xAI accepts `store: false` on the Responses API and sends `usage.cost_in_usd_ticks` there; how a given model
words its rejection of `temperature` (the adapter reads the 400's `param`, or the word in its text).

## Not done, on purpose

- No conversation history (`messages`): the app sends one set of aggregates per request.
- No streaming: answers are a few hundred characters.
- No per-user cost limit (see Spend limits): the per-user daily quota covers it.
- Rejected-but-billed answers are logged with their tokens but not added to `ai_spend_daily`.
- `ProviderRouter` state (cooldowns) is per process; several API instances each keep their own.
