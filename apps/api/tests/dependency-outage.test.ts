// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { describe, expect, it } from 'vitest';

import { isDependencyOutage } from '../src/errors/http-error.js';
import { MemoryRepositories } from '../src/database/memory.js';
import { buildTestApp } from './support.js';

/** B-14: a database that cannot serve the request is a 503 with Retry-After, not an opaque 500. */
describe('isDependencyOutage', () => {
  it.each([
    [{ code: '57P01' }], [{ code: '53300' }], [{ code: '57014' }], [{ code: '40P01' }], [{ code: '08006' }], [{ code: 'ECONNREFUSED' }],
    [new Error('timeout exceeded when trying to connect')], [new Error('Connection terminated unexpectedly')],
  ])('%j is an outage', (e) => expect(isDependencyOutage(e)).toBe(true));

  it.each([[{ code: '23505' }], [{ code: '22P02' }], [new Error('boom')], [null], ['text'], [{ code: 42 }]])('%j is not', (e) => expect(isDependencyOutage(e)).toBe(false));
});

/** In-memory repositories whose user lookup fails with [error]. */
function downRepos(error: Error): MemoryRepositories {
  const repos = new MemoryRepositories();
  repos.users.findByEmail = async () => {
    throw error;
  };
  return repos;
}

describe('the HTTP answer', () => {
  it('a lost database connection is 503 service_unavailable with Retry-After', async () => {
    const err = Object.assign(new Error('Connection terminated unexpectedly'), { code: undefined });
    const ctx = await buildTestApp({ repos: downRepos(err) });
    try {
      const res = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: 'a@b.co', password: 'password123' } });
      expect(res.statusCode).toBe(503);
      expect(res.json()).toEqual({ error: { code: 'service_unavailable', message: 'The service is temporarily unavailable, try again shortly' } });
      expect(res.headers['retry-after']).toBe('5');
      expect(res.body).not.toContain('Connection terminated');
    } finally {
      await ctx.app.close();
    }
  });

  it('a genuine bug is still a 500 internal', async () => {
    const ctx = await buildTestApp({ repos: downRepos(new TypeError('x is not a function')) });
    try {
      const res = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: 'a@b.co', password: 'password123' } });
      expect(res.statusCode).toBe(500);
      expect(res.json().error.code).toBe('internal');
    } finally {
      await ctx.app.close();
    }
  });
});
