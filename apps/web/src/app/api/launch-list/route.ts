import { NextResponse } from 'next/server';

/**
 * Launch-list sign-up. The site has no database: the entry is forwarded to
 * `LAUNCH_LIST_WEBHOOK_URL` (any HTTPS endpoint that accepts JSON). Without
 * that variable the list is closed; the route answers 200 `{ closed: true }`
 * so the form can say so without a failed request in the console.
 */
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const PLATFORMS = new Set(['ios', 'android', 'both']);

export const runtime = 'nodejs';

export async function POST(request: Request) {
  const webhook = process.env.LAUNCH_LIST_WEBHOOK_URL;
  if (!webhook) return NextResponse.json({ ok: false, closed: true });

  let body: { email?: unknown; platform?: unknown; source?: unknown };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return NextResponse.json({ error: 'Send a JSON body.' }, { status: 400 });
  }

  const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  const platform = typeof body.platform === 'string' && PLATFORMS.has(body.platform) ? body.platform : 'both';
  if (!EMAIL.test(email) || email.length > 254) {
    return NextResponse.json({ error: 'Enter a valid e-mail address.' }, { status: 400 });
  }

  const headers: Record<string, string> = { 'content-type': 'application/json' };
  const token = process.env.LAUNCH_LIST_WEBHOOK_TOKEN;
  if (token) headers.authorization = `Bearer ${token}`;

  try {
    const res = await fetch(webhook, {
      method: 'POST',
      headers,
      body: JSON.stringify({ email, platform, source: 'website', at: new Date().toISOString() }),
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) return NextResponse.json({ error: 'Could not add you right now. Try again later.' }, { status: 502 });
  } catch {
    return NextResponse.json({ error: 'Could not add you right now. Try again later.' }, { status: 502 });
  }
  return NextResponse.json({ ok: true }, { status: 201 });
}
