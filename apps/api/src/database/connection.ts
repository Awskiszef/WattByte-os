import { readFileSync } from 'node:fs';
import type { ConnectionOptions } from 'node:tls';

/** URL query parameters that decide TLS in libpq / node-postgres; node-postgres lets them override the `ssl` option. */
const SSL_URL_PARAMS = ['sslmode', 'ssl', 'sslcert', 'sslkey', 'sslrootcert', 'sslcrl', 'uselibpqcompat'] as const;

/** `sslmode` values and `ssl` flags that mean "not verified" or "not encrypted". */
const WEAK_SSLMODES = new Set(['disable', 'allow', 'prefer', 'no-verify']);
const STRONG_SSLMODES = new Set(['require', 'verify-ca', 'verify-full']);

export interface DatabaseConnectionInput {
  url: string;
  /** What the operator wrote in DATABASE_SSL; undefined = not decided (the URL then controls TLS, as it always did). */
  databaseSsl?: string;
  /** PEM file with the CA that signed the server certificate (private-CA databases). Only with DATABASE_SSL=1. */
  caFile?: string;
}

export interface DatabaseConnection {
  connectionString: string;
  ssl?: ConnectionOptions;
}

/**
 * The ONE place that turns DATABASE_URL + DATABASE_SSL into node-postgres options, used by the API, the retention job and
 * the migration step (C-06, C-11, E-07).
 *
 *  - DATABASE_SSL=1: TLS with certificate verification (and `caFile` as the trust anchor). The URL's own TLS parameters
 *    are removed so they cannot override it; a URL that asks for LESS (`sslmode=disable|no-verify|prefer|allow`,
 *    `ssl=0`) contradicts the explicit choice and is refused instead of silently winning.
 *  - DATABASE_SSL=0: deliberately unencrypted; a URL that asks for TLS contradicts it and is refused.
 *  - DATABASE_SSL not set: the URL decides, as before (development, existing deployments that put sslmode in the URL).
 */
export function resolveDatabaseConnection(input: DatabaseConnectionInput): DatabaseConnection {
  const { url, databaseSsl, caFile } = input;
  const choice = databaseSsl === undefined || databaseSsl === '' ? undefined : databaseSsl;
  if (choice !== undefined && choice !== '0' && choice !== '1') throw new Error('DATABASE_SSL must be 0 or 1');
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    // Not a URL we can read (a socket path form): nothing to inspect or strip.
    if (choice === '1') return { connectionString: url, ssl: tlsOptions(caFile) };
    return { connectionString: url };
  }
  const sslmode = parsed.searchParams.get('sslmode')?.toLowerCase();
  const sslFlag = parsed.searchParams.get('ssl')?.toLowerCase();
  const urlWeakens = (sslmode !== undefined && WEAK_SSLMODES.has(sslmode)) || sslFlag === '0' || sslFlag === 'false';
  const urlWantsTls = (sslmode !== undefined && STRONG_SSLMODES.has(sslmode)) || sslFlag === '1' || sslFlag === 'true';

  if (choice === '1') {
    if (urlWeakens) {
      const what = sslmode !== undefined && WEAK_SSLMODES.has(sslmode) ? `sslmode=${sslmode}` : `ssl=${sslFlag}`;
      throw new Error(`DATABASE_URL asks for ${what} but DATABASE_SSL=1 requires verified TLS: remove the parameter from the URL (or set DATABASE_SSL=0 on purpose)`);
    }
    for (const p of SSL_URL_PARAMS) parsed.searchParams.delete(p);
    return { connectionString: parsed.toString(), ssl: tlsOptions(caFile) };
  }
  if (choice === '0' && urlWantsTls) {
    throw new Error(`DATABASE_URL asks for ${sslmode !== undefined ? `sslmode=${sslmode}` : `ssl=${sslFlag}`} but DATABASE_SSL=0 says the link is unencrypted on purpose: decide one`);
  }
  if (caFile !== undefined && caFile !== '') throw new Error('DATABASE_SSL_CA_FILE needs DATABASE_SSL=1');
  return { connectionString: url };
}

function tlsOptions(caFile: string | undefined): ConnectionOptions {
  if (caFile === undefined || caFile === '') return { rejectUnauthorized: true };
  let ca: string;
  try {
    ca = readFileSync(caFile, 'utf8');
  } catch {
    throw new Error('DATABASE_SSL_CA_FILE cannot be read');
  }
  if (!ca.includes('BEGIN CERTIFICATE')) throw new Error('DATABASE_SSL_CA_FILE does not contain a PEM certificate');
  return { rejectUnauthorized: true, ca };
}

/** Pool settings every connection of the API gets (C-08): a database that stops answering without closing the socket must not pin the pool for the OS TCP timeout. */
export interface PoolTuning {
  max: number;
  statementTimeoutMs: number;
}

export const DEFAULT_POOL_TUNING: PoolTuning = { max: 10, statementTimeoutMs: 15_000 };

export function poolSettings(tuning: PoolTuning) {
  return {
    max: tuning.max,
    // Server side: the statement is cancelled. Client side: if the server never answers (black-holed path), the query
    // fails after a little longer and its connection is destroyed instead of waiting for the kernel.
    statement_timeout: tuning.statementTimeoutMs,
    query_timeout: tuning.statementTimeoutMs + 5_000,
    connectionTimeoutMillis: 5_000,
    // A transaction abandoned by a crashed handler must not hold locks for ever.
    idle_in_transaction_session_timeout: 30_000,
    // Detect a dead peer on idle connections, and do not keep a connection for ever (a failover/proxy swap is noticed).
    keepAlive: true,
    keepAliveInitialDelayMillis: 10_000,
    maxLifetimeSeconds: 3_600,
  } as const;
}
