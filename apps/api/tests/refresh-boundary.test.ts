// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { randomUUID } from 'node:crypto';

import { describe } from 'vitest';

import { MemoryRepositories } from '../src/database/memory.js';
import { buildTestApp } from './support.js';
import { defineRefreshEndpointBoundaryTests, defineRotateBoundaryTests } from './refresh-boundary.shared.js';

describe('refresh reuse boundary (MemoryRepositories)', () => {
  defineRotateBoundaryTests(async () => {
    const repos = new MemoryRepositories();
    return {
      repos,
      // MemoryRepositories stamps the injected `now`, nothing to pin.
      pinRevokedAt: async () => undefined,
      newUser: async () => (await repos.users.create({ email: `${randomUUID()}@test.wattbyte`, passwordHash: null })).id,
    };
  });

  defineRefreshEndpointBoundaryTests(async () => {
    let clock = new Date();
    const ctx = await buildTestApp({ now: () => clock, env: { REFRESH_REUSE_GRACE_SEC: '10' } });
    return {
      app: ctx.app,
      repos: ctx.repos,
      setClock: (at) => {
        clock = at;
      },
      pinRevokedAt: async () => undefined,
      newUser: async () => (await ctx.memory.users.create({ email: `${randomUUID()}@test.wattbyte`, passwordHash: null })).id,
    };
  });
});
