import type { Metadata } from 'next';
import { ArchitectureSection } from '@/components/sections/architecture-section';
import { CTA } from '@/components/sections/cta';
import { ProvidersSection } from '@/components/sections/providers';
import { ComingSoon } from '@/components/ui/badge';
import { PageHeader } from '@/components/ui/page-header';
import { Section } from '@/components/ui/section';
import { pageMetadata } from '@/lib/seo';

export const metadata: Metadata = pageMetadata({
  title: 'Technology',
  description: 'How WattByte is built: a Flutter app with native Kotlin and Swift integrations, a Fastify and PostgreSQL backend described by OpenAPI, and a multi-provider AI gateway.',
  path: '/technology',
});

const principles = [
  { title: 'The phone owns measurement', copy: 'System counters, charging sessions, energy maths and local storage live in the app. The backend never calculates energy.' },
  { title: 'Sync is per-day totals, opt-in', copy: 'One row per day: bytes, Wh, sessions, estimated cost. Raw samples and per-app usage never leave the phone.' },
  { title: 'Every route has a contract', copy: 'Request and response schemas are validated at the edge and exported as OpenAPI; the mobile client is generated from that document.' },
  { title: 'Fail closed', copy: 'A release build without a backend address does not compile. An unknown phone model shows "capacity unavailable" rather than a typical number.' },
  { title: 'AI reads, it does not compute', copy: 'The gateway sends period totals, forbids calculation in the prompt, validates the structured answer and keeps provider keys on the server.' },
  { title: 'Public prices, cached', copy: 'Household electricity prices come from Eurostat and are cached by the backend; a country without a public source gets a manual tariff instead of a guess.' },
];

export default function TechnologyPage() {
  return (
    <>
      <PageHeader title="How WattByte is built." copy="A high-level view of the architecture for people who want to know where their numbers come from and where they go." />
      <ArchitectureSection withLink={false} />
      <Section className="border-t border-border">
        <div className="container-x">
          <h2 className="text-2xl font-semibold tracking-[-0.02em] sm:text-3xl">Design rules the code follows</h2>
          <dl className="mt-10 grid gap-x-10 gap-y-8 sm:grid-cols-2 lg:grid-cols-3">
            {principles.map((p) => (
              <div key={p.title} className="border-t border-border pt-5">
                <dt className="text-base font-semibold">{p.title}</dt>
                <dd className="mt-2 text-sm leading-relaxed text-fg-muted">{p.copy}</dd>
              </div>
            ))}
          </dl>
          <div className="mt-12 flex flex-wrap items-center gap-3 text-sm text-fg-muted">
            <span>Public API and developer documentation</span>
            <ComingSoon />
          </div>
        </div>
      </Section>
      <ProvidersSection />
      <CTA />
    </>
  );
}
