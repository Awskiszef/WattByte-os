import type { Metadata } from 'next';
import { Hero } from '@/components/home/hero';
import { AIChatPreview } from '@/components/sections/ai-preview';
import { ArchitectureSection } from '@/components/sections/architecture-section';
import { ConsumptionBlocks } from '@/components/sections/consumption-blocks';
import { CTA } from '@/components/sections/cta';
import { DashboardPreview } from '@/components/sections/dashboard-preview';
import { ElectricityPrice } from '@/components/sections/electricity-price';
import { ExportSection } from '@/components/sections/export-section';
import { FAQ } from '@/components/sections/faq';
import { PlatformsSection } from '@/components/sections/platforms-section';
import { Pricing } from '@/components/sections/pricing';
import { PrivacySection } from '@/components/sections/privacy-section';
import { ProvidersSection } from '@/components/sections/providers';
import { RegionalSetup } from '@/components/sections/regional-setup';
import { ReportPreview } from '@/components/sections/report-preview';
import { JsonLd } from '@/components/ui/json-ld';
import { site } from '@/config/site';
import { pageMetadata, softwareApplicationJsonLd } from '@/lib/seo';

export const metadata: Metadata = pageMetadata({
  title: site.homeTitle,
  description: site.description,
  path: '/',
  absoluteTitle: true,
});

export default function HomePage() {
  return (
    <>
      <Hero />
      <DashboardPreview />
      <ConsumptionBlocks />
      <RegionalSetup />
      <ElectricityPrice />
      <AIChatPreview />
      <ProvidersSection />
      <ReportPreview />
      <ExportSection />
      <PrivacySection />
      <ArchitectureSection />
      <PlatformsSection />
      <Pricing />
      <FAQ limit={6} />
      <CTA />
      <JsonLd data={softwareApplicationJsonLd()} />
    </>
  );
}
