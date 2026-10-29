import { z } from 'zod';

import { AI_MODES, type AIMode } from './types.js';

/**
 * The only data that may reach an AI provider: pre-computed aggregates.
 *
 * `.strict()` is the privacy guard: any extra key (email, userId, token, ip,
 * deviceId, ...) makes validation fail before a prompt is built.
 */
/**
 * Every number a prompt is built from is finite and bounded far above anything one phone produces, and the free-text
 * looking fields have a fixed shape: nothing a client sends is interpolated into a prompt as arbitrary text (D-10).
 */
const bounded = (max: number) => z.number().finite().nonnegative().max(max);

const PERIOD_SHAPE = {
  day: /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/,
  week: /^\d{4}-W(0[1-9]|[1-4]\d|5[0-3])$/,
  month: /^\d{4}-(0[1-9]|1[0-2])$/,
} as const;

export const AIInputSchema = z
  .object({
    /** '2026-10-13', '2026-W41' or '2026-10', matching `periodType`. */
    period: z.string().min(4).max(10),
    periodType: z.enum(['day', 'week', 'month']),
    mobileDataGb: bounded(1_000_000),
    wifiDataGb: bounded(1_000_000),
    totalDataGb: bounded(2_000_000),
    chargingSessions: z.number().int().nonnegative().max(100_000),
    batteryEnergyKwh: bounded(1_000_000),
    wallEnergyKwh: bounded(1_000_000),
    electricityCost: bounded(1_000_000_000),
    /** ISO 4217 shape: three capital letters. */
    currency: z.string().regex(/^[A-Z]{3}$/, 'must be three capital letters'),
    previousPeriodChangePercent: z.number().finite().min(-100).max(1_000_000).nullable().optional(),
    wifiSharePercent: z.number().finite().min(0).max(100).nullable().optional(),
    averageSessionMah: bounded(100_000).nullable().optional(),
  })
  .strict()
  .superRefine((input, ctx) => {
    if (!PERIOD_SHAPE[input.periodType].test(input.period)) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['period'], message: `must look like a ${input.periodType} (${input.periodType === 'day' ? 'YYYY-MM-DD' : input.periodType === 'week' ? 'YYYY-Www' : 'YYYY-MM'})` });
    }
  });

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

const TITLE_MAX = 80;
const MESSAGE_MAX = 600;
const EMOJI_FALLBACK = '⚡';
const EMOJI_MAX = 8;
const segmenter = new Intl.Segmenter('en', { granularity: 'grapheme' });

/** The first user-perceived character, or '' for an empty string. */
function firstGrapheme(text: string): string {
  for (const part of segmenter.segment(text.trim())) return part.segment;
  return '';
}

/**
 * Cuts at the last word boundary within `max` UTF-16 units (the unit the output schema counts, and what a phone
 * measures), never in the middle of a surrogate pair; adds an ellipsis.
 */
function truncateAtWord(text: string, max: number): string {
  if (text.length <= max) return text;
  let hard = text.slice(0, max - 1);
  if (/[\ud800-\udbff]$/.test(hard)) hard = hard.slice(0, -1);
  const space = hard.lastIndexOf(' ');
  const cut = space > max * 0.5 ? hard.slice(0, space) : hard;
  return `${cut.trimEnd().replace(/[,;:.!?-]+$/, '')}…`;
}

/**
 * Length limits are limits for the app's layout that a model can only approximate; they must not turn a good answer
 * into a paid failure (D-03). Cosmetic violations are repaired: unknown keys are dropped, an over-long title or
 * message is cut at a word boundary, an emoji field holding more than one character is reduced to its first one (or to ⚡
 * when that one is longer than the field allows).
 * Structural problems (not JSON, a missing field, a wrong type, a severity outside the enum) are still rejected.
 */
function normaliseOutput(json: object): Record<string, unknown> {
  const raw = json as Record<string, unknown>;
  const title = typeof raw.title === 'string' ? truncateAtWord(raw.title.trim(), TITLE_MAX) : raw.title;
  const message = typeof raw.message === 'string' ? truncateAtWord(raw.message.trim(), MESSAGE_MAX) : raw.message;
  let emoji = raw.emoji;
  if (typeof emoji === 'string' && emoji.trim() !== '') {
    // The first character only; a sequence longer than the field allows (a ZWJ family) is replaced, not cut in half.
    const first = firstGrapheme(emoji);
    emoji = first !== '' && first.length <= EMOJI_MAX ? first : EMOJI_FALLBACK;
  }
  return { title, message, severity: raw.severity, emoji };
}

/**
 * Turns raw model text into a validated `AIOutput` or throws `OutputRejectedError`.
 * `tone` is forced to the requested mode (the model's own value is ignored); cosmetic violations are repaired
 * (see `normaliseOutput`), everything structural is validated strictly against `AIOutputSchema`.
 */
export function parseAIOutput(text: string, mode: AIMode): AIOutput {
  if (text.trim() === '') throw new OutputRejectedError('empty_output', 'empty output');
  let json: unknown;
  try {
    json = extractJson(text);
  } catch (e) {
    throw new OutputRejectedError('invalid_output', e instanceof SyntaxError && e.message.startsWith('no JSON') ? 'no JSON object in output' : 'output is not valid JSON');
  }
  if (json === null || typeof json !== 'object' || Array.isArray(json)) throw new OutputRejectedError('invalid_output', 'schema ((root): not_an_object)');
  const parsed = AIOutputSchema.safeParse({ ...normaliseOutput(json), tone: mode });
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `${i.path.join('.') || '(root)'}: ${i.code}`);
    throw new OutputRejectedError('invalid_output', `schema (${issues.join(', ')})`);
  }
  return parsed.data;
}
