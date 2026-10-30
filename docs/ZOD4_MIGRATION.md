# Zod 3 to 4 migration plan

Status: **planned, not started** (2026-10-30). Closing it removes the one accepted audit exception (GHSA-mrhx-c7xc-m3w5, BLOCKERS B-11).
Dependabot's single-package PR (#18) bumps `zod` in the root only and cannot work alone, see "Why one PR cannot do it".

## Is the migration justified

Yes, but not urgent. The advisory is in the zod 4 core that zod 3.25 ships under `zod/v4`. This code imports the v3 API only, the one
importer of `zod/v4` is openai's optional `openai/helpers/zod` (unused), and request bodies are capped at 16 KiB. The exception is therefore
documented, not hidden (`pnpm-workspace.yaml`, `auditConfig`). The migration is still the only way to make `pnpm audit` clean without an
ignore entry, and `fastify-type-provider-zod` 4.x (zod ^3 only) has no further releases for zod 3.

## Why one PR cannot do it

| Package | Now | Needs |
|---|---|---|
| `zod` | `^3.24.1` in `apps/api`, `apps/ai`, `packages/contracts` | `^4.6.7` in all three at the same time (contracts schemas are used by api) |
| `fastify-type-provider-zod` | `^4.0.2` (peer `zod ^3`) | `^6` or `^7` (peer `zod >=4.1.5`, also needs `@fastify/swagger >=9.5.1` and `openapi-types`) |
| `zod-to-json-schema` | transitive of the provider | gone (zod 4 has `z.toJSONSchema`) |

Dependabot opened one PR per directory (#14, #15, #16, closed) and one for the root (#18). Each breaks the others, so the change is one branch.

## What changes in this code (from a read of the sources, not yet compiled)

* 17 files import zod: `apps/api` (app, env, retention script, 9 route modules), `apps/ai/src/schemas.ts`, three files in `packages/contracts`.
* `apps/api/src/app.ts`: `validatorCompiler`, `serializerCompiler`, `jsonSchemaTransform` keep their names in v6/v7; check the options for the new `createJsonSchemaTransform`.
* Usage that behaves differently in zod 4 and needs a test each:
  * `z.coerce.number` (34 uses): the input type becomes `unknown`; query strings and env parsing must still reject `""`, `"abc"`, `NaN`.
  * `z.string().uuid()` (9): v4 checks the RFC 9562 variant. Test ids and any stored non-RFC ids must still pass or the tests must use real v4 ids.
  * `z.string().datetime()` and `.url()`: same call, stricter parsing; compare accepted and rejected samples before and after.
  * `z.record` (3): v4 requires key and value schemas.
  * `z.preprocess` (1), `.default()` (defaults now short-circuit and apply to the output type), `z.ZodIssueCode.custom` in `config/env.ts` (deprecated, replace with `code: 'custom'`).
  * Error text: `error.issues[].message` wording changes. `apps/api/src/errors/http-error.ts`, `config/env.ts`, `retention.ts` and `apps/ai/src/gateway.ts` render it, so tests that compare messages must be updated deliberately, not loosened.
* The OpenAPI document changes shape (new JSON Schema generator). `pnpm openapi:check`, `scripts/check-openapi-compat.mjs` (what installed apps may rely on) and the generated Dart client (`pnpm dart-client:check`, pinned generator jar) are the real risk: a field that became `anyOf`/nullable differently breaks old app builds.

## Steps

1. Branch `refactor/zod-4` from `main`. Bump zod in the three packages, the provider to the newest release that passes, add `openapi-types` if the peer requires it.
2. `tsc` first; fix type errors (they point at every `coerce`/`record`/`default` site).
3. Snapshot `openapi.json` before, regenerate after, run `pnpm openapi:compat` and diff by hand; fix schemas until the document is compatible (not the compat script).
4. Contract tests for the behaviors in the list above (accepted and rejected inputs, error shape `{ error: { code, message } }` unchanged on the wire).
5. Run everything the CI runs, including the PostgreSQL integration tests, the Dart client generation and the Dart e2e against the new API (`pnpm ci:local` plus `pnpm test:db`, `pnpm dart-client:check`, Flutter e2e).
6. Remove `auditConfig.ignoreGhsas` and the B-11 exception text; `pnpm audit` must exit 0 with nothing ignored.
7. Prove the AI gateway: provider response parsing (`apps/ai/src/schemas.ts`) with recorded fixtures, no paid calls.

## Not done yet, and why

Steps 1 to 7 are not started. They need the PostgreSQL tests, Java for the Dart client and the e2e job. As of 2026-10-30 the local side is ready: Docker Desktop runs, the whole chain
(API tests with PostgreSQL 777 of 777, `pnpm dart-client:check` with the JDK bundled in Android Studio, the Dart e2e 45 of 45 against a live API) was run by hand on the code as it is today, so there is a green baseline
to compare the migrated code with (`docs/security/PUBLIC_RELEASE_REPORT.md`, "Code"). What is still missing is GitHub Actions: the repository's jobs are refused by GitHub
("recent account payments have failed or your spending limit needs to be increased"), so the migration cannot yet be confirmed by the CI that guards `main`. Doing the migration without that check would only move risk to the
mobile clients.
