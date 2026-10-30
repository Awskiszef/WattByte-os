// Public Configuration Security Gate: nothing private may be in a public checkout or in its history.
//
//   node scripts/check-public-config.mjs [--root <dir>] [--history] [--strict-refs] [--allow-tag <name>]...
//                                        [--allowlist <file>] [--deny-literals <file>] [--manifest]
//
// Default (working tree): every tracked file, plus untracked files git does not ignore.
// --history: also every path ever added, every added line, the author and committer address of every commit, the commit
//            messages and (with --strict-refs) the refs. This is what decides whether a history may be published.
//
// Policy (docs/CONFIGURATION.md, "Public configuration"): PRIVATE_CONFIG_DENY_BY_DEFAULT.
//   * a file whose NAME is private (env file, key, keystore, provisioning profile, Firebase/service-account file, Terraform
//     state, database dump, real wrangler config, advertising material, agent tooling) fails, whatever its content;
//   * a configuration-LIKE file (json, yaml, toml, plist, xcconfig, gradle, ...) that no entry of the reviewed allowlist
//     (scripts/public-config.allowlist.json) covers fails: unknown configuration stays excluded until someone classifies it;
//   * a file's CONTENT is scanned for credentials, account-specific infrastructure values, connection strings with
//     embedded credentials, local paths and business registry numbers.
// The output names the file, the line and the rule. It never prints the matched value (only its length).
//
// Exit codes: 0 clean, 1 findings, 2 usage or environment error.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { isMainModule } from './is-main.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
export const DEFAULT_ALLOWLIST = path.join(here, 'public-config.allowlist.json');

// ------------------------------------------------------------------------------------------------ names
const isExample = (p) => /(^|[./_-])(example|sample|template|dist)(\.|$)/i.test(path.posix.basename(p));

/** Private by NAME. `except` re-allows the documented examples. */
export const PATH_RULES = [
  { id: 'env-file', re: /(^|\/)(\.env(\.[^/]+)?|[^/]+\.env)$/, except: isExample, why: 'environment file' },
  { id: 'dev-vars', re: /(^|\/)\.dev\.vars(\.[^/]+)?$/, except: isExample, why: 'Cloudflare local variables' },
  { id: 'private-key-file', re: /\.(pem|key|p8|p12|pfx|der|jks|keystore|mobileprovision|provisionprofile|certsigningrequest|cer|crt)$/i, why: 'key, certificate or signing material' },
  { id: 'ssh-key', re: /(^|\/)(id_(rsa|dsa|ecdsa|ed25519)(\.pub)?|\.ssh\/.+)$/, why: 'SSH key' },
  { id: 'signing-config', re: /(^|\/)(key\.properties|Local\.xcconfig|local\.properties)$/, why: 'signing or per-developer settings' },
  { id: 'firebase-config', re: /(^|\/)(google-services\.json|GoogleService-Info\.plist|firebase-adminsdk[^/]*\.json|\.firebaserc|firebase\.json)$/, why: 'Firebase configuration' },
  { id: 'credential-json', re: /(service[-_]?account|credentials?|client[-_]secret)[^/]*\.json$/i, except: isExample, why: 'credential file' },
  { id: 'cloud-dir', re: /(^|\/)(\.aws|\.gcloud|\.azure|\.terraform|\.wrangler|\.vercel|\.netlify|\.serverless)(\/|$)/, why: 'cloud tooling state' },
  { id: 'terraform-state', re: /\.tf(state|vars)(\.[^/]+)?$/, except: isExample, why: 'Terraform state or variables' },
  { id: 'wrangler-config', re: /(^|\/)wrangler\.(jsonc?|toml)$/, why: 'real Cloudflare deployment config (publish wrangler.example.jsonc only)' },
  { id: 'database-dump', re: /(\.(dump|bak|backup|sqlite3?|db|rdb|mdb)$|\.sql\.(gz|zip|bz2|xz)$|(^|\/)(pg_dump|dump|backup)[^/]*\.sql$)/i, why: 'database dump or backup' },
  { id: 'archive', re: /\.(zip|tar|tgz|gz|7z|rar)$/i, why: 'archive' },
  { id: 'credential-store', re: /(^|\/)(\.netrc|\.pgpass|\.htpasswd|\.git-credentials)$/, why: 'credential store' },
  { id: 'advertising-material', re: /(^|\/)(ad-video|ad_screens)(\/|$)/, why: 'advertising material' },
  { id: 'promo-render', re: /(^|\/)output\/[^/]+\.(mp4|mov|webm|m4v)$/i, why: 'rendered promotional video' },
  { id: 'agent-tooling', re: /(^|\/)\.claude\//, why: 'local agent tooling' },
];

/** Names that make a file CONFIGURATION-LIKE, i.e. it must be classified by the allowlist. */
const CONFIG_EXT = /\.(jsonc?|ya?ml|toml|ini|cfg|conf|properties|plist|xcconfig|entitlements|gradle|kts|xml|tf)$/i;
const CONFIG_NAME = /(^|\/)(Dockerfile[^/]*|docker-compose[^/]*|Podfile[^/]*|Gemfile[^/]*|Fastfile|\.npmrc|\.nvmrc|\.gitattributes|\.gitignore|\.dockerignore|CODEOWNERS)$/;
export const isConfigLike = (p) => CONFIG_EXT.test(p) || CONFIG_NAME.test(p);

// ------------------------------------------------------------------------------------------------ content
const PLACEHOLDER = /^(\$|<|\{|\*+$|x+$|\.\.\.|changeme|change-me|password|passwd|pass$|secret|example|your[-_]|replace|todo|placeholder|dummy|fake|test|redacted|none|null|undefined|abcdef|0{6,})/i;
const LOCAL_HOST = /^(localhost|127\.0\.0\.1|\[::1\]|::1|postgres|db|host\.docker\.internal|[^.]+\.(invalid|example|test|localhost))$/i;

function entropy(s) {
  const freq = new Map();
  for (const ch of s) freq.set(ch, (freq.get(ch) ?? 0) + 1);
  let h = 0;
  for (const n of freq.values()) h -= (n / s.length) * Math.log2(n / s.length);
  return h;
}

/**
 * Content rules, applied per line. `configOnly` rules run only in configuration-like files (noisy elsewhere);
 * `skipTests` rules do not run in test directories (fixtures hold made-up values there).
 */
export const CONTENT_RULES = [
  { id: 'private-key-block', re: /-----BEGIN (RSA |EC |OPENSSH |DSA |PGP |ENCRYPTED )?PRIVATE KEY( BLOCK)?-----/ },
  { id: 'aws-access-key', re: /\b(AKIA|ASIA)[0-9A-Z]{16}\b/ },
  { id: 'aws-secret-key', re: /aws_?secret_?access_?key["']?\s*[=:]\s*["']?[A-Za-z0-9/+]{30,}/i },
  { id: 'provider-key', re: /\b(sk-ant-[A-Za-z0-9_-]{20,}|sk-(proj-)?[A-Za-z0-9_-]{32,}|AIza[0-9A-Za-z_-]{35}|xai-[A-Za-z0-9]{40,}|gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{50,}|xox[baprs]-[A-Za-z0-9-]{20,}|[sr]k_live_[A-Za-z0-9]{20,}|whsec_[A-Za-z0-9]{20,}|glpat-[A-Za-z0-9_-]{20,})/, skipTests: true },
  { id: 'cloudflare-token', re: /CLOUDFLARE_(API_)?(TOKEN|KEY)["']?\s*[=:]\s*["']?[A-Za-z0-9_-]{30,}/ },
  { id: 'cloudflare-account-id', re: /["']?(account_id|zone_id|database_id)["']?\s*[:=]\s*["'][0-9a-f-]{32,36}["']/i },
  { id: 'cloudflare-resource-id', re: /["']id["']\s*:\s*["'][0-9a-f]{32}["']/, configOnly: true },
  { id: 'cloudflare-host', re: /\b[a-z0-9-]+\.(workers\.dev|pages\.dev|r2\.dev|r2\.cloudflarestorage\.com)\b/i },
  { id: 'local-user-path', re: /(\/Users\/(?!<|\$|you\b|name\b|user\b|username\b|jan\.kowalski\b)[A-Za-z0-9._-]+\/|[A-Za-z]:\\+Users\\+(?!<|%|you\b|name\b|user\b|username\b|jan\b)[A-Za-z0-9._ -]+\\|\/home\/(?!runner\b|node\b|user\b)[a-z][A-Za-z0-9._-]*\/(?!\.)(Downloads|Documents|Desktop|\.ssh|\.aws))/, skipTests: true },
  { id: 'private-dir-reference', re: /wattbyte-private-[a-z]+|\.private-confi[g]|wattbyte-public-expor[t]/ },
  { id: 'business-registry-id', re: /\b(nip|regon|vat[-_ ]?id|tax[-_ ]?id)["']?\s*[:=]\s*["']?(PL)?(?!0+["'\s,;)]|0+$)\d{9,10}\b/i },
  { id: 'generic-secret-assignment', re: /\b[A-Za-z0-9_]*(secret|token|password|passwd|api[_-]?key|private[_-]?key|credential)[A-Za-z0-9_]*["']?\s*[:=]\s*["']?([A-Za-z0-9+/_=.-]{24,})["']?/i, configOnly: true, skipTests: true, test: (m) => !PLACEHOLDER.test(m[2]) && entropy(m[2]) >= 3.7 },
  { id: 'high-entropy-token', re: /["'=:\s]([A-Za-z0-9+/_-]{40,})["',\s]*$/, configOnly: true, skipTests: true, test: (m, line, p) => !/(integrity|sha(1|256|512)|checksum|hash|digest|resolved|lock)/i.test(line) && !/(pnpm-lock|pubspec\.lock|\.arb$)/.test(p) && entropy(m[1]) >= 4.4 },
  { id: 'connection-string-credentials', re: /\b(postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis|rediss|amqps?):\/\/([^:/\s@'"`]+):([^@\s'"`]+)@([^/\s:'"`?#]+)/i, skipTests: true, test: (m) => !LOCAL_HOST.test(m[4]) && !PLACEHOLDER.test(m[3]) && !/^(user|username|name|wattbyte|app|admin|dbuser)$/i.test(m[3]) },
  { id: 'url-embedded-credentials', re: /\bhttps?:\/\/[^/\s:@'"`]+:[^/\s@'"`]{4,}@[^/\s'"`]+/i, skipTests: true, test: (m) => !/@(localhost|127\.0\.0\.1)/.test(m[0]) && !/:(\$|<|\{|\*|x+@|password|pass@|secret|token@)/i.test(m[0]) },
];

const TEST_PATH = /(^|\/)(tests?|__tests__|fixtures?)\/|\.(test|spec)\.[cm]?[jt]sx?$|_test\.dart$|(^|\/)test\//;
export const isTestPath = (p) => TEST_PATH.test(p);
const mask = (len) => `<${len} chars not shown>`;

/** @returns {{ rule: string, line: number, detail: string }[]} (never contains the matched text) */
export function scanText(text, relPath, { denyLiterals = [], allowContent = [] } = {}) {
  const findings = [];
  const config = isConfigLike(relPath);
  const tests = isTestPath(relPath);
  const lines = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (line.length > 4000) continue; // minified or generated blobs
    for (const rule of CONTENT_RULES) {
      if (rule.configOnly && !config) continue;
      if (rule.skipTests && tests) continue;
      const m = rule.re.exec(line);
      if (!m || (rule.test && !rule.test(m, line, relPath))) continue;
      if (allowContent.some((a) => a.rule === rule.id && a.re.test(relPath))) continue;
      findings.push({ rule: rule.id, line: i + 1, detail: mask(m[0].length) });
    }
    for (const d of denyLiterals) {
      const { lit, prefix } = typeof d === 'string' ? { lit: d } : d;
      if (lit && line.includes(lit) && (!prefix || relPath.startsWith(prefix))) findings.push({ rule: 'denied-literal', line: i + 1, detail: mask(lit.length) });
    }
  }
  return findings;
}

// ------------------------------------------------------------------------------------------------ allowlist
export function globToRegExp(glob) {
  let re = '';
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === '*' && glob[i + 1] === '*') {
      i++;
      if (glob[i + 1] === '/') {
        i++;
        re += '(?:.*/)?';
      } else re += '.*';
    } else if (c === '*') re += '[^/]*';
    else if (c === '?') re += '[^/]';
    else re += c.replace(/[.+^${}()|[\]\\]/g, '\\$&');
  }
  return new RegExp(`^${re}$`);
}

export function loadAllowlist(file = DEFAULT_ALLOWLIST) {
  const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
  const classes = new Set(['PRIVATE_SECRET', 'PRIVATE_INFRASTRUCTURE', 'PRIVATE_ENVIRONMENT', 'PRIVATE_BUSINESS', 'PUBLIC_BUILD_REQUIRED', 'PUBLIC_EXAMPLE', 'PUBLIC_SOURCE']);
  const allow = (raw.allow ?? []).map((e) => {
    if (!classes.has(e.class) || e.class.startsWith('PRIVATE')) throw new Error(`allowlist entry ${e.glob}: class must be a PUBLIC_* class`);
    for (const k of ['glob', 'reason', 'review']) if (!e[k]) throw new Error(`allowlist entry ${e.glob ?? '?'}: missing "${k}"`);
    return { ...e, re: globToRegExp(e.glob) };
  });
  return {
    allow,
    denyPaths: (raw.denyPaths ?? []).map((p) => ({ prefix: p })),
    allowContent: (raw.allowContent ?? []).map((a) => ({ ...a, re: globToRegExp(a.path) })),
    maxFileBytes: raw.maxFileBytes ?? 5 * 1024 * 1024,
  };
}

// ------------------------------------------------------------------------------------------------ checks
function git(root, args, opts = {}) {
  const r = spawnSync('git', ['-C', root, ...args], { encoding: 'utf8', maxBuffer: 1 << 30, ...opts });
  if (r.status !== 0 && !opts.allowFail) throw new Error(`git ${args.join(' ')} failed: ${(r.stderr ?? '').trim().slice(0, 200)}`);
  return r.stdout ?? '';
}

export function pathFindings(p, list) {
  const out = [];
  for (const r of PATH_RULES) if (r.re.test(p) && !(r.except && r.except(p))) out.push({ rule: r.id, line: 0, detail: r.why });
  for (const d of list.denyPaths) if (p === d.prefix || p.startsWith(d.prefix.endsWith('/') ? d.prefix : `${d.prefix}/`)) out.push({ rule: 'private-only-path', line: 0, detail: 'path is reserved for the private repository' });
  return out;
}

const looksBinary = (buf) => buf.subarray(0, 8000).includes(0);

export function checkTree(root, list, { denyLiterals = [] } = {}) {
  const findings = [];
  const isRepo = spawnSync('git', ['-C', root, 'rev-parse', '--git-dir'], { encoding: 'utf8' }).status === 0;
  let files;
  if (isRepo) {
    const tracked = git(root, ['ls-files', '-z']).split('\0').filter(Boolean);
    const others = git(root, ['ls-files', '-z', '--others', '--exclude-standard']).split('\0').filter(Boolean);
    files = [...new Set([...tracked, ...others])];
  } else {
    files = [];
    const walk = (d) => {
      for (const e of fs.readdirSync(path.join(root, d), { withFileTypes: true })) {
        const rel = path.posix.join(d, e.name);
        if (e.name === '.git' || e.name === 'node_modules') continue;
        if (e.isDirectory()) walk(rel);
        else files.push(rel);
      }
    };
    walk('');
  }
  const matched = new Set();
  let checked = 0;
  for (const p of files) {
    const abs = path.join(root, p);
    let st;
    try {
      st = fs.lstatSync(abs);
    } catch {
      continue; // listed by git but deleted in the working tree
    }
    if (!st.isFile()) continue;
    checked++;
    for (const f of pathFindings(p, list)) findings.push({ path: p, ...f });
    if (st.size > list.maxFileBytes) findings.push({ path: p, rule: 'large-file', line: 0, detail: `${st.size} bytes (limit ${list.maxFileBytes})` });
    const hit = list.allow.find((e) => e.re.test(p));
    if (hit) matched.add(hit.glob);
    else if (isConfigLike(p) && !pathFindings(p, list).length) findings.push({ path: p, rule: 'unclassified-config', line: 0, detail: 'configuration file not covered by the reviewed allowlist (default deny)' });
    if (st.size <= 2 * 1024 * 1024) {
      const buf = fs.readFileSync(abs);
      if (!looksBinary(buf)) for (const f of scanText(buf.toString('utf8'), p, { denyLiterals, allowContent: list.allowContent })) findings.push({ path: p, ...f });
    }
  }
  const stale = list.allow.filter((e) => !matched.has(e.glob)).map((e) => e.glob);
  return { findings, checked, stale, files };
}

// GitHub noreply addresses, Anthropic's co-author address and GitHub's public support address (Dependabot's "Signed-off-by" line).
const METADATA_EMAIL_OK = /(@users\.noreply\.github\.com|^noreply@github\.com|^noreply@anthropic\.com|^support@github\.com)$/i;

export function checkHistory(root, list, { strictRefs = false, allowTags = [], denyLiterals = [] } = {}) {
  const findings = [];
  const seen = new Set();
  const add = (f) => {
    const k = `${f.rule}|${f.path ?? ''}|${f.line}`;
    if (seen.has(k)) return;
    seen.add(k);
    findings.push(f);
  };
  // 1. every path that was ever added or modified
  const names = git(root, ['log', '--all', '--pretty=format:', '--name-only', '--diff-filter=ACMR', '-z']).split('\0').map((s) => s.replace(/^\n+/, '')).filter(Boolean);
  const paths = [...new Set(names)];
  for (const p of paths) {
    for (const f of pathFindings(p, list)) add({ path: p, ...f, detail: `${f.detail} (in history)` });
    if (isConfigLike(p) && !list.allow.some((e) => e.re.test(p)) && !pathFindings(p, list).length) add({ path: p, rule: 'unclassified-config', line: 0, detail: 'configuration file in history not covered by the allowlist' });
  }
  // 2. author and committer identities, and the addresses inside commit messages
  const ids = git(root, ['log', '--all', '--format=%ae%n%ce']).split('\n').filter(Boolean);
  for (const e of new Set(ids)) if (!METADATA_EMAIL_OK.test(e)) add({ path: '(commit metadata)', rule: 'author-email', line: 0, detail: `a commit author or committer address is not a GitHub noreply address (${mask(e.length)})` });
  const msgs = git(root, ['log', '--all', '--format=%x00%H%n%B']).split('\0').filter(Boolean);
  for (const m of msgs) {
    const [sha, ...rest] = m.split('\n');
    for (const f of scanText(rest.join('\n'), '(commit message)', { denyLiterals })) add({ path: `(commit message ${sha.slice(0, 7)})`, ...f });
    for (const em of rest.join('\n').matchAll(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}/g)) if (!METADATA_EMAIL_OK.test(em[0]) && !/@(wattbyte\.app|example\.)/i.test(em[0])) add({ path: `(commit message ${sha.slice(0, 7)})`, rule: 'message-email', line: 0, detail: `an e-mail address in a commit message (${mask(em[0].length)})` });
  }
  // 3. every added line of every commit
  const patch = git(root, ['log', '--all', '-p', '--no-color', '-U0', '--diff-filter=ACMR', '--format=@@COMMIT %H', '--', '.', ':!pnpm-lock.yaml', ':!apps/mobile/pubspec.lock', ':!*.arb']);
  let file = '';
  let sha = '';
  const byFile = new Map();
  for (const line of patch.split('\n')) {
    if (line.startsWith('@@COMMIT ')) sha = line.slice(9);
    else if (line.startsWith('+++ b/')) file = line.slice(6);
    else if (line.startsWith('+') && !line.startsWith('+++')) {
      if (!byFile.has(file)) byFile.set(file, { sha, text: [] });
      byFile.get(file).text.push(line.slice(1));
    }
  }
  for (const [p, { sha: s, text }] of byFile) {
    for (const f of scanText(text.join('\n'), p, { denyLiterals, allowContent: list.allowContent })) add({ path: `${p} (history, ${s.slice(0, 7)})`, ...f, line: 0 });
  }
  // 4. refs
  if (strictRefs) {
    const refs = git(root, ['for-each-ref', '--format=%(refname)']).split('\n').filter(Boolean);
    for (const r of refs) {
      // A clone also has remote-tracking refs of what is already published; they are not something a push would add.
      const ok = r === 'refs/heads/main' || r === 'refs/remotes/origin/main' || r === 'refs/remotes/origin/HEAD' || allowTags.some((t) => r === `refs/tags/${t}`);
      if (!ok) add({ path: r, rule: 'unapproved-ref', line: 0, detail: 'only refs/heads/main and explicitly approved tags may be published' });
    }
  }
  return { findings, commits: git(root, ['rev-list', '--all', '--count']).trim(), paths: paths.length };
}

/** Markdown table of every configuration-like file with its reviewed classification. */
export function manifest(root, list) {
  const { files } = checkTree(root, list);
  const rows = [];
  const template = (p) => isExample(p) && /(env|properties|xcconfig|json|jsonc|ya?ml|toml)/i.test(path.posix.basename(p));
  for (const p of files.sort()) {
    if (!isConfigLike(p) && !template(p)) continue;
    const e = list.allow.find((x) => x.re.test(p));
    rows.push(e || !template(p) ? { p, e: e ?? null } : { p, e: { class: 'PUBLIC_EXAMPLE', reason: 'documented template', envValues: true, review: 'synthetic values only (content scan clean)' } });
  }
  const lines = ['| Path | Class | Why it is necessary | Environment-specific values | Review | Decision |', '|---|---|---|---|---|---|'];
  for (const { p, e } of rows) {
    lines.push(e ? `| \`${p}\` | ${e.class} | ${e.reason} | ${e.envValues ? 'yes (placeholders)' : 'no'} | ${e.review} | publish |` : `| \`${p}\` | UNCLASSIFIED | - | - | - | EXCLUDED |`);
  }
  return lines.join('\n');
}

// ------------------------------------------------------------------------------------------------ cli
export function main(argv = process.argv.slice(2), out = console) {
  const opt = (name) => {
    const i = argv.indexOf(name);
    return i >= 0 ? argv[i + 1] : undefined;
  };
  const all = (name) => argv.flatMap((a, i) => (a === name ? [argv[i + 1]] : []));
  const root = path.resolve(opt('--root') ?? process.cwd());
  let list;
  try {
    list = loadAllowlist(opt('--allowlist') ?? DEFAULT_ALLOWLIST);
  } catch (e) {
    out.error(`check-public-config: cannot read the allowlist: ${e.message}`);
    return 2;
  }
  let denyLiterals = [];
  if (opt('--deny-literals')) {
    try {
      // One literal per line; "<path prefix><TAB><literal>" limits a literal to that part of the tree.
      denyLiterals = fs.readFileSync(opt('--deny-literals'), 'utf8').split('\n').filter(Boolean).map((l) => {
        const [a, b] = l.split('\t');
        return b === undefined ? { lit: a.trim() } : { prefix: a.trim(), lit: b.trim() };
      }).filter((d) => d.lit.length >= 6);
    } catch (e) {
      out.error(`check-public-config: cannot read the deny-literals file: ${e.message}`);
      return 2;
    }
  }
  try {
    if (argv.includes('--manifest')) {
      out.log(manifest(root, list));
      return 0;
    }
    const tree = checkTree(root, list, { denyLiterals });
    let findings = tree.findings;
    let summary = `${tree.checked} file(s) checked`;
    if (argv.includes('--history')) {
      const h = checkHistory(root, list, { strictRefs: argv.includes('--strict-refs'), allowTags: all('--allow-tag'), denyLiterals });
      findings = findings.concat(h.findings);
      summary += `, ${h.commits} commit(s) and ${h.paths} historical path(s) checked`;
    }
    for (const f of findings) out.log(`FAIL  ${f.path}${f.line ? `:${f.line}` : ''}  [${f.rule}]  ${f.detail}`);
    for (const s of tree.stale) out.log(`notice: allowlist entry "${s}" matched no file (stale?)`);
    out.log(`check-public-config: ${summary}, ${findings.length} finding(s)`);
    return findings.length ? 1 : 0;
  } catch (e) {
    out.error(`check-public-config: ${e.message}`);
    return 2;
  }
}

if (isMainModule(import.meta.url)) process.exit(main());
