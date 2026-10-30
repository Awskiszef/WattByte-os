// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { runSmoke } from './smoke-core.js';

// `pnpm --filter @wattbyte/ai smoke:ai`. Reads the provider keys/models from the environment
// (see docs/ai.md); never prints a key. Not part of `pnpm test`.
const { exitCode } = await runSmoke({
  env: process.env,
  print: (line) => process.stdout.write(`${line}\n`),
});
process.exitCode = exitCode;
