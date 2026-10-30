// Secret scan over the WHOLE Git history (every commit of every branch), not only the current files:
//
//   node scripts/secret-scan-history.mjs [--allow FILE] [--json]
//
// The current-tree scan (secret-scan.mjs) cannot see a key that was committed and deleted later; it stays in history and
// goes public with the first push. This reads the added lines of every commit with the same rules, the same masking and
// the same allowlist, and also reports any commit that ever added a file the tree scan treats as sensitive by name
// (.env, keystores, key.properties, ...). Output is masked: commit, path, rule and the first characters of the value.
// Exit code: 0 clean, 1 findings, 2 usage or git error.
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { isMainModule } from './is-main.mjs';
import { isAllowed, loadAllowlist, scanText, sensitiveKind } from './secret-scan.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const defaultAllow = path.join(path.dirname(fileURLToPath(import.meta.url)), 'secret-scan.allow.json');

/**
 * Parses `git log -p -U0 --format=@@@%H` output into `{ commit, file, lines: [text...] }` (added lines only; `lines` joined
 * per file so multi-line constructs such as a PEM header and its body stay together).
 */
export function parseAddedLines(log) {
  const out = [];
  let commit = '';
  let file = null;
  let lines = [];
  const flush = () => {
    if (file && lines.length) out.push({ commit, file, text: lines.join('\n') });
    lines = [];
  };
  for (const line of log.split('\n')) {
    if (line.startsWith('@@@')) {
      flush();
      file = null;
      commit = line.slice(3).trim();
    } else if (line.startsWith('+++ ')) {
      flush();
      file = line.startsWith('+++ b/') ? line.slice(6) : null; // /dev/null = a deletion
    } else if (line.startsWith('+') && file) lines.push(line.slice(1));
  }
  flush();
  return out;
}

export function scanHistory({ cwd = root, allowFile = defaultAllow } = {}) {
  const git = (args) => execFileSync('git', args, { cwd, encoding: 'utf8', maxBuffer: 1024 * 1024 * 1024 });
  const { entries, errors } = loadAllowlist(allowFile);
  const findings = [];
  const allowed = [];
  const commits = git(['rev-list', '--all']).split('\n').filter(Boolean).length;

  for (const { commit, file, text } of parseAddedLines(git(['log', '--all', '-p', '-U0', '--no-color', '--no-ext-diff', '--format=@@@%H']))) {
    const base = file.split('/').at(-1);
    if (/\.(png|jpe?g|gif|webp|ico|pdf|wav|mp[34]|ttf|otf|woff2?|jar|zip|gz|sqlite|db)$/i.test(base) || /(^|\/)(pnpm-lock\.yaml|pubspec\.lock|Podfile\.lock)$/.test(file)) continue;
    for (const hit of scanText(file, text)) {
      const item = { commit: commit.slice(0, 10), ...hit.finding, line: undefined };
      const entry = isAllowed(entries, hit);
      (entry ? allowed : findings).push(entry ? { ...item, allowedBy: entry.id } : item);
    }
  }

  // Files that were ever added and are sensitive by name, even if deleted since.
  const names = git(['log', '--all', '--diff-filter=A', '--name-only', '--no-color', '--format=@@@%H']).split('\n');
  let commit = '';
  for (const line of names) {
    if (line.startsWith('@@@')) commit = line.slice(3, 13);
    else if (line.trim()) {
      const kind = sensitiveKind(line.split('/').at(-1));
      if (kind) findings.push({ commit, file: line, rule: 'sensitive-file', masked: '(contents not read)', note: `${kind} was committed` });
    }
  }
  return { commits, findings, allowed, errors };
}

if (isMainModule(import.meta.url)) {
  const args = process.argv.slice(2);
  const allowIdx = args.indexOf('--allow');
  const allowFile = allowIdx >= 0 ? path.resolve(args[allowIdx + 1] ?? '') : defaultAllow;
  let result;
  try {
    result = scanHistory({ allowFile });
  } catch (e) {
    console.error(`secret-scan-history: ${e instanceof Error ? e.message : e}`);
    process.exit(2);
  }
  if (args.includes('--json')) console.log(JSON.stringify(result, null, 2));
  else {
    for (const err of result.errors) console.error(`secret-scan-history: ERROR ${err}`);
    for (const f of result.findings) console.error(`${f.commit}  ${f.file}  [${f.rule}]  ${f.masked}  ${f.note}`);
    console.log(`secret-scan-history: ${result.commits} commits, ${result.findings.length} finding(s), ${result.allowed.length} allowlisted`);
  }
  process.exit(result.findings.length || result.errors.length ? 1 : 0);
}
