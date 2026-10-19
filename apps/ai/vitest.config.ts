import { defineConfig } from 'vitest/config';

// Unit tests only: hermetic (ambient provider variables scrubbed, outbound network blocked except
// loopback; see tests/setup.ts). The real-provider smoke run is NOT a test: `pnpm smoke:ai`.
export default defineConfig({
  test: {
    include: ['tests/**/*.test.ts'],
    setupFiles: ['tests/setup.ts'],
  },
});
