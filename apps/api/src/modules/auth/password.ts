import { randomBytes, scrypt as scryptCb, timingSafeEqual } from 'node:crypto';

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

function scrypt(password: string, salt: Buffer, keyLen: number, params: ScryptParams): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    scryptCb(password, salt, keyLen, { ...params, maxmem: MAX_MEM }, (err, key) => (err ? reject(err) : resolve(key)));
  });
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
