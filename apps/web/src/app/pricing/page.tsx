import type { Metadata } from 'next';
import { CTA } from '@/components/sections/cta';
import { FAQ } from '@/components/sections/faq';
import { Pricing } from '@/components/sections/pricing';
import { PageHeader } from '@/components/ui/page-header';
import { faq } from '@/config/faq';
import { pageMetadata } from '@/lib/seo';

export const metadata: Metadata = pageMetadata({
  title: 'Pricing',
  description: 'WattByte is free to use. WattByte Pro adds more history, reports and a larger AI allowance. Prices are announced at launch.',
  path: '/pricing',
});

export default function PricingPage() {
  const related = faq.filter((f) => ['export', 'how-ai-works', 'delete-account'].includes(f.id));
  return (
    <>
      <PageHeader title="Free to use. Pro when you want more." copy="The free plan is the whole core app, with no time limit. Pro is in preparation and its price will be announced at launch." />
      <Pricing withHeading={false} />
      <FAQ items={related} />
      <CTA />
    </>
  );
}
