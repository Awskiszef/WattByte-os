// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { Section } from '@/components/ui/section';
import { SectionHeading } from '@/components/ui/section-heading';
import { aiProviders } from '@/config/features';

/** The routing path, as a diagram: phone, API, gateway, then exactly one provider. */
function RoutingDiagram() {
  return (
    <div className="rounded-xl border border-border bg-bg-elevated p-5 sm:p-6">
      <ol className="grid gap-3 text-sm sm:grid-cols-[1fr_1fr_1fr_1.3fr] sm:items-center">
        <li className="rounded-md border border-border bg-bg px-3 py-3">
          <p className="font-medium">WattByte app</p>
          <p className="mt-0.5 text-xs text-fg-subtle">sends period totals</p>
        </li>
        <li className="rounded-md border border-border bg-bg px-3 py-3">
          <p className="font-medium">WattByte API</p>
          <p className="mt-0.5 text-xs text-fg-subtle">quota, validation, keys</p>
        </li>
        <li className="rounded-md border border-border bg-bg px-3 py-3">
          <p className="font-medium">AI gateway</p>
          <p className="mt-0.5 text-xs text-fg-subtle">routing, retry, one fallback</p>
        </li>
        <li className="grid grid-cols-2 gap-2">
          {aiProviders.providers.map((p, i) => (
            <span
              key={p}
              className={
                i === 0
                  ? 'rounded-md border border-fg bg-fg px-3 py-2 text-center text-xs font-medium text-bg'
                  : 'rounded-md border border-border px-3 py-2 text-center text-xs text-fg-muted'
              }
            >
              {p}
            </span>
          ))}
        </li>
      </ol>
      <p className="mt-4 text-xs text-fg-subtle">One provider is asked per request. Which one is a server setting, never a choice the app or a request can make.</p>
    </div>
  );
}

export function ProvidersSection() {
  return (
    <Section className="border-t border-border">
      <div className="container-x grid gap-12 lg:grid-cols-[0.9fr_1.1fr] lg:items-center">
        <div>
          <SectionHeading title={aiProviders.headline} copy={aiProviders.copy} />
          <ul className="mt-8 space-y-3 text-sm text-fg-muted">
            {aiProviders.guarantees.map((g) => (
              <li key={g} className="flex gap-3">
                <span className="mt-[9px] h-1 w-4 shrink-0 rounded-full bg-fg" aria-hidden="true" />
                {g}
              </li>
            ))}
          </ul>
        </div>
        <RoutingDiagram />
      </div>
    </Section>
  );
}
