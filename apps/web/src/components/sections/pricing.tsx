import { Check } from 'lucide-react';
import { ButtonLink } from '@/components/ui/button';
import { ComingSoon } from '@/components/ui/badge';
import { Section } from '@/components/ui/section';
import { SectionHeading } from '@/components/ui/section-heading';
import { plans, pricingAnnouncement, type Plan } from '@/config/pricing';
import { cn } from '@/lib/cn';

function PriceLine({ plan }: { plan: Plan }) {
  if (!plan.price) return <p className="mt-5 text-lg font-medium text-fg-muted">{pricingAnnouncement}</p>;
  return (
    <p className="mt-5 text-3xl font-semibold tracking-[-0.02em] tabular">
      {plan.price.amount} <span className="text-base font-normal text-fg-muted">{plan.price.currency} / {plan.price.period}</span>
    </p>
  );
}

export function Pricing({ withHeading = true }: { withHeading?: boolean }) {
  return (
    <Section id="pricing" className="scroll-mt-16 border-t border-border">
      <div className="container-x">
        {withHeading ? (
          <SectionHeading
            align="center"
            title="Free to use. Pro when you want more."
            copy="The free plan is the whole core app. Pro will add depth for people who want more history and more AI."
          />
        ) : null}
        <div className={cn('mx-auto grid max-w-[52rem] gap-4 md:grid-cols-2', withHeading && 'mt-12')}>
          {plans.map((plan) => (
            <article
              key={plan.id}
              className={cn('flex flex-col rounded-xl border p-6 sm:p-8', plan.id === 'pro' ? 'border-border-strong bg-bg-elevated' : 'border-border')}
              aria-labelledby={`plan-${plan.id}`}
            >
              <div className="flex items-center justify-between gap-3">
                <h3 id={`plan-${plan.id}`} className="text-xl font-semibold tracking-[-0.01em]">
                  {plan.name}
                </h3>
                {plan.status === 'planned' ? <ComingSoon /> : null}
              </div>
              <p className="mt-2 text-sm text-fg-muted">{plan.summary}</p>
              <PriceLine plan={plan} />
              <ul className="mt-6 space-y-2.5 text-sm">
                {plan.features.map((f) => (
                  <li key={f} className="flex items-start gap-2.5">
                    <Check className={cn('mt-0.5 h-4 w-4 shrink-0', plan.status === 'planned' ? 'text-fg-subtle' : 'text-energy')} aria-hidden="true" />
                    <span className={plan.status === 'planned' ? 'text-fg-muted' : ''}>{f}</span>
                  </li>
                ))}
              </ul>
              {plan.footnote ? <p className="mt-4 text-xs text-fg-subtle">{plan.footnote}</p> : null}
              <div className="mt-auto pt-8">
                {plan.status === 'available' ? (
                  <ButtonLink href="/download" className="w-full">
                    Get WattByte
                  </ButtonLink>
                ) : (
                  <ButtonLink href="/download" variant="secondary" className="w-full">
                    Join the launch list
                  </ButtonLink>
                )}
              </div>
            </article>
          ))}
        </div>
      </div>
    </Section>
  );
}
