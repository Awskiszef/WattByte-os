// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// node --test scripts/secret-scan-history.test.mjs
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { describe, it } from 'node:test';

import { parseAddedLines, scanHistory } from './secret-scan-history.mjs';

const key = ['sk-', 'proj-', 'aB3dE5gH7jK9mN1pQ3sT5vX7zA9cE1fG3hJ5kL7n'].join('');

describe('parseAddedLines', () => {
  it('keeps only added lines, per commit and file, and ignores deletions', () => {
    const log = ['@@@aaa', 'diff --git a/x b/x', '--- a/x', '+++ b/x', '@@ -0,0 +1,2 @@', '+one', '+two', '-gone', '@@@bbb', '--- a/y', '+++ /dev/null', '-removed', ''].join('\n');
    assert.deepEqual(parseAddedLines(log), [{ commit: 'aaa', file: 'x', text: 'one\ntwo' }]);
  });
});

describe('scanHistory on a real throw-away repository', () => {
  it('finds a key that was committed and deleted again, and a keystore that was added and removed', () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'wb-hist-'));
    const git = (...a) => execFileSync('git', ['-C', dir, '-c', 'user.email=t@example.test', '-c', 'user.name=t', ...a], { encoding: 'utf8' });
    try {
      git('init', '-q');
      writeFileSync(path.join(dir, 'config.ts'), `export const k = "${key}";\n`);
      writeFileSync(path.join(dir, 'upload.jks'), 'x');
      git('add', '-f', '.');
      git('commit', '-q', '-m', 'oops');
      git('rm', '-q', 'config.ts', 'upload.jks');
      git('commit', '-q', '-m', 'remove it');
      const res = scanHistory({ cwd: dir, allowFile: path.join(dir, 'none.json') });
      assert.equal(res.commits, 2);
      assert.deepEqual(res.findings.map((f) => f.rule).sort(), ['openai-key', 'sensitive-file']);
      assert.ok(res.findings.every((f) => !JSON.stringify(f).includes(key)), 'the value is masked');
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('is clean on the repository itself', () => {
    const res = scanHistory();
    assert.deepEqual(res.findings, []);
  });
});
