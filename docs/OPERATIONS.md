# Operating the API

What it takes to run the WattByte API in staging or production, written for the person who gets the pager. It describes what
is in the repository and what was verified; everything that depends on a hosting provider is marked as **your decision** or
**not verified**. Configuration reference: `docs/CONFIGURATION.md`. Security and retention rules: `docs/security.md`.

## What runs

One stateless Node process (`node apps/api/dist/main.js`) in front of one PostgreSQL database. The process holds two kinds of
state that are **not** shared between instances:

* the per-IP rate limits of `@fastify/rate-limit` (in memory) and the per-account write limiter. With N instances every
  limit is effectively N times larger. Run **one instance** until that matters, or put a limiter at the proxy;
* nothing else: sessions, quotas, the AI spend ledger and the login throttle live in PostgreSQL.

Single points of failure today: the one PostgreSQL instance, and (if you run one) the one API instance. A database outage makes
`/ready` answer 503 and data routes answer 503 `service_unavailable` (not 500); the process recovers by itself.

## Build

```bash
pnpm install --frozen-lockfile
pnpm --filter "@wattbyte/api..." build         # compiles the workspace packages, then the API, and copies the .sql migrations
node scripts/smoke-production.mjs postgres://<admin>@<host>:5432/postgres     # optional: proves the compiled output (see below)
```

or the reference image (multi-stage, runs as `node`, healthcheck on `/health`, base image pinned by digest):

```bash
docker build -f apps/api/Dockerfile -t wattbyte-api:<git sha> .
```

Verified 2026-10-30 on a clean `git archive` of the commit: the image builds, `node dist/database/migrate.js` inside it applies
all migrations, the container turns `healthy`, `/ready` answers `{"status":"ok","database":"ok","schema":"ok"}`, the process
runs as user `node`, and `docker stop` ends it in about three seconds with exit code 0 (the process handles SIGTERM itself:
do not add `--init`; with Docker Desktop's `--init` the exit code was reported as 137 although the log showed a clean
shutdown). Not verified: a push to a registry, any orchestrator, TLS termination, running on amd64.

The base image digest in `apps/api/Dockerfile` is a reviewed pin, not a floating tag. Dependabot's `docker` entry opens the
update pull requests; read the Node release notes before merging one. `pnpm` itself is installed by corepack at build time at
the version in the root `package.json` (`packageManager`); that download is not hash-pinned.

## Deploy order

1. **Back up first** if the release contains a migration that is not purely additive (see "Migrations" below).
2. Run the migration as its own step with the **new** build, against the production database:
   `docker run --rm --env-file prod.env wattbyte-api:<sha> node dist/database/migrate.js` (or `pnpm --filter @wattbyte/api migrate:prod`).
   Look first with `... migrate.js --dry-run` / `--status`. It takes an advisory lock, so two runners cannot collide.
3. Start the new version. `/ready` answers 503 `"schema": "behind"` on a build whose newest migration is not applied yet, so a
   balancer never sends traffic to it early; `"ahead"` (a newer release already migrated) stays ready, which is what makes
   a rolling deploy and a rollback of the code possible.
4. Give the old process time to drain: on SIGTERM it flips `/ready` to 503 at once, waits `SHUTDOWN_DRAIN_MS` (3 s), closes the
   listener and exits, with a hard deadline of `SHUTDOWN_TIMEOUT_MS` (25 s). Set the orchestrator's stop grace period above that
   (`docker stop -t 40`, `terminationGracePeriodSeconds: 40`).

`TRUST_PROXY_HOPS` / `TRUST_PROXY_CIDRS`, `DATABASE_SSL`, `JWT_SECRET`, the AI budget and the model prices must be set; the
process refuses to start otherwise (`docs/CONFIGURATION.md`, "Environments"). That refusal is exercised by the smoke test.

### Migrations: expand, deploy, contract

A release only **adds** (nullable column, new table, index built `CONCURRENTLY` in a `-- migrate:no-transaction` file). Code that
needs the addition ships with or after it. Removing the old shape is a later release, once no running build reads it. Migration
`0006` renamed live columns in place and was **not** zero-downtime (stop the old API, migrate, start the new one); do not repeat
that pattern. A destructive or lock-heavy migration needs a verified backup, a maintenance window and the product owner's
go-ahead; the runner cannot know that.

### Rolling back

There are no down-migrations. Rolling back the **code** is safe as long as the schema change was additive: the old build runs
on the newer schema (`"schema": "ahead"` is ready). Rolling back a destructive migration means restoring the backup or shipping
a compensating migration.

## Scheduled work: retention

`node dist/scripts/retention.js` (`retention:prod`; `--dry-run` only counts) purges expired sessions, old AI history and old
per-day quota counters, in batches, under an advisory lock, and prints **one JSON line** (`ranAt`, `cutoffs`, `rows`). It exits
non-zero on failure. Without it the documented retention (`docs/security.md`) silently stops being true, and nothing in the
API notices, so the schedule and its alarm are part of the deployment:

```cron
# every day at 03:17 UTC; the wrapper pages (or at least mails) on a non-zero exit and on an empty log line
17 3 * * *  docker run --rm --env-file /etc/wattbyte/prod.env wattbyte-api:current node dist/scripts/retention.js >> /var/log/wattbyte/retention.log 2>&1
```

Kubernetes: a `CronJob` with the same image and command, `concurrencyPolicy: Forbid`, `backoffLimit: 1`, and an alert on
`kube_job_status_failed` **and** on "no successful run in 26 hours" (a job that never starts fails silently otherwise). A
scheduled GitHub workflow cannot do this job: it has no network path to a private database.

## Backups and restore

PostgreSQL holds every account, session, device, daily aggregate and AI history row; there is no other copy.

* **Backups: your decision.** Either the provider's snapshots plus point-in-time recovery, or a nightly
  `pg_dump -Fc --no-owner "$DATABASE_URL" > wattbyte-$(date +%F).dump` shipped off the host and encrypted. Pick a recovery point
  objective you can defend (a nightly dump = up to 24 hours of lost sign-ups and synced days).
* **Restore drill (do it once before launch, then quarterly).** Into a scratch database, never over production:
  `createdb wb_restore && pg_restore --no-owner -d wb_restore wattbyte-<date>.dump`, then
  `DATABASE_URL=.../wb_restore node dist/database/migrate.js --status` (no `modified`, no `unknown`; `pending` lists what the
  backup predates) and a row-count comparison of `users`, `devices`, `daily_usage` against the source. Record the date and the
  time it took. The dump/restore/compare steps were exercised on a clone of the development database during the audit
  remediation (row counts and checksums identical); a restore from *your* backup system has not been.
* **Erasure vs. backups (legal question).** A restored backup brings back accounts that were deleted after it was taken. Decide
  with the data-protection owner how long backups live and how erasures are re-applied after a restore (for example a log of
  `DELETE /me` user ids replayed after every restore). This repository cannot decide that.

## Monitoring

* `GET /health`: the process is alive (never touches the database). Use it for liveness and the container `HEALTHCHECK`.
* `GET /ready`: database reachable **and** schema current. Use it for the balancer. `schema: behind` is a deploy mistake.
* Logs are JSON lines with a `reqId` that is also returned as `x-request-id`; error messages are replaced by `omitted` on
  purpose (privacy), so correlate by `reqId` and route (see the open item below).
* Alert on: sustained 5xx or 503 `service_unavailable`; `/ready` 503 for more than a minute; the retention job (above);
  PostgreSQL disk, connections and replication lag (your provider's metrics); AI spend against `AI_BUDGET_DAILY_USD`
  (at a limit the request is a 503 `ai_unavailable` and the log says `budget_exceeded`; see `docs/ai.md`).
* There is **no metrics endpoint and no tracing** yet. Counting 5xx per route needs the access log or the proxy's metrics.

## The compiled-output smoke test

`node scripts/smoke-production.mjs <admin database url>` (CI job `api-production`; `pnpm smoke:prod`) creates a throw-away role and
database on the given server, then proves, against the **compiled** output and a production environment: the production guards
refuse a missing/placeholder `JWT_SECRET`, mock AI, the docker-compose credentials and an unset `DATABASE_SSL`; `migrate.js`
applies every migration and `--status` shows none pending; `main.js` boots and `/health` and `/ready` (`schema: ok`) answer;
register, login, refresh (including the retry inside the grace window) and an authenticated call work; both retention runs print
their JSON line; SIGTERM ends the server with exit code 0. It drops the role and database afterwards. It does **not** cover TLS
to PostgreSQL (`DATABASE_SSL=1` needs a server with a certificate), the AI providers, or any hosting platform.
