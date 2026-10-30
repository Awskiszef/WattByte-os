// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { Section } from '@/components/ui/section';
import { SectionHeading } from '@/components/ui/section-heading';
import { aboutApproach } from '@/config/about';

export function Approach() {
  return (
    <Section id="approach" className="scroll-mt-16 border-t border-border bg-bg-elevated">
      <div className="container-x">
        <SectionHeading title={aboutApproach.headline} />
        <dl className="mt-12 grid gap-x-10 gap-y-8 sm:grid-cols-2">
          {aboutApproach.items.map((item) => (
            <div key={item.title} className="border-t border-border pt-5">
              <dt className="text-lg font-semibold tracking-[-0.01em]">{item.title}</dt>
              <dd className="mt-2 max-w-[32rem] text-pretty text-sm leading-relaxed text-fg-muted sm:text-base">{item.copy}</dd>
            </div>
          ))}
        </dl>
      </div>
    </Section>
  );
}
