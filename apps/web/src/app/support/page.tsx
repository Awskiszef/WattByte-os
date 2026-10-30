// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import type { Metadata } from 'next';
import Link from 'next/link';
import { PageHeader } from '@/components/ui/page-header';
import { Prose } from '@/components/ui/prose';
import { Section } from '@/components/ui/section';
import { site } from '@/config/site';
import { pageMetadata } from '@/lib/seo';

export const metadata: Metadata = pageMetadata({
  title: 'Support',
  description: 'Help with WattByte: permissions, estimates, accounts, exports and how to reach us.',
  path: '/support',
});

const topics = [
  {
    title: 'Data totals are empty on Android',
    copy: 'WattByte needs "Usage access" to read mobile and Wi-Fi totals. Open the Permissions screen in the app or the system setting Apps with usage access, and switch WattByte on. Per-app data needs the same permission.',
  },
  {
    title: 'Numbers are marked with a tilde (~)',
    copy: 'The tilde marks an estimate: the phone did not report a charge or energy counter, so the value was calculated from the battery level and the design capacity of your model. On iPhone every energy figure is an estimate.',
  },
  {
    title: 'Battery capacity unavailable',
    copy: 'Your phone model is not in the device catalog yet. Enter the design capacity by hand in Settings, Battery Capacity; the energy figures will use it from then on.',
  },
  {
    title: 'The electricity price is wrong for me',
    copy: 'The automatic price is a national household average. Switch to a custom price in Settings, Electricity Price, and enter the tariff from your bill.',
  },
  {
    title: 'Export or delete my data',
    copy: 'Settings has Export CSV, Export JSON and Reset Statistics. Deleting the account from the Account screen removes the cloud copy as well.',
  },
];

export default function SupportPage() {
  return (
    <>
      <PageHeader title="Support." copy="Most questions are answered below or in the FAQ. For anything else, write to us and include your phone model and operating system version." />
      <Section tight>
        <div className="container-x grid gap-12 lg:grid-cols-[1.2fr_0.8fr]">
          <dl className="divide-y divide-border border-y border-border">
            {topics.map((t) => (
              <div key={t.title} className="py-5">
                <dt className="text-base font-semibold">{t.title}</dt>
                <dd className="mt-2 text-pretty text-sm leading-relaxed text-fg-muted">{t.copy}</dd>
              </div>
            ))}
          </dl>
          <Prose>
            <h2 className="!mt-0">Write to us</h2>
            <p>
              <a href={`mailto:${site.supportEmail}`}>{site.supportEmail}</a>
            </p>
            <p>We answer in English and Polish. Do not send passwords, exports or screenshots with personal data unless we ask for them.</p>
            <h2>Before you write</h2>
            <ul>
              <li>
                Read the <Link href="/faq">FAQ</Link>.
              </li>
              <li>Note your phone model, the operating system version and the WattByte version from Settings.</li>
              <li>If a number looks wrong, say which screen and which period.</li>
            </ul>
          </Prose>
        </div>
      </Section>
    </>
  );
}
