import { ArrowUpRight } from 'lucide-react';
import { LogoMark } from '@/components/layout/logo';
import { Reveal } from '@/components/ui/reveal';
import { Section } from '@/components/ui/section';
import { aboutOrganization } from '@/config/about';
import { Eyebrow } from './eyebrow';

/** WattByte × ATLASHC: the product mark next to the organisation's wordmark. */
function Lockup() {
  return (
    <div className="flex items-center gap-4 sm:gap-6" aria-label="WattByte, a product of ATLASHC">
      <span className="inline-flex items-center gap-2.5">
        <LogoMark className="h-8 w-8" />
        <span className="text-xl font-semibold tracking-[-0.02em]">WattByte</span>
      </span>
      <span className="text-2xl font-light text-fg-subtle" aria-hidden="true">
        ×
      </span>
      <span className="inline-flex h-9 items-center rounded-md border border-border-strong px-3 text-[15px] font-semibold tracking-[0.14em]">ATLASHC</span>
    </div>
  );
}

export function Organization() {
  return (
    <Section id="atlashc" className="scroll-mt-16 border-t border-border bg-bg-elevated">
      <div className="container-x grid gap-12 lg:grid-cols-2 lg:items-center">
        <div>
          <Eyebrow>{aboutOrganization.eyebrow}</Eyebrow>
          <h2 className="mt-4 text-balance text-[2rem] font-semibold leading-[1.1] tracking-[-0.02em] sm:text-[2.5rem]">{aboutOrganization.headline}</h2>
          <p className="mt-5 max-w-[34rem] text-pretty text-lg leading-relaxed text-fg-muted">{aboutOrganization.copy}</p>
          <a
            href={aboutOrganization.cta.href}
            target="_blank"
            rel="noopener noreferrer"
            className="mt-8 inline-flex h-12 items-center gap-2 rounded-md bg-fg px-6 text-base font-medium text-bg transition-opacity hover:opacity-90"
          >
            {aboutOrganization.cta.label}
            <ArrowUpRight className="h-4 w-4" aria-hidden="true" />
            <span className="sr-only">(opens atlashc.pl in a new tab)</span>
          </a>
        </div>
        <Reveal>
          <div className="rounded-xl border border-border bg-bg p-6 sm:p-8">
            <Lockup />
            <dl className="mt-8 divide-y divide-border border-t border-border">
              {aboutOrganization.facts.map((f) => (
                <div key={f.label} className="grid gap-1 py-3 sm:grid-cols-[8rem_1fr] sm:gap-4">
                  <dt className="text-sm text-fg-subtle">{f.label}</dt>
                  <dd className="text-sm text-fg">{f.value}</dd>
                </div>
              ))}
            </dl>
          </div>
        </Reveal>
      </div>
    </Section>
  );
}
