import type { Metadata } from 'next';
import { AIChatPreview } from '@/components/sections/ai-preview';
import { CTA } from '@/components/sections/cta';
import { ProvidersSection } from '@/components/sections/providers';
import { ButtonLink } from '@/components/ui/button';
import { PageHeader } from '@/components/ui/page-header';
import { Section } from '@/components/ui/section';
import { pageMetadata } from '@/lib/seo';

export const metadata: Metadata = pageMetadata({
  title: 'WattByte AI',
  description:
    'WattByte AI explains your battery, data and energy totals in plain language. Only period totals are sent, the AI never calculates, and prompts are not stored.',
  path: '/ai',
});

const steps = [
  { title: 'Your phone computes the totals', copy: 'Data in GB, charging sessions, energy in kWh, estimated cost and the change against the previous period. All of it is already on the dashboard.' },
  { title: 'The app sends only those totals', copy: 'The request is validated by a strict schema on the server. An e-mail, user id, device id or token in it is rejected before any prompt exists.' },
  { title: 'One provider writes a short explanation', copy: 'A title, a message and a tone. The prompt forbids calculating or inventing numbers; the answer is validated before it reaches you.' },
  { title: 'Nothing is kept', copy: 'The server logs which provider answered, how many tokens and what it cost. It stores neither the prompt nor the answer.' },
];

export default function AiPage() {
  return (
    <>
      <PageHeader
        title="Explanations, not more numbers."
        copy="WattByte AI reads the totals your phone already measured and tells you what changed, in a few sentences. It is a reader of your data, not a calculator and not a chatbot."
      >
        <ButtonLink href="/download">Get WattByte</ButtonLink>
        <ButtonLink href="/privacy" variant="secondary">
          Privacy details
        </ButtonLink>
      </PageHeader>
      <AIChatPreview withLink={false} />
      <Section className="border-t border-border">
        <div className="container-x">
          <h2 className="text-2xl font-semibold tracking-[-0.02em] sm:text-3xl">What happens when you tap Generate insight</h2>
          <ol className="mt-10 grid gap-8 md:grid-cols-2">
            {steps.map((s, i) => (
              <li key={s.title} className="border-t border-border pt-5">
                <p className="text-xs text-fg-subtle tabular">Step {i + 1}</p>
                <h3 className="mt-2 text-base font-semibold">{s.title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-fg-muted">{s.copy}</p>
              </li>
            ))}
          </ol>
          <p className="mt-10 max-w-[40rem] text-sm text-fg-muted">
            The free plan includes a few generations per day and Pro will include more. Every generation needs a WattByte account, because the daily allowance is counted per account.
          </p>
        </div>
      </Section>
      <ProvidersSection />
      <CTA />
    </>
  );
}
