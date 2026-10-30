// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { Sparkles } from 'lucide-react';
import { ButtonLink } from '@/components/ui/button';
import { ComingSoon } from '@/components/ui/badge';
import { DemoLabel } from '@/components/ui/demo-label';
import { Reveal } from '@/components/ui/reveal';
import { Section } from '@/components/ui/section';
import { SectionHeading } from '@/components/ui/section-heading';
import { aiDemo } from '@/config/demo-data';
import { aiSection } from '@/config/features';

export function AIChatPreview({ withLink = true }: { withLink?: boolean }) {
  return (
    <Section id="ai" className="relative scroll-mt-16 overflow-hidden border-t border-border">
      <div className="pointer-events-none absolute inset-0 -z-10" aria-hidden="true">
        <div className="glow-energy absolute left-1/2 top-0 h-[40vw] max-h-[520px] w-[70vw] max-w-[900px] -translate-x-1/2 -translate-y-1/2" />
      </div>
      <div className="container-x">
        <SectionHeading align="center" title={aiSection.headline} copy={aiSection.copy} />

        <Reveal className="mx-auto mt-12 max-w-[44rem]">
          <div className="rounded-xl border border-border bg-bg-elevated p-5 sm:p-7">
            <p className="text-xs font-medium text-fg-subtle">The questions an insight answers</p>
            <ul className="mt-3 flex flex-wrap gap-2">
              {aiDemo.questions.map((q) => (
                <li key={q} className="rounded-md border border-border bg-bg px-3 py-1.5 text-sm text-fg-muted">
                  {q}
                </li>
              ))}
            </ul>

            <div className="mt-6 rounded-lg border border-border bg-bg p-4 sm:p-5">
              <p className="inline-flex items-center gap-2 text-sm font-medium">
                <Sparkles className="h-4 w-4 text-energy" aria-hidden="true" />
                Why was my battery usage higher today?
              </p>
              <p className="mt-3 text-pretty text-base leading-relaxed">{aiDemo.answer}</p>
              <p className="mt-3 text-xs text-fg-subtle">{aiDemo.attribution}</p>
            </div>

            <div className="mt-5 flex flex-wrap items-center gap-2">
              {aiSection.actions.map((a) => (
                <span key={a} className="inline-flex h-8 items-center rounded-md border border-border px-3 text-sm">
                  {a}
                </span>
              ))}
              <span className="inline-flex h-8 items-center gap-2 rounded-md border border-dashed border-border px-3 text-sm text-fg-subtle">
                {aiSection.freeFormQuestions.label}
                <ComingSoon />
              </span>
            </div>
            <DemoLabel className="mt-4" />
          </div>
        </Reveal>

        <ul className="mx-auto mt-10 grid max-w-[56rem] gap-6 text-sm text-fg-muted sm:grid-cols-3">
          {aiSection.limits.map((l) => (
            <li key={l} className="border-t border-border pt-4">
              {l}
            </li>
          ))}
        </ul>

        {withLink ? (
          <div className="mt-10 text-center">
            <ButtonLink href="/ai" variant="secondary">
              How WattByte AI works
            </ButtonLink>
          </div>
        ) : null}
      </div>
    </Section>
  );
}
