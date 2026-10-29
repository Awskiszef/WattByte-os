import { vi } from 'vitest';

import { describeDeviceLimits } from '../device-limits-suite.js';
import { closePgApp, DATABASE_URL, makePgApp, uniqueEmail } from './helpers.js';

vi.setConfig({ testTimeout: 60_000, hookTimeout: 60_000 });

describeDeviceLimits(
  'PostgreSQL',
  async (overrides) => {
    const ctx = await makePgApp(overrides);
    return { app: ctx.app, email: (p) => uniqueEmail(p), close: () => closePgApp(ctx) };
  },
  !!DATABASE_URL,
);
