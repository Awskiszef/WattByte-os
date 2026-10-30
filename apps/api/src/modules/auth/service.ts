import type { AuthResponse, UserDto } from '@wattbyte/contracts';

import { UniqueViolation } from '../../database/memory.js';
import type { Repositories, UserRow } from '../../database/repositories.js';
import { HttpError } from '../../errors/http-error.js';
import { loginThrottleKey } from './login-throttle.js';
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
    private readonly reuseGraceMs = 60_000,
    private readonly absoluteLifetimeMs = 90 * 86_400_000,
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
    // Per-account throttle (see login-throttle.ts): keyed on the e-mail whether or not it exists, checked before any
    // hashing, so a distributed guess against one account is slowed whatever the source addresses and costs no scrypt.
    const key = loginThrottleKey(input.email);
    const now = this.now();
    const lock = await this.repos.loginThrottle.status(key, now);
    if (lock.lockedUntil) {
      throw HttpError.tooMany('rate_limited', 'Too many failed sign-in attempts. Try again later', (lock.lockedUntil.getTime() - now.getTime()) / 1000);
    }
    const user = await this.repos.users.findByEmail(input.email);
    const hash = user?.passwordHash ?? (await dummyHash());
    const ok = await verifyPassword(input.password, hash);
    if (!user || !user.passwordHash || !ok) {
      await this.repos.loginThrottle.recordFailure(key, now);
      throw HttpError.unauthorized('invalid_credentials', 'Wrong email or password');
    }
    await this.repos.loginThrottle.clear(key);
    return (await this.issue(user)).response;
  }

  /**
   * Rotates the refresh token atomically (see `SessionRepository.rotate`): of any number of concurrent requests with the
   * same token exactly one rotates, the others are retries.
   *
   * Reuse policy (`gap = now - (time the presented token was rotated)`, `grace = reuseGraceMs`, default 60 s, longer than
   * the app's own request timeout):
   *   - the successor of a rotation is a keyed function of the old token (`TokenService.successorRefreshToken`), so a
   *     client that never received the response and tries again within `grace` is given the SAME successor: a lost
   *     response is no longer a sign-out (A-05, C-03);
   *   - a rotated token presented at or after `grace`, or after its successor was already used, is suspected theft: the
   *     FAMILY of that token (the one device it belongs to) is revoked, no other device is touched;
   *   - a token revoked by logout / "sign out everywhere" is a plain 401 and touches nothing.
   * The boundary belongs to theft: with grace 10 s, 9.9 s is a retry and 10.0 s is not. The comparison lives in the
   * repositories (`rotate` receives `now` and `graceMs`), `now` comes from the injected clock, and
   * `tests/refresh-boundary.shared.ts` pins both sides of it. `docs/security.md` has the full table.
   */
  async refresh(refreshToken: string): Promise<AuthResponse> {
    const next = this.tokens.successorRefreshToken(refreshToken);
    const now = this.now();
    const result = await this.repos.sessions.rotate({
      oldHash: TokenService.hashRefresh(refreshToken),
      newHash: TokenService.hashRefresh(next),
      newExpiresAt: this.tokens.refreshExpiry(now),
      now,
      graceMs: this.reuseGraceMs,
      absoluteLifetimeMs: this.absoluteLifetimeMs,
    });
    switch (result.status) {
      case 'invalid':
        throw HttpError.unauthorized('invalid_refresh_token', 'Invalid refresh token');
      case 'expired':
        throw HttpError.unauthorized('refresh_token_expired', 'Refresh token expired');
      case 'revoked':
        throw HttpError.unauthorized('refresh_token_revoked', 'Refresh token was revoked');
      case 'reused':
        throw HttpError.unauthorized('refresh_token_reused', 'Refresh token was already used; this session was revoked');
      case 'ok':
      case 'replayed': {
        const user = await this.repos.users.findById(result.userId);
        if (!user) throw HttpError.unauthorized('invalid_refresh_token', 'Invalid refresh token');
        const accessToken = await this.tokens.signAccess({ userId: user.id, plan: user.plan, sid: result.familyId }, now);
        return {
          user: toUserDto(user),
          tokens: { accessToken, refreshToken: next, expiresIn: this.tokens.accessTtl, tokenType: 'Bearer' },
        };
      }
    }
  }

  /** Signs every device out: all refresh tokens are revoked and every access token issued so far stops working. */
  async logoutAll(userId: string): Promise<void> {
    await this.repos.sessions.revokeAllForUser(userId);
    await this.repos.users.invalidateTokensBefore(userId, secondFloor(this.now()));
  }

  /** The user's live sign-ins, newest first; `currentFamilyId` marks the one the request came from. */
  async listSessions(userId: string, currentFamilyId: string | undefined): Promise<{ id: string; createdAt: string; lastUsedAt: string; expiresAt: string; current: boolean }[]> {
    const families = await this.repos.sessions.listFamilies(userId, this.now());
    return families.map((f) => ({
      id: f.id,
      createdAt: f.startedAt.toISOString(),
      lastUsedAt: f.lastRotatedAt.toISOString(),
      expiresAt: f.expiresAt.toISOString(),
      current: f.id === currentFamilyId,
    }));
  }

  /** Signs one of the user's devices out. A family that is not the user's (or is already gone) is a 404, never an oracle. */
  async revokeSession(userId: string, familyId: string): Promise<void> {
    const mine = (await this.repos.sessions.listFamilies(userId, this.now())).some((f) => f.id === familyId);
    if (!mine) throw HttpError.notFound('session_not_found', 'No such session');
    await this.repos.sessions.revokeFamily(familyId);
  }

  /**
   * Changes the password. The current one is required (and throttled like a login: a stolen access token must not become a
   * password-guessing oracle). Every device is signed out, access tokens included; the caller gets a fresh session.
   */
  async changePassword(userId: string, input: { currentPassword: string; newPassword: string }): Promise<AuthResponse> {
    const user = await this.repos.users.findById(userId);
    if (!user) throw HttpError.unauthorized('account_not_found', 'The account no longer exists');
    if (!user.passwordHash) throw HttpError.badRequest('no_password', 'This account has no password to change');
    const key = loginThrottleKey(user.email);
    const now = this.now();
    const lock = await this.repos.loginThrottle.status(key, now);
    if (lock.lockedUntil) {
      throw HttpError.tooMany('rate_limited', 'Too many failed attempts. Try again later', (lock.lockedUntil.getTime() - now.getTime()) / 1000);
    }
    if (!(await verifyPassword(input.currentPassword, user.passwordHash))) {
      await this.repos.loginThrottle.recordFailure(key, now);
      throw HttpError.unauthorized('invalid_credentials', 'Wrong password');
    }
    await this.repos.loginThrottle.clear(key);
    const updated = await this.repos.users.setPasswordHash(userId, await hashPassword(input.newPassword));
    if (!updated) throw HttpError.unauthorized('account_not_found', 'The account no longer exists');
    await this.logoutAll(userId);
    return (await this.issue(updated)).response;
  }

  /**
   * Signs the device out: revokes the whole family of the presented token, so it works with the token the device was
   * given at sign-in as well as with its current one (a rotated token's successor is in the same family, A-06).
   * Idempotent; never reveals whether the token existed; other devices are untouched.
   */
  async logout(refreshToken: string): Promise<void> {
    const session = await this.repos.sessions.findByHash(TokenService.hashRefresh(refreshToken));
    if (session) await this.repos.sessions.revokeFamily(session.familyId);
  }

  private async issue(user: UserRow): Promise<{ response: AuthResponse; sessionId: string }> {
    const refreshToken = this.tokens.newRefreshToken();
    const session = await this.repos.sessions.create({
      userId: user.id,
      refreshHash: TokenService.hashRefresh(refreshToken),
      expiresAt: this.tokens.refreshExpiry(this.now()),
    });
    const accessToken = await this.tokens.signAccess({ userId: user.id, plan: user.plan, sid: session.familyId }, this.now());
    return {
      sessionId: session.id,
      response: {
        user: toUserDto(user),
        tokens: { accessToken, refreshToken, expiresIn: this.tokens.accessTtl, tokenType: 'Bearer' },
      },
    };
  }
}

/** The cut-off for "sign out everywhere": the start of the current second (token `iat` has second resolution). */
function secondFloor(d: Date): Date {
  return new Date(Math.floor(d.getTime() / 1000) * 1000);
}

let dummy: Promise<string> | undefined;
/** A valid scrypt hash of a random secret, computed once, used to equalise login timing. */
function dummyHash(): Promise<string> {
  dummy ??= hashPassword(`dummy-${Math.random()}-${Date.now()}`).catch((e: unknown) => {
    // A transient failure (an exhausted scrypt queue) must not be cached for the life of the process.
    dummy = undefined;
    throw e;
  });
  return dummy;
}
