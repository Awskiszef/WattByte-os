// Documentation checks (audit E-18, E-19):
//
//   node scripts/check-docs.mjs
//
//  1. every top-level docs/*.md is listed in docs/README.md (an index nobody has to remember to update);
//  2. every relative link in README.md, apps/mobile/README.md and docs/*.md points at a file or directory that exists;
//  3. the pages that describe how the system works do not call implemented things "planned" or "future".
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { isMainModule } from './is-main.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

/** Pages that must describe the present, not a plan. */
export const PRESENT_TENSE_PAGES = ['README.md', 'docs/architecture.md', 'docs/DEVELOPMENT.md'];
export const STALE_MARKER = /\[future\]|\b(?:planned|future work|not yet|nothing is uploaded)\b/i;

/** `[text](target)` links whose target is a relative path, as `{ line, target }` (anchors and queries stripped). */
export function relativeLinks(text) {
  const out = [];
  let inFence = false;
  text.split(/\r?\n/).forEach((line, i) => {
    if (/^\s*```/.test(line)) inFence = !inFence;
    if (inFence) return;
    for (const m of line.matchAll(/\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g)) {
      const target = m[1];
      if (/^(?:[a-z][a-z0-9+.-]*:|#|\/\/)/i.test(target)) continue;
      const clean = target.split('#')[0].split('?')[0];
      if (clean) out.push({ line: i + 1, target: clean });
    }
  });
  return out;
}

export function indexProblems(docsDir, indexText) {
  const problems = [];
  for (const f of readdirSync(docsDir).filter((n) => n.endsWith('.md') && n !== 'README.md').sort()) {
    if (!indexText.includes(`(${f})`)) problems.push(`docs/${f} is not linked from docs/README.md`);
  }
  return problems;
}

export function check(base = root) {
  const problems = [];
  const docsDir = path.join(base, 'docs');
  const indexFile = path.join(docsDir, 'README.md');
  if (!existsSync(indexFile)) return ['docs/README.md is missing'];
  problems.push(...indexProblems(docsDir, readFileSync(indexFile, 'utf8')));

  const pages = ['README.md', 'apps/mobile/README.md', ...readdirSync(docsDir).filter((n) => n.endsWith('.md')).map((n) => `docs/${n}`)];
  for (const rel of pages) {
    const file = path.join(base, rel);
    if (!existsSync(file)) continue;
    const text = readFileSync(file, 'utf8');
    for (const { line, target } of relativeLinks(text)) {
      if (!existsSync(path.resolve(path.dirname(file), decodeURIComponent(target)))) problems.push(`${rel}:${line}: link target ${target} does not exist`);
    }
  }
  for (const rel of PRESENT_TENSE_PAGES) {
    const file = path.join(base, rel);
    if (!existsSync(file)) continue;
    readFileSync(file, 'utf8').split(/\r?\n/).forEach((l, i) => {
      if (STALE_MARKER.test(l)) problems.push(`${rel}:${i + 1}: "${l.trim().slice(0, 80)}" reads like a plan; this page describes what exists`);
    });
  }
  return problems;
}

if (isMainModule(import.meta.url)) {
  const problems = check();
  for (const p of problems) console.error(p);
  console.log(`check-docs: ${problems.length} problem(s)`);
  process.exit(problems.length ? 1 : 0);
}
