/**
 * Campaign tags (`utm_*`) for launch-list sign-ups. The tags are read from the
 * landing URL, kept in memory and in session storage for the visit (never in a
 * cookie) and sent only with the sign-up, so each entry records which ad or
 * link brought the visitor. The route validates them again before forwarding.
 */
export const CAMPAIGN_KEYS = ['utm_source', 'utm_medium', 'utm_campaign', 'utm_content'] as const;

export type CampaignKey = (typeof CAMPAIGN_KEYS)[number];
export type Campaign = Partial<Record<CampaignKey, string>>;

/** Letters, digits, space, dot, underscore and hyphen; starts with a letter or digit; at most 100 characters. */
const VALUE = /^[\p{L}\p{N}][\p{L}\p{N} ._-]{0,99}$/u;
const STORAGE_KEY = 'wattbyte.campaign';

/** Keeps the valid tags of `input` and drops everything else. */
export function sanitizeCampaign(input: unknown): Campaign {
  const out: Campaign = {};
  if (!input || typeof input !== 'object') return out;
  const record = input as Record<string, unknown>;
  for (const key of CAMPAIGN_KEYS) {
    const raw = record[key];
    const value = typeof raw === 'string' ? raw.trim() : '';
    if (VALUE.test(value)) out[key] = value;
  }
  return out;
}

/** The valid tags in a query string such as `location.search`. */
export function campaignFromSearch(search: string): Campaign {
  return sanitizeCampaign(Object.fromEntries(new URLSearchParams(search)));
}

let current: Campaign | null = null;

/**
 * Remembers the tags of the landing URL for this visit. A URL with tags
 * replaces the stored ones; a URL without tags keeps them.
 */
export function rememberCampaign(search: string): void {
  const found = campaignFromSearch(search);
  if (Object.keys(found).length === 0) return;
  current = found;
  try {
    window.sessionStorage.setItem(STORAGE_KEY, JSON.stringify(found));
  } catch {
    // Storage blocked: the in-memory copy still covers this page view.
  }
}

/** The tags remembered for this visit, or `{}`. */
export function readCampaign(): Campaign {
  if (current) return current;
  try {
    const stored = window.sessionStorage.getItem(STORAGE_KEY);
    return stored ? sanitizeCampaign(JSON.parse(stored)) : {};
  } catch {
    return {};
  }
}
