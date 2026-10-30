// The single required check, "CI result".
//
//   NEEDS='<toJSON(needs)>' node scripts/ci-gate.mjs
//
// `needs` is the object GitHub hands to a job: { <job id>: { result, outputs } }. The `changes` job publishes one flag per
// job (scripts/ci-changes.mjs). The rules:
//   * `changes`, `hygiene` and `public-config` always run and must succeed;
//   * a job whose flag is "true" must have succeeded: skipped, cancelled, failed or missing all fail the gate;
//   * a job whose flag is "false" may be skipped (that is the point of the flag) or succeed, never fail or be cancelled.
// A skipped job is therefore never read as a pass for a change that needed it.
import { isMainModule } from './is-main.mjs';

/** Job id -> the `changes` output that switches it on. `null` = always required. */
export const JOB_FLAGS = {
  hygiene: null,
  // The Public Configuration Security Gate: no path filter may switch it off.
  'public-config': null,
  ts: 'ts',
  web: 'web',
  'api-production': 'api_production',
  contracts: 'contracts',
  'flutter-static': 'flutter_static',
  'flutter-test': 'flutter_test',
  e2e: 'e2e',
  android: 'android',
  kotlin: 'kotlin',
  ios: 'ios',
};

/** @returns {{ ok: boolean, lines: string[] }} */
export function gate(needs) {
  const lines = [];
  let ok = true;
  const fail = (m) => {
    ok = false;
    lines.push(`FAIL  ${m}`);
  };
  const changes = needs.changes;
  if (!changes || changes.result !== 'success') {
    fail(`changes: ${changes ? changes.result : 'missing'} (the job that decides the scope must succeed)`);
    return { ok, lines };
  }
  const flags = changes.outputs ?? {};
  for (const [job, flag] of Object.entries(JOB_FLAGS)) {
    const n = needs[job];
    const result = n ? n.result : 'missing';
    const required = flag === null || flags[flag] === 'true';
    if (flag !== null && flags[flag] !== 'true' && flags[flag] !== 'false') {
      fail(`${job}: scope flag "${flag}" is "${flags[flag]}" (neither true nor false)`);
    } else if (required) {
      if (result === 'success') lines.push(`ok    ${job}: success (required)`);
      else fail(`${job}: ${result} but this change needs it`);
    } else if (result === 'skipped' || result === 'success') {
      lines.push(`ok    ${job}: ${result} (not needed by this change)`);
    } else {
      fail(`${job}: ${result} (not needed, but it must not fail either)`);
    }
  }
  for (const job of Object.keys(needs)) {
    if (job !== 'changes' && !(job in JOB_FLAGS)) fail(`${job}: a job without a rule in scripts/ci-gate.mjs`);
  }
  return { ok, lines };
}

if (isMainModule(import.meta.url)) {
  let needs;
  try {
    needs = JSON.parse(process.env.NEEDS ?? '');
  } catch {
    console.error('ci-gate: NEEDS is missing or not JSON');
    process.exit(2);
  }
  const { ok, lines } = gate(needs);
  console.log(lines.join('\n'));
  if (!ok) {
    console.error('::error::CI result: at least one job failed, was cancelled or was skipped although the change needed it');
    process.exit(1);
  }
  console.log('CI result: every job this change needs has succeeded');
}
