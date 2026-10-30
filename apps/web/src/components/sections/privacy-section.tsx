// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { ButtonLink } from '@/components/ui/button';
import { Section } from '@/components/ui/section';
import { SectionHeading } from '@/components/ui/section-heading';
import { privacySection } from '@/config/features';

export function PrivacySection() {
  return (
    <Section id="privacy" className="scroll-mt-16 border-t border-border">
      <div className="container-x">
        <SectionHeading title={privacySection.headline} copy="What the app stores, what it sends and what it never does, in plain language. The full policy says the same thing with more detail." />
        <dl className="mt-12 grid gap-x-12 gap-y-8 sm:grid-cols-2 lg:grid-cols-3">
          {privacySection.points.map((p) => (
            <div key={p.title} className="border-t border-border pt-5">
              <dt className="text-base font-semibold">{p.title}</dt>
              <dd className="mt-2 text-pretty text-sm leading-relaxed text-fg-muted">{p.copy}</dd>
            </div>
          ))}
        </dl>
        <div className="mt-10">
          <ButtonLink href="/privacy" variant="secondary">
            Read Privacy Policy
          </ButtonLink>
        </div>
      </div>
    </Section>
  );
}
