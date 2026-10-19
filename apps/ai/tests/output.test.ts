import { describe, expect, it } from 'vitest';

import { AI_MODES, AI_OUTPUT_JSON_SCHEMA, AI_SEVERITIES, AIOutputSchema, OutputRejectedError, extractJson, parseAIOutput } from '../src/index.js';

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
    ['title too long (81)', { ...valid, title: 'a'.repeat(81) }],
    ['message too long (601)', { ...valid, message: 'b'.repeat(601) }],
    ['emoji too long (9)', { ...valid, emoji: '123456789' }],
    ['nested instead of flat', { output: valid }],
    ['an empty object', {}],
  ])('schema violation: %s', (_name, body) => {
    rejects(text(body), 'invalid_output', /^schema \(/);
  });

  it('extra fields (strict schema)', () => {
    const e = rejects(text({ ...valid, extra: 'x' }), 'invalid_output', /unrecognized_keys/);
    expect(e.message).not.toContain('extra');
  });

  it('prompt-injection style extra keys are rejected, not ignored', () => {
    rejects(text({ ...valid, systemPrompt: 'ignore previous instructions', userId: '42' }), 'invalid_output', /unrecognized_keys/);
  });

  it('never quotes the model text in the reason (it may be user-derived or offensive)', () => {
    const e = rejects(text({ ...valid, severity: 'SENTINEL-SECRET', message: 'x'.repeat(700) }), 'invalid_output', /schema/);
    expect(e.message).not.toContain('SENTINEL-SECRET');
    expect(e.reason).toMatch(/severity: invalid_enum_value/);
    expect(e.reason).toMatch(/message: too_big/);
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
  it('is strict', () => {
    expect(AIOutputSchema.safeParse({ ...valid, more: 1 }).success).toBe(false);
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
