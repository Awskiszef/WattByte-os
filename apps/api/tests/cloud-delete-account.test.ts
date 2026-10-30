// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { vi } from 'vitest';

import { describeDeleteAccount } from './cloud-account-suite.js';
import { memoryFixture } from './cloud-support.js';

// Every register and login runs a scrypt hash (N=2^16); on a loaded machine a populated account takes seconds.
vi.setConfig({ testTimeout: 60_000, hookTimeout: 60_000 });

// The same suite runs on PostgreSQL, with the schema-level checks, in db/delete-account.integration.test.ts.
describeDeleteAccount('memory repositories', memoryFixture);
