// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { NextResponse } from 'next/server';
import { sanitizeCampaign } from '@/lib/campaign';

/**
 * Launch-list sign-up. The site has no database: the entry is forwarded to
 * `LAUNCH_LIST_WEBHOOK_URL` (any HTTPS endpoint that accepts JSON). Without
 * that variable the list is closed; the route answers 200 `{ closed: true }`
 * so the form can say so without a failed request in the console.
 *
 * Optional `utm_source`, `utm_medium`, `utm_campaign` and `utm_content` are
 * forwarded when valid (see `src/lib/campaign.ts`); an invalid tag is dropped
 * without failing the sign-up.
 */
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const PLATFORMS = new Set(['ios', 'android', 'both']);

export const runtime = 'nodejs';

export async function POST(request: Request) {
  const webhook = process.env.LAUNCH_LIST_WEBHOOK_URL;
  if (!webhook) return NextResponse.json({ ok: false, closed: true });

  let body: Record<string, unknown>;
  try {
    const parsed: unknown = await request.json();
    body = parsed && typeof parsed === 'object' ? (parsed as Record<string, unknown>) : {};
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
      body: JSON.stringify({ email, platform, source: 'website', ...sanitizeCampaign(body), at: new Date().toISOString() }),
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) return NextResponse.json({ error: 'Could not add you right now. Try again later.' }, { status: 502 });
  } catch {
    return NextResponse.json({ error: 'Could not add you right now. Try again later.' }, { status: 502 });
  }
  return NextResponse.json({ ok: true }, { status: 201 });
}
