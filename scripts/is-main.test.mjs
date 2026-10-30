// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// E-13 / C-10: an ESM main-module guard must also fire when the script is started through a symlink.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { isMainModule } from './is-main.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));

test('isMainModule: real path, symlink and relative path are the main module; others are not', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'wb-ismain-'));
  try {
    const real = path.join(dir, 'real.mjs');
    writeFileSync(real, 'export {};\n');
    const link = path.join(dir, 'link.mjs');
    symlinkSync(real, link);
    const url = pathToFileURL(real).href;
    assert.equal(isMainModule(url, real), true);
    assert.equal(isMainModule(url, link), true);
    assert.equal(isMainModule(url, path.relative(process.cwd(), link)), true);
    assert.equal(isMainModule(url, path.join(dir, 'other.mjs')), false);
    assert.equal(isMainModule(url, undefined), false);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('wait-for-db started through a symlink runs (usage error exit 2), it does not silently exit 0', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'wb-ismain-'));
  try {
    const link = path.join(dir, 'wait-for-db-link.mjs');
    symlinkSync(path.join(here, 'wait-for-db.mjs'), link);
    const env = { ...process.env };
    delete env.DATABASE_URL;
    delete env.TEST_DATABASE_URL;
    const r = spawnSync(process.execPath, [link], { env, encoding: 'utf8' });
    assert.equal(r.status, 2, `stdout=${r.stdout} stderr=${r.stderr}`);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
