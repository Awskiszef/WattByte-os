// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { Reveal } from '@/components/ui/reveal';
import { Section } from '@/components/ui/section';
import { aboutValues } from '@/config/about';

export function Values() {
  return (
    <Section id="values" className="scroll-mt-16 border-t border-border">
      <div className="container-x">
        <h2 className="max-w-[36rem] text-balance text-[2rem] font-semibold leading-[1.1] tracking-[-0.02em] sm:text-[2.5rem] lg:text-[2.875rem]">
          {aboutValues.headline}
        </h2>
        <ol className="mt-12 divide-y divide-border border-y border-border">
          {aboutValues.values.map((v, i) => (
            <li key={v.number}>
              <Reveal delay={i * 50}>
                <div className="grid gap-4 py-8 sm:grid-cols-[6rem_1fr] sm:gap-10 lg:grid-cols-[8rem_14rem_1fr]">
                  <span className="text-4xl font-semibold leading-none tracking-[-0.04em] text-fg-subtle tabular sm:text-5xl" aria-hidden="true">
                    {v.number}
                  </span>
                  <h3 className="text-xl font-semibold tracking-[-0.01em] sm:text-2xl">
                    <span className="sr-only">{v.number}. </span>
                    {v.title}
                  </h3>
                  <p className="max-w-[36rem] text-pretty text-base leading-relaxed text-fg-muted sm:text-lg lg:col-start-3">{v.copy}</p>
                </div>
              </Reveal>
            </li>
          ))}
        </ol>
      </div>
    </Section>
  );
}
