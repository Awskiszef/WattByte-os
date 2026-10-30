// The timing equaliser of the login (a hash computed once for unknown e-mail addresses) must not remember a failure: one
// "server busy" answer used to be cached for the life of the process and broke every later unknown-e-mail login.
import { afterEach, describe, expect, it } from 'vitest';

import { configurePasswordHashing, hashPassword } from '../src/modules/auth/password.js';
import { type BuiltApp, buildTestApp } from './support.js';

let built: BuiltApp | undefined;
afterEach(async () => {
  configurePasswordHashing({ concurrency: 2, maxQueue: 8 });
  await built?.app.close();
  built = undefined;
});

describe('login timing equaliser', () => {
  it('recovers after the first hash was refused as busy', async () => {
    built = await buildTestApp({ env: { SCRYPT_CONCURRENCY: '1', SCRYPT_MAX_QUEUE: '0' } });
    const login = () => built!.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: 'nobody@example.test', password: 'password123' } });

    // Occupy the only slot, so the equaliser's own hash is refused with 503 busy (this is the first use in this process).
    const busy = hashPassword('keeps-the-slot-busy');
    const refused = await login();
    expect(refused.statusCode).toBe(503);
    await busy;

    // With a free slot the same request is an ordinary 401, and so is the next one: the failure was not cached.
    const first = await login();
    expect(first.statusCode).toBe(401);
    expect((await login()).statusCode).toBe(401);
  });
});
