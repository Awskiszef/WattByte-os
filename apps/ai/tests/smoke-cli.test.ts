import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

/**
 * The real CLI, compiled and run as a separate process: exit codes, stdout and
 * the "configured provider fails -> non-zero" rule as a user of `pnpm smoke:ai`
 * sees them. `fetch` is replaced by a preload script, so nothing leaves the machine.
 */
const ROOT = join(import.meta.dirname, '..');
let OUT = '';
let PRELOAD = '';

beforeAll(() => {
  OUT = mkdtempSync(join(tmpdir(), 'wb-smoke-cli-'));
  PRELOAD = join(OUT, 'preload.mjs');
  symlinkSync(join(ROOT, 'node_modules'), join(OUT, 'node_modules')); // so the compiled code resolves `zod`
  mkdirSync(join(OUT, 'build'));
  writeFileSync(join(OUT, 'build', 'package.json'), '{"type":"module"}');
  execFileSync(join(ROOT, 'node_modules', '.bin', 'tsc'), ['-p', 'tsconfig.smoke.json', '--outDir', join(OUT, 'build')], { cwd: ROOT, stdio: 'pipe' });
  writeFileSync(
    PRELOAD,
    `
const mode = process.env.FAKE_FETCH_MODE;
globalThis.fetch = async (url, init) => {
  process.stderr.write('FETCH ' + url + '\\n');
  if (mode === 'unauthorized') return new Response(JSON.stringify({ error: { type: 'authentication_error', message: 'bad key ' + init.headers['x-api-key'] } }), { status: 401 });
  const text = JSON.stringify({ title: 'Heavy month', message: 'More data than usual.', tone: 'normal', severity: 'info', emoji: '⚡' });
  const body = String(url).includes('anthropic')
    ? { model: 'fake-model', content: [{ type: 'text', text }], usage: { input_tokens: 300, output_tokens: 40 } }
    : { model: 'fake-model', choices: [{ message: { content: text } }], usage: { prompt_tokens: 300, completion_tokens: 40 } };
  return new Response(JSON.stringify(body), { status: 200 });
};
`,
  );
}, 120_000);

afterAll(() => {
  // unlink the symlink first so the recursive removal can never reach the real node_modules
  rmSync(join(OUT, 'node_modules'), { force: true });
  rmSync(OUT, { recursive: true, force: true });
});

function cli(env: Record<string, string>) {
  const r = spawnSync(process.execPath, ['--import', PRELOAD, join(OUT, 'build', 'scripts', 'smoke.js')], {
    cwd: ROOT,
    env: { PATH: process.env.PATH ?? '', ...env },
    encoding: 'utf8',
    timeout: 30_000,
  });
  return { code: r.status, stdout: r.stdout, stderr: r.stderr };
}

describe('smoke:ai CLI process', () => {
  it('no keys: four NOT VERIFIED lines, exit 0, no request', () => {
    const r = cli({});
    expect(r.code).toBe(0);
    expect(r.stdout.trim().split('\n').slice(1)).toEqual([
      'openai: NOT VERIFIED — API KEY MISSING',
      'anthropic: NOT VERIFIED — API KEY MISSING',
      'google: NOT VERIFIED — API KEY MISSING',
      'xai: NOT VERIFIED — API KEY MISSING',
      'summary: 0 verified, 0 failed, 4 not verified (exit 0)',
    ]);
    expect(r.stderr).not.toContain('FETCH');
  });

  it('a configured provider that answers correctly: OK line, exit 0, one request, key not printed, ambient base URL ignored', () => {
    const r = cli({ ANTHROPIC_API_KEY: 'sk-ant-LEAKCHECK', ANTHROPIC_FAST_MODEL: 'some-model', ANTHROPIC_BASE_URL: 'http://127.0.0.1:1/other-tool' });
    expect(r.code).toBe(0);
    expect(r.stdout).toMatch(/^anthropic: OK model=fake-model latency_ms=\d+ input_tokens=300 output_tokens=40 est_cost_usd=0\.001500 \(provider_estimate\)$/m);
    expect(r.stdout).toContain('openai: NOT VERIFIED — API KEY MISSING');
    expect(r.stderr.trim().split('\n')).toEqual(['FETCH https://api.anthropic.com/v1/messages']);
    expect(r.stdout + r.stderr).not.toContain('LEAKCHECK');
  });

  it('a configured provider that fails: FAILED line, exit 1, key not printed even though the provider echoed it', () => {
    const r = cli({ OPENAI_API_KEY: 'sk-oa-LEAKCHECK', OPENAI_FAST_MODEL: 'm', FAKE_FETCH_MODE: 'unauthorized' });
    expect(r.code).toBe(1);
    expect(r.stdout).toContain('openai: FAILED — openai: HTTP 401 (authentication_error)');
    expect(r.stdout).toContain('summary: 0 verified, 1 failed, 3 not verified (exit 1)');
    expect(r.stdout + r.stderr).not.toContain('LEAKCHECK');
  });

  it('a key without a model is NOT VERIFIED — MODEL MISSING and still exit 0', () => {
    const r = cli({ XAI_API_KEY: 'sk-xai-LEAKCHECK' });
    expect(r.code).toBe(0);
    expect(r.stdout).toContain('xai: NOT VERIFIED — MODEL MISSING');
    expect(r.stdout + r.stderr).not.toContain('LEAKCHECK');
  });
});
