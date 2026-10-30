import { ButtonLink } from '@/components/ui/button';
import { finalCta } from '@/config/features';

export function CTA() {
  return (
    <section className="relative overflow-hidden border-t border-border py-24 sm:py-32" aria-labelledby="cta-title">
      <div className="pointer-events-none absolute inset-0 -z-10" aria-hidden="true">
        <div className="glow-energy absolute left-1/2 top-1/2 h-[60vw] max-h-[640px] w-[80vw] max-w-[1000px] -translate-x-1/2 -translate-y-1/2" />
      </div>
      <div className="container-x text-center">
        <h2 id="cta-title" className="mx-auto max-w-[40rem] text-balance text-[2rem] font-semibold leading-[1.1] tracking-[-0.025em] sm:text-[2.75rem] lg:text-[3.25rem]">
          {finalCta.headline}
        </h2>
        <p className="mx-auto mt-5 max-w-[30rem] text-pretty text-lg text-fg-muted">{finalCta.subcopy}</p>
        <div className="mt-9 flex flex-col items-center justify-center gap-3 sm:flex-row">
          <ButtonLink href={finalCta.primary.href} size="lg">
            {finalCta.primary.label}
          </ButtonLink>
          <ButtonLink href={finalCta.secondary.href} size="lg" variant="secondary">
            {finalCta.secondary.label}
          </ButtonLink>
        </div>
      </div>
    </section>
  );
}
