// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { afterEach, describe, expect, it } from 'vitest';

import { TokenService } from '../src/modules/auth/tokens.js';
import { type BuiltApp, buildTestApp, register } from './support.js';

const apps: BuiltApp[] = [];
afterEach(async () => {
  while (apps.length) await apps.pop()!.app.close();
});

const PASSWORD = 'password123';

async function setup(env: Record<string, string> = {}) {
  let clock = new Date();
  const built = await buildTestApp({ now: () => clock, env });
  apps.push(built);
  const call = (method: 'GET' | 'POST' | 'DELETE', url: string, opts: { token?: string; payload?: unknown } = {}) =>
    built.app.inject({ method, url, headers: opts.token ? { authorization: `Bearer ${opts.token}` } : {}, payload: opts.payload as object | undefined });
  const login = async (email: string) => {
    const res = await call('POST', '/api/v1/auth/login', { payload: { email, password: PASSWORD } });
    expect(res.statusCode).toBe(200);
    return res.json().tokens as { accessToken: string; refreshToken: string };
  };
  return { ...built, call, login, advance: (ms: number) => void (clock = new Date(clock.getTime() + ms)), now: () => clock };
}

describe('sign out everywhere (A-07, A-08)', () => {
  it('revokes every refresh token and refuses every access token issued so far, on every device', async () => {
    const t = await setup();
    const phone = await register(t.app, 'out-all@test.wattbyte');
    const tablet = await t.login('out-all@test.wattbyte');
    t.advance(2_000); // the cut-off has second resolution: what follows is a new second
    const res = await t.call('POST', '/api/v1/auth/logout-all', { token: phone.accessToken });
    expect(res.statusCode).toBe(204);
    for (const tokens of [{ accessToken: phone.accessToken, refreshToken: phone.refreshToken }, tablet]) {
      expect((await t.call('GET', '/api/v1/me', { token: tokens.accessToken })).json().error.code).toBe('session_revoked');
      expect((await t.call('POST', '/api/v1/auth/refresh', { payload: { refreshToken: tokens.refreshToken } })).statusCode).toBe(401);
    }
  });

  it('a sign-in right afterwards works (the cut-off does not lock the account out)', async () => {
    const t = await setup();
    const reg = await register(t.app, 'out-all-again@test.wattbyte');
    await t.call('POST', '/api/v1/auth/logout-all', { token: reg.accessToken });
    const fresh = await t.login('out-all-again@test.wattbyte');
    expect((await t.call('GET', '/api/v1/me', { token: fresh.accessToken })).statusCode).toBe(200);
  });

  it('needs a signed-in user', async () => {
    const t = await setup();
    expect((await t.call('POST', '/api/v1/auth/logout-all')).statusCode).toBe(401);
  });
});

describe('the session list and signing one device out (A-07)', () => {
  it('lists one entry per device, marks the current one, and signing another out ends only that one', async () => {
    const t = await setup();
    const phone = await register(t.app, 'list@test.wattbyte');
    t.advance(1_000);
    const tablet = await t.login('list@test.wattbyte');

    const list = (await t.call('GET', '/api/v1/me/sessions', { token: phone.accessToken })).json().sessions as { id: string; current: boolean; createdAt: string }[];
    expect(list).toHaveLength(2);
    expect(list.filter((s) => s.current)).toHaveLength(1);
    const tabletEntry = list.find((s) => !s.current)!;

    expect((await t.call('DELETE', `/api/v1/me/sessions/${tabletEntry.id}`, { token: phone.accessToken })).statusCode).toBe(204);
    expect((await t.call('POST', '/api/v1/auth/refresh', { payload: { refreshToken: tablet.refreshToken } })).statusCode).toBe(401);
    expect((await t.call('GET', '/api/v1/me', { token: tablet.accessToken })).statusCode).toBe(401); // its access token too, at once
    expect((await t.call('GET', '/api/v1/me', { token: phone.accessToken })).statusCode).toBe(200); // the phone is untouched
    expect(((await t.call('GET', '/api/v1/me/sessions', { token: phone.accessToken })).json().sessions as unknown[]).length).toBe(1);
  });

  it('another account\'s session, an unknown id and an already ended one are 404 (no oracle); a malformed id is 400', async () => {
    const t = await setup();
    const alice = await register(t.app, 'alice-s@test.wattbyte');
    const bob = await register(t.app, 'bob-s@test.wattbyte');
    const bobSession = ((await t.call('GET', '/api/v1/me/sessions', { token: bob.accessToken })).json().sessions as { id: string }[])[0]!.id;
    expect((await t.call('DELETE', `/api/v1/me/sessions/${bobSession}`, { token: alice.accessToken })).statusCode).toBe(404);
    expect((await t.call('GET', '/api/v1/me', { token: bob.accessToken })).statusCode).toBe(200); // not touched
    expect((await t.call('DELETE', '/api/v1/me/sessions/00000000-0000-4000-8000-000000000000', { token: alice.accessToken })).statusCode).toBe(404);
    expect((await t.call('DELETE', '/api/v1/me/sessions/not-a-uuid', { token: alice.accessToken })).statusCode).toBe(400);
  });

  it('signing the current device out ends this very session', async () => {
    const t = await setup();
    const reg = await register(t.app, 'self@test.wattbyte');
    const id = ((await t.call('GET', '/api/v1/me/sessions', { token: reg.accessToken })).json().sessions as { id: string }[])[0]!.id;
    expect((await t.call('DELETE', `/api/v1/me/sessions/${id}`, { token: reg.accessToken })).statusCode).toBe(204);
    expect((await t.call('GET', '/api/v1/me', { token: reg.accessToken })).statusCode).toBe(401);
  });
});

describe('changing the password (A-07)', () => {
  it('needs the current password, signs every other device out, and returns a working session for this one', async () => {
    const t = await setup();
    const phone = await register(t.app, 'pw@test.wattbyte');
    const tablet = await t.login('pw@test.wattbyte');
    t.advance(2_000);
    const res = await t.call('POST', '/api/v1/me/password', { token: phone.accessToken, payload: { currentPassword: PASSWORD, newPassword: 'a-brand-new-password' } });
    expect(res.statusCode).toBe(200);
    const fresh = res.json().tokens as { accessToken: string; refreshToken: string };

    expect((await t.call('GET', '/api/v1/me', { token: tablet.accessToken })).statusCode).toBe(401);
    expect((await t.call('POST', '/api/v1/auth/refresh', { payload: { refreshToken: tablet.refreshToken } })).statusCode).toBe(401);
    expect((await t.call('GET', '/api/v1/me', { token: phone.accessToken })).statusCode).toBe(401); // the old session of the asking device too
    expect((await t.call('GET', '/api/v1/me', { token: fresh.accessToken })).statusCode).toBe(200);
    expect((await t.call('POST', '/api/v1/auth/refresh', { payload: { refreshToken: fresh.refreshToken } })).statusCode).toBe(200);

    expect((await t.call('POST', '/api/v1/auth/login', { payload: { email: 'pw@test.wattbyte', password: PASSWORD } })).statusCode).toBe(401);
    expect((await t.call('POST', '/api/v1/auth/login', { payload: { email: 'pw@test.wattbyte', password: 'a-brand-new-password' } })).statusCode).toBe(200);
  });

  it('a wrong current password is 401, counts against the same throttle as login, and changes nothing', async () => {
    const t = await setup();
    const reg = await register(t.app, 'pw-wrong@test.wattbyte');
    for (let i = 0; i < 5; i++) {
      expect((await t.call('POST', '/api/v1/me/password', { token: reg.accessToken, payload: { currentPassword: `wrong-${i}-password`, newPassword: 'a-brand-new-password' } })).statusCode).toBe(401);
    }
    const locked = await t.call('POST', '/api/v1/me/password', { token: reg.accessToken, payload: { currentPassword: PASSWORD, newPassword: 'a-brand-new-password' } });
    expect(locked.statusCode).toBe(429); // the right password is refused during the lock, as at login
    expect((await t.call('GET', '/api/v1/me', { token: reg.accessToken })).statusCode).toBe(200); // and nobody was signed out
  });

  it('refuses a short new password and an account that has no password', async () => {
    const t = await setup();
    const reg = await register(t.app, 'pw-short@test.wattbyte');
    expect((await t.call('POST', '/api/v1/me/password', { token: reg.accessToken, payload: { currentPassword: PASSWORD, newPassword: 'short' } })).statusCode).toBe(400);
    const social = await t.memory.users.create({ email: 'social@test.wattbyte', passwordHash: null });
    const tokens = new TokenService('test-secret-test-secret-test-secret-test-secret', 900, 30);
    const access = await tokens.signAccess({ userId: social.id, plan: 'free' });
    const res = await t.call('POST', '/api/v1/me/password', { token: access, payload: { currentPassword: 'whatever-it-is', newPassword: 'a-brand-new-password' } });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('no_password');
  });
});

describe('the session ends at its absolute lifetime (A-07)', () => {
  it('rotating cannot extend a sign-in past SESSION_ABSOLUTE_LIFETIME_DAYS', async () => {
    const t = await setup({ SESSION_ABSOLUTE_LIFETIME_DAYS: '1', REFRESH_TOKEN_TTL_DAYS: '30' });
    const reg = await register(t.app, 'abs@test.wattbyte');
    let refreshToken = reg.refreshToken;
    // keep rotating every 6 hours: each token is young, the sign-in is not
    for (let i = 0; i < 3; i++) {
      t.advance(6 * 3_600_000);
      const res = await t.call('POST', '/api/v1/auth/refresh', { payload: { refreshToken } });
      expect(res.statusCode).toBe(200);
      refreshToken = res.json().tokens.refreshToken;
    }
    t.advance(7 * 3_600_000); // 25 h after the sign-in
    const late = await t.call('POST', '/api/v1/auth/refresh', { payload: { refreshToken } });
    expect(late.statusCode).toBe(401);
    expect(late.json().error.code).toBe('refresh_token_expired');
  });
});

describe('access tokens issued before session families existed keep working until they expire (A-08 compatibility)', () => {
  it('a token without `sid` is accepted; with a sid of a signed-out device it is not', async () => {
    const t = await setup();
    const reg = await register(t.app, 'legacy@test.wattbyte');
    const tokens = new TokenService('test-secret-test-secret-test-secret-test-secret', 900, 30);
    const legacy = await tokens.signAccess({ userId: reg.userId, plan: 'free' }); // no sid, like a token issued by the previous version
    expect((await t.call('GET', '/api/v1/me', { token: legacy })).statusCode).toBe(200);
    const dead = await tokens.signAccess({ userId: reg.userId, plan: 'free', sid: '11111111-1111-4111-8111-111111111111' });
    expect((await t.call('GET', '/api/v1/me', { token: dead })).statusCode).toBe(401);
  });
});
