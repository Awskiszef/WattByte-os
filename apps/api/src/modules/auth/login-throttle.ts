// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { createHash } from 'node:crypto';

/**
 * Per-account sign-in throttle policy (A-02). Counting is per e-mail, whatever the source address, so a
 * distributed guess against one account (many IPv4 addresses, a rotating IPv6 /64) is slowed as a whole.
 *
 *  - failures are consecutive: a success clears them, and they expire after FAILURE_WINDOW_SEC without a new one;
 *  - from the LOCK_AFTER-th failure on, further attempts are refused WITHOUT checking the password for a time that
 *    doubles with every further failure: BASE_LOCK_SEC, 2x, 4x ... up to MAX_LOCK_SEC;
 *  - attempts refused during a lock are not counted (an attacker cannot extend a lock by hammering it).
 */
export const LOCK_AFTER = 5;
export const BASE_LOCK_SEC = 15;
export const MAX_LOCK_SEC = 900;
export const FAILURE_WINDOW_SEC = 3600;

/** Lock duration after the `failures`-th consecutive failure; 0 while below the threshold. */
export function lockSeconds(failures: number): number {
  if (failures < LOCK_AFTER) return 0;
  return Math.min(MAX_LOCK_SEC, BASE_LOCK_SEC * 2 ** Math.min(failures - LOCK_AFTER, 20));
}

/** The throttle key: a hash of the normalised e-mail, never the address itself. */
export function loginThrottleKey(email: string): string {
  return createHash('sha256').update(email.trim().toLowerCase()).digest('hex');
}
