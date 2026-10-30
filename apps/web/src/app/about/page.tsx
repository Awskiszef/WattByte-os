// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import type { Metadata } from 'next';
import { AboutHero } from '@/components/about/about-hero';
import { Approach } from '@/components/about/approach';
import { Building } from '@/components/about/building';
import { Join } from '@/components/about/join';
import { Mission } from '@/components/about/mission';
import { Organization } from '@/components/about/organization';
import { People } from '@/components/about/people';
import { PrivacyByDesign } from '@/components/about/privacy-by-design';
import { Story } from '@/components/about/story';
import { Values } from '@/components/about/values';
import { Vision } from '@/components/about/vision';
import { Breadcrumb } from '@/components/ui/breadcrumb';
import { JsonLd } from '@/components/ui/json-ld';
import { aboutSeo } from '@/config/about';
import { site } from '@/config/site';
import { absoluteUrl, organizationJsonLd, pageMetadata } from '@/lib/seo';

export const metadata: Metadata = pageMetadata({
  title: aboutSeo.title,
  description: aboutSeo.description,
  path: '/about',
  absoluteTitle: true,
});

export default function AboutPage() {
  return (
    <>
      <Breadcrumb items={[{ label: 'Home', href: '/' }, { label: 'About', href: '/about' }]} />
      <AboutHero />
      <Story />
      <Mission />
      <Values />
      <Building />
      <Vision />
      <Organization />
      <People />
      <Approach />
      <PrivacyByDesign />
      <Join />
      <JsonLd
        data={{
          '@context': 'https://schema.org',
          '@type': 'AboutPage',
          name: aboutSeo.title,
          description: aboutSeo.description,
          url: absoluteUrl('/about'),
          about: { '@type': 'SoftwareApplication', name: site.name, url: site.url },
          publisher: organizationJsonLd(),
        }}
      />
    </>
  );
}
