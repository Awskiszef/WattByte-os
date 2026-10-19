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

import type { Env } from './config/env.js';
import type { Repositories } from './database/repositories.js';
import { errorHandler, notFoundHandler, RouteTable } from './errors/http-error.js';
import { featureFlagsFromEnv } from './features/flags.js';
import { authenticateUnlessPublic } from './middleware/auth.js';
import { rejectNulCharacters } from './middleware/input-guards.js';
import { buildLoggerOptions } from './observability/logging.js';
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
  logger?: boolean;
  /** Receives the JSON log lines instead of stdout (tests assert on them); implies logging on. */
  logStream?: { write(msg: string): void };
  /** Global requests per minute per IP. */
  rateLimitMax?: number;
  /** Per-IP requests per minute on /ai/*; default 20. */
  aiRateLimitMax?: number;
  /** Per-IP requests per minute on credential endpoints; default 10. */
  authRateLimitMax?: number;
  now?: () => Date;
  /** Household price sources, first match wins; default: Eurostat. Tests pass fakes. */
  priceProviders?: ElectricityPriceProvider[];
}

export type App = FastifyInstance;

declare module 'fastify' {
  interface FastifyInstance {
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
    trustProxy: env.TRUST_PROXY_HOPS > 0 ? (_address: string, hop: number) => hop < env.TRUST_PROXY_HOPS : false,
    bodyLimit: 1_048_576,
  }).withTypeProvider<ZodTypeProvider>();

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

  await app.register(rateLimit, { max: deps.rateLimitMax ?? env.RATE_LIMIT_PER_MIN, timeWindow: '1 minute' });

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
  const auth = new AuthService(repos, tokens, deps.now, env.REFRESH_REUSE_GRACE_SEC * 1000);
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
  });

  await app.register(
    async (v1) => {
      await v1.register(authRoutes, { service: auth, rateLimitMax: deps.authRateLimitMax ?? env.AUTH_RATE_LIMIT_PER_MIN });
      await v1.register(usersRoutes, { repos, tokens });
      await v1.register(cloudRoutes, { repos, tokens });
      await v1.register(devicesRoutes, { repos, tokens });
      await v1.register(usageRoutes, { repos, tokens, features });
      await v1.register(electricityRoutes, { service: prices, repos, tokens });
      await v1.register(regionRoutes, { countryHeader: env.COUNTRY_HEADER });
      await v1.register(aiRoutes, { service: ai, tokens, features, rateLimitMax: deps.aiRateLimitMax ?? env.AI_RATE_LIMIT_PER_MIN });
      await v1.register(configRoutes, { environment: env.APP_ENV, features, aiDailyLimits });
    },
    { prefix: '/api/v1' },
  );

  return app;
}
