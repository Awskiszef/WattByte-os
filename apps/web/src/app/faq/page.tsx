import type { Metadata } from 'next';
import { CTA } from '@/components/sections/cta';
import { FAQ } from '@/components/sections/faq';
import { JsonLd } from '@/components/ui/json-ld';
import { PageHeader } from '@/components/ui/page-header';
import { faq } from '@/config/faq';
import { faqJsonLd, pageMetadata } from '@/lib/seo';

export const metadata: Metadata = pageMetadata({
  title: 'FAQ',
  description: 'How WattByte measures energy, whether the cost is exact, what it does with your data, and how the AI works.',
  path: '/faq',
});

export default function FaqPage() {
  return (
    <>
      <PageHeader title="Frequently asked questions." copy="Short, honest answers. If yours is missing, support will answer it." />
      <FAQ withHeading={false} />
      <CTA />
      <JsonLd data={faqJsonLd(faq)} />
    </>
  );
}
