// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// The pinned OpenAPI generator (audit E-06). One jar, one version, one SHA-256, the same for every machine and for CI:
//
//   scripts/openapi-generator.pin.json   version, download URL and SHA-256 of the jar
//
// The jar is downloaded once into a cache directory outside the repository, checked against the pinned hash and run
// with `java -jar`. Nothing is resolved through npm at generation time, so a new release of
// @openapitools/openapi-generator-cli (or of its dependencies) cannot change the generated client or run code in CI.
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
export const PIN_FILE = path.join(here, 'openapi-generator.pin.json');

/** Generator arguments shared by scripts/generate-dart-client.mjs and scripts/check-generated-client.mjs. */
export const DART_GENERATOR_ARGS = [
  'generate',
  '-i',
  'openapi.json',
  '-g',
  'dart',
  '-o',
  'out',
  '--additional-properties=pubName=wattbyte_api,pubLibrary=wattbyte_api,enumUnknownDefaultCase=true',
  '--global-property=apis,models,supportingFiles',
];

export function readPin(file = PIN_FILE) {
  const pin = JSON.parse(readFileSync(file, 'utf8'));
  for (const key of ['version', 'url', 'sha256']) {
    if (typeof pin[key] !== 'string' || !pin[key]) throw new Error(`${file}: "${key}" is missing`);
  }
  if (!/^[0-9a-f]{64}$/.test(pin.sha256)) throw new Error(`${file}: "sha256" must be 64 lowercase hex characters`);
  if (!pin.url.startsWith('https://')) throw new Error(`${file}: "url" must be https`);
  return pin;
}

export const sha256Of = (buf) => createHash('sha256').update(buf).digest('hex');

export function cacheDir() {
  return process.env.WATTBYTE_OPENAPI_GENERATOR_DIR || path.join(homedir(), '.cache', 'wattbyte', 'openapi-generator');
}

/**
 * Path of the verified jar. A cached jar is used only when its hash matches; otherwise the pinned URL is fetched,
 * verified BEFORE it is moved into place, and a mismatch throws without leaving anything behind.
 * `fetchBytes` is injectable for tests.
 */
export async function ensureGeneratorJar({
  pin = readPin(),
  dir = cacheDir(),
  fetchBytes = async (url) => {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`GET ${url} -> ${res.status}`);
    return Buffer.from(await res.arrayBuffer());
  },
  log = (m) => console.warn(m),
} = {}) {
  const jar = path.join(dir, `openapi-generator-cli-${pin.version}.jar`);
  if (existsSync(jar) && sha256Of(readFileSync(jar)) === pin.sha256) return jar;
  mkdirSync(dir, { recursive: true });
  log(`downloading openapi-generator ${pin.version} from ${pin.url}`);
  const bytes = await fetchBytes(pin.url);
  const got = sha256Of(bytes);
  if (got !== pin.sha256) {
    throw new Error(`openapi-generator ${pin.version}: SHA-256 is ${got}, the pin says ${pin.sha256}; refusing to use it`);
  }
  const part = `${jar}.${process.pid}.part`;
  try {
    writeFileSync(part, bytes);
    renameSync(part, jar);
  } finally {
    rmSync(part, { force: true });
  }
  return jar;
}

/** Runs the generator on `openapi.json` in `cwd` (an ASCII-only directory: the generator mangles other paths). */
export function runGenerator(jar, cwd, { stdio = 'inherit' } = {}) {
  return spawnSync('java', ['-jar', jar, ...DART_GENERATOR_ARGS], { cwd, encoding: 'utf8', stdio, maxBuffer: 64 * 1024 * 1024 });
}
