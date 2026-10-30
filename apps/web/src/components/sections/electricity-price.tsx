// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { Section } from '@/components/ui/section';
import { SectionHeading } from '@/components/ui/section-heading';
import { regionDemo } from '@/config/demo-data';
import { electricityPriceSection } from '@/config/features';
import { formatPeriod, getHouseholdPrice } from '@/lib/electricity-price';

/** Server component: the Polish household price from Eurostat, or an honest placeholder. */
export async function ElectricityPrice() {
  const price = await getHouseholdPrice(regionDemo.countryCode);
  const shown = price ? price.pricePerKwh.toFixed(2) : regionDemo.placeholderPrice;

  return (
    <Section tight className="border-t border-border">
      <div className="container-x grid gap-10 lg:grid-cols-2 lg:items-center">
        <SectionHeading size="md" title={electricityPriceSection.headline} copy={electricityPriceSection.copy} />
        <div className="rounded-xl border border-border bg-bg-elevated p-6 sm:p-7">
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="text-sm text-fg-subtle">Country</p>
              <p className="mt-1 text-lg font-medium">{regionDemo.country}</p>
            </div>
            <div className="text-right">
              <p className="text-sm text-fg-subtle">Currency</p>
              <p className="mt-1 text-lg font-medium">{regionDemo.currency}</p>
            </div>
          </div>
          <div className="mt-6 border-t border-border pt-6">
            <p className="text-sm text-fg-subtle">Estimated electricity price</p>
            <p className="mt-1 text-3xl font-semibold tracking-[-0.02em] tabular sm:text-4xl">
              {shown} <span className="text-base font-normal text-fg-muted">{regionDemo.currency} / kWh</span>
            </p>
            <p className="mt-3 text-xs text-fg-subtle">
              {price
                ? `Source: ${electricityPriceSection.source.name}, ${formatPeriod(price.period)}. ${electricityPriceSection.source.detail}`
                : `Live value unavailable right now. Source when online: ${electricityPriceSection.source.name}. ${electricityPriceSection.source.detail}`}
            </p>
          </div>
        </div>
      </div>
    </Section>
  );
}
