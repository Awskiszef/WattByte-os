// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { createHash, createHmac, randomBytes } from 'node:crypto';

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
  /** The session family (device) the token was issued to; absent on tokens issued before families existed. */
  sid?: string;
  /** Issue time (epoch seconds), read back by `verifyAccess`. */
  iat?: number;
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
    return new SignJWT({ plan: claims.plan, ...(claims.sid ? { sid: claims.sid } : {}) })
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
      const sid = typeof payload.sid === 'string' && UUID.test(payload.sid) ? payload.sid : undefined;
      return { userId: payload.sub, plan, ...(sid ? { sid } : {}), iat: payload.iat };
    } catch {
      return null;
    }
  }

  /** Opaque, high-entropy refresh token; only its hash is stored. */
  newRefreshToken(): string {
    return randomBytes(32).toString('base64url');
  }

  /**
   * The refresh token that rotation hands out for `oldToken`. It is a keyed function of the old token, not a fresh random
   * value, so a client that retries a lost refresh (the same old token again) is given the SAME successor instead of
   * being treated as a thief (A-05, C-03). Unpredictable without the server secret; it is only ever returned to a
   * presenter of the old token, and only within the grace window (see `SessionRepository.rotate`).
   */
  successorRefreshToken(oldToken: string): string {
    return createHmac('sha256', this.key).update('wattbyte-refresh-successor\0').update(oldToken).digest('base64url');
  }

  refreshExpiry(now = new Date()): Date {
    return new Date(now.getTime() + this.refreshTtlDays * 86_400_000);
  }

  static hashRefresh(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }
}
