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
});
