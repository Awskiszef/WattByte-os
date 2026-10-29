import { AI_PROVIDER_IDS, AIGateway, type AIProviderId, type GatewayOptions, MockProvider, ProviderRouter } from '@wattbyte/ai';

import { type App, buildApp } from '../src/app.js';
import { loadEnv } from '../src/config/env.js';
import { MemoryRepositories } from '../src/database/memory.js';
import type { ElectricityPriceProvider } from '../src/modules/electricity/provider.js';
import { spendLedger } from '../src/modules/ai/gateway.js';

export interface TestContext {
  app: App;
  repos: MemoryRepositories;
  providers: Record<AIProviderId, MockProvider>;
}

export async function makeApp(
  overrides: Record<string, string> = {},
  deps: { priceProviders?: ElectricityPriceProvider[]; gatewayOptions?: (repos: MemoryRepositories) => Partial<Omit<GatewayOptions, 'router'>> } = {},
): Promise<TestContext> {
  const env = loadEnv({
    NODE_ENV: 'test',
    JWT_SECRET: 'test-secret-test-secret-test-secret-test-secret',
    AI_FREE_DAILY_LIMIT: '2',
    AI_PREMIUM_DAILY_LIMIT: '10',
    ...overrides,
  });
  const providers = Object.fromEntries(AI_PROVIDER_IDS.map((id) => [id, new MockProvider(id)])) as Record<AIProviderId, MockProvider>;
  const repos = new MemoryRepositories();
  const gateway = new AIGateway({ router: new ProviderRouter(Object.values(providers), { cooldownMs: 0 }), sleep: async () => undefined, ledger: spendLedger(env, repos), ...deps.gatewayOptions?.(repos) });
  const app = await buildApp({
    env,
    repos,
    gateway,
    providerIds: AI_PROVIDER_IDS.slice(),
    logger: false,
    rateLimitMax: 10_000,
    authRateLimitMax: 10_000,
    refreshRateLimitMax: 10_000,
    // Unit tests never reach Eurostat: no provider unless the test passes one.
    priceProviders: deps.priceProviders ?? [],
  });
  await app.ready();
  return { app, repos, providers };
}

export async function registerUser(app: App, email = 'a@b.co', password = 'password123') {
  const res = await app.inject({ method: 'POST', url: '/api/v1/auth/register', payload: { email, password } });
  if (res.statusCode !== 201) throw new Error(`register failed: ${res.body}`);
  const body = res.json() as {
    user: { id: string; email: string; plan: string; displayName: string | null };
    tokens: { accessToken: string; refreshToken: string; tokenType: string; expiresIn: number };
  };
  return { ...body, headers: { authorization: `Bearer ${body.tokens.accessToken}` } };
}

export const sampleInput = {
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
