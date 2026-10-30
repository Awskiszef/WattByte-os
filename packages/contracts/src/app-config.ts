import { z } from 'zod';

/** Deployment the API runs in (`APP_ENV`); lets a client label a non-production backend. */
export const AppEnvironment = z.enum(['development', 'staging', 'production']);

/**
 * Server-side switches. A client hides the matching UI when one is `false`
 * and must not call the routes: they answer 503 `feature_disabled`.
 */
export const FeatureFlagsDto = z.object({
  ai: z.boolean(),
  subscriptions: z.boolean(),
  cloudSync: z.boolean(),
});

/** Daily AI generations per UTC day, as configured on the server (never hardcoded in the app). */
export const AiDailyLimitsDto = z.object({
  free: z.number().int().nonnegative(),
  premium: z.number().int().nonnegative(),
});

/**
 * Public runtime configuration, `GET /api/v1/config`. Contains no secret and
 * nothing account-specific, so it is served without authentication.
 */
/** `MAJOR.MINOR.PATCH`: the oldest app version the server still serves. */
export const AppVersion = z.string().regex(/^\d{1,4}\.\d{1,4}\.\d{1,4}$/);

export const AppConfigDto = z.object({
  environment: AppEnvironment,
  features: FeatureFlagsDto,
  ai: z.object({ dailyLimits: AiDailyLimitsDto }),
  /**
   * The oldest app version per platform the server still works with; an older app shows "update required" instead of
   * failing on requests the server no longer understands. Absent (or a platform missing) = no minimum.
   */
  minimumAppVersion: z.object({ android: AppVersion.optional(), ios: AppVersion.optional() }).optional(),
});

export type AppEnvironment = z.infer<typeof AppEnvironment>;
export type FeatureFlagsDto = z.infer<typeof FeatureFlagsDto>;
export type AppConfigDto = z.infer<typeof AppConfigDto>;
