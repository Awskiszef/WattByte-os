// node --test scripts/check-docs.test.mjs
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { after, describe, it } from 'node:test';

import { check, indexProblems, relativeLinks, STALE_MARKER } from './check-docs.mjs';

const roots = [];
function tree(files) {
  const root = mkdtempSync(path.join(tmpdir(), 'wb-docs-'));
  roots.push(root);
  for (const [rel, content] of Object.entries(files)) {
    const abs = path.join(root, ...rel.split('/'));
    mkdirSync(path.dirname(abs), { recursive: true });
    writeFileSync(abs, content);
  }
  return root;
}
after(() => roots.forEach((r) => rmSync(r, { recursive: true, force: true })));

describe('relativeLinks', () => {
  it('finds relative targets, strips anchors, skips URLs, anchors-only and fenced code', () => {
    const text = ['[a](docs/A.md) [b](B.md#section) [c](https://example.test/x) [d](#top) [e](mailto:a@b.co)', '```', '[f](nowhere.md)', '```', '[g](C.md "title")'].join('\n');
    assert.deepEqual(relativeLinks(text).map((l) => l.target), ['docs/A.md', 'B.md', 'C.md']);
  });
});

describe('check', () => {
  const good = {
    'README.md': 'See [docs](docs/README.md) and [guide](docs/GUIDE.md).\n',
    'docs/README.md': '[guide](GUIDE.md)\n',
    'docs/GUIDE.md': 'Everything is implemented. [back](../README.md)\n',
    'docs/architecture.md': 'Sync uploads aggregates.\n',
  };

  it('accepts a consistent tree', () => {
    assert.deepEqual(check(tree({ ...good, 'docs/architecture.md': '[guide](GUIDE.md)\n' })).filter((p) => !p.includes('architecture')), []);
  });

  it('reports a page missing from the index', () => {
    const root = tree({ ...good, 'docs/ORPHAN.md': 'x\n' });
    assert.ok(check(root).includes('docs/ORPHAN.md is not linked from docs/README.md'));
    assert.deepEqual(indexProblems(path.join(root, 'docs'), '[guide](GUIDE.md) [architecture](architecture.md)'), ['docs/ORPHAN.md is not linked from docs/README.md']);
  });

  it('reports a link to a file that does not exist', () => {
    const root = tree({ ...good, 'docs/GUIDE.md': '[gone](MISSING.md) [ok](../README.md)\n' });
    assert.ok(check(root).some((p) => p.startsWith('docs/GUIDE.md:1:') && p.includes('MISSING.md')));
  });

  it('reports a plan-tense statement on a page that describes the present', () => {
    const root = tree({ ...good, 'docs/architecture.md': 'HTTPS (planned: generated Dart client)\n' });
    assert.ok(check(root).some((p) => p.startsWith('docs/architecture.md:1:')));
    assert.ok(STALE_MARKER.test('nothing is uploaded yet') && STALE_MARKER.test('[future] POST /usage/sync'));
    assert.ok(!STALE_MARKER.test('a plan for the unplanned'));
  });

  it('is clean on the repository itself', () => {
    assert.deepEqual(check(), []);
  });
});
