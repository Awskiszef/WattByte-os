import type { AuthResponse, UserDto } from '@wattbyte/contracts';

import { UniqueViolation } from '../../database/memory.js';
import type { Repositories, UserRow } from '../../database/repositories.js';
import { HttpError } from '../../errors/http-error.js';
import { hashPassword, verifyPassword } from './password.js';
import { TokenService } from './tokens.js';

export function toUserDto(u: UserRow): UserDto {
  return { id: u.id, email: u.email, displayName: u.displayName, plan: u.plan, createdAt: u.createdAt.toISOString() };
}

/**
 * Email + password accounts with rotating, revocable refresh tokens.
 * Apple / Google sign-in plug into `issue()` once their verification exists.
 */
export class AuthService {
  constructor(
    private readonly repos: Repositories,
    private readonly tokens: TokenService,
    private readonly now: () => Date = () => new Date(),
    private readonly reuseGraceMs = 10_000,
  ) {}

  async register(input: { email: string; password: string; displayName?: string | null }): Promise<AuthResponse> {
    const passwordHash = await hashPassword(input.password);
    let user: UserRow;
    try {
      user = await this.repos.users.create({ email: input.email, passwordHash, displayName: input.displayName ?? null });
    } catch (e) {
      if (e instanceof UniqueViolation) throw HttpError.conflict('email_taken', 'An account with this email already exists');
      throw e;
    }
    return (await this.issue(user)).response;
  }

  /**
   * Same cost for an unknown e-mail, an account without a password and a wrong
   * password: a scrypt verification always runs, so response time does not reveal
   * which accounts exist. The error is always `invalid_credentials`.
   */
  async login(input: { email: string; password: string }): Promise<AuthResponse> {
    const user = await this.repos.users.findByEmail(input.email);
    const hash = user?.passwordHash ?? (await dummyHash());
    const ok = await verifyPassword(input.password, hash);
    if (!user || !user.passwordHash || !ok) throw HttpError.unauthorized('invalid_credentials', 'Wrong email or password');
    return (await this.issue(user)).response;
  }

  /**
   * Rotates the refresh token atomically (see `SessionRepository.rotate`): of any
   * number of concurrent requests with the same token exactly one succeeds.
   *
   * Reuse policy, with `gap = now - (time the presented token was rotated)` and `grace = reuseGraceMs`:
   *   - `gap <  grace`: a client retry. Rejected (`refresh_token_reused`), no other session is touched.
   *   - `gap >= grace`: suspected theft. Rejected, and every session of the user is revoked.
   * The boundary belongs to theft: with the default 10 s, 9.9 s is a retry and 10.0 s is not. A token that
   * was revoked without a successor (logout) is never a retry. The comparison lives in the repositories
   * (`rotate` receives `now` and `graceMs`) and `now` comes from the injected clock, so the tests in
   * `tests/refresh-boundary.shared.ts` pin both sides of it. `docs/security.md` has the full table.
   */
  async refresh(refreshToken: string): Promise<AuthResponse> {
    const next = this.tokens.newRefreshToken();
    const now = this.now();
    const result = await this.repos.sessions.rotate({
      oldHash: TokenService.hashRefresh(refreshToken),
      newHash: TokenService.hashRefresh(next),
      newExpiresAt: this.tokens.refreshExpiry(now),
      now,
      graceMs: this.reuseGraceMs,
    });
    switch (result.status) {
      case 'invalid':
        throw HttpError.unauthorized('invalid_refresh_token', 'Invalid refresh token');
      case 'expired':
        throw HttpError.unauthorized('refresh_token_expired', 'Refresh token expired');
      case 'reused':
        throw HttpError.unauthorized(
          'refresh_token_reused',
          result.familyRevoked ? 'Refresh token was already used; all sessions were revoked' : 'Refresh token was already used',
        );
      case 'ok': {
        const user = await this.repos.users.findById(result.userId);
        if (!user) throw HttpError.unauthorized('invalid_refresh_token', 'Invalid refresh token');
        const accessToken = await this.tokens.signAccess({ userId: user.id, plan: user.plan }, now);
        return {
          user: toUserDto(user),
          tokens: { accessToken, refreshToken: next, expiresIn: this.tokens.accessTtl, tokenType: 'Bearer' },
        };
      }
    }
  }

  /** Idempotent; never reveals whether the token existed. */
  async logout(refreshToken: string): Promise<void> {
    const session = await this.repos.sessions.findByHash(TokenService.hashRefresh(refreshToken));
    if (session && !session.revokedAt) await this.repos.sessions.revoke(session.id);
  }

  private async issue(user: UserRow): Promise<{ response: AuthResponse; sessionId: string }> {
    const refreshToken = this.tokens.newRefreshToken();
    const session = await this.repos.sessions.create({
      userId: user.id,
      refreshHash: TokenService.hashRefresh(refreshToken),
      expiresAt: this.tokens.refreshExpiry(this.now()),
    });
    const accessToken = await this.tokens.signAccess({ userId: user.id, plan: user.plan }, this.now());
    return {
      sessionId: session.id,
      response: {
        user: toUserDto(user),
        tokens: { accessToken, refreshToken, expiresIn: this.tokens.accessTtl, tokenType: 'Bearer' },
      },
    };
  }
}

let dummy: Promise<string> | undefined;
/** A valid scrypt hash of a random secret, computed once, used to equalise login timing. */
function dummyHash(): Promise<string> {
  dummy ??= hashPassword(`dummy-${Math.random()}-${Date.now()}`);
  return dummy;
}
