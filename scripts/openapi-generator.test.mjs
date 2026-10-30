// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// node --test scripts/openapi-generator.test.mjs
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { after, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { DART_GENERATOR_ARGS, ensureGeneratorJar, PIN_FILE, readPin, sha256Of } from './openapi-generator.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dirs = [];
const tmp = () => {
  const d = mkdtempSync(path.join(tmpdir(), 'wb-gen-'));
  dirs.push(d);
  return d;
};
after(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

const bytes = Buffer.from('pretend this is a jar');
const pinFor = (b) => ({ version: '9.9.9', url: 'https://example.test/g.jar', sha256: sha256Of(b) });

describe('the generator pin (E-06)', () => {
  it('is complete, https and agrees with openapitools.json', () => {
    const pin = readPin();
    assert.match(pin.sha256, /^[0-9a-f]{64}$/);
    assert.ok(pin.url.startsWith('https://repo1.maven.org/'));
    assert.ok(pin.url.endsWith(`openapi-generator-cli-${pin.version}.jar`));
    const cli = JSON.parse(readFileSync(path.join(root, 'openapitools.json'), 'utf8'));
    assert.equal(cli['generator-cli'].version, pin.version, 'openapitools.json and the pin must name the same generator');
  });

  it('is rejected when a field is missing or the hash is malformed', () => {
    const dir = tmp();
    const bad = path.join(dir, 'pin.json');
    writeFileSync(bad, JSON.stringify({ version: '1', url: 'https://x.test/a.jar', sha256: 'abc' }));
    assert.throws(() => readPin(bad), /64 lowercase hex/);
    writeFileSync(bad, JSON.stringify({ version: '1', url: 'http://x.test/a.jar', sha256: 'a'.repeat(64) }));
    assert.throws(() => readPin(bad), /https/);
    writeFileSync(bad, JSON.stringify({ version: '1' }));
    assert.throws(() => readPin(bad), /"url" is missing/);
    assert.ok(existsSync(PIN_FILE));
  });

  it('shares one argument list that pins the dart generator and the enum behaviour', () => {
    assert.ok(DART_GENERATOR_ARGS.includes('dart'));
    assert.ok(DART_GENERATOR_ARGS.some((a) => a.includes('enumUnknownDefaultCase=true')));
  });
});

describe('ensureGeneratorJar', () => {
  it('downloads once, stores it under the pinned name and reuses it', async () => {
    const dir = tmp();
    let fetches = 0;
    const opts = { pin: pinFor(bytes), dir, log: () => {}, fetchBytes: async () => (fetches += 1, bytes) };
    const jar = await ensureGeneratorJar(opts);
    assert.equal(path.basename(jar), 'openapi-generator-cli-9.9.9.jar');
    assert.deepEqual(readFileSync(jar), bytes);
    assert.equal(await ensureGeneratorJar(opts), jar);
    assert.equal(fetches, 1);
  });

  it('refuses a download whose hash differs and leaves nothing in the cache', async () => {
    const dir = tmp();
    await assert.rejects(
      ensureGeneratorJar({ pin: pinFor(bytes), dir, log: () => {}, fetchBytes: async () => Buffer.from('tampered') }),
      /refusing to use it/,
    );
    assert.deepEqual(readdirSync(dir), []);
  });

  it('does not trust a cached jar that was replaced: it is fetched again and verified', async () => {
    const dir = tmp();
    const opts = { pin: pinFor(bytes), dir, log: () => {}, fetchBytes: async () => bytes };
    const jar = await ensureGeneratorJar(opts);
    writeFileSync(jar, 'evil');
    assert.equal(await ensureGeneratorJar(opts), jar);
    assert.deepEqual(readFileSync(jar), bytes);
    writeFileSync(jar, 'evil');
    await assert.rejects(ensureGeneratorJar({ ...opts, fetchBytes: async () => Buffer.from('also evil') }), /refusing/);
  });

  it('reports a failed download', async () => {
    await assert.rejects(
      ensureGeneratorJar({ pin: pinFor(bytes), dir: tmp(), log: () => {}, fetchBytes: async () => { throw new Error('offline'); } }),
      /offline/,
    );
  });
});
