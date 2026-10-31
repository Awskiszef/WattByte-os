// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { describe, expect, it } from 'vitest';
import robots from '@/app/robots';
import sitemap from '@/app/sitemap';
import { routes } from '@/config/navigation';
import { site } from '@/config/site';
import { absoluteUrl, pageMetadata } from '@/lib/seo';

describe('sitemap and robots', () => {
  it('lists every public route once, with absolute URLs', () => {
    const entries = sitemap();
    expect(entries).toHaveLength(routes.length);
    const urls = entries.map((e) => e.url);
    expect(new Set(urls).size).toBe(urls.length);
    for (const url of urls) expect(url.startsWith(site.url)).toBe(true);
    expect(urls).toContain(site.url);
    expect(urls).toContain(`${site.url}/privacy`);
  });

  it('robots allows the site and points at the sitemap', () => {
    const r = robots();
    expect(r.sitemap).toBe(`${site.url}/sitemap.xml`);
    expect(JSON.stringify(r.rules)).toContain('"allow":"/"');
  });
});

describe('page metadata', () => {
  it('sets canonical, Open Graph and Twitter for a page', () => {
    const m = pageMetadata({ title: 'Features', description: 'x', path: '/features' });
    expect(m.alternates?.canonical).toBe(`${site.url}/features`);
    expect(m.openGraph?.url).toBe(`${site.url}/features`);
    expect(m.openGraph?.title).toBe('Features — WattByte');
    expect((m.twitter as { card?: string } | undefined)?.card).toBe('summary_large_image');
  });

  it('uses the exact homepage title', () => {
    const m = pageMetadata({ title: site.homeTitle, description: site.description, path: '/', absoluteTitle: true });
    expect(m.title).toEqual({ absolute: site.homeTitle });
    expect(absoluteUrl('/')).toBe(site.url);
  });
});
