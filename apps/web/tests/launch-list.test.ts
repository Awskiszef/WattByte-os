import { afterEach, describe, expect, it, vi } from 'vitest';
import { POST } from '@/app/api/launch-list/route';

const req = (body: unknown) =>
  new Request('http://localhost/api/launch-list', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe('POST /api/launch-list', () => {
  it('reports a closed list when no webhook is configured', async () => {
    vi.stubEnv('LAUNCH_LIST_WEBHOOK_URL', '');
    const res = await POST(req({ email: 'a@b.co' }));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: false, closed: true });
  });

  it('rejects an invalid address', async () => {
    vi.stubEnv('LAUNCH_LIST_WEBHOOK_URL', 'https://example.test/hook');
    const res = await POST(req({ email: 'nope' }));
    expect(res.status).toBe(400);
  });

  it('forwards a valid entry and answers 201', async () => {
    vi.stubEnv('LAUNCH_LIST_WEBHOOK_URL', 'https://example.test/hook');
    vi.stubEnv('LAUNCH_LIST_WEBHOOK_TOKEN', 'secret');
    const fetchMock = vi.fn(async () => new Response('{}', { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);
    const res = await POST(req({ email: ' You@Example.com ', platform: 'ios' }));
    expect(res.status).toBe(201);
    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe('https://example.test/hook');
    expect((init.headers as Record<string, string>).authorization).toBe('Bearer secret');
    expect(JSON.parse(String(init.body))).toMatchObject({ email: 'you@example.com', platform: 'ios', source: 'website' });
  });

  describe('campaign tags', () => {
    const forwarded = async (body: Record<string, unknown>) => {
      vi.stubEnv('LAUNCH_LIST_WEBHOOK_URL', 'https://example.test/hook');
      const fetchMock = vi.fn(async () => new Response('{}', { status: 200 }));
      vi.stubGlobal('fetch', fetchMock);
      const res = await POST(req({ email: 'a@b.co', platform: 'android', ...body }));
      expect(res.status).toBe(201);
      const [, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
      return JSON.parse(String(init.body)) as Record<string, unknown>;
    };

    it('forwards valid utm fields with the entry', async () => {
      const payload = await forwarded({
        utm_source: 'tiktok',
        utm_medium: 'paid_social',
        utm_campaign: ' launch-test.2026 ',
        utm_content: 'Hook A świeży',
      });
      expect(payload).toMatchObject({
        email: 'a@b.co',
        platform: 'android',
        source: 'website',
        utm_source: 'tiktok',
        utm_medium: 'paid_social',
        utm_campaign: 'launch-test.2026',
        utm_content: 'Hook A świeży',
      });
    });

    it('drops invalid utm fields and keeps the sign-up and the valid ones', async () => {
      const payload = await forwarded({
        utm_source: 'meta',
        utm_medium: '<script>alert(1)</script>',
        utm_campaign: 'x'.repeat(101),
        utm_content: 42,
        utm_term: 'not-forwarded',
        source: 'evil',
      });
      expect(payload).toMatchObject({ email: 'a@b.co', source: 'website', utm_source: 'meta' });
      expect(payload).not.toHaveProperty('utm_medium');
      expect(payload).not.toHaveProperty('utm_campaign');
      expect(payload).not.toHaveProperty('utm_content');
      expect(payload).not.toHaveProperty('utm_term');
    });

    it.each(['', '   ', '=HYPERLINK("x")', '-ads', 'a/b', 'a&b=c', 'line\nbreak'])('drops the value %j', async (value) => {
      const payload = await forwarded({ utm_source: value });
      expect(payload).not.toHaveProperty('utm_source');
    });

    it('accepts a value of exactly 100 characters', async () => {
      const payload = await forwarded({ utm_campaign: 'c'.repeat(100) });
      expect(payload.utm_campaign).toBe('c'.repeat(100));
    });

    it('still works without any utm fields', async () => {
      const payload = await forwarded({});
      expect(Object.keys(payload).sort()).toEqual(['at', 'email', 'platform', 'source']);
    });
  });
});
