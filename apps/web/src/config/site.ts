/**
 * Site-wide facts. Everything that names the product, its URL or its public
 * contact points lives here so no component repeats it.
 */
export const site = {
  name: 'WattByte',
  legalName: 'WattByte',
  /** The business that operates WattByte. Shown on the legal and contact pages and in the footer. */
  company: {
    name: 'Example Operator',
    owner: 'Example Owner',
    legalForm: 'Sole proprietorship (jednoosobowa działalność gospodarcza)',
    nip: '0000000000',
    vatId: 'PL0000000000',
    regon: '000000000',
    address: {
      street: 'Example Street 1',
      postalCode: '00-000',
      city: 'Example City',
      region: 'Example Region',
      country: 'Poland',
      countryCode: 'PL',
    },
  },
  url: (process.env.NEXT_PUBLIC_SITE_URL ?? 'https://wattbyte.app').replace(/\/$/, ''),
  tagline: 'Understand what your device consumes.',
  homeTitle: "WattByte — Understand Your Device's Energy & Data Usage",
  description:
    'WattByte helps you understand battery, network and estimated energy usage with clear analytics, reports and AI-powered insights.',
  locale: 'en',
  /** Public mailbox. Confirm it exists before the site goes live. */
  supportEmail: 'support@wattbyte.app',
  /** Store listings are not live yet: both badges render as "Coming soon" until a URL is set. */
  stores: {
    appStore: null as string | null,
    googlePlay: null as string | null,
  },
  platforms: [
    { id: 'ios', name: 'iOS', requirement: 'iPhone with iOS 15 or later' },
    { id: 'android', name: 'Android', requirement: 'Android 10 or later' },
  ],
  languages: ['English', 'Polish'],
  /** Dates shown on the legal pages. */
  legal: {
    privacyUpdated: '2026-10-20',
    termsUpdated: '2026-10-20',
    cookiesUpdated: '2026-10-20',
  },
} as const;

export const demoDisclaimer = 'Example data. Not a real user.';
