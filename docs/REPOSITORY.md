# Repository hygiene

What Git ignores, what is tracked on purpose, and how to check what a commit would contain. Nothing in this repository is allowed to
be a credential, a signing key, a database dump or a file that names somebody's private infrastructure.

## What is ignored

Root `.gitignore`, plus nested files in `apps/mobile`, `apps/mobile/ios`, `apps/mobile/android` and `apps/web`, and a root `.gitattributes`.

| Ignored | Examples |
|---|---|
| Secrets and signing material | `.env`, `.env.*`, `*.env` (but `.env.example` stays), `.dev.vars`, `*.jks`, `*.keystore`, `key.properties`, `*.p12`, `*.p8`, `*.pem`, `*.pfx`, `*.cer`, `*.mobileprovision`, `secrets/`, `id_rsa*`, `apps/mobile/ios/Flutter/Local.xcconfig` |
| Cloud and deployment state | `.wrangler/`, `.aws/`, `.terraform/`, `*.tfstate`, `*.tfvars`, `google-services.json`, `GoogleService-Info.plist`, service-account files, `apps/web/wrangler.jsonc` (your own copy of `wrangler.example.jsonc`) |
| Database dumps and backups | `*.dump`, `*.bak`, `*.sqlite`, `*.sql.gz`, `pg_dump*`, `backups/` |
| Build output and caches | `node_modules/`, `dist/`, `coverage/`, `build/`, `.dart_tool/`, `.gradle/`, `Pods/`, `DerivedData/`, `*.apk`, `*.aab`, `*.ipa`, `*.log` |
| Flutter-generated files | `ios/Flutter/Generated.xcconfig`, `ios/Flutter/ephemeral/`, `GeneratedPluginRegistrant.*`, `lib/l10n/generated/` (recreated by `flutter pub get`) |
| Editor and OS files | `.DS_Store`, `.idea/`, `.vscode/*` (except `settings.json`) |

**Tracked on purpose:** `pnpm-lock.yaml`, `apps/mobile/pubspec.lock`, `apps/mobile/ios/Podfile` and `Podfile.lock`,
`packages/contracts/openapi/openapi.json`, the generated Dart client `apps/mobile/lib/generated/api/**`, and the templates
`apps/api/.env.example`, `apps/web/.env.example`, `apps/web/wrangler.example.jsonc`, `apps/mobile/android/key.properties.example`,
`apps/mobile/ios/Flutter/Local.xcconfig.example`, `apps/mobile/config/*.example.json`.

`.gitattributes` stores LF everywhere (`* text=auto eol=lf`) and marks generated files as `linguist-generated`.

## Local configuration: copy a template, never commit the copy

| You need | Copy | To (git-ignored) |
|---|---|---|
| API settings | `apps/api/.env.example` | `apps/api/.env` |
| Website settings | `apps/web/.env.example` | `apps/web/.env.local` |
| Cloudflare deployment | `apps/web/wrangler.example.jsonc` | `apps/web/wrangler.jsonc` |
| Mobile build defines | `apps/mobile/config/*.example.json` | `apps/mobile/config/<name>.json` |
| Android release signing | `apps/mobile/android/key.properties.example` | `apps/mobile/android/key.properties` |
| iOS signing team | `apps/mobile/ios/Flutter/Local.xcconfig.example` | `apps/mobile/ios/Flutter/Local.xcconfig` |

## Checking what would be committed

```bash
git status --porcelain --untracked-files=all          # what a commit would add
git check-ignore -v -- <path>                         # which rule ignores a path
node scripts/secret-scan.mjs --list-files             # the files the secret scanner reads
node scripts/secret-scan.mjs                          # nothing that looks like a credential (masked output)
node scripts/check-public-config.mjs                  # configuration policy: file names, unknown config files, account-specific values
node scripts/check-public-config.mjs --history        # the same over every commit, including author addresses and commit messages
```

CI runs the last three on every pull request (job `Public Configuration Security Gate` and `Hygiene`). A configuration file the policy
does not know fails until it is listed, with a reason, in `scripts/public-config.allowlist.json`.

## Before you push

* Everything you push is readable by anyone, and a force-push or a deleted branch does not remove it from clones and caches.
* The name and e-mail address of every commit become public with it. GitHub offers a `noreply` address (Settings → Emails → "Keep my email addresses private").
* If you committed a secret by mistake, treat it as leaked: revoke it first, then remove it from the history.
