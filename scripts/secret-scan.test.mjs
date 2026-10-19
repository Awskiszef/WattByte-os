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

import { globToRegExp, isIgnored, listFiles, loadAllowlist, mask, parseGitignore, scan, scanText, sensitiveKind } from './secret-scan.mjs';

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
    assert.deepEqual(res.findings.map((f) => f.file), ['src/leak.ts']);
    assert.deepEqual(listFiles(root).files.sort(), ['.gitignore', 'bin/blob.dat', 'pnpm-lock.yaml', 'src/leak.ts', 'src/ok.ts']);
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
