import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

import { ENV_VARIABLES, envWarnings, loadEnv } from '../src/config/env.js';

const SECRET = 'k3J9xQ2vLm8Zp4Rt7Yw1Nb6Hc5Df0Gs2AaBbCcDd';
const DB = 'postgres://app:s3cr3t-db-pass@db.internal:5432/wattbyte';

const base = { JWT_SECRET: SECRET };
const production = { ...base, NODE_ENV: 'production', DATABASE_URL: DB, DATABASE_SSL: '1', TRUST_PROXY_HOPS: '1' };
const staging = { ...production, APP_ENV: 'staging' };

describe('APP_ENV resolution', () => {
  it('is derived from NODE_ENV when not set', () => {
    expect(loadEnv({ ...base, NODE_ENV: 'development' }).APP_ENV).toBe('development');
    expect(loadEnv({ ...base, NODE_ENV: 'test' }).APP_ENV).toBe('development');
    expect(loadEnv(production).APP_ENV).toBe('production');
  });

  it('refuses an unspecified environment instead of treating it as development (B-07)', () => {
    // A deployment that forgot NODE_ENV used to run as development: placeholder secret, mock AI, no TLS, no warnings.
    expect(() => loadEnv({ ...base })).toThrow(/NODE_ENV: not set/);
    expect(() => loadEnv({ ...base, NODE_ENV: '', APP_ENV: '' })).toThrow(/NODE_ENV: not set/);
    expect(() => loadEnv({ JWT_SECRET: 'change-me-to-a-long-random-secret-of-at-least-32-chars', AI_MOCK: '1' })).toThrow(/NODE_ENV: not set/);
    // either variable is enough to say what this is; a typo is still refused by the enum
    expect(loadEnv({ ...base, APP_ENV: 'development' }).APP_ENV).toBe('development');
    expect(() => loadEnv({ ...base, NODE_ENV: 'prod' })).toThrow(/NODE_ENV/);
  });

  it('accepts exactly development | staging | production', () => {
    expect(loadEnv({ ...base, APP_ENV: 'development' }).APP_ENV).toBe('development');
    expect(loadEnv(staging).APP_ENV).toBe('staging');
    expect(loadEnv({ ...production, APP_ENV: 'production' }).APP_ENV).toBe('production');
    for (const bad of ['prod', 'Production', 'test', 'local', '1']) {
      expect(() => loadEnv({ ...base, NODE_ENV: 'development', APP_ENV: bad }), bad).toThrow(/APP_ENV/);
    }
  });

  it('an empty APP_ENV counts as unset, like every other empty variable', () => {
    expect(loadEnv({ ...base, NODE_ENV: 'development', APP_ENV: '' }).APP_ENV).toBe('development');
  });

  it('NODE_ENV and APP_ENV cannot contradict each other in a way that skips the guards', () => {
    expect(() => loadEnv({ ...production, APP_ENV: 'development' })).toThrow(/skip the production guards/);
    expect(() => loadEnv({ ...base, NODE_ENV: 'development', APP_ENV: 'staging', DATABASE_URL: DB })).toThrow(/APP_ENV=staging requires NODE_ENV=production/);
    expect(() => loadEnv({ ...base, NODE_ENV: 'test', APP_ENV: 'production', DATABASE_URL: DB, DATABASE_SSL: '1' })).toThrow(/NODE_ENV=production/);
  });
});

describe.each(['staging', 'production'] as const)('%s refuses unsafe configuration', (appEnv) => {
  const ok = { ...production, APP_ENV: appEnv };

  it('accepts a complete, real configuration', () => {
    const env = loadEnv(ok);
    expect(env.APP_ENV).toBe(appEnv);
    expect(env.AI_MOCK).toBe('0');
  });

  it('refuses a placeholder JWT_SECRET', () => {
    for (const secret of [
      'change-me-to-a-long-random-secret-of-at-least-32-chars',
      'this-is-an-example-secret-value-123456789',
      'placeholder-placeholder-placeholder-12345',
      'test-secret-test-secret-test-secret-test-secret',
    ]) {
      expect(() => loadEnv({ ...ok, JWT_SECRET: secret }), secret).toThrow(/placeholder/);
    }
  });

  it('refuses a short JWT_SECRET (checked in every environment) and a repeated-pattern one', () => {
    expect(() => loadEnv({ ...ok, JWT_SECRET: 'Xk9$mQ2' })).toThrow(/at least 32 characters/);
    expect(() => loadEnv({ ...ok, JWT_SECRET: 'a'.repeat(64) })).toThrow(/repeated pattern/);
    expect(() => loadEnv({ ...ok, JWT_SECRET: 'abababababababababababababababababababab' })).toThrow(/repeated pattern/);
    expect(() => loadEnv({ ...ok, JWT_SECRET: '1234512345123451234512345123451234512345' })).toThrow(/repeated pattern/);
  });

  it('refuses AI_MOCK=1', () => {
    expect(() => loadEnv({ ...ok, AI_MOCK: '1' })).toThrow(/AI_MOCK=1 is not allowed/);
    expect(loadEnv({ ...ok, AI_MOCK: '0' }).AI_MOCK).toBe('0');
  });

  it('refuses a missing DATABASE_URL and the development database credentials', () => {
    const { DATABASE_URL: _omit, ...withoutUrl } = ok;
    expect(() => loadEnv(withoutUrl)).toThrow(/DATABASE_URL is required/);
    expect(() => loadEnv({ ...ok, DATABASE_URL: '' })).toThrow(/DATABASE_URL is required/);
    expect(() => loadEnv({ ...ok, DATABASE_URL: 'postgres://wattbyte:wattbyte@localhost:5432/wattbyte' })).toThrow(/development credentials/);
    // the user name alone is fine, only the documented throw-away pair is refused
    expect(loadEnv({ ...ok, DATABASE_URL: 'postgres://wattbyte:another-password@db:5432/wattbyte' }).DATABASE_URL).toContain('db:5432');
  });

  it('requires TRUST_PROXY_HOPS to be stated, 0 included (B-03)', () => {
    const { TRUST_PROXY_HOPS: _omitted, ...noHops } = production;
    expect(() => loadEnv({ ...noHops, APP_ENV: appEnv })).toThrow(/TRUST_PROXY_CIDRS .* or TRUST_PROXY_HOPS .* must be set explicitly/);
    expect(loadEnv({ ...noHops, APP_ENV: appEnv, TRUST_PROXY_HOPS: '0' }).TRUST_PROXY_HOPS).toBe(0);
    expect(loadEnv({ ...noHops, APP_ENV: appEnv, TRUST_PROXY_HOPS: '2' }).TRUST_PROXY_HOPS).toBe(2);
  });

  it('reports every problem at once, without echoing a secret', () => {
    const err = (() => {
      try {
        loadEnv({ NODE_ENV: 'production', APP_ENV: appEnv, JWT_SECRET: 'change-me-to-a-long-random-secret-of-at-least-32-chars', AI_MOCK: '1' });
      } catch (e) {
        return e as Error;
      }
      throw new Error('should have thrown');
    })();
    expect(err.message).toMatch(new RegExp(`Invalid ${appEnv} environment`));
    expect(err.message).toMatch(/placeholder/);
    expect(err.message).toMatch(/AI_MOCK/);
    expect(err.message).toMatch(/DATABASE_URL/);
    expect(err.message).not.toContain('change-me-to-a-long');
  });
});

describe('DATABASE_SSL policy', () => {
  it('production refuses to guess: DATABASE_SSL must be set explicitly', () => {
    const { DATABASE_SSL: _omit, ...unset } = production;
    expect(() => loadEnv(unset)).toThrow(/DATABASE_SSL must be set explicitly/);
    expect(loadEnv({ ...production, DATABASE_SSL: '1' }).DATABASE_SSL).toBe('1');
    // '0' is a conscious choice (private link, sidecar proxy): accepted, but warned about
    const plain = loadEnv({ ...production, DATABASE_SSL: '0' });
    expect(plain.DATABASE_SSL).toBe('0');
    expect(envWarnings(plain).join('\n')).toMatch(/DATABASE_SSL=0/);
  });

  it('staging only warns about an unencrypted connection', () => {
    const { DATABASE_SSL: _omit, ...unset } = staging;
    const env = loadEnv(unset);
    expect(env.DATABASE_SSL).toBe('0');
    expect(envWarnings(env).join('\n')).toMatch(/DATABASE_SSL=0/);
  });

  it('development has no SSL requirement and no warnings', () => {
    expect(envWarnings(loadEnv({ ...base, NODE_ENV: 'development' }))).toEqual([]);
  });
});

describe('development stays permissive', () => {
  it('accepts placeholders, the mock provider, no database and short TTL experiments', () => {
    const env = loadEnv({
      NODE_ENV: 'development',
      JWT_SECRET: 'change-me-to-a-long-random-secret-of-at-least-32-chars',
      AI_MOCK: '1',
      ACCESS_TOKEN_TTL_SEC: '90',
    });
    expect(env).toMatchObject({ APP_ENV: 'development', AI_MOCK: '1', ACCESS_TOKEN_TTL_SEC: 90 });
    expect(env.DATABASE_URL).toBeUndefined();
  });

  it('still refuses a short secret and a malformed value', () => {
    expect(() => loadEnv({ NODE_ENV: 'development', JWT_SECRET: 'short' })).toThrow(/at least 32 characters/);
    expect(() => loadEnv({ ...base, NODE_ENV: 'development', PORT: 'eighty' })).toThrow(/PORT/);
    expect(() => loadEnv({ ...base, NODE_ENV: 'development', DATABASE_URL: 'not a url' })).toThrow(/DATABASE_URL/);
  });
});

describe('warnings for allowed-but-risky production settings', () => {
  it('flags an unconfigured proxy count', () => {
    expect(envWarnings(loadEnv({ ...production, TRUST_PROXY_HOPS: '0' })).join('\n')).toMatch(/TRUST_PROXY_HOPS=0/);
    expect(envWarnings(loadEnv({ ...production, TRUST_PROXY_HOPS: '1' })).join('\n')).not.toMatch(/TRUST_PROXY_HOPS/);
  });

  it('an access token cannot be configured to live longer than an hour (A-08): it can only be revoked through its device', () => {
    expect(() => loadEnv({ ...production, ACCESS_TOKEN_TTL_SEC: '7200' })).toThrow(/ACCESS_TOKEN_TTL_SEC/);
    expect(loadEnv({ ...production, ACCESS_TOKEN_TTL_SEC: '3600' }).ACCESS_TOKEN_TTL_SEC).toBe(3600);
  });
});

describe('new settings', () => {
  it('feature flags default to ai=1, subscriptions=0, cloud sync=1 and accept only 0/1', () => {
    const env = loadEnv({ ...base, NODE_ENV: 'development' });
    expect([env.FEATURE_AI, env.FEATURE_SUBSCRIPTIONS, env.FEATURE_CLOUD_SYNC]).toEqual(['1', '0', '1']);
    expect(() => loadEnv({ ...base, NODE_ENV: 'development', FEATURE_AI: 'yes' })).toThrow(/FEATURE_AI/);
    expect(() => loadEnv({ ...base, NODE_ENV: 'development', FEATURE_CLOUD_SYNC: 'true' })).toThrow(/FEATURE_CLOUD_SYNC/);
  });

  it('retention, readiness timeout and log level have safe defaults and bounds', () => {
    const env = loadEnv({ ...base, NODE_ENV: 'development' });
    expect(env).toMatchObject({ AI_HISTORY_RETENTION_DAYS: 90, READY_DB_TIMEOUT_MS: 2000, LOG_LEVEL: 'info', REFRESH_REUSE_GRACE_SEC: 60, SESSION_ABSOLUTE_LIFETIME_DAYS: 90 });
    expect(() => loadEnv({ ...base, NODE_ENV: 'development', AI_HISTORY_RETENTION_DAYS: '0' })).toThrow(/AI_HISTORY_RETENTION_DAYS/);
    expect(() => loadEnv({ ...base, NODE_ENV: 'development', AI_HISTORY_RETENTION_DAYS: '1.5' })).toThrow(/AI_HISTORY_RETENTION_DAYS/);
    expect(() => loadEnv({ ...base, NODE_ENV: 'development', READY_DB_TIMEOUT_MS: '5' })).toThrow(/READY_DB_TIMEOUT_MS/);
    expect(() => loadEnv({ ...base, NODE_ENV: 'development', LOG_LEVEL: 'verbose' })).toThrow(/LOG_LEVEL/);
  });
});

describe('documentation matches the code', () => {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
  const example = readFileSync(path.join(root, 'apps/api/.env.example'), 'utf8');
  const docs = readFileSync(path.join(root, 'docs/CONFIGURATION.md'), 'utf8');

  it('.env.example and docs/CONFIGURATION.md mention every variable the server reads', () => {
    expect(ENV_VARIABLES.length).toBeGreaterThan(30);
    const missingInExample = ENV_VARIABLES.filter((v) => !new RegExp(`^#?\\s*${v}=`, 'm').test(example));
    const missingInDocs = ENV_VARIABLES.filter((v) => !docs.includes(`\`${v}\``));
    expect(missingInExample, 'variables missing in apps/api/.env.example').toEqual([]);
    expect(missingInDocs, 'variables missing in docs/CONFIGURATION.md').toEqual([]);
  });

  it('.env.example only names variables that exist', () => {
    const names = [...example.matchAll(/^#?\s*([A-Z][A-Z0-9_]+)=/gm)].map((m) => m[1]!);
    expect(names.filter((n) => !ENV_VARIABLES.includes(n))).toEqual([]);
  });

  it('.env.example loads as a development configuration, and as nothing stricter', () => {
    const values = Object.fromEntries(
      example
        .split('\n')
        .filter((l) => /^[A-Z][A-Z0-9_]+=/.test(l))
        .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]),
    );
    const env = loadEnv(values);
    expect(env.APP_ENV).toBe('development');
    // The template starts a first run without any provider key (E-15); staging and production refuse the mock below.
    expect(env.AI_MOCK).toBe('1');
    // copying the template to a staging or production host is refused, not silently accepted
    expect(() => loadEnv({ ...values, NODE_ENV: 'production' })).toThrow(/skip the production guards/); // APP_ENV=development in the file
    expect(() => loadEnv({ ...values, NODE_ENV: 'production', APP_ENV: 'production' })).toThrow(/placeholder/);
    expect(() => loadEnv({ ...values, NODE_ENV: 'production', APP_ENV: 'staging' })).toThrow(/development credentials/);
    expect(() => loadEnv({ ...values, NODE_ENV: 'production', APP_ENV: 'staging', JWT_SECRET: 'k3J9xQ2vLm8Zp4Rt7Yw1Nb6Hc5Df0Gs2AaBbCcDd', DATABASE_URL: 'postgres://app:s3cr3t-db-pass@db.internal:5432/wattbyte', TRUST_PROXY_HOPS: '1' })).toThrow(/AI_MOCK=1 is not allowed/);
  });
});
