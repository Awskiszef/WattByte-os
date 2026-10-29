import { AI_PROVIDER_IDS, AIGateway, type AIProviderId, MockProvider, ProviderRouter } from '@wattbyte/ai';

import { type App, buildApp } from '../src/app.js';
import { type Env, loadEnv } from '../src/config/env.js';
import { MemoryRepositories } from '../src/database/memory.js';
import type { Repositories } from '../src/database/repositories.js';
import { TokenService } from '../src/modules/auth/tokens.js';
import { spendLedger } from '../src/modules/ai/gateway.js';

export const TEST_SECRET = 'test-secret-test-secret-test-secret-test-secret';

/** Collects the JSON log lines the app writes, so a test can assert on exactly what would reach a log service. */
export class LogCapture {
  readonly lines: string[] = [];

  write(msg: string): void {
    for (const line of msg.split('\n')) if (line.trim()) this.lines.push(line);
  }

  /** Every line, parsed; a non-JSON line fails the test that asked for it. */
  records(): Record<string, unknown>[] {
    return this.lines.map((l) => JSON.parse(l) as Record<string, unknown>);
  }

  text(): string {
    return this.lines.join('\n');
  }
}

export interface BuildOptions {
  env?: Record<string, string>;
  repos?: Repositories;
  logStream?: { write(msg: string): void };
  now?: () => Date;
  rateLimitMax?: number;
  authRateLimitMax?: number;
  refreshRateLimitMax?: number;
  aiRateLimitMax?: number;
}

export interface BuiltApp {
  app: App;
  env: Env;
  repos: Repositories;
  memory: MemoryRepositories;
  providers: Record<AIProviderId, MockProvider>;
}

/** Same wiring as `makeApp`, with the knobs the hardening tests need (clock, log stream, limits, repositories). */
export async function buildTestApp(opts: BuildOptions = {}): Promise<BuiltApp> {
  const env = loadEnv({
    NODE_ENV: 'test',
    JWT_SECRET: TEST_SECRET,
    AI_FREE_DAILY_LIMIT: '2',
    AI_PREMIUM_DAILY_LIMIT: '10',
    ...opts.env,
  });
  const providers = Object.fromEntries(AI_PROVIDER_IDS.map((id) => [id, new MockProvider(id)])) as Record<AIProviderId, MockProvider>;
  const memory = new MemoryRepositories();
  const repos = opts.repos ?? memory;
  const gateway = new AIGateway({ router: new ProviderRouter(Object.values(providers), { cooldownMs: 0 }), sleep: async () => undefined, ledger: spendLedger(env, repos) });
  const app = await buildApp({
    env,
    repos,
    gateway,
    providerIds: AI_PROVIDER_IDS.slice(),
    logger: false,
    logStream: opts.logStream,
    now: opts.now,
    rateLimitMax: opts.rateLimitMax ?? 100_000,
    authRateLimitMax: opts.authRateLimitMax ?? 100_000,
    refreshRateLimitMax: opts.refreshRateLimitMax ?? 100_000,
    aiRateLimitMax: opts.aiRateLimitMax ?? 100_000,
    priceProviders: [],
  });
  await app.ready();
  return { app, env, repos, memory, providers };
}

export interface Registered {
  userId: string;
  email: string;
  accessToken: string;
  refreshToken: string;
  headers: { authorization: string };
}

export async function register(app: App, email: string, password = 'password123', extra: Record<string, unknown> = {}): Promise<Registered> {
  const res = await app.inject({ method: 'POST', url: '/api/v1/auth/register', payload: { email, password, ...extra } });
  if (res.statusCode !== 201) throw new Error(`register failed: ${res.statusCode} ${res.body}`);
  const body = res.json() as { user: { id: string; email: string }; tokens: { accessToken: string; refreshToken: string } };
  return {
    userId: body.user.id,
    email: body.user.email,
    accessToken: body.tokens.accessToken,
    refreshToken: body.tokens.refreshToken,
    headers: { authorization: `Bearer ${body.tokens.accessToken}` },
  };
}

/**
 * An account with a live session, created straight in the repositories: no scrypt (about 100 ms and 64 MiB of
 * memory per hash), so the many tests that are not about passwords stay cheap and do not starve the timing-
 * sensitive login test that runs next to them. The password flows are tested through `register` / `/auth/login`.
 */
export async function seedUser(repos: Repositories, email: string): Promise<Registered> {
  const tokens = new TokenService(TEST_SECRET, 900, 30);
  const user = await repos.users.create({ email, passwordHash: null });
  const refreshToken = tokens.newRefreshToken();
  await repos.sessions.create({ userId: user.id, refreshHash: TokenService.hashRefresh(refreshToken), expiresAt: tokens.refreshExpiry() });
  const accessToken = await tokens.signAccess({ userId: user.id, plan: user.plan });
  return { userId: user.id, email: user.email, accessToken, refreshToken, headers: { authorization: `Bearer ${accessToken}` } };
}

/** The shape every failure must have; `code` is the machine contract, `message` is human text. */
export function expectErrorBody(body: unknown, code: string): void {
  if (typeof body !== 'object' || body === null) throw new Error(`not an object: ${String(body)}`);
  const keys = Object.keys(body);
  if (keys.length !== 1 || keys[0] !== 'error') throw new Error(`error body must have exactly one key "error": ${JSON.stringify(body)}`);
  const { error } = body as { error: { code?: unknown; message?: unknown } };
  if (Object.keys(error).sort().join() !== 'code,message') throw new Error(`error must have exactly code + message: ${JSON.stringify(error)}`);
  if (error.code !== code) throw new Error(`expected error code ${code}, got ${String(error.code)} (${JSON.stringify(error)})`);
  if (typeof error.message !== 'string' || error.message.length === 0) throw new Error('error.message must be a non-empty string');
}

export const sampleAiInput = {
  period: '2026-10',
  periodType: 'month',
  mobileDataGb: 187.4,
  wifiDataGb: 1433.8,
  totalDataGb: 1621.2,
  chargingSessions: 94,
  batteryEnergyKwh: 1.56,
  wallEnergyKwh: 1.84,
  electricityCost: 2.31,
  currency: 'PLN',
  previousPeriodChangePercent: 34,
};

export const sampleDay = (date: string) => ({
  date,
  mobileBytes: 1_000,
  wifiBytes: 2_000,
  chargedWh: 5,
  wallWh: 6,
  chargingSessions: 1,
  estimatedCost: 0.01,
  currency: 'PLN',
  dataEstimated: false,
  energyEstimated: true,
});

/** A PostgreSQL error as `pg` throws it: SQLSTATE, constraint, a `detail` that echoes the offending value. */
export function pgStyleError(leakedValue: string): Error {
  return Object.assign(new Error('duplicate key value violates unique constraint "users_email_key"'), {
    name: 'error',
    length: 262,
    severity: 'ERROR',
    code: '23505',
    detail: `Key (lower(email))=(${leakedValue}) already exists.`,
    schema: 'public',
    table: 'users',
    constraint: 'users_email_key',
    file: 'nbtinsert.c',
    line: '666',
    routine: '_bt_check_unique',
  });
}
