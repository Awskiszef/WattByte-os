// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import type { Metadata } from 'next';
import { ConsumptionBlocks } from '@/components/sections/consumption-blocks';
import { CTA } from '@/components/sections/cta';
import { DashboardPreview } from '@/components/sections/dashboard-preview';
import { ExportSection } from '@/components/sections/export-section';
import { PlatformsSection } from '@/components/sections/platforms-section';
import { RegionalSetup } from '@/components/sections/regional-setup';
import { ReportPreview } from '@/components/sections/report-preview';
import { ButtonLink } from '@/components/ui/button';
import { PageHeader } from '@/components/ui/page-header';
import { pageMetadata } from '@/lib/seo';

export const metadata: Metadata = pageMetadata({
  title: 'Features',
  description:
    'Battery, energy, mobile data and Wi-Fi measured separately: charging sessions, Wh and kWh, estimated electricity cost, history, reports and CSV or JSON export.',
  path: '/features',
});

export default function FeaturesPage() {
  return (
    <>
      <PageHeader
        title="Every number your phone already knows, made readable."
        copy="WattByte reads the counters the operating system keeps anyway and turns them into battery, energy, data and cost you can act on. Nothing here needs an account."
      >
        <ButtonLink href="/download">Get WattByte</ButtonLink>
        <ButtonLink href="/ai" variant="secondary">
          See WattByte AI
        </ButtonLink>
      </PageHeader>
      <DashboardPreview />
      <ConsumptionBlocks />
      <RegionalSetup />
      <div id="reports" className="scroll-mt-16" />
      <ReportPreview />
      <ExportSection />
      <PlatformsSection />
      <CTA />
    </>
  );
}
