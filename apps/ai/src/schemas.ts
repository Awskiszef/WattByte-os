import { z } from 'zod';

import { AI_MODES, type AIMode } from './types.js';

/**
 * The only data that may reach an AI provider: pre-computed aggregates.
 *
 * `.strict()` is the privacy guard: any extra key (email, userId, token, ip,
 * deviceId, ...) makes validation fail before a prompt is built.
 */
export const AIInputSchema = z
  .object({
    /** '2026-10-13', '2026-W41' or '2026-10'. */
    period: z.string().min(4).max(10),
    periodType: z.enum(['day', 'week', 'month']),
    mobileDataGb: z.number().nonnegative(),
    wifiDataGb: z.number().nonnegative(),
    totalDataGb: z.number().nonnegative(),
    chargingSessions: z.number().int().nonnegative(),
    batteryEnergyKwh: z.number().nonnegative(),
    wallEnergyKwh: z.number().nonnegative(),
    electricityCost: z.number().nonnegative(),
    currency: z.string().length(3),
    previousPeriodChangePercent: z.number().nullable().optional(),
    wifiSharePercent: z.number().min(0).max(100).nullable().optional(),
    averageSessionMah: z.number().nonnegative().nullable().optional(),
  })
  .strict();

export type AIInput = z.infer<typeof AIInputSchema>;

export const AI_SEVERITIES = ['info', 'notice', 'celebrate'] as const;

/** Unified structured output. Anything else from a model is rejected. */
export const AIOutputSchema = z
  .object({
    title: z.string().trim().min(1).max(80),
    message: z.string().trim().min(1).max(600),
    tone: z.enum(AI_MODES),
    severity: z.enum(AI_SEVERITIES),
    emoji: z.string().trim().min(1).max(8),
  })
  .strict();

export type AIOutput = z.infer<typeof AIOutputSchema>;

/**
 * The same shape as `AIOutputSchema` as a JSON Schema, for providers that can constrain the model to it
 * (OpenAI `text.format`). Strict mode wants every property required and no extras; the length limits stay
 * with `AIOutputSchema`, which validates every answer whatever the provider promised.
 * `tests/output.test.ts` keeps the two in step.
 */
export const AI_OUTPUT_JSON_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['title', 'message', 'tone', 'severity', 'emoji'],
  properties: {
    title: { type: 'string' },
    message: { type: 'string' },
    tone: { type: 'string', enum: [...AI_MODES] },
    severity: { type: 'string', enum: [...AI_SEVERITIES] },
    emoji: { type: 'string' },
  },
} as const;

/** Extracts the first JSON object from model text (handles ```json fences). */
export function extractJson(text: string): unknown {
  const unfenced = text.replace(/```(?:json)?/gi, '').trim();
  const start = unfenced.indexOf('{');
  const end = unfenced.lastIndexOf('}');
  if (start < 0 || end <= start) throw new SyntaxError('no JSON object in model output');
  return JSON.parse(unfenced.slice(start, end + 1));
}

/** Model text that must not reach a user: empty, not JSON, or not matching `AIOutputSchema`. */
export class OutputRejectedError extends Error {
  constructor(
    readonly kind: 'empty_output' | 'invalid_output',
    /** Short, content-free reason: field paths and Zod issue codes, never the model's text. */
    readonly reason: string,
  ) {
    super(`output rejected: ${reason}`);
    this.name = 'OutputRejectedError';
  }
}

/**
 * Turns raw model text into a validated `AIOutput` or throws `OutputRejectedError`.
 * `tone` is forced to the requested mode (the model's own value is ignored);
 * every other field is validated strictly, so extra keys are rejected.
 */
export function parseAIOutput(text: string, mode: AIMode): AIOutput {
  if (text.trim() === '') throw new OutputRejectedError('empty_output', 'empty output');
  let json: unknown;
  try {
    json = extractJson(text);
  } catch (e) {
    throw new OutputRejectedError('invalid_output', e instanceof SyntaxError && e.message.startsWith('no JSON') ? 'no JSON object in output' : 'output is not valid JSON');
  }
  const parsed = AIOutputSchema.safeParse({ ...(json as object), tone: mode });
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `${i.path.join('.') || '(root)'}: ${i.code}`);
    throw new OutputRejectedError('invalid_output', `schema (${issues.join(', ')})`);
  }
  return parsed.data;
}
