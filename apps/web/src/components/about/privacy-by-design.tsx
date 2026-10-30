// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { ButtonLink } from '@/components/ui/button';
import { Section } from '@/components/ui/section';
import { SectionHeading } from '@/components/ui/section-heading';
import { aboutPrivacy } from '@/config/about';

export function PrivacyByDesign() {
  return (
    <Section id="privacy" className="scroll-mt-16 border-t border-border">
      <div className="container-x">
        <SectionHeading title={aboutPrivacy.headline} copy={aboutPrivacy.copy} />
        <ol className="mt-12 grid gap-4 md:grid-cols-2 lg:grid-cols-5">
          {aboutPrivacy.points.map((p) => (
            <li key={p.title} className="rounded-xl border border-border bg-bg-elevated p-5">
              <h3 className="text-base font-semibold tracking-[-0.01em]">{p.title}</h3>
              <p className="mt-2 text-pretty text-sm leading-relaxed text-fg-muted">{p.copy}</p>
            </li>
          ))}
        </ol>
        <div className="mt-10">
          <ButtonLink href={aboutPrivacy.cta.href} variant="secondary">
            {aboutPrivacy.cta.label}
          </ButtonLink>
        </div>
      </div>
    </Section>
  );
}
