// Decides which CI jobs a change needs.
//
//   node scripts/ci-changes.mjs --base <sha> [--head HEAD] --event pull_request|push|schedule|workflow_dispatch
//
// It lists the files changed between --base and --head, classifies every path and writes one `name=value` line per job
// flag to $GITHUB_OUTPUT (and a table to $GITHUB_STEP_SUMMARY). The job `CI result` (scripts/ci-gate.mjs) then requires
// a job to have succeeded when its flag is true and accepts "skipped" only when it is false, so a skipped job can never
// count as a passed one for a change that needed it.
//
// Rules of thumb that are built in on purpose:
//   * A path that matches no rule is "unknown" and switches everything on (except iOS). Adding a directory without a
//     rule makes CI slower, never blind.
//   * Nothing narrows the checks of `hygiene` (secrets, history, dependency audit, docs, workflow pins, script tests):
//     it runs for every change, including a documentation-only one.
//   * Shared inputs (lockfile, workspace files, toolchain versions, the workflows themselves) widen the scope instead of
//     narrowing it.
import { spawnSync } from 'node:child_process';
import { appendFileSync } from 'node:fs';

import { isMainModule } from './is-main.mjs';

/** Path rules. A file may match several; `set` lists the facts it establishes. First match of the `exclusive` kind wins. */
export const RULES = [
  // Documentation and repository metadata: only `hygiene` needs to look at these.
  { re: /^docs\//, set: ['docs'] },
  { re: /^[^/]+\.md$/, set: ['docs'] },
  { re: /^(LICENSE|NOTICE)$/, set: ['docs'] },
  { re: /^apps\/[^/]+\/(README|CHANGELOG)\.md$/, set: ['docs'] },
  { re: /^apps\/[^/]+\/docs\//, set: ['docs'] },
  { re: /^\.github\/(CODEOWNERS|dependabot\.yml|pull_request_template\.md|ISSUE_TEMPLATE\/|rulesets\/|FUNDING\.yml)/, set: ['docs'] },
  { re: /^(\.gitattributes|\.gitignore|\.gitleaks\.toml|\.githooks\/|\.claude\/|\.dockerignore)/, set: ['docs'] },
  // Hygiene runs the unit tests of these scripts on every change, so a change to one needs nothing else.
  { re: /^scripts\/(secret-scan|check-docs|is-main|github-protect-main)[^/]*$/, set: ['docs'] },

  // The workflows and the scripts that drive them change what CI does: everything must prove itself.
  { re: /^\.github\/workflows\//, set: ['ci_config'] },
  { re: /^scripts\/ci-[^/]*$/, set: ['ci_config'] },
  { re: /^scripts\/check-workflow-pins[^/]*$/, set: ['ci_config'] },

  // TypeScript workspace inputs shared by every package.
  { re: /^(package\.json|pnpm-lock\.yaml|pnpm-workspace\.yaml|tsconfig\.base\.json|eslint\.config\.js|\.nvmrc)$/, set: ['root_ts'] },
  { re: /^openapitools\.json$/, set: ['contracts', 'mobile'] },

  { re: /^apps\/web\//, set: ['web'] },
  { re: /^apps\/ai\//, set: ['ai'] },
  { re: /^packages\/contracts\/openapi\//, set: ['contracts', 'mobile'] },
  { re: /^packages\/contracts\//, set: ['contracts'] },
  { re: /^packages\/device-specs\//, set: ['devspecs', 'mobile'] },
  { re: /^apps\/api\/(Dockerfile|\.dockerignore)$/, set: ['api', 'docker'] },
  { re: /^apps\/api\//, set: ['api'] },
  { re: /^infrastructure\//, set: ['api'] },

  // The generator, the drift checks and the production smoke test sit between the API and the app.
  { re: /^scripts\/(generate-dart-client|dart-client-postprocess|openapi-generator|check-generated-client|check-openapi-compat|check-device-specs|copy-migrations|smoke-|wait-for-db|test-db|fake-eurostat)[^/]*$/, set: ['api', 'contracts', 'mobile'] },

  // Mobile. The more specific native rules come first so that an iOS file does not also count as an Android one.
  { re: /^apps\/mobile\/lib\/generated\//, set: ['mobile', 'generated_client'] },
  { re: /^apps\/mobile\/(ios\/|packages\/wattbyte_system\/ios\/|tool\/check_widget_links\.sh$)/, set: ['mobile', 'ios'] },
  { re: /^apps\/mobile\/(android\/|packages\/wattbyte_system\/android\/|tool\/check_release_guard\.sh$)/, set: ['mobile', 'android_native'] },
  { re: /^apps\/mobile\/(pubspec\.(yaml|lock)|packages\/[^/]+\/pubspec\.(yaml|lock))$/, set: ['mobile', 'ios', 'android_native'] },
  { re: /^apps\/mobile\//, set: ['mobile'] },
];

const NON_DOC_FACTS = ['ci_config', 'root_ts', 'web', 'ai', 'contracts', 'devspecs', 'api', 'docker', 'mobile', 'ios', 'android_native', 'generated_client', 'unknown'];

/** Facts established by a list of changed paths. */
export function factsFor(files) {
  const facts = new Set();
  for (const file of files) {
    const hits = RULES.filter((r) => r.re.test(file));
    if (hits.length === 0) {
      facts.add('unknown');
      continue;
    }
    // Documentation rules are exclusive: apps/mobile/README.md is a document, not a change to the app.
    if (hits.some((r) => r.set.includes('docs'))) {
      facts.add('docs');
      continue;
    }
    // The other rules are additive: an iOS file also counts as a mobile file.
    for (const r of hits) for (const f of r.set) facts.add(f);
  }
  return facts;
}

/** Date and time arithmetic is where the time-zone matrix earns its keep. */
export const TZ_SENSITIVE = /DateTime|LocalDate|TimeZone|timezone|DST|toLocal\(|toUtc\(|Duration\(|midnight|isUtc|\bTZ\b|DateFormat|Calendar/;

/**
 * @param {Iterable<string>} files changed paths, relative to the repository root
 * @param {{event: string, tzTouched?: boolean}} ctx
 */
export function decide(files, ctx) {
  const list = [...files];
  const facts = factsFor(list);
  const event = ctx.event;
  const nonDoc = NON_DOC_FACTS.filter((f) => facts.has(f));
  const areas = ['web', 'ai', 'contracts', 'devspecs', 'api', 'mobile'].filter((f) => facts.has(f));
  const unknown = facts.has('unknown');
  const scheduled = event === 'schedule' || event === 'workflow_dispatch';
  // FULL: the whole pipeline. On main only when a change reaches across components; pull requests get the scoped FAST pipeline
  // unless a shared input changed, which widens the scope to every dependent module.
  const wide = unknown || facts.has('root_ts') || facts.has('ci_config');
  const full = scheduled || (event === 'push' && (wide || areas.length >= 2));
  const everything = full || unknown || facts.has('ci_config');
  const all = (flag) => everything || flag;

  const tsAi = all(facts.has('ai') || facts.has('root_ts'));
  const tsContracts = all(facts.has('contracts') || facts.has('ai') || facts.has('root_ts'));
  const tsDevspecs = all(facts.has('devspecs') || facts.has('root_ts'));
  const tsApi = all(facts.has('api') || facts.has('contracts') || facts.has('ai') || facts.has('devspecs') || facts.has('root_ts'));
  const tsPackages = [tsAi && '@wattbyte/ai', tsContracts && '@wattbyte/contracts', tsDevspecs && '@wattbyte/device-specs', tsApi && '@wattbyte/api'].filter(Boolean);
  const web = all(facts.has('web') || facts.has('root_ts'));
  const mobile = all(facts.has('mobile'));
  const iosPaths = facts.has('ios') || facts.has('ci_config') || scheduled;
  const nodeMatrix = everything || facts.has('root_ts') ? ['22', '24'] : ['22'];
  const tzExtra = full || Boolean(ctx.tzTouched);
  const tzMatrix = tzExtra ? ['UTC', 'Europe/Warsaw', 'America/New_York'] : ['Europe/Warsaw'];

  return {
    docs_only: nonDoc.length === 0 && list.length > 0,
    full,
    // TypeScript packages (lint, typecheck, tests, build) with their dependents, see apps/*/package.json.
    ts: tsAi || tsContracts || tsDevspecs || tsApi,
    ts_filters: tsPackages.map((p) => `--filter ${p}`).join(' '),
    // A build needs the packages it imports, so each selected package is built together with its dependencies (`pkg...`).
    ts_build_filters: tsPackages.map((p) => `--filter ${p}...`).join(' '),
    ts_api: tsApi,
    node_matrix: JSON.stringify(nodeMatrix),
    web,
    api_production: all(tsApi || facts.has('docker')),
    contracts: all(facts.has('contracts') || facts.has('api') || facts.has('ai') || facts.has('devspecs') || facts.has('generated_client')),
    flutter_static: all(mobile),
    flutter_test: all(mobile),
    tz_matrix: JSON.stringify(tzMatrix),
    e2e: all(mobile || tsApi),
    android: all(mobile),
    android_full: all(facts.has('android_native')) || full,
    kotlin: all(facts.has('android_native')),
    ios: iosPaths,
    reasons: [
      `files=${list.length}`,
      `facts=${[...facts].sort().join(',') || 'none'}`,
      `event=${event}`,
      full ? 'FULL (' + (scheduled ? 'scheduled or manual' : wide ? 'shared input changed' : 'change spans several components') + ')' : 'FAST',
      ctx.tzTouched ? 'date/time code touched' : '',
    ].filter(Boolean),
  };
}

function git(args) {
  const r = spawnSync('git', args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')} failed: ${r.stderr}`);
  return r.stdout;
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 2) out[argv[i].replace(/^--/, '')] = argv[i + 1];
  return out;
}

if (isMainModule(import.meta.url)) {
  const args = parseArgs(process.argv.slice(2));
  const event = args.event ?? 'pull_request';
  const head = args.head ?? 'HEAD';
  let files;
  let tzTouched = false;
  let degraded = false;
  try {
    if (!args.base || /^0+$/.test(args.base)) throw new Error('no usable base commit');
    files = git(['diff', '--name-only', '--no-renames', args.base, head]).split('\n').filter(Boolean);
    tzTouched = git(['diff', '-G', TZ_SENSITIVE.source, '--name-only', args.base, head, '--', 'apps/mobile']).trim().length > 0;
  } catch (e) {
    // Unknown base (first push, force push, shallow clone): run everything rather than guess.
    degraded = true;
    files = ['<unknown change set>'];
    console.error(`ci-changes: ${e.message}; running the full pipeline`);
  }
  const d = decide(files, { event, tzTouched });
  if (degraded) d.reasons.push('base commit unavailable');
  const lines = Object.entries(d).filter(([k]) => k !== 'reasons').map(([k, v]) => `${k}=${v}`);
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, lines.join('\n') + '\n');
  const table = ['| flag | value |', '|---|---|', ...Object.entries(d).filter(([k]) => k !== 'reasons').map(([k, v]) => `| ${k} | \`${v}\` |`)];
  const summary = `### What this change needs\n\n${d.reasons.join(' · ')}\n\n${table.join('\n')}\n`;
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary);
  console.log(lines.join('\n'));
  console.log(d.reasons.join(' | '));
}
