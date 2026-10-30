// Tests for scripts/check-public-config.mjs with synthetic repositories. Every "secret" is assembled from fragments at run
// time, so this file contains no literal that looks like a credential, and none of them is valid for any service.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';

import { DEFAULT_ALLOWLIST, globToRegExp, isConfigLike, loadAllowlist, main, scanText } from './check-public-config.mjs';

const ALLOW = {
  allow: [
    { glob: '**/package.json', class: 'PUBLIC_BUILD_REQUIRED', reason: 'manifest', review: 'test' },
    { glob: 'apps/web/wrangler.example.jsonc', class: 'PUBLIC_EXAMPLE', reason: 'template', review: 'test' },
    { glob: 'config/settings.json', class: 'PUBLIC_SOURCE', reason: 'classified on purpose', review: 'test' },
  ],
  denyPaths: ['docs/remediation'],
};

function sh(cwd, ...args) {
  const r = spawnSync('git', ['-C', cwd, '-c', 'user.name=Test', '-c', 'user.email=test@users.noreply.github.com', '-c', 'commit.gpgsign=false', ...args], { encoding: 'utf8', env: { ...process.env, GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_SYSTEM: '/dev/null' } });
  assert.equal(r.status, 0, `git ${args.join(' ')}: ${r.stderr}`);
  return r.stdout;
}

/** A throw-away git repository holding `files` (path -> content), committed on main. */
function repo(files, { email = 'dev@users.noreply.github.com', message = 'initial' } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wb-pubcfg-'));
  sh(dir, 'init', '-q', '-b', 'main');
  write(dir, files);
  sh(dir, 'add', '-A');
  sh(dir, 'commit', '-q', '-m', message, `--author=Dev <${email}>`);
  return dir;
}
function write(dir, files) {
  for (const [p, c] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(dir, p)), { recursive: true });
    fs.writeFileSync(path.join(dir, p), c);
  }
}
function allowFile() {
  const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'wb-allow-')), 'allow.json');
  fs.writeFileSync(f, JSON.stringify(ALLOW));
  return f;
}
/** Runs the checker and returns { code, out } where out is everything it printed. */
function run(dir, extra = []) {
  const lines = [];
  const sink = { log: (s) => lines.push(String(s)), error: (s) => lines.push(String(s)) };
  const code = main(['--root', dir, '--allowlist', allowFile(), ...extra], sink);
  return { code, out: lines.join('\n') };
}
const rules = (out) => [...out.matchAll(/\[([a-z-]+)\]/g)].map((m) => m[1]);

const CLEAN = { 'package.json': '{"name":"x","private":true}\n', 'src/index.ts': 'export const x = 1;\n' };

test('a clean repository passes with exit code 0', () => {
  const r = run(repo(CLEAN));
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /0 finding\(s\)/);
});

test('private file NAMES fail whatever they contain', () => {
  const names = {
    '.env': 'A=1',
    'apps/api/.env.production': 'A=1',
    '.env.local': 'A=1',
    'prod.env': 'A=1',
    '.dev.vars': 'A=1',
    'android/key.properties': 'a=b',
    'ios/Flutter/Local.xcconfig': 'A=B',
    'app/google-services.json': '{}',
    'ios/GoogleService-Info.plist': '<plist/>',
    'keys/server.pem': 'x',
    'signing/release.keystore': 'x',
    'certs/app.p12': 'x',
    'AuthKey_ABC123.p8': 'x',
    'profiles/app.mobileprovision': 'x',
    'infra/terraform.tfstate': '{}',
    'infra/prod.tfvars': 'a=1',
    'apps/web/wrangler.jsonc': '{}',
    'backup/db.dump': 'x',
    'backup/db.sql.gz': 'x',
    'data/app.sqlite': 'x',
    'apps/ad-video/package.json': '{}',
    'apps/mobile/tool/ad_screens/run.dart': 'x',
    '.claude/launch.json': '{}',
    '.aws/credentials': 'x',
    'cfg/service-account-prod.json': '{}',
    'docs/remediation/PLAN.md': 'x',
  };
  const r = run(repo({ ...CLEAN, ...names }));
  assert.equal(r.code, 1);
  for (const p of Object.keys(names)) assert.ok(r.out.includes(`FAIL  ${p}`), `expected a finding for ${p}\n${r.out}`);
});

test('documented examples are allowed', () => {
  const ok = {
    '.env.example': 'DATABASE_URL=postgres://user:password@localhost:5432/db\n',
    '.env.production.example': 'JWT_SECRET=\n',
    'android/key.properties.example': 'storeFile=\n',
    'ios/Flutter/Local.xcconfig.example': 'DEVELOPMENT_TEAM = ABCDE12345\n',
    'infra/terraform.tfvars.example': 'region = "eu"\n',
    'apps/web/wrangler.example.jsonc': '{ "kv_namespaces": [{ "binding": "X", "id": "REPLACE_WITH_YOUR_KV_NAMESPACE_ID" }] }\n',
  };
  const r = run(repo({ ...CLEAN, ...ok }));
  assert.equal(r.code, 0, r.out);
});

test('an unknown configuration file is excluded until it is classified', () => {
  const dir = repo({ ...CLEAN, 'unknown/settings.yaml': 'a: 1\n' });
  const r = run(dir);
  assert.equal(r.code, 1);
  assert.deepEqual(rules(r.out), ['unclassified-config']);
  assert.equal(run(repo({ ...CLEAN, 'config/settings.json': '{"a":1}\n' })).code, 0);
});

test('credentials are found by content and the value is never printed', () => {
  const planted = {
    aws: 'AKIA' + 'ABCDEFGHIJKLMNOP',
    pem: '-----BEGIN ' + 'RSA PRIVATE KEY-----',
    openai: 'sk-' + 'proj-' + 'q'.repeat(12) + 'Z9x8Y7w6V5u4T3s2R1p0',
    github: 'ghp_' + 'A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8',
    cfAccount: '"account_' + 'id": "0123456789abcdef0123456789abcdef"',
    cfHost: 'https://demo-app.' + 'workers.dev/hook',
    conn: 'postgres://' + 'app:Zq8vTn4LxP2wRb@' + 'db.prod-cluster.example-corp.net:5432/app',
    userPath: '/Users/' + 'alice' + '/Downloads/project',
    nip: "nip: '" + '1234567890' + "'",
  };
  const files = { ...CLEAN };
  for (const [k, v] of Object.entries(planted)) files[`src/${k}.ts`] = `// ${v}\n`;
  const r = run(repo(files));
  assert.equal(r.code, 1);
  assert.deepEqual(
    new Set(rules(r.out)),
    new Set(['aws-access-key', 'private-key-block', 'provider-key', 'cloudflare-account-id', 'cloudflare-host', 'connection-string-credentials', 'local-user-path', 'business-registry-id']),
  );
  for (const v of Object.values(planted)) assert.ok(!r.out.includes(v.slice(4, 30)), `the output must not contain a planted value (${v.slice(0, 6)}…)`);
});

test('placeholders, local databases and made-up values do not trip the content rules', () => {
  const ok = [
    'postgres://wattbyte:wattbyte@localhost:5432/wattbyte',
    'postgres://user:password@host.example/db',
    'postgres://${USER}:${PASS}@db:5432/app',
    '/Users/<you>/project and C:\\Users\\<you>\\project',
    "nip: '0000000000'",
    '"id": "REPLACE_WITH_YOUR_KV_NAMESPACE_ID"',
  ].join('\n');
  assert.deepEqual(scanText(ok, 'docs/example.md'), []);
  assert.deepEqual(scanText(ok, 'wrangler.example.jsonc'), []);
});

test('configuration files get the stricter generic rules, source files and tests do not', () => {
  const token = ['Zk3Qm9Xv2L', 'p7Rt5Wd8Yn', '4Bc6Hs1Jf0Ga'].join('');
  const line = `"api_key": "${token}"`;
  assert.equal(scanText(line, 'app/config.json').some((f) => f.rule === 'generic-secret-assignment'), true);
  assert.equal(scanText(line, 'apps/api/tests/a.test.ts').length, 0);
  assert.equal(scanText('"api_key": "changeme-changeme-changeme-12"', 'app/config.json').length, 0);
});

test('a denied literal from a private list is found without being printed', () => {
  const dir = repo({ ...CLEAN, 'src/a.ts': 'const street = "Fictional Lane 12";\n' });
  const list = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'wb-lit-')), 'lit.txt');
  fs.writeFileSync(list, 'Fictional Lane 12\n');
  const r = run(dir, ['--deny-literals', list]);
  assert.equal(r.code, 1);
  assert.deepEqual(rules(r.out), ['denied-literal']);
  assert.ok(!r.out.includes('Fictional'));
});

test('history: a file that was deleted later is still found', () => {
  const dir = repo({ ...CLEAN, '.env': 'A=1\n' });
  sh(dir, 'rm', '-q', '.env');
  sh(dir, 'commit', '-q', '-m', 'remove it');
  assert.equal(run(dir).code, 0, 'the working tree itself is clean');
  const r = run(dir, ['--history']);
  assert.equal(r.code, 1);
  assert.match(r.out, /\.env.*\[env-file\].*in history/);
});

test('history: a credential added and removed again is still found', () => {
  const dir = repo({ ...CLEAN, 'src/a.ts': '// ' + 'AKIA' + 'ABCDEFGHIJKLMNOP' + '\n' });
  fs.writeFileSync(path.join(dir, 'src/a.ts'), 'export {};\n');
  sh(dir, 'commit', '-q', '-am', 'drop it');
  assert.equal(run(dir).code, 0);
  const r = run(dir, ['--history']);
  assert.equal(r.code, 1);
  assert.ok(rules(r.out).includes('aws-access-key'));
});

test('history: a personal author address and an address in a message fail, noreply addresses pass', () => {
  const personal = repo(CLEAN, { email: 'someone@' + 'gmail.com' });
  assert.ok(rules(run(personal, ['--history']).out).includes('author-email'));
  const inMessage = repo(CLEAN, { message: 'fix\n\nreported by someone@' + 'gmail.com' });
  assert.ok(rules(run(inMessage, ['--history']).out).includes('message-email'));
  const clean = repo(CLEAN, { email: '12345+dev@users.noreply.github.com' });
  assert.equal(run(clean, ['--history', '--strict-refs']).code, 0);
});

test('history: --strict-refs allows main and approved tags only', () => {
  const dir = repo(CLEAN);
  assert.equal(run(dir, ['--history', '--strict-refs']).code, 0);
  sh(dir, 'tag', 'v1.0.0');
  sh(dir, 'branch', 'internal-work');
  const r = run(dir, ['--history', '--strict-refs']);
  assert.equal(r.code, 1);
  assert.equal(rules(r.out).filter((x) => x === 'unapproved-ref').length, 2);
  sh(dir, 'branch', '-q', '-D', 'internal-work');
  assert.equal(run(dir, ['--history', '--strict-refs', '--allow-tag', 'v1.0.0']).code, 0);
});

test('a file over the size limit fails', () => {
  const dir = repo({ ...CLEAN });
  const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'wb-small-')), 'a.json');
  fs.writeFileSync(f, JSON.stringify({ ...ALLOW, maxFileBytes: 10 }));
  const lines = [];
  const code = main(['--root', dir, '--allowlist', f], { log: (s) => lines.push(s), error: (s) => lines.push(s) });
  assert.equal(code, 1);
  assert.ok(lines.join('\n').includes('[large-file]'));
});

test('exit code 2 for an unreadable or invalid allowlist', () => {
  const bad = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'wb-bad-')), 'a.json');
  fs.writeFileSync(bad, JSON.stringify({ allow: [{ glob: 'x', class: 'PRIVATE_SECRET', reason: 'r', review: 'r' }] }));
  const sink = { log: () => {}, error: () => {} };
  assert.equal(main(['--allowlist', bad], sink), 2);
  assert.equal(main(['--allowlist', '/nonexistent/allow.json'], sink), 2);
});

test('the committed allowlist is valid and every entry is reviewed', () => {
  const list = loadAllowlist(DEFAULT_ALLOWLIST);
  assert.ok(list.allow.length > 20);
  for (const e of list.allow) {
    assert.ok(e.reason.length > 8 && e.review.length > 4, e.glob);
    assert.match(e.class, /^PUBLIC_/);
  }
});

test('glob matching and the configuration-like test', () => {
  assert.ok(globToRegExp('**/package.json').test('package.json'));
  assert.ok(globToRegExp('**/package.json').test('apps/web/package.json'));
  assert.ok(!globToRegExp('*.json').test('a/b.json'));
  assert.ok(globToRegExp('apps/mobile/ios/**/*.plist').test('apps/mobile/ios/Runner/Info.plist'));
  assert.ok(isConfigLike('a/b/settings.yaml') && isConfigLike('Dockerfile') && isConfigLike('x/.gitignore'));
  assert.ok(!isConfigLike('src/index.ts') && !isConfigLike('README.md'));
});
