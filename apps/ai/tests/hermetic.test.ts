import { describe, expect, it } from 'vitest';

import { AMBIENT_ENV_PATTERNS, blockExternalFetch, scrubAmbientEnv } from './helpers/hermetic.js';
import { startServer } from './helpers/server.js';

describe('hermetic test environment', () => {
  it('the worker environment carries no provider, endpoint or proxy variable (this shell sets ANTHROPIC_BASE_URL for another tool)', () => {
    const leaked = Object.keys(process.env).filter((k) => AMBIENT_ENV_PATTERNS.some((p) => p.test(k)));
    expect(leaked).toEqual([]);
    expect(process.env.ANTHROPIC_BASE_URL).toBeUndefined();
    expect(process.env.OPENAI_API_KEY).toBeUndefined();
  });

  it('scrubAmbientEnv removes keys, base URLs, models-of-others and proxies, and nothing else', () => {
    const env: Record<string, string | undefined> = {
      ANTHROPIC_BASE_URL: 'x', ANTHROPIC_API_KEY: 'x', OPENAI_API_KEY: 'x', OPENAI_BASE_URL: 'x', OPENAI_API_BASE: 'x',
      GEMINI_API_KEY: 'x', GOOGLE_AI_API_KEY: 'x', XAI_API_KEY: 'x', HTTPS_PROXY: 'x', http_proxy: 'x', NODE_USE_ENV_PROXY: '1',
      AZURE_OPENAI_ENDPOINT: 'x', STRIPE_API_KEY: 'x',
      PATH: '/bin', HOME: '/h', TZ: 'UTC', NODE_ENV: 'test',
    };
    const removed = scrubAmbientEnv(env);
    expect(Object.keys(env).sort()).toEqual(['HOME', 'NODE_ENV', 'PATH', 'TZ']);
    expect(removed).toHaveLength(13);
  });

  it('outbound fetch to a real provider host is blocked before it leaves the machine', async () => {
    for (const url of ['https://api.anthropic.com/v1/messages', 'https://api.openai.com/v1/chat/completions', 'http://169.254.169.254/latest/meta-data']) {
      await expect(fetch(url, { method: 'POST' })).rejects.toThrow(/outbound request to .* blocked/);
    }
  });

  it('loopback stays reachable so real-socket doubles work', async () => {
    const server = await startServer((_req, res) => void res.writeHead(200).end('ok'));
    try {
      const res = await fetch(`${server.origin}/ping`);
      expect(await res.text()).toBe('ok');
    } finally {
      await server.close();
    }
  });

  it('blockExternalFetch is idempotent and keeps working on a stub target', async () => {
    const seen: string[] = [];
    const target = { fetch: ((u: string) => (seen.push(String(u)), Promise.resolve(new Response('ok')))) as unknown as typeof fetch };
    blockExternalFetch(target);
    const once = target.fetch;
    blockExternalFetch(target);
    expect(target.fetch).toBe(once);
    await expect(target.fetch('https://example.com/')).rejects.toThrow(/blocked/);
    expect(await (await target.fetch('http://localhost:1/x')).text()).toBe('ok');
    expect(seen).toEqual(['http://localhost:1/x']);
  });
});
