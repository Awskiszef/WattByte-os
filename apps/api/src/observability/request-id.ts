// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { randomUUID } from 'node:crypto';
import type { IncomingMessage } from 'node:http';

/** An incoming id is echoed only when it is short and made of harmless characters (no log or header injection). */
export const REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]{8,64}$/;

/** Fastify `genReqId`: the caller's `x-request-id` when it is well formed, otherwise a fresh UUID. */
export function generateRequestId(req: IncomingMessage): string {
  const incoming = req.headers['x-request-id'];
  // A repeated header arrives joined with ", " and fails the pattern, so it is replaced too.
  return typeof incoming === 'string' && REQUEST_ID_PATTERN.test(incoming) ? incoming : randomUUID();
}
