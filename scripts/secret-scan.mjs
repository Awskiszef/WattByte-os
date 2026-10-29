// Secret scan: pure Node, no dependencies. Scans the files that WOULD be tracked
// by Git (it honours every .gitignore in the tree itself, so it works in a folder
// that is not a repository yet) and fails on anything that looks like a credential.
//
//   node scripts/secret-scan.mjs [--root DIR] [--allow FILE] [--json] [--list-files] [--verbose]
//
// Detects: provider API keys (OpenAI sk-, Anthropic sk-ant-, Google AIza, xAI xai-,
// AWS AKIA/ASIA, GitHub, Slack, Stripe), PEM private-key blocks, JWT-shaped strings,
// URLs with an embedded password, *SECRET / *PASSWORD / *TOKEN / *API_KEY assignments
// with a non-placeholder value, keystore passwords in gradle/properties files, and
// sensitive files that are present AND not ignored (.env*, *.jks, key.properties ...).
//
// Output is masked: a finding shows the first characters of the value and its length,
// never the value. Files that are ignored (a local apps/api/.env, a keystore) are not
// opened at all; their presence is only reported as a notice.
//
// Exit code: 0 clean, 1 unallowlisted findings or an invalid allowlist, 2 usage error.
// Accepted exceptions live in scripts/secret-scan.allow.json, each with a justification.
import { lstatSync, readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { isMainModule } from './is-main.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const defaultRoot = path.resolve(here, '..');
const defaultAllow = path.join(here, 'secret-scan.allow.json');

// ---------------------------------------------------------------- masking

/** First characters + length. Never the whole value (short values reveal fewer characters). */
export function mask(value) {
  const reveal = Math.min(4, Math.floor(value.length / 3));
  return `${value.slice(0, reveal)}\u2026 (${value.length} chars)`;
}

// ------------------------------------------------------- gitignore emulation

/** Glob (gitignore flavour) to a RegExp that matches a whole relative path. */
export function globToRegExp(glob) {
  let re = '';
  for (let i = 0; i < glob.length; i += 1) {
    const c = glob[i];
    if (c === '*') {
      if (glob[i + 1] === '*') {
        i += 1;
        if (glob[i + 1] === '/') {
          i += 1;
          re += '(?:.*/)?';
        } else re += '.*';
      } else re += '[^/]*';
    } else if (c === '?') re += '[^/]';
    else if (c === '[') {
      const end = glob.indexOf(']', i + 2);
      if (end === -1) re += '\\[';
      else {
        let cls = glob.slice(i + 1, end);
        if (cls[0] === '!') cls = `^${cls.slice(1)}`;
        re += `[${cls.replace(/\\/g, '\\\\')}]`;
        i = end;
      }
    } else if (c === '\\' && i + 1 < glob.length) {
      i += 1;
      re += glob[i].replace(/[.+^${}()|[\]\\]/g, '\\$&');
    } else re += c.replace(/[.+^${}()|[\]\\]/g, '\\$&');
  }
  return new RegExp(`^${re}$`);
}

/** Parses one .gitignore into rules relative to `baseRel` (posix, '' for the root). */
export function parseGitignore(text, baseRel = '') {
  const rules = [];
  for (const rawLine of text.split(/\r?\n/)) {
    let line = rawLine.replace(/(?<!\\)\s+$/, '');
    if (!line || line.startsWith('#')) continue;
    let negate = false;
    if (line.startsWith('!')) {
      negate = true;
      line = line.slice(1);
    }
    if (line.startsWith('\\#') || line.startsWith('\\!')) line = line.slice(1);
    const dirOnly = line.endsWith('/');
    if (dirOnly) line = line.slice(0, -1);
    if (!line) continue;
    const anchored = line.includes('/');
    if (line.startsWith('/')) line = line.slice(1);
    const re = globToRegExp(anchored ? line : `**/${line}`);
    rules.push({ negate, dirOnly, re, baseRel });
  }
  return rules;
}

/** Last matching rule wins (deeper .gitignore files come later in `rules`). */
export function isIgnored(rules, relPath, isDir) {
  let ignored = false;
  for (const r of rules) {
    if (r.dirOnly && !isDir) continue;
    let sub = relPath;
    if (r.baseRel) {
      if (!relPath.startsWith(`${r.baseRel}/`)) continue;
      sub = relPath.slice(r.baseRel.length + 1);
    }
    if (r.re.test(sub)) ignored = !r.negate;
  }
  return ignored;
}

// ------------------------------------------------------------ file walking

const ALWAYS_SKIP_DIRS = new Set(['.git', 'node_modules']);
const LOCKFILES = new Set([
  'pnpm-lock.yaml',
  'package-lock.json',
  'yarn.lock',
  'pubspec.lock',
  'Podfile.lock',
  'Package.resolved',
  'gradle.lockfile',
  'Cargo.lock',
]);
const BINARY_EXT = new Set(
  (
    'png jpg jpeg gif webp ico icns bmp tiff heic pdf ttf otf woff woff2 eot zip gz tgz bz2 xz 7z rar jar aar so a dylib ' +
    'dll exe class dex o apk aab ipa mp3 mp4 mov wav m4a ogg flac webm car nib riv lottie sqlite db'
  ).split(' '),
);
const MAX_BYTES = 2 * 1024 * 1024;

/**
 * Lists the files that would be tracked. Ignored files that are sensitive by name are
 * returned separately (never opened) so they can be reported as notices.
 */
export function listFiles(root) {
  const files = [];
  const ignoredSensitive = [];
  const skippedLarge = [];
  const walk = (dirAbs, dirRel, inheritedRules) => {
    let rules = inheritedRules;
    let entries;
    try {
      entries = readdirSync(dirAbs, { withFileTypes: true });
    } catch {
      return;
    }
    const ignoreFile = entries.find((e) => e.name === '.gitignore' && e.isFile());
    if (ignoreFile) {
      const text = readFileSync(path.join(dirAbs, '.gitignore'), 'utf8');
      rules = rules.concat(parseGitignore(text, dirRel));
    }
    for (const e of entries.sort((a, b) => a.name.localeCompare(b.name))) {
      if (e.isSymbolicLink()) continue; // never followed: they can leave the tree
      const rel = dirRel ? `${dirRel}/${e.name}` : e.name;
      const abs = path.join(dirAbs, e.name);
      if (e.isDirectory()) {
        if (ALWAYS_SKIP_DIRS.has(e.name)) continue;
        if (isIgnored(rules, rel, true)) continue;
        walk(abs, rel, rules);
      } else if (e.isFile()) {
        if (isIgnored(rules, rel, false)) {
          if (sensitiveKind(e.name)) ignoredSensitive.push(rel);
          continue;
        }
        files.push(rel);
      }
    }
  };
  walk(root, '', []);
  return { files, ignoredSensitive, skippedLarge };
}

// ------------------------------------------------------------- sensitive files

const ENV_EXAMPLE = /^\.env(\.[\w-]+)*\.(example|sample|template|dist)$/i;

/** Returns a label when the file NAME alone makes it unsafe to track. */
export function sensitiveKind(name) {
  if (ENV_EXAMPLE.test(name)) return null;
  if (/^\.env(\..+)?$/i.test(name)) return 'environment file';
  if (/\.(jks|keystore|p12|pfx|p8|mobileprovision)$/i.test(name)) return 'signing material';
  if (name === 'key.properties') return 'Android signing properties';
  if (/^id_(rsa|dsa|ecdsa|ed25519)$/.test(name)) return 'SSH private key';
  if (/^(google-services\.json|GoogleService-Info\.plist)$/.test(name)) return null;
  return null;
}

// ----------------------------------------------------------------- detectors

const PLACEHOLDER_WORDS =
  /(change[-_ ]?me|changeit|your[-_ ]|example|placeholder|dummy|fake|sample|redacted|xxxx|todo|insert|replace|secret[-_]?here|not[-_]?a[-_]?real|<[^>]*>|\*{3,}|\.{3,})/i;

const CONFIG_EXT = new Set(['.env', '.properties', '.yml', '.yaml', '.sh', '.bash', '.zsh', '.toml', '.ini', '.cfg', '.conf', '.xcconfig', '.md']);

function isConfigLike(relPath) {
  const base = path.posix.basename(relPath);
  if (/^\.env/.test(base) || base === 'Dockerfile') return true;
  return CONFIG_EXT.has(path.posix.extname(base).toLowerCase());
}

/** A value that is code, not a credential: references, interpolation, identifiers. */
function isBenignValue(v, name = '') {
  if (v.length < 8) return true;
  if (/\s/.test(v)) return true; // natural language, not a credential
  if (/[^\x21-\x7E]/.test(v)) return true; // non-ASCII: prose, never a generated secret
  if (/[${}()<>[\]`]/.test(v)) return true; // interpolation, calls, templates, generics
  if (/^(process\.env|secrets\.|env\.|System\.getenv|Platform\.environment|Deno\.env)/i.test(v)) return true;
  if (PLACEHOLDER_WORDS.test(v)) return true;
  if (/^(password|passwd|secret|token|apikey|api_key|api-key)$/i.test(v)) return true;
  const identifierLike =
    /^[A-Za-z]+(?:[_.\-][A-Za-z]+\d{0,2})*\d{0,2}$/.test(v) || /^[a-z]+(?:[A-Z][a-z]+)+\d{0,2}$/.test(v);
  // A passphrase made of dictionary words ("my-long-jwt-secret") is still a secret when it
  // is assigned to a SECRET/PASSWORD name; only key NAMES (refresh_token_v2) are benign.
  const strongName = /secret|password|passwd|private/i.test(name);
  if (identifierLike && !(strongName && v.length >= 16)) return true;
  if (/^[A-Z0-9_]+$/.test(v) && v.includes('_')) return true; // SCREAMING_CASE constant name
  if (/^https?:\/\/[^@]*$/i.test(v)) return true; // a plain URL, not a credential
  if (/^[./~][\w./-]*$/.test(v)) return true; // a path
  return false;
}

function isPlaceholderPassword(p) {
  return (
    p.length < 3 ||
    /^[$%{<]/.test(p) ||
    /\$\{|\$[A-Za-z_]|%s|\{\{/.test(p) ||
    /^(password|passwd|pass|pwd|secret|xxx+|\*+|changeme|change_me|your_?password|user|admin|redacted)$/i.test(p) ||
    PLACEHOLDER_WORDS.test(p)
  );
}

const RULES = [
  { id: 'anthropic-key', re: /(?<![A-Za-z0-9_-])sk-ant-[A-Za-z0-9_-]{20,}/g, note: 'Anthropic API key' },
  {
    id: 'openai-key',
    re: /(?<![A-Za-z0-9_-])sk-(?!ant-)(?:proj-|svcacct-|admin-)?[A-Za-z0-9_-]{20,}/g,
    note: 'OpenAI-style API key',
    skip: (v) => PLACEHOLDER_WORDS.test(v) || /^sk-[a-z-]+$/.test(v),
  },
  { id: 'google-api-key', re: /(?<![A-Za-z0-9_-])AIza[0-9A-Za-z_-]{35}(?![0-9A-Za-z_-])/g, note: 'Google API key' },
  { id: 'xai-key', re: /(?<![A-Za-z0-9_-])xai-[A-Za-z0-9]{20,}/g, note: 'xAI API key' },
  { id: 'aws-access-key', re: /(?<![A-Za-z0-9])(?:AKIA|ASIA)[0-9A-Z]{16}(?![A-Za-z0-9])/g, note: 'AWS access key id' },
  { id: 'github-token', re: /(?<![A-Za-z0-9_])(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{50,})/g, note: 'GitHub token' },
  { id: 'slack-token', re: /(?<![A-Za-z0-9-])xox[abprs]-[A-Za-z0-9-]{20,}/g, note: 'Slack token' },
  { id: 'stripe-key', re: /(?<![A-Za-z0-9_])[sr]k_live_[A-Za-z0-9]{20,}/g, note: 'Stripe live key' },
  {
    id: 'private-key-block',
    re: /-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED |PGP )?PRIVATE KEY(?: BLOCK)?-----/g,
    note: 'PEM private key block',
    noValue: true,
  },
  {
    id: 'jwt',
    re: /(?<![A-Za-z0-9_-])eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}(?![A-Za-z0-9_-])/g,
    note: 'JWT-shaped string',
  },
];

const URL_PASSWORD = /\b([a-z][a-z0-9+.-]{1,20}):\/\/([^\s:/?#@'"`<>]+):([^\s@/?#'"`<>]+)@([^\s/?#'"`<>:]+)/gi;
const SECRET_NAME = '[A-Za-z0-9_.-]*(?:secret|password|passwd|token|api[_-]?key|private[_-]?key|access[_-]?key)[A-Za-z0-9_.-]*';
const ASSIGNMENT = new RegExp(
  `(?<![A-Za-z0-9_])(${SECRET_NAME})["']?\\s*[:=]\\s*(?:"([^"\\n]*)"|'([^'\\n]*)'|\`([^\`\\n]*)\`|([^\\s#"',;]+))`,
  'gi',
);
const KEYSTORE_RULE = 'keystore-password';
const KEYSTORE_NAME = /^(?:store|key)(?:password|pass)$|^(?:store|key)_password$/i;

/**
 * Scans one file's text. Returns `{ finding, raw }` pairs; `raw` (the secret itself)
 * is only used to match the allowlist and is never printed or serialised.
 */
export function scanText(relPath, text) {
  const out = [];
  const configLike = isConfigLike(relPath);
  const base = path.posix.basename(relPath);
  const isGradleOrProps = /\.(gradle|kts|properties)(\.[\w-]+)?$/.test(base);
  const lines = text.split(/\r?\n/);
  lines.forEach((line, idx) => {
    const lineNo = idx + 1;
    if (line.length > 20000) return; // minified blobs
    const push = (rule, value, note, extra = {}) =>
      out.push({
        finding: { file: relPath, line: lineNo, rule, masked: value === undefined ? '(no value)' : mask(value), note },
        raw: { value: value ?? '', ...extra },
      });

    for (const rule of RULES) {
      for (const m of line.matchAll(rule.re)) {
        if (rule.skip?.(m[0])) continue;
        push(rule.id, rule.noValue ? undefined : m[0], rule.note);
      }
    }

    for (const m of line.matchAll(URL_PASSWORD)) {
      const [, scheme, user, pass, host] = m;
      if (isPlaceholderPassword(pass)) continue;
      push('url-password', pass, `${scheme}:// URL with an embedded password for user "${user}" at ${host}`, { host, user });
    }

    for (const m of line.matchAll(ASSIGNMENT)) {
      const name = m[1];
      const quoted = m[2] ?? m[3] ?? m[4];
      const value = quoted ?? m[5];
      if (value === undefined) continue;
      if (quoted === undefined && !configLike && !isGradleOrProps) continue; // unquoted RHS in code is an expression
      // Markdown prose reads like "tokens: values"; only `NAME=value` counts there.
      const separator = m[0].slice(name.length).match(/[:=]/)?.[0];
      if (quoted === undefined && base.endsWith('.md') && separator !== '=') continue;
      if (isBenignValue(value, name)) continue;
      if (!/\d|[^A-Za-z0-9_.-]/.test(value) && value.length < 16) continue; // letters only and short: a word, not a secret
      const keystore = isGradleOrProps && KEYSTORE_NAME.test(name);
      push(keystore ? KEYSTORE_RULE : 'secret-assignment', value, `${name} is assigned a literal value`, { name });
    }
  });
  return out;
}

// ------------------------------------------------------------------ allowlist

/** Loads and validates the allowlist; returns `{ entries, errors }`. */
export function loadAllowlist(file, readText = (f) => readFileSync(f, 'utf8')) {
  let parsed;
  try {
    parsed = JSON.parse(readText(file));
  } catch (e) {
    if (e && e.code === 'ENOENT') return { entries: [], errors: [] };
    return { entries: [], errors: [`${file}: cannot read allowlist (${e instanceof Error ? e.message : e})`] };
  }
  const list = Array.isArray(parsed) ? parsed : parsed.allow;
  if (!Array.isArray(list)) return { entries: [], errors: [`${file}: expected {"allow": [...]}`] };
  const errors = [];
  const entries = [];
  list.forEach((raw, i) => {
    const id = raw?.id ?? `#${i + 1}`;
    if (typeof raw?.rule !== 'string' || !raw.rule) errors.push(`allowlist ${id}: "rule" is required`);
    else if (typeof raw.justification !== 'string' || raw.justification.trim().length < 20)
      errors.push(`allowlist ${id}: a written "justification" (at least 20 characters) is required`);
    else if (!raw.paths?.length && raw.valueEquals === undefined && !raw.valuePrefix && !raw.valueRegex)
      errors.push(`allowlist ${id}: needs "paths" or a value matcher (valueEquals / valuePrefix / valueRegex); a bare rule would switch the rule off`);
    else {
      let valueRe;
      if (raw.valueRegex) {
        try {
          valueRe = new RegExp(raw.valueRegex);
        } catch {
          errors.push(`allowlist ${id}: invalid valueRegex`);
          return;
        }
      }
      entries.push({
        ...raw,
        id,
        pathRes: (raw.paths ?? []).map(globToRegExp),
        valueRe,
        used: false,
      });
    }
  });
  return { entries, errors };
}

function isAllowed(entries, { finding, raw }) {
  for (const e of entries) {
    if (e.rule !== '*' && e.rule !== finding.rule) continue;
    if (e.pathRes.length && !e.pathRes.some((re) => re.test(finding.file))) continue;
    if (e.valueEquals !== undefined && raw.value !== e.valueEquals) continue;
    if (e.valuePrefix && !raw.value.startsWith(e.valuePrefix)) continue;
    if (e.valueRe && !e.valueRe.test(raw.value)) continue;
    if (e.hosts && !e.hosts.includes(raw.host)) continue;
    e.used = true;
    return e;
  }
  return null;
}

// ----------------------------------------------------------------------- scan

/**
 * Scans a tree. Returns `{ filesScanned, findings, allowlisted, notices, errors, unusedAllow }`.
 * `findings` contains only masked data.
 */
export function scan({ root = defaultRoot, allowFile = defaultAllow } = {}) {
  const { entries, errors } = loadAllowlist(allowFile);
  const { files, ignoredSensitive } = listFiles(root);
  const found = [];
  const notices = [];
  let filesScanned = 0;

  for (const rel of files) {
    const base = path.posix.basename(rel);
    const kind = sensitiveKind(base);
    if (kind) {
      // Present and NOT ignored: it would be committed. Only the path is reported.
      found.push({
        finding: { file: rel, line: 0, rule: 'sensitive-file', masked: '(contents not read)', note: `${kind} would be tracked` },
        raw: { value: base },
      });
      continue;
    }
    if (LOCKFILES.has(base)) continue;
    if (BINARY_EXT.has(path.posix.extname(base).slice(1).toLowerCase())) continue;
    const abs = path.join(root, ...rel.split('/'));
    let st;
    try {
      st = lstatSync(abs);
    } catch {
      continue;
    }
    if (st.size > MAX_BYTES) {
      notices.push(`skipped ${rel}: ${(st.size / 1024 / 1024).toFixed(1)} MB (over the ${MAX_BYTES / 1024 / 1024} MB scan limit)`);
      continue;
    }
    const buf = readFileSync(abs);
    if (buf.subarray(0, 8000).includes(0)) continue; // binary
    filesScanned += 1;
    found.push(...scanText(rel, buf.toString('utf8')));
  }

  for (const rel of ignoredSensitive) notices.push(`ignored sensitive file present (not tracked, not scanned): ${rel}`);

  const findings = [];
  const allowlisted = [];
  for (const f of found) {
    const hit = isAllowed(entries, f);
    if (hit) allowlisted.push({ ...f.finding, allowedBy: hit.id });
    else findings.push(f.finding);
  }
  const unusedAllow = entries.filter((e) => !e.used).map((e) => e.id);
  return { filesScanned, findings, allowlisted, notices, errors, unusedAllow };
}

// ------------------------------------------------------------------------ CLI

function parseCli(argv) {
  const opts = { root: defaultRoot, allow: defaultAllow, json: false, list: false, verbose: false };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--json') opts.json = true;
    else if (a === '--list-files') opts.list = true;
    else if (a === '--verbose') opts.verbose = true;
    else if (a === '--root') opts.root = path.resolve(argv[(i += 1)] ?? '');
    else if (a === '--allow') opts.allow = path.resolve(argv[(i += 1)] ?? '');
    else throw new Error(`unknown argument ${a}`);
  }
  return opts;
}

function main() {
  let opts;
  try {
    opts = parseCli(process.argv.slice(2));
  } catch (e) {
    console.error(`secret-scan: ${e.message}`);
    console.error('usage: node scripts/secret-scan.mjs [--root DIR] [--allow FILE] [--json] [--list-files] [--verbose]');
    process.exit(2);
  }
  if (opts.list) {
    const { files } = listFiles(opts.root);
    console.log(files.join('\n'));
    return;
  }
  const result = scan({ root: opts.root, allowFile: opts.allow });
  if (opts.json) console.log(JSON.stringify(result, null, 2));
  else {
    for (const err of result.errors) console.error(`secret-scan: ERROR ${err}`);
    for (const f of result.findings) {
      console.error(`${f.file}${f.line ? `:${f.line}` : ''}  [${f.rule}]  ${f.masked}  ${f.note}`);
    }
    if (opts.verbose) for (const f of result.allowlisted) console.log(`allowlisted (${f.allowedBy}): ${f.file}:${f.line} [${f.rule}] ${f.masked}`);
    for (const n of result.notices) console.warn(`notice: ${n}`);
    for (const id of result.unusedAllow) console.warn(`notice: allowlist entry ${id} matched nothing (stale?)`);
    console.log(
      `secret-scan: ${result.filesScanned} files scanned, ${result.findings.length} finding(s), ` +
        `${result.allowlisted.length} allowlisted, ${result.notices.length} notice(s)`,
    );
  }
  if (result.findings.length || result.errors.length) process.exit(1);
}

if (isMainModule(import.meta.url)) main();
