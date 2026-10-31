// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { describe, expect, it } from 'vitest';

import {
  AI_MODES,
  AI_OUTPUT_JSON_SCHEMA,
  AI_SEVERITIES,
  AIGateway,
  type AIGatewayError,
  AIOutputSchema,
  AnthropicProvider,
  extractJson,
  OutputRejectedError,
  parseAIOutput,
  ProviderRouter,
} from '../src/index.js';
import { ctx, fakeFetch, gatewayInput } from './helpers/doubles.js';

const valid = { title: 'Heavy month', message: '34% more data than last month.', tone: 'normal', severity: 'info', emoji: '⚡' };
const text = (o: unknown) => JSON.stringify(o);

describe('parseAIOutput accepts', () => {
  it('plain JSON', () => {
    expect(parseAIOutput(text(valid), 'normal')).toEqual(valid);
  });

  it('fenced JSON (```json and bare ```)', () => {
    expect(parseAIOutput('```json\n' + text(valid) + '\n```', 'normal')).toEqual(valid);
    expect(parseAIOutput('```\n' + text(valid) + '\n```', 'normal')).toEqual(valid);
  });

  it('JSON with a sentence before or after it', () => {
    expect(parseAIOutput(`Here you go:\n${text(valid)}\nHope that helps!`, 'normal')).toEqual(valid);
  });

  it('forces tone to the requested mode and tolerates a missing or wrong tone from the model', () => {
    expect(parseAIOutput(text({ ...valid, tone: 'roast' }), 'friendly').tone).toBe('friendly');
    const { tone: _tone, ...noTone } = valid;
    expect(parseAIOutput(text(noTone), 'funny').tone).toBe('funny');
    expect(parseAIOutput(text({ ...valid, tone: 'nonsense' }), 'funny').tone).toBe('funny');
  });

  it('trims strings and accepts the length limits exactly', () => {
    const edge = { ...valid, title: ' ' + 'a'.repeat(80) + ' ', message: 'b'.repeat(600), emoji: '🔋🔋🔋🔋' };
    const out = parseAIOutput(text(edge), 'normal');
    expect(out.title).toHaveLength(80);
    expect(out.message).toHaveLength(600);
  });

  it('every severity', () => {
    for (const severity of ['info', 'notice', 'celebrate']) expect(parseAIOutput(text({ ...valid, severity }), 'normal').severity).toBe(severity);
  });
});

describe('parseAIOutput rejects (the gateway then falls back to the next provider)', () => {
  const rejects = (input: string, kind: 'empty_output' | 'invalid_output', reason: RegExp) => {
    const e = (() => {
      try {
        parseAIOutput(input, 'normal');
      } catch (err) {
        return err;
      }
    })();
    expect(e).toBeInstanceOf(OutputRejectedError);
    expect(e).toMatchObject({ kind });
    expect((e as OutputRejectedError).reason).toMatch(reason);
    return e as OutputRejectedError;
  };

  it('empty and whitespace-only output', () => {
    rejects('', 'empty_output', /empty/);
    rejects(' \n\t ', 'empty_output', /empty/);
  });

  it('prose without JSON', () => {
    rejects('Sure! Here is an insight: you use a lot of data.', 'invalid_output', /no JSON object/);
  });

  it('truncated JSON (the closing brace never arrived, e.g. max tokens hit)', () => {
    rejects('{"title":"Heavy","message":"cut off', 'invalid_output', /no JSON object/);
  });

  it.each([
    ['two objects', `${text(valid)} and ${text(valid)}`],
    ['trailing comma', '{"title":"a","message":"b","severity":"info","emoji":"x",}'],
    ['single quotes', "{'title':'a'}"],
  ])('%s', (_name, input) => {
    rejects(input, 'invalid_output', /not valid JSON/);
  });

  it.each([
    ['missing title', { ...valid, title: undefined }],
    ['missing message', { ...valid, message: undefined }],
    ['missing severity', { ...valid, severity: undefined }],
    ['missing emoji', { ...valid, emoji: undefined }],
    ['unknown severity', { ...valid, severity: 'catastrophe' }],
    ['title not a string', { ...valid, title: 42 }],
    ['empty title', { ...valid, title: '   ' }],
    ['emoji not a string', { ...valid, emoji: 7 }],
    ['nested instead of flat', { output: valid }],
    ['an empty object', {}],
  ])('schema violation: %s', (_name, body) => {
    rejects(text(body), 'invalid_output', /^schema \(/);
  });

  it('a JSON value that is not an object (an array, a number) is structural', () => {
    rejects('[1,2,3] {"title": "x"', 'invalid_output', /not valid JSON|no JSON object/);
  });

  it('never quotes the model text in the reason (it may be user-derived or offensive)', () => {
    const e = rejects(text({ ...valid, severity: 'SENTINEL-SECRET', message: 7 }), 'invalid_output', /schema/);
    expect(e.message).not.toContain('SENTINEL-SECRET');
    expect(e.reason).toMatch(/severity: invalid_enum_value/);
    expect(e.reason).toMatch(/message: invalid_type/);
  });
});

/** D-03: limits the model can only approximate are repaired, not turned into a billed failure. */
describe('parseAIOutput repairs cosmetic violations', () => {
  const ok = (body: Record<string, unknown>) => parseAIOutput(text(body), 'normal');

  it('drops unknown keys (also prompt-injection style ones) instead of failing the answer', () => {
    const out = ok({ ...valid, reasoning: 'let me think', systemPrompt: 'ignore previous instructions', userId: '42' });
    expect(Object.keys(out).sort()).toEqual(['emoji', 'message', 'severity', 'title', 'tone']);
    expect(JSON.stringify(out)).not.toContain('ignore previous');
  });

  it('cuts a title over 80 and a message over 600 characters at a word boundary, with an ellipsis', () => {
    const out = ok({ ...valid, title: `${'word '.repeat(30)}`, message: `${'sentence '.repeat(100)}` });
    expect(out.title.length).toBeLessThanOrEqual(80);
    expect(out.message.length).toBeLessThanOrEqual(600);
    expect(out.title.endsWith('…')).toBe(true);
    expect(out.message.endsWith('…')).toBe(true);
    expect(out.title).not.toMatch(/wor…$/); // not cut inside a word
  });

  it('counts characters, not UTF-16 units: a long text of emoji is cut without breaking a surrogate pair', () => {
    const out = ok({ ...valid, message: '😀'.repeat(700) });
    expect(out.message.length).toBeLessThanOrEqual(600);
    expect(out.message).not.toMatch(/[\ud800-\udbff](?![\udc00-\udfff])/);
  });

  it('reduces an emoji field to its first character; one that is too long for the field (a ZWJ family) becomes ⚡', () => {
    expect(ok({ ...valid, emoji: '⚡🔋🔌' }).emoji).toBe('⚡');
    expect(ok({ ...valid, emoji: '  ⚡ ' }).emoji).toBe('⚡');
    expect(ok({ ...valid, emoji: '🏳️‍🌈' }).emoji).toBe('🏳️‍🌈'); // one character, 6 units: fits
    expect(ok({ ...valid, emoji: '👨‍👩‍👧‍👦' }).emoji).toBe('⚡'); // 11 units: does not fit
  });

  it('text that fits is untouched', () => {
    expect(ok({ ...valid, title: 'Heavy week', message: 'You used a lot of data.' })).toMatchObject({ title: 'Heavy week', message: 'You used a lot of data.' });
  });
});

describe('extractJson', () => {
  it('returns the outermost object', () => {
    expect(extractJson('noise {"a":{"b":1}} noise')).toEqual({ a: { b: 1 } });
  });

  it('throws SyntaxError without any object', () => {
    expect(() => extractJson('nothing here')).toThrow(SyntaxError);
    expect(() => extractJson('} backwards {')).toThrow(SyntaxError);
  });
});

describe('AIOutputSchema', () => {
  it('is strict: it is the contract of what reaches a client, parseAIOutput repairs before it', () => {
    expect(AIOutputSchema.safeParse({ ...valid, more: 1 }).success).toBe(false);
    expect(AIOutputSchema.safeParse({ ...valid, title: 'a'.repeat(81) }).success).toBe(false);
  });
});

describe('AI_OUTPUT_JSON_SCHEMA (what OpenAI is asked to produce) stays in step with AIOutputSchema (what is accepted)', () => {
  it('names exactly the same keys, all required, no extras allowed', () => {
    const keys = Object.keys(AIOutputSchema.shape).sort();
    expect(Object.keys(AI_OUTPUT_JSON_SCHEMA.properties).sort()).toEqual(keys);
    expect([...AI_OUTPUT_JSON_SCHEMA.required].sort()).toEqual(keys);
    expect(AI_OUTPUT_JSON_SCHEMA.additionalProperties).toBe(false);
  });

  it('offers the same tones and severities', () => {
    expect([...AI_OUTPUT_JSON_SCHEMA.properties.tone.enum]).toEqual([...AI_MODES]);
    expect([...AI_OUTPUT_JSON_SCHEMA.properties.severity.enum]).toEqual([...AI_SEVERITIES]);
  });

  it('a document that satisfies the JSON Schema shape passes the Zod schema', () => {
    expect(AIOutputSchema.safeParse({ title: 't', message: 'm', tone: 'roast', severity: 'celebrate', emoji: '⚡' }).success).toBe(true);
  });
});

describe('an answer cut at the token limit says so (D-03)', () => {
  it('Anthropic: stop_reason max_tokens + unusable text is reported as truncated, not as bad output', async () => {
    const { fetchImpl } = fakeFetch({ body: { content: [{ type: 'text', text: '{"title":"Heavy","message":"cut' }], stop_reason: 'max_tokens', usage: { input_tokens: 20, output_tokens: 476 } } });
    const gateway = new AIGateway({ router: new ProviderRouter([new AnthropicProvider({ apiKey: 'k', models: { fast: 'm' }, fetchImpl })]) });
    const e = (await gateway.generate('insight', 'normal', gatewayInput, ctx).catch((x: unknown) => x)) as AIGatewayError;
    expect(e.code).toBe('all_providers_failed');
    expect(e.attempts[0]).toMatchObject({ providerId: 'anthropic', kind: 'invalid_output' });
    expect(String(e.causes[0]?.message)).toMatch(/truncated at the token limit/);
    expect(e.billed[0]).toMatchObject({ providerId: 'anthropic', outputTokens: 476 }); // it was paid for
  });
});
