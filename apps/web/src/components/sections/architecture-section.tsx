// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { ButtonLink } from '@/components/ui/button';
import { Section } from '@/components/ui/section';
import { SectionHeading } from '@/components/ui/section-heading';
import { architecture } from '@/config/features';

export function ArchitectureSection({ withLink = true }: { withLink?: boolean }) {
  return (
    <Section id="technology" className="scroll-mt-16 border-t border-border">
      <div className="container-x">
        <SectionHeading title={architecture.headline} copy={architecture.copy} />
        <ol className="mt-12 grid gap-4 lg:grid-cols-3">
          {architecture.layers.map((layer) => (
            <li key={layer.name} className="rounded-xl border border-border bg-bg-elevated p-6">
              <h3 className="text-base font-semibold">{layer.name}</h3>
              <ul className="mt-4 flex flex-wrap gap-2">
                {layer.items.map((item) => (
                  <li key={item} className="rounded-md border border-border bg-bg px-2.5 py-1 font-mono text-[12px] text-fg">
                    {item}
                  </li>
                ))}
              </ul>
              <p className="mt-4 text-sm leading-relaxed text-fg-muted">{layer.detail}</p>
            </li>
          ))}
        </ol>
        {withLink ? (
          <div className="mt-8">
            <ButtonLink href="/technology" variant="secondary">
              More about the architecture
            </ButtonLink>
          </div>
        ) : null}
      </div>
    </Section>
  );
}
