import { randomBytes, scrypt as scryptCb, timingSafeEqual } from 'node:crypto';

import { HttpError } from '../../errors/http-error.js';

// scrypt from the Node standard library: no native build step, memory-hard.
// N=2^16, r=8, p=1 needs 64 MiB per hash (OWASP-recommended tier); Node's
// default maxmem is 32 MiB, so it is raised explicitly.
const N = 2 ** 16;
const R = 8;
const P = 1;
const KEY_LEN = 64;
const MAX_MEM = 256 * 1024 * 1024;

interface ScryptParams {
  N: number;
  r: number;
  p: number;
}

export interface HashingLimits {
  /** Hashes that run at once; each one holds 64 MiB and one libuv thread. */
  concurrency: number;
  /** Hashes that may wait for a slot; the next one is refused with 503 instead of queueing without bound. */
  maxQueue: number;
}

// Process-wide on purpose: the resource being protected (memory and the shared libuv pool) is process-wide.
let limits: HashingLimits = { concurrency: 2, maxQueue: 8 };
let running = 0;
const waiting: (() => void)[] = [];

export function configurePasswordHashing(next: HashingLimits): void {
  limits = next;
}

/** For tests and diagnostics. */
export function passwordHashingLoad(): { running: number; waiting: number } {
  return { running, waiting: waiting.length };
}

/**
 * Runs `work` in one of `limits.concurrency` slots. An unbounded queue of 64 MiB hashes starves the libuv pool
 * (DNS, new database connections, provider calls) and can exhaust memory, so a full queue answers 503 at once (A-04).
 * A finished hash hands its slot straight to the next waiter.
 */
async function inSlot<T>(work: () => Promise<T>): Promise<T> {
  if (running >= limits.concurrency) {
    if (waiting.length >= limits.maxQueue) throw new HttpError(503, 'busy', 'The server is busy, try again shortly', 2);
    await new Promise<void>((resolve) => waiting.push(resolve));
  } else {
    running += 1;
  }
  try {
    return await work();
  } finally {
    const next = waiting.shift();
    if (next) next();
    else running -= 1;
  }
}

function scrypt(password: string, salt: Buffer, keyLen: number, params: ScryptParams): Promise<Buffer> {
  return inSlot(
    () =>
      new Promise<Buffer>((resolve, reject) => {
        scryptCb(password, salt, keyLen, { ...params, maxmem: MAX_MEM }, (err, key) => (err ? reject(err) : resolve(key)));
      }),
  );
}

/** Returns `scrypt$N$r$p$salt$hash` (all base64url). */
export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const key = await scrypt(password.normalize('NFKC'), salt, KEY_LEN, { N, r: R, p: P });
  return ['scrypt', N, R, P, salt.toString('base64url'), key.toString('base64url')].join('$');
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [algo, n, r, p, saltB64, hashB64] = stored.split('$');
  if (algo !== 'scrypt' || !n || !r || !p || !saltB64 || !hashB64) return false;
  const params = { N: Number(n), r: Number(r), p: Number(p) };
  if (!Number.isInteger(params.N) || params.N > 2 ** 20 || params.r > 32 || params.p > 16) return false;
  const expected = Buffer.from(hashB64, 'base64url');
  const key = await scrypt(password.normalize('NFKC'), Buffer.from(saltB64, 'base64url'), expected.length, params);
  return key.length === expected.length && timingSafeEqual(key, expected);
}
