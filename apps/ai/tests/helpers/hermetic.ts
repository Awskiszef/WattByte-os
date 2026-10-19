/**
 * Test hermeticity. The developer's shell may carry variables meant for other
 * tools (ANTHROPIC_BASE_URL, OPENAI_API_KEY, HTTPS_PROXY, ...). None of them may
 * influence these tests, and no test may reach a real provider.
 */

export const AMBIENT_ENV_PATTERNS: readonly RegExp[] = [
  /^(OPENAI|ANTHROPIC|GOOGLE|GEMINI|XAI|GROK|AZURE_OPENAI)_/i,
  /(^|_)(API_KEY|BASE_URL|API_BASE|ENDPOINT|PROXY)$/i,
  /^NODE_USE_ENV_PROXY$/i,
];

/** Deletes every provider/endpoint/proxy variable from `env`; returns the names removed. */
export function scrubAmbientEnv(env: Record<string, string | undefined>): string[] {
  const removed: string[] = [];
  for (const name of Object.keys(env)) {
    if (AMBIENT_ENV_PATTERNS.some((p) => p.test(name))) {
      delete env[name];
      removed.push(name);
    }
  }
  return removed;
}

const LOOPBACK_HOSTS = new Set(['127.0.0.1', 'localhost', '[::1]', '::1']);
const GUARDED = Symbol.for('wattbyte.test.fetchGuard');

/** Makes `target.fetch` reject for every host except loopback (local HTTP doubles). Idempotent. */
export function blockExternalFetch(target: { fetch: typeof fetch } = globalThis): void {
  const current = target.fetch as typeof fetch & { [GUARDED]?: true };
  if (current[GUARDED]) return;
  const real = current;
  const guarded = ((input: Parameters<typeof fetch>[0], init?: Parameters<typeof fetch>[1]) => {
    const raw = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    const host = new URL(raw).hostname;
    if (!LOOPBACK_HOSTS.has(host)) return Promise.reject(new Error(`hermetic test: outbound request to ${host} blocked`));
    return real(input, init);
  }) as typeof fetch & { [GUARDED]?: true };
  guarded[GUARDED] = true;
  target.fetch = guarded;
}
