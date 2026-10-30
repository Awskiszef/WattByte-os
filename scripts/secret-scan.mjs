// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

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
import { execFileSync } from 'node:child_process';
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
const MAX_BYTES = 32 * 1024 * 1024;
const LINE_WINDOW = 20000;
const LINE_OVERLAP = 512;

/**
 * The files Git already tracks under `root` (paths relative to it, posix), or null when `root` is not
 * inside a repository or git is not installed. A tracked file is committed whatever .gitignore says
 * (`git add -f`, or a rule added after the file), so the walk must still look inside it (E-01).
 */
export function trackedFiles(root) {
  try {
    const out = execFileSync('git', ['-C', root, 'ls-files', '-z', '--cached'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      maxBuffer: 256 * 1024 * 1024,
    });
    return new Set(out.split('\0').filter(Boolean));
  } catch {
    return null;
  }
}

/**
 * Lists the files that would be tracked: what the .gitignore walk yields plus whatever Git itself already
 * tracks (`tracked`: a Set, or undefined to ask git, or null to skip that). Ignored files that are
 * sensitive by name and untracked are returned separately (never opened) so they can be reported as notices.
 */
export function listFiles(root, { tracked } = {}) {
  const trackedSet = tracked === undefined ? trackedFiles(root) : tracked;
  const files = [];
  const ignoredSensitive = [];
  const trackedIgnored = [];
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
          if (trackedSet?.has(rel)) {
            files.push(rel);
            trackedIgnored.push(rel);
          } else if (sensitiveKind(e.name)) ignoredSensitive.push(rel);
          continue;
        }
        files.push(rel);
      }
    }
  };
  walk(root, '', []);
  if (trackedSet) {
    // Tracked files inside a directory that .gitignore (or ALWAYS_SKIP_DIRS' siblings) hides from the walk.
    const seen = new Set(files);
    for (const rel of [...trackedSet].sort()) {
      if (seen.has(rel) || rel.split('/').some((part) => ALWAYS_SKIP_DIRS.has(part))) continue;
      let st;
      try {
        st = lstatSync(path.join(root, ...rel.split('/')));
      } catch {
        continue; // tracked but deleted in the work tree
      }
      if (!st.isFile()) continue;
      files.push(rel);
      trackedIgnored.push(rel);
    }
    files.sort();
  }
  return { files, ignoredSensitive, trackedIgnored, skippedLarge };
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
  /(change[-_ ]?me|changeit|your[-_ ]|example|placeholder|dummy|fake|sample|redacted|xxxx|todo|insert|replace|secret[-_]?here|not[-_]?a[-_]?real|<[A-Za-z][A-Za-z _-]*>|\*{3,}|\.{3,})/i;

const CONFIG_EXT = new Set([
  '.env', '.properties', '.yml', '.yaml', '.sh', '.bash', '.zsh', '.toml', '.ini', '.cfg', '.conf', '.xcconfig', '.md',
  '.tf', '.tfvars', '.hcl', '.txt', '.service', '.envrc', '.rc', '.tpl', '.tmpl', '.j2', '.list', '.vars', '.config', '.local',
]);

function isConfigLike(relPath) {
  const base = path.posix.basename(relPath);
  if (/^\.env/.test(base) || /^Dockerfile/.test(base)) return true;
  const ext = path.posix.extname(base).toLowerCase();
  // No extension at all (Makefile, Procfile, Jenkinsfile, .npmrc, .netrc ...) is a config file too, and so is
  // a name such as `settings.yml.local` whose last extension is a deployment suffix.
  if (ext === '') return true;
  if (CONFIG_EXT.has(ext)) return true;
  return /\.(env|ya?ml|properties|conf|ini|toml)\.[\w-]+$/i.test(base);
}

/**
 * Interpolation, a call, an index or a generic type: code, not a credential. A bracket on its own is not
 * enough (a generated password may contain any of ( ) [ ] { } < > and a backtick): the whole value has to
 * have the shape of the expression (E-02).
 */
function isCodeReference(v) {
  return (
    /\$\{[^}]*\}|\{\{.*\}\}|^\$[A-Za-z_{(]|^%\(\w+\)s$/.test(v) ||
    // `mock-access-$counter`: a bare $name only counts as interpolation when the rest is words and separators.
    (/\$[A-Za-z_]/.test(v) && /^[A-Za-z_.:/-]*$/.test(v.replace(/\$[A-Za-z_]\w*/g, ''))) ||
    /^<[^<>]*>$/.test(v) ||
    /^<[A-Za-z]/.test(v) || // the head of an `<angle placeholder with spaces>` cut at the first space
    /^[A-Za-z_$][\w.$]*\(.*\)$/.test(v) ||
    /^[A-Za-z_$][\w.$]*(?:\[[^\]]*\])+$/.test(v) ||
    /^[A-Za-z_][\w.]*<[\w\s,.?<>[\]]*>(?:\(.*\))?$/.test(v)
  );
}

/** A value that is code, not a credential: references, interpolation, identifiers. */
function isBenignValue(v, name = '') {
  if (v.length < 8) return true;
  if (/\s/.test(v)) return true; // natural language, not a credential
  if (/[^\x21-\x7E]/.test(v)) return true; // non-ASCII: prose, never a generated secret
  if (isCodeReference(v)) return true;
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
  { id: 'sendgrid-key', re: /(?<![A-Za-z0-9_.-])SG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}(?![A-Za-z0-9_-])/g, note: 'SendGrid API key' },
  { id: 'npm-token', re: /(?<![A-Za-z0-9_])npm_[A-Za-z0-9]{36}(?![A-Za-z0-9])/g, note: 'npm access token' },
  { id: 'huggingface-token', re: /(?<![A-Za-z0-9_])hf_[A-Za-z0-9]{34,}/g, note: 'Hugging Face token' },
  { id: 'groq-key', re: /(?<![A-Za-z0-9_])gsk_[A-Za-z0-9]{40,}/g, note: 'Groq API key' },
  { id: 'resend-key', re: /(?<![A-Za-z0-9_])re_[A-Za-z0-9]{6,}_[A-Za-z0-9]{16,}/g, note: 'Resend API key' },
  { id: 'twilio-key', re: /(?<![A-Za-z0-9])(?:AC|SK)[0-9a-f]{32}(?![A-Za-z0-9])/g, note: 'Twilio account SID or API key SID' },
  { id: 'google-oauth-token', re: /(?<![A-Za-z0-9_])ya29\.[A-Za-z0-9_-]{30,}/g, note: 'Google OAuth access token' },
  { id: 'pypi-token', re: /(?<![A-Za-z0-9_-])pypi-[A-Za-z0-9_-]{50,}/g, note: 'PyPI token' },
  { id: 'digitalocean-token', re: /(?<![A-Za-z0-9_])dop_v1_[a-f0-9]{64}/g, note: 'DigitalOcean token' },
  { id: 'shopify-token', re: /(?<![A-Za-z0-9_])shp(?:at|ss|ca|pa)_[a-f0-9]{32}/g, note: 'Shopify token' },
  { id: 'mailgun-key', re: /(?<![A-Za-z0-9_-])key-[0-9a-f]{32}(?![A-Za-z0-9])/g, note: 'Mailgun API key' },
  { id: 'supabase-token', re: /(?<![A-Za-z0-9_])sbp_[a-f0-9]{40}/g, note: 'Supabase access token' },
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
const SECRET_WORDS = [
  'secret', 'password', 'passwd', 'passphrase', 'pass(?![a-z])', 'pwd', 'pepper', 'token', 'credential', 'api[_-]?key',
  'private[_-]?key', 'access[_-]?key', '(?:signing|encryption|hmac|jwt|auth|session|master|license|webhook|service)[_-]?key',
].join('|');
const SECRET_NAME = `[A-Za-z0-9_.-]*(?:${SECRET_WORDS})[A-Za-z0-9_.-]*`;
// NAME = v, NAME: v, and typed declarations (`password: string = "v"`, `val dbPass: String = "v"`).
const ASSIGNMENT = new RegExp(
  `(?<![A-Za-z0-9_])(${SECRET_NAME})["']?(?:\\s*:\\s*[A-Za-z_][\\w.<>\\[\\]?|]*)?\\s*[:=]\\s*(?:"([^"\\n]*)"|'([^'\\n]*)'|\`([^\`\\n]*)\`|([^\\s"']+))`,
  'gi',
);
const KEYSTORE_RULE = 'keystore-password';
const KEYSTORE_NAME = /^(?:store|key)(?:password|pass)$|^(?:store|key)_password$/i;
// CREATE ROLE app PASSWORD 'v'; ALTER USER app WITH ENCRYPTED PASSWORD 'v'; IDENTIFIED BY 'v'
const SQL_PASSWORD = /\b(?:PASSWORD|IDENTIFIED\s+BY)\s+'((?:[^']|'')+)'/gi;
const BEARER = /\bBearer\s+([A-Za-z0-9._~+/=-]{20,})/g;
const TOKEN_CANDIDATE = /(?<![A-Za-z0-9+/_-])[A-Za-z0-9+/_-]{32,}={0,2}(?![A-Za-z0-9+/_-])/g;

/** Shannon entropy in bits per character. */
export function entropy(text) {
  const counts = new Map();
  for (const c of text) counts.set(c, (counts.get(c) ?? 0) + 1);
  let h = 0;
  for (const n of counts.values()) h -= (n / text.length) * Math.log2(n / text.length);
  return h;
}

/** A long random-looking token: mixed case and digits, not hex (a hash/commit id), not a path or a word list. */
function looksGenerated(v) {
  if (/^[0-9a-f]+$/i.test(v)) return false;
  if (!/[a-z]/.test(v) || !/[A-Z]/.test(v) || !/\d/.test(v)) return false;
  if (/^[A-Za-z0-9]+(?:[-_][A-Za-z]+){2,}$/.test(v) && !/\d/.test(v.replace(/^[A-Za-z]+/, ''))) return false;
  return entropy(v) >= 4.5;
}
const ENTROPY_FILES = /(?:^|\/)(?:\.env[\w.-]*|[^/]+\.(?:properties|ya?ml|toml|ini|cfg|conf|xcconfig|sh|bash|zsh|tf|tfvars|hcl|service|envrc))$/i;

/**
 * Scans one file's text. Returns `{ finding, raw }` pairs; `raw` (the secret itself)
 * is only used to match the allowlist and is never printed or serialised.
 */
export function scanText(relPath, text, { binary = false } = {}) {
  const out = [];
  const configLike = isConfigLike(relPath);
  const base = path.posix.basename(relPath);
  const isGradleOrProps = /\.(gradle|kts|properties)(\.[\w-]+)?$/.test(base);
  const lines = text.split(/\r?\n/);
  const seen = new Set();
  const reported = new Set(); // values some other rule already reported: one finding per secret
  const scanLine = (line, lineNo) => {
    const push = (rule, value, note, extra = {}) => {
      const key = `${lineNo}\0${rule}\0${value}`;
      if (seen.has(key)) return; // the overlap of two windows of one long line
      seen.add(key);
      if (value !== undefined) reported.add(value);
      out.push({
        finding: { file: relPath, line: lineNo, rule, masked: value === undefined ? '(no value)' : mask(value), note },
        raw: { value: value ?? '', ...extra },
      });
    };

    for (const rule of RULES) {
      for (const m of line.matchAll(rule.re)) {
        if (rule.skip?.(m[0])) continue;
        push(rule.id, rule.noValue ? undefined : m[0], rule.note);
      }
    }

    if (!binary) {
      for (const m of line.matchAll(SQL_PASSWORD)) {
        const v = m[1].replace(/''/g, "'");
        if (isPlaceholderPassword(v) || isBenignValue(v, 'password')) continue;
        push('sql-password', v, 'SQL statement sets a literal role password');
      }
      for (const m of line.matchAll(BEARER)) {
        const v = m[1];
        if (v.startsWith('eyJ') || !/\d/.test(v) || isBenignValue(v, 'token')) continue; // JWTs have their own rule
        push('bearer-token', v, 'Authorization header carries a literal bearer token');
      }
    }

    for (const m of line.matchAll(URL_PASSWORD)) {
      const [, scheme, user, pass, host] = m;
      if (isPlaceholderPassword(pass)) continue;
      push('url-password', pass, `${scheme}:// URL with an embedded password for user "${user}" at ${host}`, { host, user });
    }

    for (const m of binary ? [] : line.matchAll(ASSIGNMENT)) {
      const name = m[1];
      const quoted = m[2] ?? m[3] ?? m[4];
      const value = quoted ?? m[5]?.replace(/[,;]+$/, '');
      if (value === undefined) continue;
      // An unquoted value that runs straight into a quote is the head of an expression (`signingValue("x")`).
      if (quoted === undefined && /["']/.test(line[m.index + m[0].length] ?? '')) continue;
      if (quoted === undefined && !configLike && !isGradleOrProps) continue; // unquoted RHS in code is an expression
      // Markdown prose reads like "tokens: values"; only `NAME=value` counts there.
      const separator = m[0].slice(name.length).match(/[:=]/)?.[0];
      if (quoted === undefined && base.endsWith('.md') && separator !== '=') continue;
      if (isBenignValue(value, name)) continue;
      if (!/\d|[^A-Za-z0-9_.-]/.test(value) && value.length < 16) continue; // letters only and short: a word, not a secret
      const keystore = isGradleOrProps && KEYSTORE_NAME.test(name);
      push(keystore ? KEYSTORE_RULE : 'secret-assignment', value, `${name} is assigned a literal value`, { name });
    }

    if (!binary && ENTROPY_FILES.test(relPath)) {
      for (const m of line.matchAll(TOKEN_CANDIDATE)) {
        const v = m[0];
        if (reported.has(v) || !looksGenerated(v) || /^https?:/i.test(line.slice(Math.max(0, m.index - 8), m.index))) continue;
        if (/(?:sha\d*|integrity|checksum|digest|hash|commit)\b/i.test(line.slice(0, m.index))) continue;
        push('high-entropy-string', v, 'long random-looking string in a configuration file');
      }
    }
  };
  lines.forEach((line, idx) => {
    if (line.length <= LINE_WINDOW) return scanLine(line, idx + 1);
    // A minified blob is scanned in overlapping windows, not skipped: a key must not hide behind a long line (E-12).
    for (let at = 0; at < line.length; at += LINE_WINDOW - LINE_OVERLAP) {
      scanLine(line.slice(at, at + LINE_WINDOW), idx + 1);
      if (at + LINE_WINDOW >= line.length) break;
    }
  });
  return out;
}

/**
 * Text of a file for scanning. UTF-16 (BOM, or the telltale NUL in every other byte) is decoded; any other
 * file with a NUL is treated as binary and reduced to its printable runs instead of being skipped (E-12).
 */
export function decodeFile(buf) {
  if (buf.length >= 2 && buf[0] === 0xff && buf[1] === 0xfe) return { text: buf.subarray(2).toString('utf16le'), binary: false };
  if (buf.length >= 2 && buf[0] === 0xfe && buf[1] === 0xff) {
    const swapped = Buffer.from(buf.subarray(2));
    swapped.swap16();
    return { text: swapped.toString('utf16le'), binary: false };
  }
  const head = buf.subarray(0, 8000);
  if (!head.includes(0)) return { text: buf.toString('utf8'), binary: false };
  let evenNul = 0;
  let oddNul = 0;
  for (let i = 0; i < head.length; i += 1) if (head[i] === 0) (i % 2 ? (oddNul += 1) : (evenNul += 1));
  const half = head.length / 2;
  if (oddNul > half * 0.3 && evenNul === 0) return { text: buf.toString('utf16le'), binary: false };
  if (evenNul > half * 0.3 && oddNul === 0) {
    const swapped = Buffer.from(buf);
    swapped.swap16();
    return { text: swapped.toString('utf16le'), binary: false };
  }
  const runs = buf.toString('latin1').match(/[\x20-\x7e]{12,}/g) ?? [];
  return { text: runs.join('\n'), binary: true };
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

export function isAllowed(entries, { finding, raw }) {
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
  const { files, ignoredSensitive, trackedIgnored } = listFiles(root);
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
      // Not looking is not the same as clean: a file this large has to be allowlisted by name on purpose.
      found.push({
        finding: {
          file: rel,
          line: 0,
          rule: 'file-not-scanned',
          masked: '(contents not read)',
          note: `${(st.size / 1024 / 1024).toFixed(1)} MB is over the ${MAX_BYTES / 1024 / 1024} MB scan limit`,
        },
        raw: { value: base },
      });
      continue;
    }
    const buf = readFileSync(abs);
    filesScanned += 1;
    const { text, binary } = decodeFile(buf);
    if (binary) notices.push(`${rel} looks binary: only provider keys, private-key blocks, JWTs and URL passwords were looked for in its printable strings`);
    found.push(...scanText(rel, text, { binary }));
  }

  for (const rel of ignoredSensitive) notices.push(`ignored sensitive file present (not tracked, not scanned): ${rel}`);
  for (const rel of trackedIgnored) notices.push(`${rel} is tracked although .gitignore ignores it (scanned like any tracked file)`);

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
