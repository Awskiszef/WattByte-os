# Documentation

Where things are. Everything here is English unless the table says otherwise; user-visible app strings are in the ARB files
(`apps/mobile/lib/l10n`, English and Polish).
`scripts/check-docs.mjs` (CI job `hygiene`, `pnpm docs:check`) fails when a file in this folder is missing from this index,
when a relative link in the README or in any page here points nowhere, or when the architecture page goes back to calling
implemented things "planned".

## Start here

| Page | What it answers |
|---|---|
| [../README.md](../README.md) | Quickstarts for the backend and the app |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Prerequisites, first run, every test command, what `pnpm ci:local` does and does not cover |
| [architecture.md](architecture.md) | Layers, data flow, modules, contracts |
| [PROJECT_STATUS.md](PROJECT_STATUS.md) | What exists, and what not to assume about a pre-release project |

## Reference

| Page | What it answers |
|---|---|
| [CONFIGURATION.md](CONFIGURATION.md) | Every API environment variable, the rules per environment, migrations, boot and readiness |
| [CONFIGURATION_MOBILE.md](CONFIGURATION_MOBILE.md) | Build defines, build modes, the release guard, feature flags (the one place the define matrix lives) |
| [api.md](api.md) | Endpoints and conventions |
| [API_COMPATIBILITY.md](API_COMPATIBILITY.md) | What may change in `/api/v1` while installed apps are out there |
| [ai.md](ai.md) | The AI gateway: providers, routing, retries, spend limits, prompts |
| [AUTO_SETUP.md](AUTO_SETUP.md) | Region, currency, device and price detection after sign-up |
| [BATTERY_CAPACITY.md](BATTERY_CAPACITY.md) | Where the battery capacity comes from and how reliable it is |
| [SETTING_SOURCES.md](SETTING_SOURCES.md) | Which source a setting came from and which one wins |
| [SYNC_OWNERSHIP.md](SYNC_OWNERSHIP.md) | Who owns local data versus account data, account switching |
| [CLOUD_DATA.md](CLOUD_DATA.md) | What is uploaded, exported and erased |
| [PLATFORM_SUPPORT.md](PLATFORM_SUPPORT.md) | What each OS version can and cannot measure |
| [ACCESSIBILITY_DATA_SCREENS.md](ACCESSIBILITY_DATA_SCREENS.md) | Accessibility of the data screens |

## Operations and release

| Page | What it answers |
|---|---|
| [OPERATIONS.md](OPERATIONS.md) | Running the API: image, deploy order, rollback, retention schedule, backups and restore, monitoring |
| [CI_CD.md](CI_CD.md) | The GitHub side: workflows, repository settings that are active, what the plan does not allow, environments |
| [CI.md](CI.md) | The pipeline, the local command for each job, the release workflow and its secrets |
| [CI_OPTIMIZATION_BASELINE.md](CI_OPTIMIZATION_BASELINE.md) | What the CI cost before it was scoped: runs, jobs, minutes (measured) |
| [CI_OPTIMIZATION_REPORT.md](CI_OPTIMIZATION_REPORT.md) | Before and after, what is estimated, what could have been lost |
| [ZOD4_MIGRATION.md](ZOD4_MIGRATION.md) | Plan and risks of the zod 3 to 4 migration (removes the last audit exception) |
| [RELEASE.md](RELEASE.md) | Store checklist, signing, what needs an Apple or Google account |
| [REPOSITORY.md](REPOSITORY.md) | What Git ignores, what is tracked on purpose, local configuration templates, how to check what a commit would contain |
| [DEVICE_TEST_PLAN.md](DEVICE_TEST_PLAN.md) | What to check on real phones |

## Privacy and security

| Page | What it answers |
|---|---|
| [privacy.md](privacy.md) | What the app and the API collect, where it goes, retention (technical description, not legal advice) |
| [security.md](security.md) | Authentication, sessions, limits, retention, threat notes |

## Verification, audit and history

| Page | What it answers |
|---|---|
| [REGRESSION_TESTS.md](REGRESSION_TESTS.md) | The regression suites and how to run them |
| [VERIFICATION_STATUS.md](VERIFICATION_STATUS.md) | What the status words (TESTED, BUILD VERIFIED, BLOCKED, ...) mean |

The mobile app's own notes are in [../apps/mobile/README.md](../apps/mobile/README.md) (**Polish**).
