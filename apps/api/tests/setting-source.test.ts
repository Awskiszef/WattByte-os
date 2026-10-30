// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { vi } from 'vitest';

import { makeApp, registerUser } from './helpers.js';
import { describeSettingSources } from './setting-source-suite.js';

// Every register runs a scrypt hash (N=2^16); on a loaded machine that takes seconds.
vi.setConfig({ testTimeout: 60_000, hookTimeout: 60_000 });

// The same suite runs on PostgreSQL in db/setting-source.integration.test.ts.
let n = 0;
describeSettingSources('memory repositories', async () => {
  const { app } = await makeApp();
  return {
    app,
    register: async (prefix) => (await registerUser(app, `${prefix}-${n++}@test.wattbyte`)).headers,
    close: () => app.close(),
  };
});
