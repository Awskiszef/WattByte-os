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
      pending.push(...current);
    } else if (current !== null && typeof current === 'object') {
      for (const [key, v] of Object.entries(current)) {
        if (key.includes('\u0000')) return true;
        pending.push(v);
      }
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
}
