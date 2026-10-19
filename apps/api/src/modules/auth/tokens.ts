import { createHash, randomBytes } from 'node:crypto';

import { jwtVerify, SignJWT } from 'jose';

import type { Plan } from '../../database/repositories.js';

const ISSUER = 'wattbyte';
const AUDIENCE = 'wattbyte-mobile';
/** Only the algorithm this service signs with; never derived from the token's own header. */
const ALGORITHMS = ['HS256'];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface AccessClaims {
  userId: string;
  plan: Plan;
}

export class TokenService {
  private readonly key: Uint8Array;

  constructor(
    secret: string,
    private readonly accessTtlSec: number,
    private readonly refreshTtlDays: number,
  ) {
    this.key = new TextEncoder().encode(secret);
  }

  get accessTtl(): number {
    return this.accessTtlSec;
  }

  /** Short-lived HS256 JWT carrying only the user id and plan. */
  signAccess(claims: AccessClaims, now = new Date()): Promise<string> {
    const iat = Math.floor(now.getTime() / 1000);
    return new SignJWT({ plan: claims.plan })
      .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
      .setSubject(claims.userId)
      .setIssuer(ISSUER)
      .setAudience(AUDIENCE)
      .setIssuedAt(iat)
      .setExpirationTime(iat + this.accessTtlSec)
      .sign(this.key);
  }

  async verifyAccess(token: string): Promise<AccessClaims | null> {
    try {
      const { payload } = await jwtVerify(token, this.key, {
        issuer: ISSUER,
        audience: AUDIENCE,
        algorithms: ALGORITHMS,
        // A token without an expiry would be valid forever: jose only checks `exp` when it is present.
        requiredClaims: ['exp', 'iat', 'sub'],
      });
      // The subject becomes a uuid query parameter: anything else is not one of our tokens.
      if (!payload.sub || !UUID.test(payload.sub)) return null;
      const plan = payload.plan === 'premium' ? 'premium' : 'free';
      return { userId: payload.sub, plan };
    } catch {
      return null;
    }
  }

  /** Opaque, high-entropy refresh token; only its hash is stored. */
  newRefreshToken(): string {
    return randomBytes(32).toString('base64url');
  }

  refreshExpiry(now = new Date()): Date {
    return new Date(now.getTime() + this.refreshTtlDays * 86_400_000);
  }

  static hashRefresh(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }
}
