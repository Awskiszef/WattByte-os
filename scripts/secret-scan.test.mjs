// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// node --test scripts/secret-scan.test.mjs
//
// Key-shaped fixtures are assembled at run time from pieces so this file never
// contains a literal that the scanner (which scans itself) would have to allow.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { after, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { decodeFile, entropy, globToRegExp, isIgnored, listFiles, loadAllowlist, mask, parseGitignore, scan, scanText, sensitiveKind, trackedFiles } from './secret-scan.mjs';

const cli = path.join(path.dirname(fileURLToPath(import.meta.url)), 'secret-scan.mjs');
const body = (n) => 'aB3dE5gH7jK9mN1pQ3sT5vX7zA9cE1fG3hJ5kL7nP9rT2uW4yB6dF8hK0mR'.slice(0, n);
const join = (...parts) => parts.join('');

const tmpRoots = [];
function tree(files) {
  const root = mkdtempSync(path.join(tmpdir(), 'wb-secret-scan-'));
  tmpRoots.push(root);
  for (const [rel, content] of Object.entries(files)) {
    const abs = path.join(root, ...rel.split('/'));
    mkdirSync(path.dirname(abs), { recursive: true });
    writeFileSync(abs, content);
  }
  return root;
}
after(() => {
  for (const r of tmpRoots) rmSync(r, { recursive: true, force: true });
});

const rulesOf = (rel, text) => scanText(rel, text).map((r) => r.finding.rule);

describe('mask', () => {
  it('shows the first four characters and the length, never the value', () => {
    const key = join('sk-', 'proj-', body(40));
    const m = mask(key);
    assert.ok(m.startsWith('sk-p'));
    assert.ok(m.includes(`(${key.length} chars)`));
    assert.ok(!m.includes(key.slice(0, 12)), 'only four characters may be revealed');
  });

  it('reveals less of a short value', () => {
    const m = mask('abcdefgh');
    assert.equal(m.startsWith('ab'), true);
    assert.ok(!m.includes('abcdefgh'));
    assert.ok(!mask('abc').includes('abc'));
  });
});

describe('provider keys', () => {
  const cases = [
    ['openai-key', join('sk-', 'proj-', body(48))],
    ['openai-key', join('sk-', body(48))],
    ['anthropic-key', join('sk-', 'ant-api03-', body(50))],
    ['google-api-key', join('AI', 'za', body(35))],
    ['xai-key', join('xai', '-', body(40))],
    ['aws-access-key', join('AK', 'IA', 'ABCDEFGHIJKLMNOP')],
    ['github-token', join('gh', 'p_', body(40))],
    ['slack-token', join('xo', 'xb-', '1234567890-', body(24))],
    ['stripe-key', join('sk', '_live_', body(26))],
  ];
  for (const [rule, key] of cases) {
    it(`flags ${rule} (${key.slice(0, 4)}...)`, () => {
      const hits = scanText('src/config.ts', `const value = "${key}";`);
      assert.deepEqual(
        hits.map((h) => h.finding.rule),
        [rule],
      );
      const printed = JSON.stringify(hits.map((h) => h.finding));
      assert.ok(!printed.includes(key), 'the finding must not contain the key');
      assert.ok(!printed.includes(key.slice(0, 16)), 'the finding must not contain a long prefix of the key');
    });
  }

  it('flags a PEM private key block without printing a value', () => {
    const hits = scanText('deploy/key.pem', `${join('-----BEGIN ', 'RSA PRIVATE KEY-----')}\nMIIE...\n`);
    assert.deepEqual(hits.map((h) => h.finding.rule), ['private-key-block']);
    assert.equal(hits[0].finding.masked, '(no value)');
  });

  it('flags a JWT-shaped string', () => {
    const jwt = join('ey', 'Jhbgc', body(12), '.', 'ey', 'Jzdwi', body(12), '.', body(30));
    assert.deepEqual(rulesOf('fixtures/a.json', `{"t": "${jwt}"}`), ['jwt']);
  });

  it('does not flag placeholders, short strings or look-alikes inside words', () => {
    for (const text of [
      'OPENAI_API_KEY=sk-your-key-here-xxxxxxxxxxxxxxxxxxxx',
      'const id = "task-scheduler-name-with-many-dashes-in-it";',
      'const d = "disk-encryption-key-material-label-text";',
      'the key AKIA is documented',
      'process.env.ANTHROPIC_API_KEY',
      'const xai = "xai-"',
      'const g = "AIza"',
    ]) {
      assert.deepEqual(rulesOf('docs/x.md', text), [], text);
    }
  });
});

describe('URLs with embedded passwords', () => {
  it('flags a real-looking password and masks it', () => {
    const pw = join('S3cr3t', 'Pw9z');
    const hits = scanText('apps/api/.env.example', `DATABASE_URL=postgres://svc_user:${pw}@db.internal:5432/app`);
    assert.deepEqual(hits.map((h) => h.finding.rule), ['url-password']);
    assert.ok(!JSON.stringify(hits.map((h) => h.finding)).includes(pw));
    assert.equal(hits[0].raw.host, 'db.internal');
  });

  it('ignores placeholders, interpolation and password-less URLs', () => {
    for (const text of [
      'postgres://user:password@localhost/db',
      'postgres://user:${DB_PASSWORD}@db/app',
      'postgres://user:$DB_PASSWORD@db/app',
      "'$scheme://$user:$password@$host'",
      'postgres://user:<password>@host/db',
      'https://example.com:8080/path',
      'postgres://user@host/db',
    ]) {
      assert.deepEqual(rulesOf('README.md', text), [], text);
    }
  });
});

describe('secret assignments', () => {
  it('flags literal values in env, yaml and code, but not in a different context', () => {
    assert.deepEqual(rulesOf('apps/api/.env.prod', `JWT_SECRET=${body(40)}`), ['secret-assignment']);
    assert.deepEqual(rulesOf('.github/workflows/x.yml', `        JWT_SECRET: ${body(40)}`), ['secret-assignment']);
    assert.deepEqual(rulesOf('src/a.ts', `const cfg = { password: '${body(14)}9' };`), ['secret-assignment']);
    assert.deepEqual(rulesOf('src/a.dart', `final apiKey = "${body(30)}";`), ['secret-assignment']);
    assert.deepEqual(rulesOf('data/a.json', `{"clientSecret": "${body(30)}"}`), ['secret-assignment']);
  });

  it('does not flag placeholders, references, identifiers or prose', () => {
    for (const [rel, text] of [
      ['apps/api/.env.example', 'JWT_SECRET=change-me-to-a-long-random-secret-of-at-least-32-chars'],
      ['apps/api/.env.example', 'OPENAI_API_KEY='],
      ['src/a.ts', 'const token = process.env.API_TOKEN_VALUE_X;'],
      ['src/a.ts', 'password: string;'],
      ['src/a.ts', 'accessToken: tokenStore.read(),'],
      ['src/a.dart', "static const _refreshTokenKey = 'refresh_token_v2';"],
      ['lib/l10n/app_en.arb', '"passwordHint": "At least 8 characters long",'],
      ['lib/l10n/app_pl.arb', '"password": "Haslo"'],
      ['docs/AUDIT.md', 'Odświeżanie tokenu: współbieżne użycie tego samego refresh tokenu'],
      ['.github/workflows/x.yml', '          JWT_SECRET: ${{ secrets.JWT_SECRET }}'],
      ['scripts/x.sh', 'export JWT_SECRET="$(openssl rand -hex 32)"'],
      ['src/a.ts', "if (password === 'something-literal-here1') return;"],
    ]) {
      assert.deepEqual(rulesOf(rel, text), [], `${rel}: ${text}`);
    }
  });

  it('flags a dictionary-word passphrase assigned to a SECRET name, not to a key-name constant', () => {
    const phrase = join('correct-horse-', 'battery-staple-long');
    assert.deepEqual(rulesOf('src/a.ts', `JWT_SECRET: '${phrase}'`), ['secret-assignment']);
    assert.deepEqual(rulesOf('src/a.ts', "const kTokenKey = 'refresh_token_storage_key';"), []);
  });
});

describe('keystore passwords', () => {
  it('flags literal store/key passwords in gradle and properties files', () => {
    assert.deepEqual(rulesOf('android/key.properties.local', `storePassword=${body(12)}7`), ['keystore-password']);
    assert.deepEqual(rulesOf('android/app/build.gradle.kts', `storePassword = "${body(12)}7"`), ['keystore-password']);
    assert.deepEqual(rulesOf('android/key.properties', `keyPassword=${body(12)}7`), ['keystore-password']);
  });

  it('accepts placeholders and environment lookups', () => {
    assert.deepEqual(rulesOf('android/key.properties.example', 'storePassword=CHANGE_ME'), []);
    assert.deepEqual(rulesOf('android/app/build.gradle.kts', 'storePassword = signingValue("storePassword", "WATTBYTE_KEYSTORE_PASSWORD")'), []);
    assert.deepEqual(rulesOf('android/app/build.gradle.kts', 'storePassword = System.getenv("X")'), []);
  });
});

describe('sensitive files', () => {
  it('classifies by name', () => {
    assert.ok(sensitiveKind('.env'));
    assert.ok(sensitiveKind('.env.production'));
    assert.ok(sensitiveKind('upload.jks'));
    assert.ok(sensitiveKind('release.keystore'));
    assert.ok(sensitiveKind('key.properties'));
    assert.ok(sensitiveKind('AuthKey_ABC.p8'));
    assert.ok(sensitiveKind('dev.mobileprovision'));
    assert.equal(sensitiveKind('.env.example'), null);
    assert.equal(sensitiveKind('key.properties.example'), null);
    assert.equal(sensitiveKind('environment.ts'), null);
  });

  it('flags a tracked-looking .env by path only and never reads it', () => {
    const marker = join('sk-', 'proj-', body(40));
    const root = tree({ 'apps/api/.env': `OPENAI_API_KEY=${marker}\nJWT_SECRET=${body(40)}\n`, 'README.md': '# hi\n' });
    const res = scan({ root, allowFile: path.join(root, 'none.json') });
    assert.deepEqual(res.findings.map((f) => [f.file, f.rule]), [['apps/api/.env', 'sensitive-file']]);
    assert.equal(res.findings[0].masked, '(contents not read)');
    assert.ok(!JSON.stringify(res).includes(marker));
    assert.ok(!JSON.stringify(res).includes(body(40)));
  });

  it('only notes an ignored .env or keystore, without opening it', () => {
    const marker = join('sk-', 'proj-', body(40));
    const root = tree({
      '.gitignore': '.env\n*.jks\n!.env.example\n',
      'apps/api/.env': `OPENAI_API_KEY=${marker}\n`,
      'apps/api/.env.example': 'JWT_SECRET=change-me-to-a-long-random-secret\n',
      'android/upload.jks': 'binary-ish',
    });
    const res = scan({ root, allowFile: path.join(root, 'none.json') });
    assert.deepEqual(res.findings, []);
    assert.deepEqual(res.notices.sort(), [
      'ignored sensitive file present (not tracked, not scanned): android/upload.jks',
      'ignored sensitive file present (not tracked, not scanned): apps/api/.env',
    ]);
    assert.ok(!JSON.stringify(res).includes(marker));
  });

  it('flags a keystore and key.properties that are not ignored', () => {
    const root = tree({ 'android/upload.keystore': 'x', 'android/key.properties': 'storePassword=x', 'ok.txt': 'fine' });
    const res = scan({ root, allowFile: path.join(root, 'none.json') });
    assert.deepEqual(res.findings.map((f) => f.file).sort(), ['android/key.properties', 'android/upload.keystore']);
  });
});

describe('gitignore emulation and file selection', () => {
  it('translates globs', () => {
    assert.ok(globToRegExp('**/build').test('a/b/build'));
    assert.ok(globToRegExp('**/build').test('build'));
    assert.ok(globToRegExp('*.jks').test('x.jks'));
    assert.ok(!globToRegExp('*.jks').test('a/x.jks'));
    assert.ok(globToRegExp('a/**/b').test('a/x/y/b'));
    assert.ok(globToRegExp('a/**/b').test('a/b'));
    assert.ok(globToRegExp('?.txt').test('a.txt'));
  });

  it('applies negation, anchoring, directory-only rules and nested files', () => {
    const rules = [
      ...parseGitignore('.env\n.env.*\n!.env.example\n/dist/\nbuild/\n*.log\n'),
      ...parseGitignore('!keep.log\nlocal/\n', 'apps/api'),
    ];
    assert.equal(isIgnored(rules, '.env', false), true);
    assert.equal(isIgnored(rules, 'apps/api/.env.local', false), true);
    assert.equal(isIgnored(rules, 'apps/api/.env.example', false), false);
    assert.equal(isIgnored(rules, 'dist', true), true);
    assert.equal(isIgnored(rules, 'apps/dist', true), false, 'anchored to the .gitignore directory');
    assert.equal(isIgnored(rules, 'x/build', true), true);
    assert.equal(isIgnored(rules, 'x/build', false), false, 'directory-only rule does not match a file');
    assert.equal(isIgnored(rules, 'a.log', false), true);
    assert.equal(isIgnored(rules, 'apps/api/keep.log', false), false);
    assert.equal(isIgnored(rules, 'apps/api/local', true), true);
    assert.equal(isIgnored(rules, 'apps/web/local', true), false);
  });

  it('skips ignored directories, lockfiles, binary and oversize content', () => {
    const key = join('sk-', 'proj-', body(40));
    const root = tree({
      '.gitignore': 'build/\n',
      'build/out.txt': `k=${key}`,
      'node_modules/pkg/index.js': `k="${key}"`,
      'pnpm-lock.yaml': `resolution: ${key}`,
      'bin/blob.dat': `\u0000${key}`,
      'src/ok.ts': 'export const ok = 1;\n',
      'src/leak.ts': `export const k = "${key}";\n`,
    });
    const res = scan({ root, allowFile: path.join(root, 'none.json') });
    // bin/blob.dat holds a NUL, so it is read as binary: its printable strings are still searched for provider keys (E-12).
    assert.deepEqual(res.findings.map((f) => f.file), ['bin/blob.dat', 'src/leak.ts']);
    assert.deepEqual(listFiles(root, { tracked: null }).files.sort(), ['.gitignore', 'bin/blob.dat', 'pnpm-lock.yaml', 'src/leak.ts', 'src/ok.ts']);
  });
});

describe('gitignore emulation against git itself', () => {
  const gitOk = spawnSync('git', ['--version'], { encoding: 'utf8' }).status === 0;

  it('lists exactly the files git would consider untracked-and-not-ignored', { skip: !gitOk && 'git is not installed' }, () => {
    const root = tree({
      '.gitignore': ['node_modules/', 'dist/', '.env', '.env.*', '!.env.example', '*.jks', '/tmp-root/', 'build/', '**/gen/*.g.dart', '*.log', '!keep.log', 'a/**/deep.txt'].join('\n') + '\n',
      'apps/api/.env': 'x',
      'apps/api/.env.example': 'x',
      'apps/api/.env.production': 'x',
      'apps/api/src/main.ts': 'x',
      'apps/api/dist/main.js': 'x',
      'apps/mobile/.gitignore': 'lib/l10n/generated/\n/local.properties\n!lib/keep/\n',
      'apps/mobile/lib/l10n/generated/a.dart': 'x',
      'apps/mobile/lib/l10n/app_en.arb': 'x',
      'apps/mobile/local.properties': 'x',
      'apps/mobile/lib/gen/a.g.dart': 'x',
      'apps/mobile/lib/gen/a.dart': 'x',
      'apps/mobile/android/upload.jks': 'x',
      'apps/mobile/android/build/out.txt': 'x',
      'tmp-root/a.txt': 'x',
      'sub/tmp-root/a.txt': 'x',
      'x.log': 'x',
      'keep.log': 'x',
      'a/b/c/deep.txt': 'x',
      'a/b/c/shallow.txt': 'x',
      'node_modules/pkg/index.js': 'x',
      'packages/x/node_modules/y/z.js': 'x',
    });
    const bare = mkdtempSync(path.join(tmpdir(), 'wb-bare-'));
    tmpRoots.push(bare);
    assert.equal(spawnSync('git', ['init', '--bare', '-q', bare]).status, 0);
    const out = spawnSync('git', [`--git-dir=${bare}`, `--work-tree=${root}`, 'ls-files', '--others', '--exclude-standard'], { encoding: 'utf8' });
    assert.equal(out.status, 0, out.stderr);
    const fromGit = out.stdout.split('\n').filter(Boolean).sort();
    assert.deepEqual(listFiles(root).files.sort(), fromGit);
  });
});

describe('allowlist', () => {
  const key = join('sk-', 'proj-', body(40));
  const run = (allow, files = { 'docs/a.md': `key: "${key}"\n` }) => {
    const root = tree({ ...files, 'allow.json': JSON.stringify(allow) });
    return scan({ root, allowFile: path.join(root, 'allow.json') });
  };

  it('suppresses a matching finding and keeps counting it', () => {
    const res = run({
      allow: [{ id: 'e1', rule: 'openai-key', paths: ['docs/**'], justification: 'documentation example that is not a real credential' }],
    });
    assert.deepEqual(res.findings, []);
    assert.equal(res.allowlisted.length, 1);
    assert.equal(res.allowlisted[0].allowedBy, 'e1');
    assert.deepEqual(res.unusedAllow, []);
  });

  it('does not suppress a finding in another path and reports the stale entry', () => {
    const res = run({
      allow: [{ id: 'e1', rule: 'openai-key', paths: ['tests/**'], justification: 'fixtures for the unit tests only, not real' }],
    });
    assert.equal(res.findings.length, 1);
    assert.deepEqual(res.unusedAllow, ['e1']);
  });

  it('matches by value and host', () => {
    const [pw, prodHost] = ['wattbyte', 'prod.example.org'];
    const files = { 'a.md': `DATABASE_URL=postgres://u:${pw}@localhost/db\nOTHER=postgres://u:${pw}@${prodHost}/db\n` };
    const res = run(
      {
        allow: [
          {
            id: 'dev-db',
            rule: 'url-password',
            valueEquals: 'wattbyte',
            hosts: ['localhost'],
            justification: 'documented local development database credentials',
          },
        ],
      },
      files,
    );
    assert.equal(res.allowlisted.length, 1);
    assert.equal(res.findings.length, 1);
    assert.equal(res.findings[0].line, 2);
  });

  it('rejects entries without a justification, or that would switch a rule off', () => {
    assert.match(loadAllowlist('x', () => JSON.stringify({ allow: [{ rule: 'jwt', paths: ['a'] }] })).errors[0], /justification/);
    assert.match(
      loadAllowlist('x', () => JSON.stringify({ allow: [{ rule: 'jwt', justification: 'a perfectly long written reason' }] })).errors[0],
      /needs "paths" or a value matcher/,
    );
    assert.match(loadAllowlist('x', () => JSON.stringify({ allow: [{ paths: ['a'], justification: 'a perfectly long written reason' }] })).errors[0], /rule/);
    assert.match(loadAllowlist('x', () => 'not json').errors[0], /cannot read allowlist/);
  });
});

describe('command line', () => {
  const node = process.execPath;

  it('exits 1 and prints only masked data for a finding', () => {
    const key = join('sk-', 'ant-api03-', body(50));
    const root = tree({ 'src/a.ts': `export const k = "${key}";\n` });
    const r = spawnSync(node, [cli, '--root', root, '--allow', path.join(root, 'none.json')], { encoding: 'utf8' });
    assert.equal(r.status, 1);
    const out = r.stdout + r.stderr;
    assert.match(out, /src\/a\.ts:1 {2}\[anthropic-key\] {2}sk-a/);
    assert.ok(!out.includes(key));
    assert.ok(!out.includes(key.slice(0, 14)));
  });

  it('exits 0 on a clean tree and 1 on an invalid allowlist', () => {
    const root = tree({ 'src/a.ts': 'export const a = 1;\n', 'bad.json': JSON.stringify({ allow: [{ rule: 'jwt', paths: ['x'] }] }) });
    assert.equal(spawnSync(node, [cli, '--root', root, '--allow', path.join(root, 'none.json')], { encoding: 'utf8' }).status, 0);
    assert.equal(spawnSync(node, [cli, '--root', root, '--allow', path.join(root, 'bad.json')], { encoding: 'utf8' }).status, 1);
  });

  it('exits 2 on an unknown argument', () => {
    assert.equal(spawnSync(node, [cli, '--nope'], { encoding: 'utf8' }).status, 2);
  });
});

// ---- audit E-01, E-02, E-11, E-12 ------------------------------------------------------------------------------

const gitAvailable = spawnSync('git', ['--version'], { encoding: 'utf8' }).status === 0;
const git = (root, ...args) => {
  const r = spawnSync('git', ['-C', root, '-c', 'user.email=t@example.test', '-c', 'user.name=t', ...args], { encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
};

describe('a tracked file is scanned even when .gitignore says to ignore it (E-01)', { skip: !gitAvailable && 'git is not installed' }, () => {
  it('opens a force-added ignored file and a tracked file in an ignored directory', () => {
    const key = join('sk-', 'proj-', body(40));
    const root = tree({
      '.gitignore': '.env.production\nvendor/\n',
      '.env.production': `OPENAI_API_KEY=${key}\n`,
      'vendor/lib/config.ts': `export const k = "${key}";\n`,
      'src/ok.ts': 'export const ok = 1;\n',
    });
    git(root, 'init', '-q');
    git(root, 'add', '-f', '.gitignore', '.env.production', 'vendor/lib/config.ts', 'src/ok.ts');
    assert.deepEqual([...trackedFiles(root)].sort(), ['.env.production', '.gitignore', 'src/ok.ts', 'vendor/lib/config.ts']);
    const res = scan({ root, allowFile: path.join(root, 'none.json') });
    const byFile = Object.fromEntries(res.findings.map((f) => [f.file, f.rule]));
    assert.equal(byFile['.env.production'], 'sensitive-file', 'a tracked .env file is reported by name');
    assert.equal(byFile['vendor/lib/config.ts'], 'openai-key', 'a tracked file inside an ignored directory is opened');
    assert.ok(res.notices.some((n) => n.startsWith('.env.production is tracked although')));
  });

  it('still leaves an untracked ignored file closed', () => {
    const root = tree({ '.gitignore': '.env\n', '.env': `JWT_SECRET=${body(40)}\n`, 'a.ts': 'export {};\n' });
    git(root, 'init', '-q');
    git(root, 'add', '.gitignore', 'a.ts');
    const res = scan({ root, allowFile: path.join(root, 'none.json') });
    assert.deepEqual(res.findings, []);
    assert.ok(res.notices.some((n) => n.includes('ignored sensitive file present')));
  });

  it('outside a repository the gitignore emulation alone decides', () => {
    const root = tree({ '.gitignore': 'x.ts\n', 'x.ts': 'a', 'y.ts': 'b' });
    assert.equal(trackedFiles(root), null);
    assert.deepEqual(listFiles(root).files.sort(), ['.gitignore', 'y.ts']);
  });
});

describe('realistic generated passwords are reported (E-02)', () => {
  it('does not mistake brackets, quotes-free symbols or ; , # inside a value for code', () => {
    const pw = 'aB3$(dE5)gH7[jK9]mN1{pQ3}';
    assert.deepEqual(rulesOf('src/a.ts', `const password = "${pw}";`), ['secret-assignment']);
    assert.deepEqual(rulesOf('app/.env.production', `DB_PASSWORD=${body(10)}#${body(8)};${body(6)},${body(5)}7`), ['secret-assignment']);
    assert.deepEqual(rulesOf('src/a.ts', join('const password = "aB3', '`dE5`gH7<jK9>mN1";')), ['secret-assignment']);
  });

  it('still treats real code and interpolation as references', () => {
    for (const [rel, text] of [
      ['src/a.ts', 'const password = "${process.env.DB_PASSWORD}";'],
      ['src/a.ts', 'const token = "getToken(account)";'],
      ['src/a.ts', 'const token = "cache[user][session]";'],
      ['src/a.dart', "accessToken: 'mock-access-$_counter',"],
      ['src/a.dart', "final secret = 'prefix-${config.name}-suffix';"],
      ['docs/a.md', 'JWT_SECRET=<openssl rand -base64 48>'],
    ]) {
      assert.deepEqual(rulesOf(rel, text), [], `${rel}: ${text}`);
    }
  });
});

describe('recall (E-11)', () => {
  it('catches typed declarations and the other secret names', () => {
    for (const text of [
      `const password: string = "${body(20)}7";`,
      `val dbPass: String = "${body(20)}7"`,
      `let apiToken: String = "${body(20)}7"`,
      `const PEPPER = "${body(20)}7";`,
      `final signingKey = '${body(20)}7';`,
      `DB_PASS = "${body(20)}7"`,
      `hmacKey: "${body(20)}7"`,
    ]) assert.deepEqual(rulesOf('src/a.ts', text), ['secret-assignment'], text);
  });

  it('reads extension-less and unlisted config files like config', () => {
    assert.deepEqual(rulesOf('infra/Procfile', `web: DB_PASSWORD=${body(20)}7 node main.js`), ['secret-assignment']);
    assert.deepEqual(rulesOf('.npmrc', `//registry.example.test/:_authToken=${body(30)}7`), ['secret-assignment']);
    assert.deepEqual(rulesOf('infra/main.tf', `password = ${body(20)}7`), ['secret-assignment']);
    assert.deepEqual(rulesOf('config/app.yml.local', `jwt_secret: ${body(30)}7`), ['secret-assignment']);
  });

  it('catches SQL role passwords and bearer headers', () => {
    assert.deepEqual(rulesOf('db/init.sql', `CREATE ROLE app LOGIN PASSWORD '${body(20)}7';`), ['sql-password']);
    assert.deepEqual(rulesOf('db/init.sql', `ALTER USER app WITH ENCRYPTED PASSWORD '${body(20)}7';`), ['sql-password']);
    assert.deepEqual(rulesOf('db/init.sql', "CREATE ROLE app PASSWORD 'change-me';"), []);
    assert.deepEqual(rulesOf('db/init.sql', "ALTER ROLE app PASSWORD :'pw';"), []);
    assert.deepEqual(rulesOf('scripts/call.sh', `curl -H "Authorization: Bearer ${body(32)}1"`), ['bearer-token']);
    assert.deepEqual(rulesOf('scripts/call.sh', 'curl -H "Authorization: Bearer $TOKEN"'), []);
    assert.deepEqual(rulesOf('src/a.ts', 'headers.set("Authorization", `Bearer ${token}`);'), []);
  });

  it('knows more provider key formats', () => {
    const cases = {
      'sendgrid-key': join('SG', '.', body(22), '.', body(43)),
      'npm-token': join('npm', '_', body(36)),
      'huggingface-token': join('hf', '_', body(36)),
      'groq-key': join('gsk', '_', body(48)),
      'resend-key': join('re', '_', body(8), '_', body(24)),
      'twilio-key': join('SK', 'a1b2c3d4e5f60718293a4b5c6d7e8f90'),
      'digitalocean-token': join('dop', '_v1_', 'a1b2c3d4e5f60718293a4b5c6d7e8f90'.repeat(2)),
      'mailgun-key': join('key', '-', 'a1b2c3d4e5f60718293a4b5c6d7e8f90'),
    };
    for (const [rule, value] of Object.entries(cases)) assert.deepEqual(rulesOf('src/a.ts', `fetch(u, { x: "${value}" });`), [rule], rule);
  });

  it('flags a long random string in a config file under any name, once, and not a hash or a word list', () => {
    const random = 'Zx9fQ2mLp7Vc4TnB8wYd1KsRh6GjUe3A';
    assert.ok(entropy(random) > 4.5);
    assert.deepEqual(rulesOf('deploy/app.yml', `    webhook: ${random}`), ['high-entropy-string']);
    assert.deepEqual(rulesOf('apps/api/.env.production', `X=${random}`), ['high-entropy-string']);
    assert.deepEqual(rulesOf('apps/api/.env.production', `SESSION_SECRET=${random}`), ['secret-assignment'], 'one finding per secret');
    for (const text of [
      '    image: ghcr.io/a/b@sha256:' + '0123456789abcdef'.repeat(4),
      '    uses: actions/checkout@' + '0123456789abcdef0123456789abcdef01234567',
      '    description: the-quick-brown-fox-jumps-over-the-lazy-dog-again',
      '    path: ' + 'abcdefghijklmnopqrstuvwxyzabcdefghij',
    ]) assert.deepEqual(rulesOf('deploy/app.yml', text), [], text);
    assert.deepEqual(rulesOf('src/a.ts', `const x = "${random}";`), [], 'not applied to source code');
  });
});

describe('files that used to be skipped silently (E-12)', () => {
  const key = join('sk-', 'proj-', body(40));

  it('decodes UTF-16 with and without a BOM', () => {
    const line = `export const k = "${key}";\n`;
    const le = Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from(line, 'utf16le')]);
    const be = Buffer.from(Buffer.from(line, 'utf16le')).swap16();
    const beBom = Buffer.concat([Buffer.from([0xfe, 0xff]), be]);
    const bare = Buffer.from(line, 'utf16le');
    for (const buf of [le, beBom, bare, be]) {
      const { text, binary } = decodeFile(buf);
      assert.equal(binary, false);
      assert.deepEqual(rulesOf('src/u.ts', text), ['openai-key']);
    }
  });

  it('reads a file with a stray NUL as binary and still searches its printable strings', () => {
    const buf = Buffer.concat([Buffer.from([0, 1, 2, 3]), Buffer.from(`\0\0token=${key}\0\0`), Buffer.from([0xff, 0, 7])]);
    const { text, binary } = decodeFile(buf);
    assert.equal(binary, true);
    assert.deepEqual(scanText('bin/x.dat', text, { binary }).map((r) => r.finding.rule), ['openai-key']);
    assert.deepEqual(scanText('bin/x.dat', `password="${body(20)}7"`, { binary: true }), [], 'assignments are not guessed at in binary data');
  });

  it('scans a long line in windows instead of skipping it', () => {
    const filler = 'x'.repeat(30000);
    assert.deepEqual(rulesOf('dist/app.js', `${filler};var k="${key}";${filler}`), ['openai-key']);
    // a key that straddles a window boundary is still found once
    const edge = 'y'.repeat(19700);
    assert.deepEqual(rulesOf('dist/app.js', `${edge}"${key}"${'z'.repeat(5000)}`), ['openai-key']);
  });

  it('reports a file over the size limit instead of passing it', () => {
    const root = tree({ 'big/data.txt': 'a' });
    // the limit is 32 MB; a sparse file of that size is cheap to create
    const abs = path.join(root, 'big', 'data.txt');
    writeFileSync(abs, Buffer.alloc(33 * 1024 * 1024, 0x61));
    const res = scan({ root, allowFile: path.join(root, 'none.json') });
    assert.deepEqual(res.findings.map((f) => [f.file, f.rule]), [['big/data.txt', 'file-not-scanned']]);
  });
});

describe('the repository .gitignore and the scanner agree on env files', () => {
  it('template names the scanner calls safe are not ignored, real env files are', async () => {
    const { readFileSync } = await import('node:fs');
    const rules = parseGitignore(readFileSync(path.join(path.dirname(cli), '..', '.gitignore'), 'utf8'));
    for (const template of ['.env.example', '.env.production.example', '.env.staging.example', '.env.sample', '.env.test.sample', '.env.dist', '.env.prod.dist', '.env.template']) {
      assert.equal(sensitiveKind(template), null, `${template} is a template for the scanner`);
      assert.equal(isIgnored(rules, template, false), false, `${template} must be trackable`);
      assert.equal(isIgnored(rules, `apps/api/${template}`, false), false, `apps/api/${template} must be trackable`);
    }
    for (const real of ['.env', '.env.production', '.env.local', '.env.production.local', 'apps/api/.env', 'prod.env']) {
      assert.equal(isIgnored(rules, real, false), true, `${real} must stay ignored`);
    }
  });
});
