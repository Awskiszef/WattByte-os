import { isIPv4, isIPv6 } from 'node:net';

import { AI_PROVIDER_IDS, modelPriceFor, PROVIDER_ENV_VARS, providerEnvProblems } from '@wattbyte/ai';
import { z } from 'zod';

import { resolveDatabaseConnection } from '../database/connection.js';

/** Deployments the API knows about; see docs/CONFIGURATION.md for what each one enforces. */
export const APP_ENVS = ['development', 'staging', 'production'] as const;
export type AppEnv = (typeof APP_ENVS)[number];

/** `'0' | '1'` switch, spelled the same way as AI_MOCK / DATABASE_SSL. */
const Flag = (fallback: '0' | '1') => z.enum(['0', '1']).default(fallback);

/**
 * A JSON object given as one environment variable (`{"openai": 5}`), parsed and validated here so a typo is a
 * boot error with the variable's name, not a surprise at the first request. The value is never echoed.
 */
const JsonVariable = <T extends z.ZodTypeAny>(name: string, shape: T) =>
  z
    .string()
    .transform((raw, ctx): z.infer<T> => {
      let value: unknown;
      try {
        value = JSON.parse(raw);
      } catch {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: `${name} must be valid JSON` });
        return z.NEVER;
      }
      const parsed = shape.safeParse(value);
      if (!parsed.success) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: `${name}: ${parsed.error.issues.map((i) => `${i.path.join('.') || '(root)'} ${i.message}`).join('; ')}` });
        return z.NEVER;
      }
      return parsed.data as z.infer<T>;
    });

const ProviderId = z.enum(AI_PROVIDER_IDS);
/** Model name -> USD per 1M tokens, e.g. `{"gpt-x":{"input":0.4,"output":1.6}}`. */
const ModelPricesShape = z.record(z.string().min(1).max(128), z.object({ input: z.number().nonnegative().finite(), output: z.number().nonnegative().finite() }).strict());
/** Provider -> USD per UTC day, e.g. `{"openai":5,"xai":2}`. */
const ProviderBudgetShape = z.record(ProviderId, z.number().nonnegative().finite());

/** Shared with `scripts/retention.ts`, which runs without the rest of the API configuration. */
export const RetentionEnvShape = {
  /** AI usage log rows (`ai_generations`) older than this are purged by `pnpm retention`. */
  AI_HISTORY_RETENTION_DAYS: z.coerce.number().int().min(1).max(3650).default(90),
} as const;

const EnvSchema = z
  .object({
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
    /** Which deployment this is. Default: `production` when NODE_ENV=production, otherwise `development`. One of NODE_ENV / APP_ENV must be set (see loadEnv). */
    APP_ENV: z.enum(APP_ENVS).optional(),
    PORT: z.coerce.number().int().positive().default(8080),
    HOST: z.string().default('0.0.0.0'),
    LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']).default('info'),
    DATABASE_URL: z.string().url().optional(),
    JWT_SECRET: z.string().min(32, 'JWT_SECRET must be at least 32 characters'),
    ACCESS_TOKEN_TTL_SEC: z.coerce.number().int().positive().max(3600).default(900),
    REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().positive().default(30),
    /**
     * A rotated refresh token presented again less than this long after its rotation is a retry
     * (rejected, no other session touched); at or beyond it, it is treated as theft.
     */
    REFRESH_REUSE_GRACE_SEC: z.coerce.number().int().nonnegative().max(600).default(60),
    /** A sign-in (a session family) ends this long after it started, however often its refresh token rotates. */
    SESSION_ABSOLUTE_LIFETIME_DAYS: z.coerce.number().int().min(1).max(3650).default(90),
    /** Set to the number of reverse proxies in front of the API; 0 trusts no forwarded header. */
    TRUST_PROXY_HOPS: z.coerce.number().int().nonnegative().default(0),
    /**
     * Alternative to TRUST_PROXY_HOPS that checks WHO the proxy is: comma-separated addresses / CIDRs of the reverse proxies
     * (e.g. `10.0.0.0/8,fd00::/8`). Forwarded headers (and COUNTRY_HEADER) are honoured only on a connection from one of
     * them; a client that reaches the origin directly cannot choose its address. Mutually exclusive with TRUST_PROXY_HOPS.
     */
    TRUST_PROXY_CIDRS: z.string().max(1024).optional(),
    /** Requests per minute per client IP: everything, credential endpoints, AI endpoints. */
    RATE_LIMIT_PER_MIN: z.coerce.number().int().positive().default(120),
    AUTH_RATE_LIMIT_PER_MIN: z.coerce.number().int().positive().default(10),
    /** `POST /auth/refresh` has its own, higher bucket: many devices behind one NAT address refresh independently of logins. */
    REFRESH_RATE_LIMIT_PER_MIN: z.coerce.number().int().positive().default(60),
    /** Password hashes (64 MiB scrypt each) running at once; more wait in a queue. */
    SCRYPT_CONCURRENCY: z.coerce.number().int().min(1).max(32).default(2),
    /** Hashes allowed to wait; beyond that the API answers 503 with Retry-After instead of queueing without bound. */
    SCRYPT_MAX_QUEUE: z.coerce.number().int().min(0).max(1_000).default(8),
    /** Requests per minute per SIGNED-IN USER, all AI routes together (one bucket). */
    AI_RATE_LIMIT_PER_MIN: z.coerce.number().int().positive().default(20),
    /** AI generations running at the same time in this process; the next one is answered 503 at once (D-09). */
    AI_MAX_CONCURRENT: z.coerce.number().int().min(1).max(1_000).default(16),
    DATABASE_SSL: z.enum(['0', '1']).default('0'),
    /** PEM file with the CA that signed the database certificate (private-CA / managed databases); needs DATABASE_SSL=1. */
    DATABASE_SSL_CA_FILE: z.string().max(1024).optional(),
    /** Installations one account may register; the next one is refused with 409 device_limit_reached (re-registering a known one always works). */
    MAX_DEVICES_PER_ACCOUNT: z.coerce.number().int().min(1).max(1_000).default(25),
    /** Registrations and syncs per signed-in account per minute (on top of the per-client limit). */
    CLOUD_WRITE_RATE_LIMIT_PER_MIN: z.coerce.number().int().min(1).max(10_000).default(30),
    /** Connections the API keeps to PostgreSQL. */
    DATABASE_POOL_MAX: z.coerce.number().int().min(1).max(200).default(10),
    /** A statement running longer is cancelled by the server (the client gives up 5 s later). */
    DATABASE_STATEMENT_TIMEOUT_MS: z.coerce.number().int().min(1_000).max(300_000).default(15_000),
    /** How long GET /ready waits for `SELECT 1` before answering 503. */
    READY_DB_TIMEOUT_MS: z.coerce.number().int().min(100).max(30_000).default(2_000),
    /** Longest time a client may take to send one whole request (headers and body); a stalled client is cut off. */
    REQUEST_TIMEOUT_MS: z.coerce.number().int().min(100).max(120_000).default(30_000),
    /** Idle keep-alive connections close after this; keep it just above the load balancer's idle timeout (ALB: 60 s). */
    KEEP_ALIVE_TIMEOUT_MS: z.coerce.number().int().min(100).max(300_000).default(65_000),
    /** Open connections the server accepts at once; more are refused. 0 = no limit. */
    MAX_CONNECTIONS: z.coerce.number().int().nonnegative().default(5_000),
    /** Requests served on one connection before it is recycled. 0 = no limit. */
    MAX_REQUESTS_PER_SOCKET: z.coerce.number().int().nonnegative().default(1_000),
    /** On SIGTERM /ready answers 503 immediately; this is how long the process then waits before it stops listening. */
    SHUTDOWN_DRAIN_MS: z.coerce.number().int().min(0).max(60_000).default(3_000),
    /** Hard deadline for the whole shutdown; keep it below the orchestrator's grace period (Kubernetes/ECS: 30 s). */
    SHUTDOWN_TIMEOUT_MS: z.coerce.number().int().min(1_000).max(300_000).default(25_000),
    AI_FREE_DAILY_LIMIT: z.coerce.number().int().nonnegative().default(3),
    AI_PREMIUM_DAILY_LIMIT: z.coerce.number().int().nonnegative().default(50),
    AI_MOCK: Flag('0'),
    /** Server-side feature switches; a disabled feature answers 503 `feature_disabled`. */
    FEATURE_AI: Flag('1'),
    FEATURE_SUBSCRIPTIONS: Flag('0'),
    FEATURE_CLOUD_SYNC: Flag('1'),
    ...RetentionEnvShape,
    /**
     * AI behaviour. Providers, their keys and their model names are the variables below; these decide how
     * a request uses them (docs/ai.md). Time values are milliseconds.
     */
    /** Tried first for every AI task when it has a key; unset = each task's own routing order. */
    AI_DEFAULT_PROVIDER: ProviderId.optional(),
    /** The whole request: every call, retry pause and the fallback together. Keep it below the client's own timeout (the app waits 90 s). */
    AI_REQUEST_TIMEOUT_MS: z.coerce.number().int().min(1_000).max(300_000).default(60_000),
    /** One call to one provider. */
    AI_ATTEMPT_TIMEOUT_MS: z.coerce.number().int().min(1_000).max(120_000).default(20_000),
    /** Extra calls to the same provider after a transient failure (429, 5xx, no connection), with exponential backoff and jitter. */
    AI_MAX_RETRIES: z.coerce.number().int().min(0).max(5).default(2),
    /** One request may go to ONE other provider after a failure that allows it (never after a bad request, a bad key, a refusal or unusable output). */
    AI_FALLBACK_ENABLED: Flag('1'),
    /** Whether a 429 counts as a failure that allows the fallback. */
    AI_FALLBACK_ON_RATE_LIMIT: Flag('1'),
    /** Per-model prices (JSON) for cost tracking and budgets; without them costs are flat per-provider estimates. */
    AI_MODEL_PRICES: JsonVariable('AI_MODEL_PRICES', ModelPricesShape).optional(),
    /** Spend limits in USD (estimates unless prices are configured or the provider reports the charge). Unset = no limit. */
    AI_BUDGET_DAILY_USD: z.coerce.number().nonnegative().finite().optional(),
    AI_BUDGET_MONTHLY_USD: z.coerce.number().nonnegative().finite().optional(),
    /** The free plan's share of the day's budget; default half of AI_BUDGET_DAILY_USD. Free accounts cost nothing to create. */
    AI_BUDGET_FREE_DAILY_USD: z.coerce.number().nonnegative().finite().optional(),
    /** Staging/production refuse to start with real AI providers and no AI_BUDGET_DAILY_USD unless this says so on purpose (`1`). */
    AI_BUDGET_UNLIMITED: Flag('0'),
    AI_BUDGET_PROVIDER_DAILY_USD: JsonVariable('AI_BUDGET_PROVIDER_DAILY_USD', ProviderBudgetShape).optional(),
    OPENAI_API_KEY: z.string().optional(),
    OPENAI_FAST_MODEL: z.string().optional(),
    OPENAI_QUALITY_MODEL: z.string().optional(),
    ANTHROPIC_API_KEY: z.string().optional(),
    ANTHROPIC_FAST_MODEL: z.string().optional(),
    ANTHROPIC_QUALITY_MODEL: z.string().optional(),
    GOOGLE_AI_API_KEY: z.string().optional(),
    GEMINI_FAST_MODEL: z.string().optional(),
    GEMINI_QUALITY_MODEL: z.string().optional(),
    XAI_API_KEY: z.string().optional(),
    XAI_FAST_MODEL: z.string().optional(),
    XAI_QUALITY_MODEL: z.string().optional(),
    /** Household electricity prices: how long a fetched value is reused (Eurostat updates twice a year). */
    ELECTRICITY_PRICE_CACHE_HOURS: z.coerce.number().positive().default(168),
    EUROSTAT_BASE_URL: z.string().url().optional(),
    /** Request header with the caller's country (e.g. `cf-ipcountry` behind Cloudflare). Empty = /region answers null. */
    COUNTRY_HEADER: z.string().max(64).default(''),
  })
  .transform((v) => ({
    ...v,
    APP_ENV: v.APP_ENV ?? (v.NODE_ENV === 'production' ? ('production' as const) : ('development' as const)),
  }));

export type Env = z.infer<typeof EnvSchema>;


/** Every variable the server reads; `.env.example` and docs/CONFIGURATION.md are checked against this list. */
export const ENV_VARIABLES: readonly string[] = Object.keys(EnvSchema.innerType().shape);

/** The proxy allow-list as an array (empty when unset). Entries are trimmed; empty ones are dropped. */
export function trustedProxyList(env: Pick<Env, 'TRUST_PROXY_CIDRS'>): string[] {
  return (env.TRUST_PROXY_CIDRS ?? '').split(',').map((s) => s.trim()).filter((s) => s !== '');
}

/** Why an entry of TRUST_PROXY_CIDRS is not an IPv4/IPv6 address or CIDR (empty list when all are fine). */
export function proxyCidrProblems(value: string): string[] {
  const problems: string[] = [];
  const entries = trustedProxyList({ TRUST_PROXY_CIDRS: value });
  if (entries.length === 0) problems.push('TRUST_PROXY_CIDRS is set but lists no address');
  for (const entry of entries) {
    const [addr = '', prefix, ...extra] = entry.split('/');
    const family = isIPv4(addr) ? 4 : isIPv6(addr) ? 6 : 0;
    const max = family === 4 ? 32 : 128;
    const prefixOk = prefix === undefined || (/^\d{1,3}$/.test(prefix) && Number(prefix) <= max);
    if (family === 0 || extra.length > 0 || !prefixOk) problems.push(`TRUST_PROXY_CIDRS entry "${entry}" is not an IPv4/IPv6 address or CIDR`);
    else if (prefix !== undefined && Number(prefix) === 0) problems.push(`TRUST_PROXY_CIDRS entry "${entry}" would trust every address`);
  }
  return problems;
}

/** Secrets that appear in docs or examples and must never run a real server. */
const PLACEHOLDER_SECRET = /change-?me|example|placeholder|secret-secret|test-secret/i;

/** A real secret (`openssl rand -base64 48`) uses far more than this many distinct characters. */
const MIN_DISTINCT_SECRET_CHARS = 10;

/** The throw-away credentials of infrastructure/docker/docker-compose.yml. */
function usesDevelopmentDatabaseCredentials(url: string): boolean {
  try {
    const u = new URL(url);
    return decodeURIComponent(u.username) === 'wattbyte' && decodeURIComponent(u.password) === 'wattbyte';
  } catch {
    return false;
  }
}

/**
 * Rules for the deployments that serve real traffic (`staging` and `production`).
 * Staging is held to the production bar on purpose: a staging that accepts a
 * placeholder secret or the mock AI provider hides exactly the mistakes that
 * production must not make.
 */
function strictEnvironmentProblems(env: Env, source: NodeJS.ProcessEnv): string[] {
  const problems: string[] = [];
  if (env.NODE_ENV !== 'production') problems.push(`APP_ENV=${env.APP_ENV} requires NODE_ENV=production`);
  if (PLACEHOLDER_SECRET.test(env.JWT_SECRET)) problems.push('JWT_SECRET looks like a placeholder; generate a real one');
  else if (new Set(env.JWT_SECRET).size < MIN_DISTINCT_SECRET_CHARS) {
    problems.push('JWT_SECRET is made of a repeated pattern; generate a real one (openssl rand -base64 48)');
  }
  if (env.AI_MOCK === '1') problems.push(`AI_MOCK=1 is not allowed when APP_ENV=${env.APP_ENV}`);
  if (!env.DATABASE_URL) problems.push(`DATABASE_URL is required when APP_ENV=${env.APP_ENV}`);
  else if (usesDevelopmentDatabaseCredentials(env.DATABASE_URL)) {
    problems.push('DATABASE_URL uses the development credentials of docker-compose.yml');
  }
  // Behind a reverse proxy every client shares the proxy's address unless the hop count is set; with a wrong
  // one clients choose their own address. There is no safe default, so the operator must state it (B-03).
  if (source.TRUST_PROXY_HOPS === undefined && source.TRUST_PROXY_CIDRS === undefined) {
    problems.push('TRUST_PROXY_CIDRS (the proxies\' addresses, preferred) or TRUST_PROXY_HOPS (their number; 0 = deliberately none, clients connect directly) must be set explicitly');
  }
  problems.push(...aiSpendProblems(env, source));
  // The default ('0') would silently send credentials and data in clear: the operator must choose.
  if (env.APP_ENV === 'production' && source.DATABASE_SSL === undefined) {
    problems.push('DATABASE_SSL must be set explicitly (1 = TLS with certificate verification, 0 = deliberately unencrypted private link)');
  }
  return problems;
}

/** Real AI providers can be called: the feature is on, the mock is off and at least one provider has a key. */
export function aiIsLive(env: Pick<Env, 'FEATURE_AI' | 'AI_MOCK'>, source: NodeJS.ProcessEnv): boolean {
  if (env.FEATURE_AI !== '1' || env.AI_MOCK === '1') return false;
  return AI_PROVIDER_IDS.some((id) => (source[PROVIDER_ENV_VARS[id].apiKey] ?? '').trim() !== '');
}

/**
 * Staging/production with real providers need a spend ceiling the application enforces (D-02, B-08): accounts are free
 * and unverified, so the per-account quota alone does not bound the bill. The ceiling is only as good as the prices it
 * is measured with, so every configured model needs an AI_MODEL_PRICES entry (D-07). `AI_BUDGET_UNLIMITED=1` is the
 * conscious opt-out (logged as a warning at every boot).
 */
function aiSpendProblems(env: Env, source: NodeJS.ProcessEnv): string[] {
  if (!aiIsLive(env, source)) return [];
  const budgetSet = env.AI_BUDGET_DAILY_USD !== undefined || env.AI_BUDGET_MONTHLY_USD !== undefined || env.AI_BUDGET_PROVIDER_DAILY_USD !== undefined;
  if (env.AI_BUDGET_UNLIMITED === '1') {
    return budgetSet ? ['AI_BUDGET_UNLIMITED=1 contradicts the AI_BUDGET_* limits that are set; remove one'] : [];
  }
  if (env.AI_BUDGET_DAILY_USD === undefined) {
    return ['AI_BUDGET_DAILY_USD must be set when real AI providers are configured (AI_BUDGET_MONTHLY_USD and AI_BUDGET_PROVIDER_DAILY_USD refine it), or AI_BUDGET_UNLIMITED=1 to run without an application-level spend ceiling on purpose'];
  }
  const problems: string[] = [];
  for (const id of AI_PROVIDER_IDS) {
    const vars = PROVIDER_ENV_VARS[id];
    if ((source[vars.apiKey] ?? '').trim() === '') continue;
    for (const name of [vars.fastModel, vars.qualityModel]) {
      const model = (source[name] ?? '').trim();
      if (model !== '' && modelPriceFor(env.AI_MODEL_PRICES, model) === undefined) {
        problems.push(`${name}=${model} has no entry in AI_MODEL_PRICES: the spend limits would measure it at a flat provider price`);
      }
    }
  }
  return problems;
}

/**
 * AI configuration that cannot work, in every environment: a key without a model, a default provider
 * without a key, an attempt that may outlast the whole request. Skipped when AI is off or mocked, because
 * then no real provider is built and a leftover variable is harmless.
 */
function aiProblems(env: Env, source: NodeJS.ProcessEnv): string[] {
  const problems: string[] = [];
  if (env.AI_ATTEMPT_TIMEOUT_MS > env.AI_REQUEST_TIMEOUT_MS) {
    problems.push('AI_ATTEMPT_TIMEOUT_MS must not be larger than AI_REQUEST_TIMEOUT_MS (one call cannot outlast the whole request)');
  }
  if (env.FEATURE_AI === '1' && env.AI_MOCK !== '1') {
    problems.push(...providerEnvProblems(source, { defaultProvider: env.AI_DEFAULT_PROVIDER }));
  }
  return problems;
}

/** Fails fast with a readable list of what is missing or unsafe. */
export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const cleaned = Object.fromEntries(Object.entries(source).filter(([, v]) => v !== ''));
  // An unspecified environment is not 'development': a deployment that forgot NODE_ENV would run with every
  // staging/production guard skipped (placeholder secret, mock AI, development database, no TLS), silently (B-07).
  // The development profile has to be asked for.
  if (cleaned.NODE_ENV === undefined && cleaned.APP_ENV === undefined) {
    throw new Error(
      'Invalid environment:\n  NODE_ENV: not set. Set NODE_ENV=development for local work, NODE_ENV=test for tests, or NODE_ENV=production (with APP_ENV=staging|production); an unspecified environment is refused because it would skip the production guards',
    );
  }
  const parsed = EnvSchema.safeParse(cleaned);
  if (!parsed.success) {
    const lines = parsed.error.issues.map((i) => `  ${i.path.join('.')}: ${i.message}`);
    throw new Error(`Invalid environment:\n${lines.join('\n')}`);
  }
  const env = parsed.data;
  const problems: string[] = [];
  // The proxy allow-list is parsed here so that a typo fails the boot instead of silently trusting nothing or everything.
  if (env.TRUST_PROXY_CIDRS !== undefined) {
    if (cleaned.TRUST_PROXY_HOPS !== undefined && env.TRUST_PROXY_HOPS > 0) {
      problems.push('TRUST_PROXY_CIDRS and TRUST_PROXY_HOPS are alternatives: set one (CIDRS verifies the proxy, HOPS only counts)');
    }
    problems.push(...proxyCidrProblems(env.TRUST_PROXY_CIDRS));
  }
  // DATABASE_URL must not contradict DATABASE_SSL (a `sslmode=disable` in the URL used to win silently, C-11).
  if (env.DATABASE_URL) {
    try {
      resolveDatabaseConnection({ url: env.DATABASE_URL, databaseSsl: cleaned.DATABASE_SSL, caFile: undefined });
    } catch (e) {
      problems.push(e instanceof Error ? e.message : 'DATABASE_URL and DATABASE_SSL disagree');
    }
  }
  // Guards keyed on one variable only could be bypassed by setting the other one.
  if (env.NODE_ENV === 'production' && env.APP_ENV === 'development') {
    problems.push('NODE_ENV=production with APP_ENV=development would skip the production guards');
  }
  problems.push(...aiProblems(env, cleaned));
  if (env.APP_ENV !== 'development') problems.push(...strictEnvironmentProblems(env, cleaned));
  if (problems.length) {
    throw new Error(`Invalid ${env.APP_ENV} environment:\n${problems.map((p) => `  ${p}`).join('\n')}`);
  }
  return env;
}

/** Things that are allowed but worth saying out loud at boot (logged by main.ts). */
export function envWarnings(env: Env): string[] {
  const out: string[] = [];
  if (env.AI_REQUEST_TIMEOUT_MS > 85_000) {
    out.push('AI_REQUEST_TIMEOUT_MS is above 85 s: the app gives up on an AI call after 90 s, and the server would keep paying for an answer nobody reads');
  }
  if (env.APP_ENV === 'development') return out;
  if (env.DATABASE_SSL === '0') out.push('DATABASE_SSL=0: PostgreSQL traffic is not encrypted; acceptable only on a private link');
  if (env.AI_BUDGET_UNLIMITED === '1' && aiIsLive(env, process.env)) {
    out.push('AI_BUDGET_UNLIMITED=1: nothing in this application limits AI spend; set a spending limit at every provider');
  }
  if (env.TRUST_PROXY_HOPS === 0 && !env.TRUST_PROXY_CIDRS) {
    out.push('TRUST_PROXY_HOPS=0: behind a reverse proxy every client shares the proxy address and one rate-limit bucket');
  }
  return out;
}
