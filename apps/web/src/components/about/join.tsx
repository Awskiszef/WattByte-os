// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { ButtonLink } from '@/components/ui/button';
import { aboutJoin } from '@/config/about';
import { Eyebrow } from './eyebrow';

export function Join() {
  return (
    <section className="relative overflow-hidden border-t border-border py-24 sm:py-32" aria-labelledby="join-title">
      <div className="pointer-events-none absolute inset-0 -z-10" aria-hidden="true">
        <div className="glow-energy absolute left-1/2 top-1/2 h-[60vw] max-h-[640px] w-[80vw] max-w-[1000px] -translate-x-1/2 -translate-y-1/2" />
      </div>
      <div className="container-x text-center">
        <Eyebrow className="mx-auto">{aboutJoin.eyebrow}</Eyebrow>
        <h2 id="join-title" className="mx-auto mt-4 max-w-[30rem] text-balance text-[2.25rem] font-semibold leading-[1.05] tracking-[-0.03em] sm:text-[3rem] lg:text-[3.75rem]">
          {aboutJoin.headline}
        </h2>
        <p className="mx-auto mt-5 max-w-[34rem] text-pretty text-lg text-fg-muted">{aboutJoin.copy}</p>
        <div className="mt-9 flex flex-col items-center justify-center gap-3 sm:flex-row">
          <ButtonLink href={aboutJoin.primary.href} size="lg">
            {aboutJoin.primary.label}
          </ButtonLink>
          <ButtonLink href={aboutJoin.secondary.href} size="lg" variant="secondary">
            {aboutJoin.secondary.label}
          </ButtonLink>
        </div>
        <p className="mt-5 text-sm text-fg-subtle">{aboutJoin.note}</p>
      </div>
    </section>
  );
}
