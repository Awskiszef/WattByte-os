// node --test scripts/check-workflow-pins.test.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { check, checkRelease, findUnpinned, jobBlocks } from './check-workflow-pins.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const sha = 'a'.repeat(40);

describe('findUnpinned', () => {
  it('accepts a full SHA (with a trailing comment), local actions and docker images', () => {
    const text = [`      - uses: actions/checkout@${sha} # v7`, '      - uses: ./.github/actions/x', '      - uses: docker://alpine:3'].join('\n');
    assert.deepEqual(findUnpinned(text), []);
  });

  it('rejects tags, branches, short SHAs and a missing ref', () => {
    const text = ['      - uses: actions/checkout@v7', '      - uses: a/b@main', '      - uses: a/c@abc1234', '      - uses: a/d', `        uses: a/e@${sha.slice(1)}`].join('\n');
    assert.deepEqual(findUnpinned(text).map((b) => b.uses), ['actions/checkout@v7', 'a/b@main', 'a/c@abc1234', 'a/d', `a/e@${sha.slice(1)}`]);
  });
});

const workflow = (jobs) => `name: Release\njobs:\n${jobs}\n`;
const guardJob = '  guard:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ok\n';

describe('checkRelease', () => {
  it('splits jobs', () => {
    assert.deepEqual(jobBlocks(workflow(`${guardJob}  build:\n    needs: guard\n    steps: []\n`)).map((j) => j.name), ['guard', 'build']);
  });

  it('accepts a gated build job without secrets and a signing job in the release environment', () => {
    const text = workflow(
      `${guardJob}  android-build:\n    needs: guard\n    steps:\n      - run: build\n  android-sign:\n    needs: [guard, android-build]\n    environment: release\n    steps:\n      - run: echo \${{ secrets.ANDROID_KEY_PASSWORD }}\n`,
    );
    assert.deepEqual(checkRelease(text), []);
  });

  it('flags a job that bypasses the guard, one that reads secrets without being a signing job, and a signing job outside the environment', () => {
    const text = workflow(
      `${guardJob}  sneaky:\n    steps:\n      - run: echo \${{ secrets.X }}\n  android-sign:\n    needs: guard\n    steps:\n      - run: echo \${{ secrets.Y }}\n`,
    );
    assert.deepEqual(checkRelease(text), [
      'job sneaky does not depend on guard',
      `job sneaky reads secrets but is not one of android-sign, ios-archive`,
      'job android-sign is not in the release environment',
    ]);
  });

  it('flags a missing guard', () => {
    assert.ok(checkRelease(workflow('  build:\n    steps: []\n')).includes('release.yml has no `guard` job'));
  });
});

describe('the repository workflows', () => {
  it('are pinned and the release workflow is gated', () => {
    const files = ['ci.yml', 'release.yml'].map((f) => path.join(root, '.github', 'workflows', f));
    assert.deepEqual(check(files), []);
    assert.match(readFileSync(files[1], 'utf8'), /^ {2}guard:$/m);
  });
});
