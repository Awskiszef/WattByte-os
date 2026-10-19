import { Check } from 'lucide-react';
import { DemoLabel } from '@/components/ui/demo-label';
import { Reveal } from '@/components/ui/reveal';
import { Section } from '@/components/ui/section';
import { SectionHeading } from '@/components/ui/section-heading';
import { regionalSetup } from '@/config/features';

const review = [
  { label: 'Region', value: 'Poland', source: 'device region' },
  { label: 'Currency', value: 'PLN', source: 'follows region' },
  { label: 'Electricity price', value: 'Automatic', source: 'public household average' },
  { label: 'Battery capacity', value: '4,575 mAh', source: 'device catalog, Pixel 8' },
];

export function RegionalSetup() {
  return (
    <Section id="setup" className="scroll-mt-16 border-t border-border">
      <div className="container-x grid gap-12 lg:grid-cols-2 lg:items-center">
        <div>
          <SectionHeading title={regionalSetup.headline} copy={regionalSetup.copy} />
          <dl className="mt-8 grid gap-5 sm:grid-cols-2">
            {regionalSetup.detects.map((d) => (
              <div key={d.label}>
                <dt className="text-sm font-medium">{d.label}</dt>
                <dd className="mt-1 text-sm text-fg-muted">{d.detail}</dd>
              </div>
            ))}
          </dl>
          <p className="mt-8 text-sm text-fg-muted">
            Region comes from, in order: {regionalSetup.sources.join(', ').toLowerCase()}. {regionalSetup.note}
          </p>
        </div>
        <Reveal>
          <div className="mx-auto w-full max-w-[26rem] rounded-xl border border-border bg-bg-elevated p-5 sm:p-6">
            <p className="text-sm font-medium">Your setup</p>
            <p className="mt-1 text-xs text-fg-subtle">Detected in a few seconds. Edit any value, then continue.</p>
            <ul className="mt-5 divide-y divide-border">
              {review.map((r) => (
                <li key={r.label} className="flex items-center justify-between gap-4 py-3">
                  <div>
                    <p className="text-sm">{r.label}</p>
                    <p className="text-xs text-fg-subtle">{r.source}</p>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-medium tabular">{r.value}</span>
                    <Check className="h-4 w-4 text-energy" aria-hidden="true" />
                  </div>
                </li>
              ))}
            </ul>
            <div className="mt-5 h-10 rounded-md bg-fg text-center text-sm font-medium leading-10 text-bg" aria-hidden="true">
              Continue
            </div>
            <DemoLabel className="mt-3" />
          </div>
        </Reveal>
      </div>
    </Section>
  );
}
