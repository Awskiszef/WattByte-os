// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { ButtonLink } from '@/components/ui/button';
import { aboutHero } from '@/config/about';
import { Eyebrow } from './eyebrow';
import { FlowField } from './flow-field';

export function AboutHero() {
  return (
    <section className="relative overflow-hidden pb-20 pt-16 sm:pt-24 lg:pb-28 lg:pt-32" aria-labelledby="about-title">
      <div className="pointer-events-none absolute inset-0 -z-10" aria-hidden="true">
        <FlowField className="motion-flow absolute inset-0 h-full w-full" />
        <div className="glow-energy absolute -right-[10%] -top-[30%] h-[50vw] max-h-[640px] w-[50vw] max-w-[640px]" />
      </div>
      <div className="container-x">
        <div className="max-w-[44rem]">
          <Eyebrow className="rise rise-1">{aboutHero.eyebrow}</Eyebrow>
          <h1
            id="about-title"
            className="rise-solid rise-2 mt-5 text-balance text-[2.6rem] font-semibold leading-[1.04] tracking-[-0.03em] sm:text-[3.4rem] lg:text-[4.25rem]"
          >
            {aboutHero.headline}
          </h1>
          <p className="rise-solid rise-3 mt-6 max-w-[36rem] text-pretty text-lg leading-relaxed text-fg-muted sm:text-xl">{aboutHero.subheadline}</p>
          <div className="rise rise-4 mt-9 flex flex-col gap-3 sm:flex-row">
            <ButtonLink href={aboutHero.primary.href} size="lg">
              {aboutHero.primary.label}
            </ButtonLink>
            <ButtonLink href={aboutHero.secondary.href} size="lg" variant="secondary">
              {aboutHero.secondary.label}
            </ButtonLink>
          </div>
        </div>
      </div>
    </section>
  );
}
