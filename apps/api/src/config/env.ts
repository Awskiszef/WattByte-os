import { AI_PROVIDER_IDS, providerEnvProblems } from '@wattbyte/ai';
import { z } from 'zod';

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
    /** Which deployment this is. Default: `production` when NODE_ENV=production, otherwise `development`. */
    APP_ENV: z.enum(APP_ENVS).optional(),
    PORT: z.coerce.number().int().positive().default(8080),
    HOST: z.string().default('0.0.0.0'),
    LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']).default('info'),
    DATABASE_URL: z.string().url().optional(),
    JWT_SECRET: z.string().min(32, 'JWT_SECRET must be at least 32 characters'),
    ACCESS_TOKEN_TTL_SEC: z.coerce.number().int().positive().default(900),
    REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().positive().default(30),
    /**
     * A rotated refresh token presented again less than this long after its rotation is a retry
     * (rejected, no other session touched); at or beyond it, it is treated as theft.
     */
    REFRESH_REUSE_GRACE_SEC: z.coerce.number().int().nonnegative().default(10),
    /** Set to the number of reverse proxies in front of the API; 0 trusts no forwarded header. */
    TRUST_PROXY_HOPS: z.coerce.number().int().nonnegative().default(0),
    /** Requests per minute per client IP: everything, credential endpoints, AI endpoints. */
    RATE_LIMIT_PER_MIN: z.coerce.number().int().positive().default(120),
    AUTH_RATE_LIMIT_PER_MIN: z.coerce.number().int().positive().default(10),
    AI_RATE_LIMIT_PER_MIN: z.coerce.number().int().positive().default(20),
    DATABASE_SSL: z.enum(['0', '1']).default('0'),
    /** How long GET /ready waits for `SELECT 1` before answering 503. */
    READY_DB_TIMEOUT_MS: z.coerce.number().int().min(100).max(30_000).default(2_000),
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
  // The default ('0') would silently send credentials and data in clear: the operator must choose.
  if (env.APP_ENV === 'production' && source.DATABASE_SSL === undefined) {
    problems.push('DATABASE_SSL must be set explicitly (1 = TLS with certificate verification, 0 = deliberately unencrypted private link)');
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
  const parsed = EnvSchema.safeParse(cleaned);
  if (!parsed.success) {
    const lines = parsed.error.issues.map((i) => `  ${i.path.join('.')}: ${i.message}`);
    throw new Error(`Invalid environment:\n${lines.join('\n')}`);
  }
  const env = parsed.data;
  const problems: string[] = [];
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
  if (env.TRUST_PROXY_HOPS === 0) {
    out.push('TRUST_PROXY_HOPS=0: behind a reverse proxy every client shares the proxy address and one rate-limit bucket');
  }
  if (env.ACCESS_TOKEN_TTL_SEC > 3600) out.push('ACCESS_TOKEN_TTL_SEC is above one hour; a stolen access token cannot be revoked before it expires');
  return out;
}
