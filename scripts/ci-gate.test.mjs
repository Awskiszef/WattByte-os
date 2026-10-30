// node --test scripts/ci-gate.test.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { gate, JOB_FLAGS } from './ci-gate.mjs';

const ALL_OFF = Object.fromEntries(Object.values(JOB_FLAGS).filter(Boolean).map((f) => [f, 'false']));
const needs = (flags, results) => ({
  changes: { result: 'success', outputs: { ...ALL_OFF, ...flags } },
  hygiene: { result: 'success' },
  'public-config': { result: 'success' },
  ...Object.fromEntries(Object.keys(JOB_FLAGS).filter((j) => j !== 'hygiene' && j !== 'public-config').map((j) => [j, { result: 'skipped' }])),
  ...results,
});

describe('CI result gate', () => {
  it('docs-only: hygiene succeeded and everything else skipped is a pass', () => {
    assert.equal(gate(needs({}, {})).ok, true);
  });
  it('a needed job that was skipped is a failure, not a pass', () => {
    const r = gate(needs({ web: 'true' }, { web: { result: 'skipped' } }));
    assert.equal(r.ok, false);
    assert.match(r.lines.join('\n'), /web: skipped but this change needs it/);
  });
  it('a needed job that succeeded passes', () => {
    assert.equal(gate(needs({ web: 'true' }, { web: { result: 'success' } })).ok, true);
  });
  it('failed, cancelled and missing jobs fail the gate whether or not they were needed', () => {
    for (const result of ['failure', 'cancelled']) {
      assert.equal(gate(needs({ web: 'true' }, { web: { result } })).ok, false, `needed ${result}`);
      assert.equal(gate(needs({}, { web: { result } })).ok, false, `unneeded ${result}`);
    }
    const n = needs({ web: 'true' }, {});
    delete n.web;
    assert.equal(gate(n).ok, false);
  });
  it('hygiene must always succeed', () => {
    assert.equal(gate(needs({}, { hygiene: { result: 'skipped' } })).ok, false);
    assert.equal(gate(needs({}, { hygiene: { result: 'failure' } })).ok, false);
  });
  it('the Public Configuration Security Gate must always succeed: skipped, failed or cancelled all fail CI result', () => {
    for (const result of ['skipped', 'failure', 'cancelled']) assert.equal(gate(needs({}, { 'public-config': { result } })).ok, false, result);
    const n = needs({}, {});
    delete n['public-config'];
    assert.equal(gate(n).ok, false, 'missing');
  });
  it('without a successful scope job nothing is trusted', () => {
    const n = needs({}, {});
    n.changes.result = 'failure';
    assert.equal(gate(n).ok, false);
    assert.equal(gate({}).ok, false);
  });
  it('a flag that is neither true nor false is an error, not a skip', () => {
    assert.equal(gate(needs({ ios: 'maybe' }, {})).ok, false);
  });
  it('a job nobody wrote a rule for is rejected', () => {
    assert.equal(gate(needs({}, { surprise: { result: 'success' } })).ok, false);
  });
});

describe('ci.yml and the gate agree', () => {
  const yml = readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '.github', 'workflows', 'ci.yml'), 'utf8');
  const jobBlock = (id) => {
    const m = new RegExp(`^  ${id}:\\n([\\s\\S]*?)(?=^  [a-z0-9-]+:\\n|(?![\\s\\S]))`, 'm').exec(yml);
    return m ? m[1] : null;
  };
  it('every job the gate knows exists, is listed in the gate job `needs`, and is switched by its own flag', () => {
    const gateBlock = jobBlock('ci-ok');
    assert.ok(gateBlock, 'job ci-ok exists');
    for (const [job, flag] of Object.entries(JOB_FLAGS)) {
      const block = jobBlock(job);
      assert.ok(block, `job ${job} exists in ci.yml`);
      assert.match(gateBlock, new RegExp(`^\\s+- ${job}$`, 'm'), `${job} is in the needs of ci-ok`);
      if (flag) assert.match(block, new RegExp(`if: needs\\.changes\\.outputs\\.${flag} == 'true'`), `${job} runs only when ${flag}`);
      else assert.doesNotMatch(block, /^\s{4}if:/m, `${job} always runs`);
    }
  });
  it('the gate job always runs and every `changes` output it relies on is published', () => {
    assert.match(jobBlock('ci-ok'), /if: always\(\)/);
    const changes = jobBlock('changes');
    for (const flag of Object.values(JOB_FLAGS).filter(Boolean)) assert.match(changes, new RegExp(`${flag}: \\$\\{\\{ steps\\.scope\\.outputs\\.${flag} \\}\\}`), flag);
  });
});
