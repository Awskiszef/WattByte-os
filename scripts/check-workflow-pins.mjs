// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// Static checks on the GitHub workflows (audit E-09, E-10, E-20):
//
//   node scripts/check-workflow-pins.mjs [workflow files...]      (default: .github/workflows/*.yml)
//
//  1. every `uses:` of a remote action is pinned to a full 40-character commit SHA (a tag can be moved);
//  2. in release.yml every job except `guard` depends on `guard` (directly or through another job), so a new job cannot
//     bypass the branch and CI gate;
//  3. in release.yml only the jobs listed in SECRET_JOBS read `secrets.*`: the job that builds third-party code
//     (android-build) holds none;
//  4. in ci.yml the job `public-config` (the Public Configuration Security Gate) does not choose its gate with hashFiles(), a file the
//     change under test controls, and fails when no gate step ran and passed.
// This is a text check, not a YAML parser: it relies on the layout the workflows already use (two-space job keys).
import { readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { isMainModule } from './is-main.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const SECRET_JOBS = new Set(['android-sign', 'ios-archive']);

/** Remote `uses:` lines that are not pinned to a commit SHA. */
export function findUnpinned(text) {
  const bad = [];
  text.split(/\r?\n/).forEach((line, i) => {
    const m = line.match(/^\s*(?:-\s+)?uses:\s*([^\s#]+)/);
    if (!m) return;
    const ref = m[1];
    if (ref.startsWith('./') || ref.startsWith('docker://')) return;
    if (!/@[0-9a-f]{40}$/.test(ref)) bad.push({ line: i + 1, uses: ref });
  });
  return bad;
}

/** Splits the `jobs:` section into `{ name, body }` blocks. */
export function jobBlocks(text) {
  const lines = text.split(/\r?\n/);
  const start = lines.findIndex((l) => /^jobs:\s*$/.test(l));
  if (start === -1) return [];
  const blocks = [];
  for (let i = start + 1; i < lines.length; i += 1) {
    const m = lines[i].match(/^ {2}([A-Za-z0-9_-]+):\s*$/);
    if (m) blocks.push({ name: m[1], lines: [] });
    else if (blocks.length && !/^\S/.test(lines[i])) blocks.at(-1).lines.push(lines[i]);
    else if (/^\S/.test(lines[i]) && lines[i].trim()) break; // next top-level key
  }
  return blocks.map((b) => ({ name: b.name, body: b.lines.join('\n') }));
}

function needsOf(body) {
  const inline = body.match(/^ {4}needs:\s*\[([^\]]*)\]/m) ?? body.match(/^ {4}needs:\s*([A-Za-z0-9_-]+)\s*$/m);
  return inline ? inline[1].split(',').map((s) => s.trim()).filter(Boolean) : [];
}

/** Problems with the release workflow's gate and its secret scope. */
export function checkRelease(text) {
  const problems = [];
  const jobs = jobBlocks(text);
  const byName = new Map(jobs.map((j) => [j.name, j]));
  if (!byName.has('guard')) problems.push('release.yml has no `guard` job');
  const dependsOnGuard = (name, seen = new Set()) => {
    if (name === 'guard') return true;
    if (seen.has(name)) return false;
    seen.add(name);
    return needsOf(byName.get(name)?.body ?? '').some((n) => dependsOnGuard(n, seen));
  };
  for (const job of jobs) {
    if (job.name !== 'guard' && !dependsOnGuard(job.name)) problems.push(`job ${job.name} does not depend on guard`);
    if (/\bsecrets\./.test(job.body) && !SECRET_JOBS.has(job.name)) problems.push(`job ${job.name} reads secrets but is not one of ${[...SECRET_JOBS].join(', ')}`);
    if (SECRET_JOBS.has(job.name) && !/^ {4}environment:\s*release\s*$/m.test(job.body)) problems.push(`job ${job.name} is not in the release environment`);
  }
  return problems;
}

/** Problems with the Public Configuration Security Gate job of ci.yml, which is a required check. */
export function checkPublicGate(text) {
  const job = jobBlocks(text).find((j) => j.name === 'public-config');
  if (!job) return ['ci.yml has no `public-config` job'];
  const problems = [];
  // Comments may name hashFiles() to explain the rule; only the lines of the workflow itself count.
  const body = job.body.split('\n').filter((line) => !/^\s*#/.test(line)).join('\n');
  // A pull request can add or remove a file, so a file must not decide which gate runs, or whether one runs at all.
  if (/hashFiles\(/.test(body)) problems.push('job public-config uses hashFiles(): a file of the change under test would choose its gate');
  // Choosing steps is not enough: a job whose steps are all skipped still succeeds.
  if (!/steps\.[A-Za-z0-9_]+\.outcome/.test(body)) problems.push('job public-config passes when every gate step is skipped (no step checks their outcome)');
  return problems;
}

export function check(files) {
  const problems = [];
  for (const file of files) {
    const text = readFileSync(file, 'utf8');
    for (const b of findUnpinned(text)) problems.push(`${path.relative(root, file)}:${b.line}: ${b.uses} is not pinned to a commit SHA`);
    if (path.basename(file) === 'release.yml') for (const p of checkRelease(text)) problems.push(`${path.relative(root, file)}: ${p}`);
    if (path.basename(file) === 'ci.yml') for (const p of checkPublicGate(text)) problems.push(`${path.relative(root, file)}: ${p}`);
  }
  return problems;
}

if (isMainModule(import.meta.url)) {
  const dir = path.join(root, '.github', 'workflows');
  const args = process.argv.slice(2);
  const files = args.length ? args.map((a) => path.resolve(a)) : readdirSync(dir).filter((f) => /\.ya?ml$/.test(f)).map((f) => path.join(dir, f));
  const problems = check(files);
  for (const p of problems) console.error(p);
  console.log(`check-workflow-pins: ${files.length} workflow(s), ${problems.length} problem(s)`);
  process.exit(problems.length ? 1 : 0);
}
