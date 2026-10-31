// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const url = (search: string) => `https://wattbyte.app/download${search}`;

describe('campaignFromSearch', () => {
  it('reads the four utm tags and ignores other parameters', async () => {
    const { campaignFromSearch } = await import('@/lib/campaign');
    const search = new URL(url('?utm_source=tiktok&utm_medium=paid&utm_campaign=launch+test&utm_content=hook-a&utm_term=x&ref=y')).search;
    expect(campaignFromSearch(search)).toEqual({ utm_source: 'tiktok', utm_medium: 'paid', utm_campaign: 'launch test', utm_content: 'hook-a' });
  });

  it('returns nothing for a URL without tags', async () => {
    const { campaignFromSearch } = await import('@/lib/campaign');
    expect(campaignFromSearch('')).toEqual({});
    expect(campaignFromSearch('?utm_source=%3Cscript%3E')).toEqual({});
  });
});

describe('rememberCampaign / readCampaign', () => {
  let store: Map<string, string>;

  beforeEach(() => {
    vi.resetModules();
    store = new Map();
    vi.stubGlobal('window', {
      sessionStorage: {
        getItem: (k: string) => store.get(k) ?? null,
        setItem: (k: string, v: string) => void store.set(k, v),
      },
    });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('keeps the landing tags for the visit, in session storage only', async () => {
    const { rememberCampaign, readCampaign } = await import('@/lib/campaign');
    rememberCampaign('?utm_source=meta&utm_content=hook-b');
    rememberCampaign('');
    expect(readCampaign()).toEqual({ utm_source: 'meta', utm_content: 'hook-b' });
    expect(JSON.parse(store.get('wattbyte.campaign') ?? '{}')).toEqual({ utm_source: 'meta', utm_content: 'hook-b' });
  });

  it('replaces the tags when the visitor lands again through another tagged link', async () => {
    const { rememberCampaign, readCampaign } = await import('@/lib/campaign');
    rememberCampaign('?utm_source=meta&utm_content=hook-b');
    rememberCampaign('?utm_source=tiktok');
    expect(readCampaign()).toEqual({ utm_source: 'tiktok' });
  });

  it('reads tags stored earlier in the same tab after a reload', async () => {
    store.set('wattbyte.campaign', JSON.stringify({ utm_source: 'youtube', utm_medium: 'bad value!' }));
    const { readCampaign } = await import('@/lib/campaign');
    expect(readCampaign()).toEqual({ utm_source: 'youtube' });
  });

  it('falls back to memory when session storage is blocked', async () => {
    vi.stubGlobal('window', {
      get sessionStorage(): Storage {
        throw new Error('SecurityError');
      },
    });
    const { rememberCampaign, readCampaign } = await import('@/lib/campaign');
    expect(readCampaign()).toEqual({});
    rememberCampaign('?utm_source=meta');
    expect(readCampaign()).toEqual({ utm_source: 'meta' });
  });
});
