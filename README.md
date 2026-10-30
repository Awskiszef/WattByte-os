# WattByte

Local-first mobile app that shows how much data and energy a phone uses, plus a
small TypeScript backend for accounts, aggregate sync and AI summaries.

```
wattbyte/
├── apps/
│   ├── mobile/        Flutter app (Android + iOS) + local plugin packages/wattbyte_system
│   ├── api/           TypeScript REST API (Fastify, PostgreSQL, Zod, OpenAPI) + reference Dockerfile
│   ├── web/           Marketing website wattbyte.app (Next.js, Tailwind; see apps/web/README.md)
│   └── ai/            AI Gateway library (OpenAI / Anthropic / Google / xAI: routing, retry, fallback, spend limits)
├── packages/
│   ├── contracts/     Zod contracts shared by the API + generated openapi/openapi.json
│   └── device-specs/  The device battery catalogue (also bundled into the app)
├── infrastructure/docker/   local PostgreSQL (wattbyte + wattbyte_test)
├── scripts/           Dart client generation (pinned generator), secret scan, workflow checks, DB helpers, production smoke test
├── docs/              start at docs/README.md
└── .github/workflows/ ci.yml (scope-aware CI incl. macOS), release.yml (manual, gated, signed builds)
```

Boundaries (see `docs/architecture.md`):

- **Flutter** owns system APIs, calculations, local storage, offline-first behaviour and sync queueing.
- **API** owns accounts, auth, cloud sync of per-day aggregates, quotas and AI access.
- **AI** only interprets already computed numbers (insights, summaries, roast). It never calculates.

## Prerequisites

- Node **22.9+** (`.nvmrc`), pnpm 11.9.0, Docker (local PostgreSQL). pnpm: `corepack enable` on Node up to 24; on Node 25+
  corepack is gone, use `npm install -g pnpm@11.9.0` or `npx pnpm@11.9.0 <command>`.
- Flutter stable (CI: 3.41.6), Java 17+, Android SDK; Xcode for iOS.

All versions, the Windows notes and the maintainer notes: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Backend quickstart

```bash
pnpm install
pnpm db:up                                   # PostgreSQL in Docker; port 5432 taken? WB_PG_PORT=55432 pnpm db:up (and the same port in .env)
cp apps/api/.env.example apps/api/.env       # works as it is in development (mock AI, placeholder secret)
pnpm db:migrate                              # the API scripts load apps/api/.env themselves
pnpm --filter @wattbyte/api dev              # http://localhost:8080/health, /ready, /openapi.json
```

Every API environment variable and the rules for staging and production: [docs/CONFIGURATION.md](docs/CONFIGURATION.md).
Running it for real (image, migrations, backups, scheduling, monitoring): [docs/OPERATIONS.md](docs/OPERATIONS.md).

## Mobile quickstart

```bash
cd apps/mobile
flutter pub get && flutter gen-l10n
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8080     # iOS simulator; Android emulator: http://10.0.2.2:8080
flutter run --dart-define=LOCAL_ONLY_DEV=true                     # no backend, no account; debug builds only
```

Every build needs a backend address: a build without one is an invalid configuration, not a local app. The defines, the
build modes, the release guard and the staging/production commands have one home:
[docs/CONFIGURATION_MOBILE.md](docs/CONFIGURATION_MOBILE.md).

## Tests

```bash
pnpm lint && pnpm typecheck && pnpm build
pnpm test:db          # API tests including the PostgreSQL suites (plain `pnpm test` skips them and says so)
pnpm test:scripts     # the repository scripts
pnpm secret-scan      # nothing that looks like a credential in what would be committed (masked output)
pnpm ci:local         # the TypeScript part of CI in one command (not the mobile, audit or end-to-end jobs)
cd apps/mobile && flutter analyze && flutter test
```

What each CI job runs and its local equivalent: [docs/CI.md](docs/CI.md). OpenAPI and the generated Dart client:
`pnpm openapi`, `pnpm dart-client` ([docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)).

## Contributing

Contributions are welcome through pull requests; `main` changes only with a green CI result. How to branch, what to run and the
rules that never bend: [CONTRIBUTING.md](CONTRIBUTING.md). The pipelines and what is enforced: [docs/CI_CD.md](docs/CI_CD.md).

## Security

Report vulnerabilities privately, never as a public issue: [SECURITY.md](SECURITY.md).

## License

WattByte is licensed under the [Apache License, Version 2.0](LICENSE) ([NOTICE](NOTICE)). The name and logo are not covered by
the license (section 6). Third-party material and its licenses are listed in `NOTICE`.

## Documentation

[docs/README.md](docs/README.md) is the index: start here, reference, operations, privacy and security, verification reports,
history. The most used: [architecture](docs/architecture.md), [API](docs/api.md), [API configuration](docs/CONFIGURATION.md),
[mobile configuration](docs/CONFIGURATION_MOBILE.md), [CI](docs/CI.md), [release](docs/RELEASE.md),
[privacy](docs/privacy.md), [security](docs/security.md). The git status of this folder and what would be committed:
[docs/REPOSITORY.md](docs/REPOSITORY.md).
