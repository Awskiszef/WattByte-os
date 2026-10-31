// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

export type NavLink = { label: string; href: string; comingSoon?: false } | { label: string; comingSoon: true };

export const mainNav = [
  { label: 'Product', href: '/#product' },
  { label: 'Features', href: '/features' },
  { label: 'Insights', href: '/#insights' },
  { label: 'AI', href: '/ai' },
  { label: 'Privacy', href: '/privacy' },
  { label: 'Pricing', href: '/pricing' },
  { label: 'FAQ', href: '/faq' },
] as const satisfies readonly NavLink[];

export const navActions = {
  signIn: { label: 'Sign in', href: '/sign-in' },
  download: { label: 'Download', href: '/download' },
} as const;

export const footerColumns: ReadonlyArray<{ title: string; links: readonly NavLink[] }> = [
  {
    title: 'Product',
    links: [
      { label: 'Features', href: '/features' },
      { label: 'AI', href: '/ai' },
      { label: 'Reports', href: '/features#reports' },
      { label: 'Pricing', href: '/pricing' },
    ],
  },
  {
    title: 'Resources',
    links: [
      { label: 'FAQ', href: '/faq' },
      { label: 'Support', href: '/support' },
      { label: 'Status', comingSoon: true },
    ],
  },
  {
    title: 'Company',
    links: [
      { label: 'About', href: '/about' },
      { label: 'Contact', href: '/contact' },
    ],
  },
  {
    title: 'Legal',
    links: [
      { label: 'Privacy', href: '/privacy' },
      { label: 'Terms', href: '/terms' },
      { label: 'Cookies', href: '/cookies' },
    ],
  },
  {
    title: 'Developers',
    links: [
      { label: 'API', comingSoon: true },
      { label: 'Documentation', comingSoon: true },
    ],
  },
];

/** Every public route, used by the sitemap and by the tests that check links. */
export const routes = [
  '/',
  '/features',
  '/about',
  '/ai',
  '/pricing',
  '/privacy',
  '/terms',
  '/cookies',
  '/faq',
  '/support',
  '/contact',
  '/download',
  '/technology',
  '/sign-in',
] as const;

export type Route = (typeof routes)[number];
