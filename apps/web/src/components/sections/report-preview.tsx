// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { TrendingDown } from 'lucide-react';
import { ComingSoon } from '@/components/ui/badge';
import { DemoLabel } from '@/components/ui/demo-label';
import { Reveal } from '@/components/ui/reveal';
import { Section } from '@/components/ui/section';
import { SectionHeading } from '@/components/ui/section-heading';
import { weeklyReportDemo } from '@/config/demo-data';
import { reportsSection } from '@/config/features';
import { cn } from '@/lib/cn';

const insightExamples = [
  'You used 12% less mobile data than last week.',
  'You charged your phone 9 times this week.',
  'Wi-Fi represented 89% of your total data usage.',
  'Your average charging session added 1,860 mAh.',
];

export function ReportPreview() {
  const max = Math.max(...weeklyReportDemo.dailyWh);
  return (
    <Section id="insights" className="scroll-mt-16 border-t border-border">
      <div className="container-x">
        <SectionHeading title={reportsSection.headline} copy={reportsSection.copy} />
        <div className="mt-12 grid gap-6 lg:grid-cols-[1.1fr_0.9fr]">
          <Reveal>
            <article className="rounded-xl border border-border bg-bg-elevated p-6 sm:p-8" aria-labelledby="weekly-report-title">
              <div className="flex flex-wrap items-baseline justify-between gap-2">
                <h3 id="weekly-report-title" className="text-lg font-semibold tracking-[-0.01em]">
                  {weeklyReportDemo.title}
                </h3>
                <p className="text-xs text-fg-subtle tabular">Mon 13 to Sun 19 Oct</p>
              </div>
              <div className="mt-6 flex h-24 items-end gap-2" aria-hidden="true">
                {weeklyReportDemo.dailyWh.map((v, i) => (
                  <div key={i} className="flex-1 rounded-sm bg-energy/80" style={{ height: `${(v / max) * 100}%` }} />
                ))}
              </div>
              <dl className="mt-6 divide-y divide-border">
                {weeklyReportDemo.rows.map((row) => (
                  <div key={row.label} className="flex items-center justify-between gap-4 py-3">
                    <dt className="text-sm text-fg-muted">{row.label}</dt>
                    <dd className="text-sm font-medium tabular">{row.value}</dd>
                  </div>
                ))}
                <div className="flex items-center justify-between gap-4 py-3">
                  <dt className="text-sm text-fg-muted">{weeklyReportDemo.trend.label}</dt>
                  <dd className="inline-flex items-center gap-1.5 text-sm font-medium tabular text-energy">
                    <TrendingDown className="h-4 w-4" aria-hidden="true" />
                    {weeklyReportDemo.trend.value}
                    <span className="sr-only">compared with the previous week</span>
                  </dd>
                </div>
              </dl>
              <DemoLabel className="mt-4" />
            </article>
          </Reveal>

          <div className="flex flex-col gap-6">
            <Reveal delay={60}>
              <div className="rounded-xl border border-border bg-bg-elevated p-6 sm:p-7">
                <h3 className="text-base font-semibold">Report periods</h3>
                <ul className="mt-4 flex flex-wrap gap-2">
                  {reportsSection.periods.map((p) => (
                    <li
                      key={p.label}
                      className={cn(
                        'inline-flex h-8 items-center gap-2 rounded-md border px-3 text-sm',
                        'comingSoon' in p && p.comingSoon ? 'border-dashed border-border text-fg-subtle' : 'border-border text-fg',
                      )}
                    >
                      {p.label}
                      {'comingSoon' in p && p.comingSoon ? <ComingSoon /> : null}
                    </li>
                  ))}
                </ul>
                <p className="mt-4 text-sm text-fg-muted">Weekly and monthly summaries can also be written by WattByte AI from the same totals.</p>
              </div>
            </Reveal>
            <Reveal delay={120}>
              <div className="rounded-xl border border-border bg-bg-elevated p-6 sm:p-7">
                <h3 className="text-base font-semibold">Insights, computed on your phone</h3>
                <ul className="mt-4 space-y-3 text-sm text-fg-muted">
                  {insightExamples.map((i) => (
                    <li key={i} className="border-l-2 border-energy/70 pl-3">
                      {i}
                    </li>
                  ))}
                </ul>
                <p className="mt-4 text-xs text-fg-subtle">Rule-based, no network needed. They appear after a few days of use.</p>
              </div>
            </Reveal>
          </div>
        </div>
      </div>
    </Section>
  );
}
