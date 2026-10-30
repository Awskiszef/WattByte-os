// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { blockExternalFetch, scrubAmbientEnv } from './helpers/hermetic.js';

// Runs before every test file: see helpers/hermetic.ts.
scrubAmbientEnv(process.env);
blockExternalFetch();
