/**
 * Copy for /about. Every claim about the product is backed by the app, the
 * API or docs/ in this repository; every claim about the organisation comes
 * from `site.company`. Nothing here states team size, offices, customers or
 * dates that are not on record.
 */
import { operator } from './operator';
import { site } from './site';

export const aboutHero = {
  eyebrow: 'About WattByte',
  headline: 'Technology should make consumption understandable.',
  subheadline: 'WattByte is building a clearer way to understand how devices consume energy, battery power and network data.',
  primary: { label: 'Explore WattByte', href: '/features' },
  secondary: { label: 'Our mission', href: '#mission' },
} as const;

export const aboutStory = {
  headline: 'It started with a simple question.',
  pull: 'We know how much battery we have left. But how much energy have we actually consumed?',
  paragraphs: [
    'Every day, billions of devices draw energy and move data. The people using them mostly see the basics: a battery percentage, a count of gigabytes used this month.',
    'What that activity costs, how much energy it really represents and how it changes over time is harder to see. The figures exist, but they are scattered across system settings, expressed in units nobody uses, or not shown at all.',
    'WattByte exists to change that relationship with the data. It brings the measurements the operating system already provides, energy estimates based on the device itself, regional electricity prices and readable analysis into one place.',
  ],
} as const;

export const aboutMission = {
  headline: 'Make every watt understandable.',
  copy: 'Our mission is to turn complex device consumption data into clear, accessible and actionable information.',
  pillars: [
    { id: 'clarity', title: 'Clarity', copy: 'Complex measurements should be easy to understand.' },
    { id: 'awareness', title: 'Awareness', copy: 'Better information helps people make more informed decisions about technology.' },
    { id: 'control', title: 'Control', copy: 'Users should understand their own data and decide how to use it.' },
  ],
} as const;

export const aboutValues = {
  headline: 'Built around principles, not buzzwords.',
  values: [
    {
      number: '01',
      title: 'Transparency',
      copy: 'Users deserve clear information about how their devices behave and how measurements are calculated.',
    },
    {
      number: '02',
      title: 'Privacy',
      copy: 'Personal usage data deserves careful handling, clear permissions and meaningful user control.',
    },
    {
      number: '03',
      title: 'Accuracy',
      copy: 'Estimates should be identified as estimates. Measurements should be presented with appropriate context and limitations.',
    },
    {
      number: '04',
      title: 'Simplicity',
      copy: 'Powerful technology should not require users to understand complex technical terminology.',
    },
  ],
} as const;

export type BuildingArea = {
  id: string;
  title: string;
  copy: string;
  /** What is true today, per platform, so the page never implies parity that does not exist. */
  status: string;
  comingSoon?: string;
};

export const aboutBuilding = {
  headline: 'A better understanding of everyday technology.',
  copy: 'Six areas, one app. Each one is built on what the operating system actually exposes, which differs between Android and iPhone.',
  areas: [
    {
      id: 'battery',
      title: 'Battery intelligence',
      copy: 'Understanding battery consumption and usage patterns.',
      status: 'Charging sessions on both platforms. Charge and energy counters where Android reports them; estimates from the battery level on iPhone.',
    },
    {
      id: 'energy',
      title: 'Energy analytics',
      copy: 'Estimating energy consumption in Wh and kWh.',
      status: 'Battery energy, wall energy at an adjustable efficiency and kWh, each marked when it is an estimate.',
    },
    {
      id: 'network',
      title: 'Network insights',
      copy: 'Understanding mobile data and Wi-Fi usage.',
      status: 'Daily, weekly and monthly totals on both platforms. Data by app on Android only; iOS gives apps no per-app figures.',
    },
    {
      id: 'cost',
      title: 'Cost awareness',
      copy: 'Connecting estimated energy consumption with regional electricity prices.',
      status: 'A public household price from Eurostat for supported countries, or a tariff you enter yourself.',
    },
    {
      id: 'ai',
      title: 'AI insights',
      copy: 'Making technical usage information easier to interpret.',
      status: 'Insight, weekly summary, monthly summary and a playful roast, written from period totals only.',
      comingSoon: 'Free-form questions',
    },
    {
      id: 'reports',
      title: 'Reports and history',
      copy: 'Identifying trends and comparing consumption over time.',
      status: 'Today, yesterday, 7 and 30 days, this month and the previous month; weekly and monthly summaries.',
      comingSoon: 'Custom date ranges',
    },
  ] satisfies readonly BuildingArea[],
} as const;

export const aboutVision = {
  headline: 'Beyond percentages and gigabytes.',
  copy: 'We believe the next generation of device analytics should go beyond showing raw numbers. It should help people understand what those numbers mean.',
  directions: [
    'Energy analysis that reads like an explanation, not a spreadsheet',
    'More accurate estimates wherever the system data allows it',
    'Reports that point at what changed and why it matters',
    'Regional setup that keeps working without being configured',
    'Analytical tools that improve with every release',
  ],
  note: 'No release dates here on purpose. Each of these ships when it is real.',
} as const;

export const aboutOrganization = {
  eyebrow: 'The organization behind WattByte',
  headline: 'Built by ATLASHC.',
  copy: 'WattByte is a product developed within the ATLASHC technology ecosystem, focused on creating useful, modern digital experiences.',
  facts: [
    { label: 'Business', value: site.company.name },
    { label: 'Legal form', value: 'Sole proprietorship, registered in Poland' },
    { label: 'Based in', value: `${site.company.address.city}, ${site.company.address.region}` },
    { label: 'Owner', value: site.company.owner },
  ],
  cta: { label: 'Explore ATLASHC', href: 'https://atlashc.pl' },
} as const;

export const aboutPeople = {
  headline: 'The people building WattByte.',
  copy: 'WattByte is developed independently, by a small team that also owns the decisions: what gets measured, what gets stored and what the app says about it.',
  founder: operator.founder,
  philosophy: [
    'Decisions are made close to the code, so a rule like "an estimate is always labelled" is a line in the source, not a slide.',
    'There is no growth team and no advertising SDK to feed. The product is the whole business.',
    'Releases follow the platforms’ real limits: when iOS does not expose a number, the app says so instead of inventing one.',
  ],
} as const;

export const aboutApproach = {
  headline: 'Thoughtfully engineered. Continuously improved.',
  items: [
    {
      title: 'Native integration',
      copy: 'A Flutter app with native Swift and Kotlin integrations reads the counters each platform exposes and keeps every measurement on the phone.',
    },
    {
      title: 'Reliable foundations',
      copy: 'A backend in TypeScript on Fastify and PostgreSQL, with every route described by an OpenAPI schema and a generated mobile client.',
    },
    {
      title: 'Intelligent analysis',
      copy: 'A modular AI gateway that can route to several providers, keeps the keys on the server and sends period totals only.',
    },
    {
      title: 'Continuous improvement',
      copy: 'Unit, integration and widget tests, a device test plan, and development driven by the documented limits of Android and iOS.',
    },
  ],
} as const;

export const aboutPrivacy = {
  headline: 'Your data should remain yours.',
  copy: 'Privacy is a design input, not a page added at the end. These are the rules the implementation follows.',
  points: [
    { title: 'Transparent processing', copy: 'The privacy policy lists every value the app stores and every value that can leave the phone, and when.' },
    { title: 'Permissions explained', copy: 'Each system permission is explained on screen before the system prompt, and the optional ones can be declined.' },
    { title: 'Control over the account', copy: 'Cloud sync is off by default. The account, with everything attached to it, can be deleted from inside the app.' },
    { title: 'Measurements kept apart from estimates', copy: 'A value calculated from the battery level or a design capacity is marked as an estimate, in the app and in exports.' },
    { title: 'Data minimisation', copy: 'Raw samples and per-app usage never leave the phone. Sync uploads one row of totals per day, nothing more.' },
  ],
  cta: { label: 'Read our Privacy Policy', href: '/privacy' },
} as const;

export const aboutJoin = {
  eyebrow: 'The future of WattByte',
  headline: 'We’re just getting started.',
  copy: 'We’re building WattByte to make device energy and data consumption easier to understand. Follow our progress and be part of what’s next.',
  primary: { label: 'Explore WattByte', href: '/features' },
  secondary: { label: 'Get the app', href: '/download' },
  note: 'WattByte is not in the stores yet. The download page has the launch list.',
} as const;

export const aboutSeo = {
  title: 'About WattByte — Our Mission, Story & Vision',
  description:
    'Learn about WattByte, our mission to make device energy and data consumption understandable, and the technology and principles behind our product.',
} as const;
