// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { vi } from 'vitest';

import { describeDeviceLimits } from './device-limits-suite.js';
import { makeApp } from './helpers.js';

vi.setConfig({ testTimeout: 60_000, hookTimeout: 60_000 });

let n = 0;
// The same suite runs on PostgreSQL in db/device-limits.integration.test.ts.
describeDeviceLimits('memory repositories', async (overrides) => {
  const ctx = await makeApp(overrides);
  return { app: ctx.app, email: (p) => `${p}-${n++}@test.wattbyte`, close: () => ctx.app.close() };
});
