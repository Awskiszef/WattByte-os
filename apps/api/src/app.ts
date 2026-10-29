import rateLimit from '@fastify/rate-limit';
import swagger from '@fastify/swagger';
import type { AIGateway } from '@wattbyte/ai';
import Fastify, { type FastifyInstance } from 'fastify';
import * as contracts from '@wattbyte/contracts';
import {
  createJsonSchemaTransformObject,
  jsonSchemaTransform,
  serializerCompiler,
  validatorCompiler,
  type ZodTypeProvider,
} from 'fastify-type-provider-zod';

import { type Env, trustedProxyList } from './config/env.js';
import type { Repositories } from './database/repositories.js';
import { errorHandler, notFoundHandler, RouteTable } from './errors/http-error.js';
import { featureFlagsFromEnv } from './features/flags.js';
import { authenticateUnlessPublic } from './middleware/auth.js';
import { rejectNulCharacters } from './middleware/input-guards.js';
import { buildLoggerOptions } from './observability/logging.js';
import { clientKey } from './middleware/client-key.js';
import { GroupedLocalStore } from './middleware/rate-limit-store.js';
import { configurePasswordHashing } from './modules/auth/password.js';
import { requestBodyDeadline } from './middleware/request-deadline.js';
import { makeViaTrustedProxy } from './middleware/trusted-proxy.js';
import { generateRequestId } from './observability/request-id.js';
import { aiRoutes } from './modules/ai/routes.js';
import { AiService } from './modules/ai/service.js';
import { authRoutes } from './modules/auth/routes.js';
import { AuthService } from './modules/auth/service.js';
import { TokenService } from './modules/auth/tokens.js';
import { cloudRoutes } from './modules/cloud/routes.js';
import { configRoutes } from './modules/config/routes.js';
import { devicesRoutes } from './modules/devices/routes.js';
import { EurostatElectricityPriceProvider } from './modules/electricity/eurostat.js';
import type { ElectricityPriceProvider } from './modules/electricity/provider.js';
import { electricityRoutes } from './modules/electricity/routes.js';
import { ElectricityPriceService } from './modules/electricity/service.js';
import { regionRoutes } from './modules/region/routes.js';
import { healthRoutes } from './modules/health/routes.js';
import { usageRoutes } from './modules/usage/routes.js';
import { usersRoutes } from './modules/users/routes.js';

export const API_VERSION = '0.1.0';

export interface AppDeps {
  env: Env;
  repos: Repositories;
  gateway: AIGateway;
  providerIds: string[];
  /** Newest migration file of this build; /ready answers 503 while the database has not applied it. Unset = not checked. */
  expectedSchemaVersion?: string;
  logger?: boolean;
  /** Receives the JSON log lines instead of stdout (tests assert on them); implies logging on. */
  logStream?: { write(msg: string): void };
  /** Global requests per minute per IP. */
  rateLimitMax?: number;
  /** Per-IP requests per minute on /ai/*; default 20. */
  aiRateLimitMax?: number;
  /** Per-IP requests per minute on credential endpoints; default 10. */
  authRateLimitMax?: number;
  /** Per-IP requests per minute on /auth/refresh; default 60. */
  refreshRateLimitMax?: number;
  now?: () => Date;
  /** Household price sources, first match wins; default: Eurostat. Tests pass fakes. */
  priceProviders?: ElectricityPriceProvider[];
}

export type App = FastifyInstance;

/** Process lifecycle seen by request handling; main.ts flips `draining` on SIGTERM. */
export interface Lifecycle {
  draining: boolean;
}

declare module 'fastify' {
  interface FastifyInstance {
    lifecycle: Lifecycle;
    /** Every registered route (method + path pattern); used for 405 answers and the route audit tests. */
    routeTable: RouteTable;
  }
}

/** Wires every module; nothing here touches process.env or the network. */
export async function buildApp(deps: AppDeps): Promise<App> {
  const { env, repos } = deps;
  const loggerOn = deps.logStream !== undefined || (deps.logger ?? env.NODE_ENV !== 'test');
  const app = Fastify({
    logger: loggerOn ? buildLoggerOptions({ level: env.LOG_LEVEL, stream: deps.logStream }) : false,
    // Take the caller's x-request-id only when it is well formed (see generateRequestId); echo it on every response.
    requestIdHeader: false,
    genReqId: generateRequestId,
    // Router-level failures (a malformed URL) never reach a route; they still use the error contract.
    frameworkErrors: (error, request, reply) => {
      void reply.header('x-request-id', request.id);
      errorHandler(error, request, reply);
    },
    // Only trust X-Forwarded-For when told how many proxies sit in front; otherwise clients could spoof the IP and dodge rate limits.
    // A proxy allow-list (TRUST_PROXY_CIDRS) verifies who forwards; a hop count only counts and trusts whoever connects.
    trustProxy: trustedProxyList(env).length > 0 ? trustedProxyList(env) : env.TRUST_PROXY_HOPS > 0 ? (_address: string, hop: number) => hop < env.TRUST_PROXY_HOPS : false,
    // Every body of this API is tiny (the largest, /usage/sync, sets its own 64 KiB limit): a small default keeps
    // the work and memory an attacker-sized body can cause small (B-04).
    bodyLimit: 16_384,
    // Node's own default (300 s) is overridden by Fastify's 0 = unlimited: a client that stalls with an
    // open body would hold its socket for ever (B-06). `connectionsCheckingInterval` is how often Node looks.
    requestTimeout: env.REQUEST_TIMEOUT_MS,
    keepAliveTimeout: env.KEEP_ALIVE_TIMEOUT_MS,
    maxRequestsPerSocket: env.MAX_REQUESTS_PER_SOCKET,
    http: { connectionsCheckingInterval: Math.max(100, Math.min(5_000, Math.floor(env.REQUEST_TIMEOUT_MS / 2))) },
  }).withTypeProvider<ZodTypeProvider>();

  // Node rejects a headersTimeout below keepAliveTimeout with surprising resets on reused connections.
  app.server.headersTimeout = Math.max(app.server.headersTimeout, env.KEEP_ALIVE_TIMEOUT_MS + 5_000);
  app.server.maxConnections = env.MAX_CONNECTIONS;
  // Node enforces requestTimeout only until the headers are complete; this covers the body (B-06).
  app.addHook('onRequest', requestBodyDeadline(env.REQUEST_TIMEOUT_MS));
  configurePasswordHashing({ concurrency: env.SCRYPT_CONCURRENCY, maxQueue: env.SCRYPT_MAX_QUEUE });
  const lifecycle: Lifecycle = { draining: false };
  app.decorate('lifecycle', lifecycle);
  // While draining every response asks the client (and the proxy) to take its next request elsewhere.
  app.addHook('onSend', async (_request, reply) => {
    if (lifecycle.draining) reply.header('connection', 'close');
  });

  const routes = new RouteTable();
  app.addHook('onRoute', (route) => routes.add(route.method, route.url));
  app.decorate('routeTable', routes);

  app.setValidatorCompiler(validatorCompiler);
  app.setSerializerCompiler(serializerCompiler);
  app.setErrorHandler(errorHandler);
  // Only JSON bodies exist in this API. Fastify also accepts text/plain by default, which would let a
  // string reach the validators; without a parser it is a clean 415 `unsupported_media_type`.
  app.removeContentTypeParser('text/plain');

  await app.register(swagger, {
    openapi: {
      openapi: '3.0.3',
      info: {
        title: 'WattByte API',
        version: API_VERSION,
        description:
          'Accounts, device registration, per-day aggregate sync and AI summaries. ' +
          'Raw samples and per-app usage never leave the phone.',
      },
      components: {
        securitySchemes: { bearerAuth: { type: 'http', scheme: 'bearer', bearerFormat: 'JWT' } },
      },
    },
    transform: jsonSchemaTransform,
    // Named components so the generated Dart client gets real model classes.
    transformObject: createJsonSchemaTransformObject({
      schemas: {
        ErrorResponse: contracts.ErrorResponse,
        HealthResponse: contracts.HealthResponse,
        ReadyResponse: contracts.ReadyResponse,
        RegisterRequest: contracts.RegisterRequest,
        LoginRequest: contracts.LoginRequest,
        RefreshRequest: contracts.RefreshRequest,
        UserDto: contracts.UserDto,
        TokenPair: contracts.TokenPair,
        AuthResponse: contracts.AuthResponse,
        ChangePasswordRequest: contracts.ChangePasswordRequest,
        SessionDto: contracts.SessionDto,
        SessionListResponse: contracts.SessionListResponse,
        UpdateMeRequest: contracts.UpdateMeRequest,
        DeviceRegisterRequest: contracts.DeviceRegisterRequest,
        DeviceDto: contracts.DeviceDto,
        DeviceListResponse: contracts.DeviceListResponse,
        DailyUsageDto: contracts.DailyUsageDto,
        UsageSyncRequest: contracts.UsageSyncRequest,
        UsageSyncResponse: contracts.UsageSyncResponse,
        UsageDailyResponse: contracts.UsageDailyResponse,
        AIInput: contracts.AIInputSchema,
        AIOutput: contracts.AIOutputSchema,
        AIGenerateRequest: contracts.AIGenerateRequest,
        AIGenerateResponse: contracts.AIGenerateResponse,
        DeviceSpecificationDto: contracts.DeviceSpecificationDto,
        UserSettingsDto: contracts.UserSettingsDto,
        UpdateUserSettingsRequest: contracts.UpdateUserSettingsRequest,
        ElectricityPriceDto: contracts.ElectricityPriceDto,
        RegionResponse: contracts.RegionResponse,
        ...contracts.cloudDataOpenApiSchemas,
        AppConfigDto: contracts.AppConfigDto,
      },
    }),
  });

  // The key is the client's /64 for IPv6 and the plain address for IPv4 (also inherited by the per-route limits).
  await app.register(rateLimit, {
    max: deps.rateLimitMax ?? env.RATE_LIMIT_PER_MIN,
    timeWindow: '1 minute',
    keyGenerator: (request) => clientKey(request.ip),
    // Routes with the same `groupId` share one bucket (credential endpoints).
    store: GroupedLocalStore as unknown as NonNullable<Parameters<typeof rateLimit>[1]>['store'],
  });

  // Unknown paths and wrong methods answer with the error contract (404 / 405), rate limited like any route.
  app.setNotFoundHandler({ preHandler: app.rateLimit() }, notFoundHandler(routes));

  // onSend runs for every reply, errors and 404s included.
  app.addHook('onSend', async (request, reply) => {
    reply.header('x-request-id', request.id);
    reply.header('cache-control', 'no-store');
    reply.header('x-content-type-options', 'nosniff');
  });

  const tokens = new TokenService(env.JWT_SECRET, env.ACCESS_TOKEN_TTL_SEC, env.REFRESH_TOKEN_TTL_DAYS);
  const features = featureFlagsFromEnv(env);
  const aiDailyLimits = { free: env.AI_FREE_DAILY_LIMIT, premium: env.AI_PREMIUM_DAILY_LIMIT };
  // Deny by default: every route needs a bearer token unless it is marked `config: { public: true }`.
  // `preParsing` runs after the rate limiter (an onRequest hook) and before the body is read or validated.
  app.addHook('preParsing', authenticateUnlessPublic(tokens, repos));
  // PostgreSQL text cannot hold U+0000: refuse it as invalid input instead of letting the insert fail as a 500.
  app.addHook('preValidation', rejectNulCharacters);
  const auth = new AuthService(repos, tokens, deps.now, env.REFRESH_REUSE_GRACE_SEC * 1000, env.SESSION_ABSOLUTE_LIFETIME_DAYS * 86_400_000);
  // The AI routes pass `request.log` per call, so AI log lines carry the request id.
  const ai = new AiService(repos, deps.gateway, aiDailyLimits, deps.now);

  const prices = new ElectricityPriceService(
    deps.priceProviders ?? [new EurostatElectricityPriceProvider({ baseUrl: env.EUROSTAT_BASE_URL })],
    repos.prices,
    {
      cacheMs: env.ELECTRICITY_PRICE_CACHE_HOURS * 3_600_000,
      now: deps.now,
      // The `err` serializer logs type, code and stack frames; the upstream's own text is not logged.
      onError: (country, e) => app.log.warn({ country, err: e }, 'electricity price source failed'),
    },
  );

  app.get('/openapi.json', { config: { public: true }, schema: { hide: true } }, async () => app.swagger());
  await app.register(healthRoutes, {
    repos,
    providerIds: deps.providerIds,
    version: API_VERSION,
    readyTimeoutMs: env.READY_DB_TIMEOUT_MS,
    expectedSchemaVersion: deps.expectedSchemaVersion,
  });

  await app.register(
    async (v1) => {
      await v1.register(authRoutes, { service: auth, tokens, rateLimitMax: deps.authRateLimitMax ?? env.AUTH_RATE_LIMIT_PER_MIN, refreshRateLimitMax: deps.refreshRateLimitMax ?? env.REFRESH_RATE_LIMIT_PER_MIN });
      await v1.register(usersRoutes, { repos, tokens, auth });
      await v1.register(cloudRoutes, { repos, tokens });
      await v1.register(devicesRoutes, { repos, tokens });
      await v1.register(usageRoutes, { repos, tokens, features });
      await v1.register(electricityRoutes, { service: prices, repos, tokens });
      await v1.register(regionRoutes, { countryHeader: env.COUNTRY_HEADER, viaTrustedProxy: makeViaTrustedProxy(env) });
      await v1.register(aiRoutes, { service: ai, tokens, features, rateLimitMax: deps.aiRateLimitMax ?? env.AI_RATE_LIMIT_PER_MIN });
      await v1.register(configRoutes, { environment: env.APP_ENV, features, aiDailyLimits });
    },
    { prefix: '/api/v1' },
  );

  return app;
}
