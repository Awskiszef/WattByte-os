import { ComingSoon } from '@/components/ui/badge';
import { DemoLabel } from '@/components/ui/demo-label';
import { Reveal } from '@/components/ui/reveal';
import { Section } from '@/components/ui/section';
import { SectionHeading } from '@/components/ui/section-heading';
import { consumptionBlocks, type ConsumptionBlock } from '@/config/features';
import { weeklyReportDemo } from '@/config/demo-data';
import { cn } from '@/lib/cn';

function Capabilities({ block }: { block: ConsumptionBlock }) {
  return (
    <ul className="mt-5 space-y-2 text-sm text-fg-muted">
      {block.capabilities.map((c) => (
        <li key={c.label} className="flex items-start gap-2.5">
          <span className={cn('mt-[7px] h-1.5 w-1.5 shrink-0 rounded-full', c.comingSoon ? 'bg-fg-subtle' : 'bg-fg')} aria-hidden="true" />
          <span className="inline-flex flex-wrap items-center gap-2">
            {c.label}
            {c.comingSoon ? <ComingSoon /> : null}
          </span>
        </li>
      ))}
    </ul>
  );
}

function BlockShell({ block, children, className }: { block: ConsumptionBlock; children?: React.ReactNode; className?: string }) {
  return (
    <article className={cn('flex flex-col rounded-xl border border-border bg-bg-elevated p-6 sm:p-7', className)}>
      <h3 className="text-xl font-semibold tracking-[-0.01em]">{block.title}</h3>
      <p className="mt-2 text-pretty text-base text-fg-muted">{block.copy}</p>
      <Capabilities block={block} />
      {children ? <div className="mt-auto pt-6">{children}</div> : null}
    </article>
  );
}

/** Charging session: a level rising from 23 % to 100 % over a bar. */
function ChargingVisual() {
  return (
    <div className="rounded-lg border border-border bg-bg p-4">
      <div className="flex items-baseline justify-between text-xs text-fg-subtle">
        <span>Charging session</span>
        <span className="tabular">22:41 to 00:12</span>
      </div>
      <div className="mt-3 flex items-end gap-1" aria-hidden="true">
        {[23, 31, 42, 55, 66, 76, 84, 90, 95, 98, 100].map((lvl, i) => (
          <div key={i} className="flex-1 rounded-sm bg-energy/80" style={{ height: `${Math.max(6, lvl * 0.4)}px`, opacity: 0.35 + i * 0.06 }} />
        ))}
      </div>
      <div className="mt-3 grid grid-cols-3 gap-2 text-xs">
        <div>
          <p className="text-fg-subtle">Level</p>
          <p className="mt-0.5 font-medium tabular">23% to 100%</p>
        </div>
        <div>
          <p className="text-fg-subtle">Charge added</p>
          <p className="mt-0.5 font-medium tabular">3,520 mAh</p>
        </div>
        <div>
          <p className="text-fg-subtle">Energy</p>
          <p className="mt-0.5 font-medium tabular text-energy">13.6 Wh</p>
        </div>
      </div>
    </div>
  );
}

function EnergyVisual() {
  const steps = [
    { label: 'Battery energy', value: '13.6 Wh' },
    { label: 'Wall energy at 85% efficiency', value: '16.0 Wh' },
    { label: 'As kWh', value: '0.016 kWh' },
    { label: 'At 0.24 €/kWh', value: '€0.0038' },
  ];
  return (
    <div className="rounded-lg border border-border bg-bg p-4">
      <ol className="divide-y divide-border text-sm">
        {steps.map((s) => (
          <li key={s.label} className="flex items-center justify-between gap-4 py-2 first:pt-0 last:pb-0">
            <span className="text-fg-muted">{s.label}</span>
            <span className="font-medium tabular">{s.value}</span>
          </li>
        ))}
      </ol>
    </div>
  );
}

function BarsVisual({ tone, values, labels }: { tone: 'data'; values: readonly number[]; labels: readonly string[] }) {
  const max = Math.max(...values);
  return (
    <div className="rounded-lg border border-border bg-bg p-4">
      <div className="flex h-20 items-end gap-1.5" aria-hidden="true">
        {values.map((v, i) => (
          <div key={i} className="flex-1 rounded-sm bg-data/80" style={{ height: `${(v / max) * 100}%` }} />
        ))}
      </div>
      <div className="mt-2 flex justify-between text-[10px] text-fg-subtle">
        {labels.map((l) => (
          <span key={l}>{l}</span>
        ))}
      </div>
      <p className="sr-only">{`Daily totals: ${values.join(', ')}.`}</p>
      <p className={cn('mt-3 text-xs', tone === 'data' ? 'text-fg-muted' : '')}>12% less than the previous week.</p>
    </div>
  );
}

function HistoryVisual() {
  const chips = consumptionBlocks.find((b) => b.id === 'history')!.capabilities;
  return (
    <div className="flex flex-wrap gap-2">
      {chips.map((c, i) => (
        <span
          key={c.label}
          className={cn(
            'inline-flex h-8 items-center gap-2 rounded-md border px-3 text-sm',
            c.comingSoon ? 'border-dashed border-border text-fg-subtle' : i === 0 ? 'border-fg bg-fg text-bg' : 'border-border text-fg-muted',
          )}
        >
          {c.label}
          {c.comingSoon ? <span className="text-[10px]">soon</span> : null}
        </span>
      ))}
    </div>
  );
}

export function ConsumptionBlocks({ showHeading = true }: { showHeading?: boolean }) {
  const by = Object.fromEntries(consumptionBlocks.map((b) => [b.id, b])) as Record<ConsumptionBlock['id'], ConsumptionBlock>;
  return (
    <Section id="features" className="scroll-mt-16">
      <div className="container-x">
        {showHeading ? (
          <SectionHeading
            title="Everything your device consumes. In one place."
            copy="Battery, energy, mobile data and Wi-Fi are measured separately and kept side by side, so a change in one is easy to see against the others."
          />
        ) : null}
        <div className={cn('grid gap-4 md:grid-cols-2', showHeading && 'mt-12')}>
          <Reveal>
            <BlockShell block={by.battery} className="h-full">
              <ChargingVisual />
            </BlockShell>
          </Reveal>
          <Reveal delay={60}>
            <BlockShell block={by.energy} className="h-full">
              <EnergyVisual />
            </BlockShell>
          </Reveal>
          <Reveal>
            <BlockShell block={by.mobile} className="h-full">
              <BarsVisual tone="data" values={[1.2, 0.9, 1.8, 1.1, 0.6, 2.1, 0.5]} labels={['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']} />
            </BlockShell>
          </Reveal>
          <Reveal delay={60}>
            <BlockShell block={by.wifi} className="h-full">
              <div className="rounded-lg border border-border bg-bg p-4">
                <div className="flex items-baseline justify-between text-xs text-fg-subtle">
                  <span>This week</span>
                  <span className="tabular">{weeklyReportDemo.rows[3]!.value} Wi-Fi</span>
                </div>
                <div className="mt-3 flex h-2 overflow-hidden rounded-full bg-surface-2" aria-hidden="true">
                  <div className="h-full bg-data" style={{ width: '89%' }} />
                  <div className="h-full bg-data/40" style={{ width: '11%' }} />
                </div>
                <div className="mt-2 flex justify-between text-xs text-fg-muted">
                  <span>Wi-Fi 89%</span>
                  <span>Mobile 11%</span>
                </div>
              </div>
            </BlockShell>
          </Reveal>
          <Reveal className="md:col-span-2">
            <BlockShell block={by.history}>
              <HistoryVisual />
            </BlockShell>
          </Reveal>
        </div>
        <DemoLabel className="mt-3" />
      </div>
    </Section>
  );
}
