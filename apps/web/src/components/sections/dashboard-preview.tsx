// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { MetricCard } from '@/components/home/metric-card';
import { Counter } from '@/components/home/counter';
import { UsageChart } from '@/components/home/usage-chart';
import { DemoLabel } from '@/components/ui/demo-label';
import { Reveal } from '@/components/ui/reveal';
import { Section } from '@/components/ui/section';
import { SectionHeading } from '@/components/ui/section-heading';
import { todayDemo } from '@/config/demo-data';

export function DashboardPreview() {
  return (
    <Section id="product" className="scroll-mt-16">
      <div className="container-x">
        <SectionHeading
          title="One screen. Battery, energy, data and what they cost."
          copy="The dashboard is the whole product in a glance: what the phone used today, what that is in energy, and the estimated cost at your local electricity price."
        />
        <Reveal className="mt-12">
          <div className="rounded-xl border border-border bg-bg-elevated p-4 sm:p-6 lg:p-8">
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <h3 className="text-lg font-semibold tracking-[-0.01em]">Today</h3>
              <DemoLabel />
            </div>
            <div className="mt-5 grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-5">
              <MetricCard label="Battery used" value={<Counter value={todayDemo.batteryMah} />} unit="mAh" />
              <MetricCard label="Energy" value={<Counter value={todayDemo.energyWh} fractionDigits={1} />} unit="Wh" tone="energy" />
              <MetricCard label="Estimated electricity cost" value={<span className="tabular">{todayDemo.costLabel}</span>} hint="At your local price per kWh" />
              <MetricCard label="Mobile data" value={<Counter value={todayDemo.mobileGb} fractionDigits={1} />} unit="GB" tone="data" />
              <MetricCard label="Wi-Fi" value={<Counter value={todayDemo.wifiGb} fractionDigits={1} />} unit="GB" tone="data" />
            </div>
            <div className="mt-6 rounded-lg border border-border bg-bg p-4 sm:p-6">
              <div className="flex flex-wrap items-baseline justify-between gap-2">
                <p className="text-sm font-medium">Energy through the day</p>
                <p className="text-xs text-fg-subtle">Wh per hour</p>
              </div>
              <UsageChart className="mt-4" />
            </div>
          </div>
        </Reveal>
      </div>
    </Section>
  );
}
