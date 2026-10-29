import { afterEach, describe, expect, it } from 'vitest';

import { MemoryRepositories } from '../src/database/memory.js';
import { type BuiltApp, buildTestApp } from './support.js';

const apps: BuiltApp[] = [];
afterEach(async () => {
  await Promise.all(apps.splice(0).map((c) => c.app.close()));
});

/** A store that reports which migration it has reached. */
class VersionedRepos extends MemoryRepositories {
  constructor(private version: string | null | Error) {
    super();
  }
  async schemaVersion(): Promise<string | null> {
    if (this.version instanceof Error) throw this.version;
    return this.version;
  }
}

async function ready(repos: MemoryRepositories, expectedSchemaVersion?: string) {
  const ctx = await buildTestApp({ repos, expectedSchemaVersion });
  apps.push(ctx);
  return ctx.app.inject({ url: '/ready' });
}

describe('GET /ready and the schema version (C-07)', () => {
  it('503 while the database is behind the newest migration of this build', async () => {
    const res = await ready(new VersionedRepos('0011_x.sql'), '0012_y.sql');
    expect(res.statusCode).toBe(503);
    expect(res.json()).toMatchObject({ status: 'degraded', database: 'ok', schema: 'behind' });
  });

  it('503 when no migration has been applied at all', async () => {
    const res = await ready(new VersionedRepos(null), '0001_init.sql');
    expect(res.statusCode).toBe(503);
    expect(res.json()).toMatchObject({ schema: 'behind' });
  });

  it('200 when the newest migration is applied', async () => {
    const res = await ready(new VersionedRepos('0012_y.sql'), '0012_y.sql');
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'ok', database: 'ok', schema: 'ok' });
  });

  it('200 when a newer release already migrated further (rolling deploy)', async () => {
    const res = await ready(new VersionedRepos('0013_z.sql'), '0012_y.sql');
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'ok', schema: 'ahead' });
  });

  it('a failing version query is a database problem, not a pass', async () => {
    const res = await ready(new VersionedRepos(new Error('relation "schema_migrations" does not exist')), '0012_y.sql');
    expect(res.statusCode).toBe(503);
    expect(res.json()).toMatchObject({ database: 'unavailable' });
    expect(res.body).not.toContain('schema_migrations');
  });

  it('no expectation configured: unchanged behaviour, no schema field', async () => {
    const res = await ready(new VersionedRepos('0001_init.sql'));
    expect(res.statusCode).toBe(200);
    expect(res.json()).not.toHaveProperty('schema');
  });

  it('a store without a schema (in-memory) reports unchecked and stays ready', async () => {
    const res = await ready(new MemoryRepositories(), '0012_y.sql');
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ schema: 'unchecked' });
  });
});
