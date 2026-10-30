// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

/**
 * Product facts shown on the site. Every entry is backed by the mobile app,
 * the API or the docs in this repository; anything not yet built is marked
 * `comingSoon` and rendered that way.
 */
export type Capability = { label: string; comingSoon?: boolean };

export type ConsumptionBlock = {
  id: 'battery' | 'energy' | 'mobile' | 'wifi' | 'history';
  title: string;
  copy: string;
  capabilities: readonly Capability[];
};

export const consumptionBlocks: readonly ConsumptionBlock[] = [
  {
    id: 'battery',
    title: 'Battery',
    copy: 'Understand where your battery goes instead of staring at another percentage.',
    capabilities: [
      { label: 'Battery used today in mAh' },
      { label: 'Estimated energy in Wh' },
      { label: 'Charging sessions: start, end, levels and charge added' },
      { label: 'Average session length and longest session' },
      { label: 'Historical usage by day, week and month' },
    ],
  },
  {
    id: 'energy',
    title: 'Energy',
    copy: 'Turn battery usage into actual energy and estimated electricity cost.',
    capabilities: [
      { label: 'Wh and kWh, not just percent' },
      { label: 'Estimated electricity cost per day and per month' },
      { label: 'Wall energy with a charging efficiency you can adjust' },
      { label: 'Electricity price matched to your region' },
    ],
  },
  {
    id: 'mobile',
    title: 'Mobile data',
    copy: 'See what the cellular connection actually moves, day by day.',
    capabilities: [
      { label: 'Daily usage' },
      { label: 'Weekly and monthly totals' },
      { label: 'Comparison with the previous week' },
      { label: 'Data by app on Android' },
    ],
  },
  {
    id: 'wifi',
    title: 'Wi-Fi',
    copy: 'Wi-Fi is counted on its own, so you can see how much of your traffic never touches the mobile plan.',
    capabilities: [
      { label: 'Daily, weekly and monthly Wi-Fi totals' },
      { label: 'Wi-Fi share of all traffic' },
      { label: 'Download and upload counted separately' },
    ],
  },
  {
    id: 'history',
    title: 'History',
    copy: 'Every day is kept on your phone, so a spike can be traced back instead of guessed.',
    capabilities: [
      { label: 'Today' },
      { label: 'Yesterday' },
      { label: '7 days' },
      { label: '30 days' },
      { label: 'This month and the previous month' },
      { label: 'Custom range', comingSoon: true },
    ],
  },
];

export const regionalSetup = {
  headline: 'Ready before you configure anything.',
  copy: 'WattByte automatically adapts currency, regional settings and energy pricing to your location.',
  detects: [
    { label: 'Region', detail: 'From the device region setting or the system locale, or chosen by you.' },
    { label: 'Currency', detail: 'Follows the region through a fixed country-to-currency table.' },
    { label: 'Electricity price', detail: 'A public household average for your country, or a tariff you type in.' },
    { label: 'Battery capacity', detail: 'Looked up for your phone model in a device catalog, or entered by hand.' },
  ],
  sources: ['Device region', 'System locale', 'Country detection on the server', 'Your own choice'],
  note: 'No location permission is requested and no location is stored.',
} as const;

export const electricityPriceSection = {
  headline: 'A real price, not a guess.',
  copy: 'For supported countries WattByte uses the household electricity price published by Eurostat, taxes included. Elsewhere you enter your own tariff.',
  source: {
    name: 'Eurostat nrg_pc_204',
    detail: 'Household consumers, consumption band DC, all taxes and levies included, national currency.',
  },
} as const;

export const aiSection = {
  headline: 'Ask WattByte.',
  copy: 'WattByte AI reads the totals your phone already computed and explains them in plain language.',
  actions: ['Generate insight', 'Weekly summary', 'Monthly summary', 'Roast me'],
  limits: [
    'Only period totals are sent: data in GB, charging sessions, energy in kWh, estimated cost and the change against the previous period.',
    'The AI never calculates, converts or invents a number. It explains numbers the app measured.',
    'It cannot name the app that used the energy: iOS exposes no per-app data, and Android exposes data by app, not energy.',
  ],
  freeFormQuestions: { comingSoon: true, label: 'Free-form questions' },
} as const;

export const aiProviders = {
  headline: 'Built to stay flexible.',
  copy: 'The AI layer is a gateway, not a single model. Each request is routed to one configured provider; after an outage or a rate limit, at most one other provider is tried. Your totals are never sent to every provider at once.',
  providers: ['OpenAI', 'Anthropic', 'Google', 'xAI'],
  guarantees: [
    'Provider keys live on the server, never in the app',
    'Requests carry period totals only; an e-mail, user id or token is rejected before a prompt exists',
    'Prompts and answers are not stored by WattByte',
    'Daily and monthly spend limits per provider',
  ],
} as const;

export const reportsSection = {
  headline: 'From raw measurements to useful reports.',
  copy: 'Daily and weekly totals are built on the phone. Weekly and monthly AI summaries turn them into a few sentences you can act on.',
  periods: [
    { label: 'Daily' },
    { label: 'Weekly' },
    { label: 'Monthly' },
    { label: 'Custom range', comingSoon: true },
  ],
} as const;

export const exportSection = {
  headline: 'Your data shouldn’t be trapped in an app.',
  copy: 'Export everything WattByte stores on your phone from Settings, in formats a spreadsheet or a script can read.',
  formats: [
    { label: 'CSV', detail: 'Daily data and charging sessions, one row per day or session.' },
    { label: 'JSON', detail: 'Days, sessions, settings and battery capacity in one document.' },
  ],
  cloud: 'If you use cloud sync, the server keeps a JSON and CSV export of your account too.',
} as const;

export const privacySection = {
  headline: 'Your usage data is personal. We treat it that way.',
  points: [
    {
      title: 'Only what the features need',
      copy: 'Daily totals, battery samples and charging sessions are stored in the app’s private storage. Per-app usage is read when you open the screen and never saved.',
    },
    {
      title: 'Nothing leaves the phone unless you choose',
      copy: 'Cloud sync is off by default and has its own switch. When it is on, one row per day is uploaded: bytes, Wh, sessions and estimated cost. Never raw samples.',
    },
    {
      title: 'You control the account',
      copy: 'Delete the account from inside the app. It removes the account and every synced row, in one step.',
    },
    {
      title: 'No ads, no trackers',
      copy: 'No analytics SDK, no advertising SDK, no crash-reporting service. Your data is not sold to advertisers.',
    },
    {
      title: 'A secure connection',
      copy: 'The app talks to the WattByte backend over HTTPS only, and keeps its sign-in tokens in the system keychain.',
    },
    {
      title: 'Permissions explained first',
      copy: 'Each system permission is explained on screen before the system prompt appears, and each one can be declined.',
    },
  ],
} as const;

export const architecture = {
  headline: 'Built like infrastructure, not a weekend prototype.',
  copy: 'Measurement happens on the phone. The backend only holds accounts, optional daily totals and the AI gateway.',
  layers: [
    {
      name: 'Mobile',
      items: ['Flutter', 'Native Kotlin integration', 'Native Swift integration'],
      detail: 'Reads system counters, builds charging sessions and keeps everything in local SQLite. Home-screen widgets on both platforms.',
    },
    {
      name: 'Backend',
      items: ['Fastify', 'TypeScript', 'PostgreSQL', 'OpenAPI'],
      detail: 'Accounts, optional cloud sync of per-day totals, device catalog and the electricity price cache. Every route is described by an OpenAPI schema.',
    },
    {
      name: 'AI gateway',
      items: ['OpenAI', 'Anthropic', 'Google', 'xAI'],
      detail: 'One interface over four providers with routing, retry, a single fallback and spend limits.',
    },
  ],
} as const;

export const platformsSection = {
  headline: 'One WattByte. Across your devices.',
  copy: 'The same app, the same numbers, on iPhone and Android. Your data stays on each phone unless you sync it.',
} as const;

export const finalCta = {
  headline: 'Your device already generates the data. WattByte makes it useful.',
  subcopy: 'Understand your battery, data and energy usage in one place.',
  primary: { label: 'Get WattByte', href: '/download' },
  secondary: { label: 'Explore the product', href: '/features' },
} as const;

export const hero = {
  eyebrow: 'Energy & data intelligence for your devices',
  headline: 'Know what your device consumes.',
  subheadline: 'WattByte turns battery, network and energy usage into clear insights, costs and recommendations.',
  primary: { label: 'Download WattByte', href: '/download' },
  secondary: { label: 'Explore features', href: '/features' },
} as const;
