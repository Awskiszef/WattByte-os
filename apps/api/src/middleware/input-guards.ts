import type { FastifyRequest } from 'fastify';

import { HttpError } from '../errors/http-error.js';

/**
 * True when any string in `value` (values and object keys, at any depth) contains a NUL character.
 * Iterative on purpose: a hostile body can nest arbitrarily deep and must not overflow the stack.
 */
export function containsNul(value: unknown): boolean {
  const pending: unknown[] = [value];
  while (pending.length > 0) {
    const current = pending.pop();
    if (typeof current === 'string') {
      if (current.includes('\u0000')) return true;
    } else if (Array.isArray(current)) {
      // A loop, not push(...current): spreading a large array exceeds the argument limit (RangeError) and
      // every body route would answer 500 (B-10).
      for (const item of current) pending.push(item);
    } else if (current !== null && typeof current === 'object') {
      for (const [key, v] of Object.entries(current)) {
        if (key.includes('\u0000')) return true;
        pending.push(v);
      }
    }
  }
  return false;
}

/** No request body of this API legitimately holds an array this long (the largest is 92 days of usage). */
export const MAX_BODY_ARRAY_LENGTH = 1000;

/**
 * True when any array in `value`, at any depth, has more than `max` elements. Checked before schema validation:
 * zod validates every element and records issues for each, so work and memory would otherwise grow with an
 * attacker-chosen element count (B-04).
 */
export function hasOversizedArray(value: unknown, max = MAX_BODY_ARRAY_LENGTH): boolean {
  const pending: unknown[] = [value];
  while (pending.length > 0) {
    const current = pending.pop();
    if (Array.isArray(current)) {
      if (current.length > max) return true;
      for (const item of current) pending.push(item);
    } else if (current !== null && typeof current === 'object') {
      for (const v of Object.values(current)) pending.push(v);
    }
  }
  return false;
}

/**
 * App-level `preValidation` hook. PostgreSQL text columns cannot hold U+0000 and answer such an insert with
 * an encoding error, which would reach the client as a 500 for what is plainly bad input. No field of this API
 * has a use for a NUL, so it is refused up front with the same 400 as any other invalid field.
 */
export async function rejectNulCharacters(request: FastifyRequest): Promise<void> {
  if (containsNul(request.body) || containsNul(request.query) || containsNul(request.params)) {
    throw HttpError.badRequest('validation', 'Text must not contain NUL characters');
  }
  if (hasOversizedArray(request.body)) {
    throw HttpError.badRequest('validation', `Lists in the request must not have more than ${MAX_BODY_ARRAY_LENGTH} entries`);
  }
}
