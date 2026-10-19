import { Counter } from '@/components/home/counter';
import { UsageChart } from '@/components/home/usage-chart';
import { ComingSoon } from '@/components/ui/badge';
import { DemoLabel } from '@/components/ui/demo-label';
import { Reveal } from '@/components/ui/reveal';
import { Section } from '@/components/ui/section';
import { SectionHeading } from '@/components/ui/section-heading';
import { aboutBuilding, type BuildingArea } from '@/config/about';
import { aiDemo, todayDemo, weeklyReportDemo } from '@/config/demo-data';

/** A small, real-looking fragment of the WattByte interface for each area. */
function Fragment({ id }: { id: BuildingArea['id'] }) {
  switch (id) {
    case 'battery':
      return (
        <div className="rounded-lg border border-border bg-bg p-4">
          <p className="text-[11px] text-fg-subtle">Battery used today</p>
          <p className="mt-1 text-2xl font-semibold tracking-[-0.02em]">
            <Counter value={todayDemo.batteryMah} /> <span className="text-sm font-normal text-fg-muted">mAh</span>
          </p>
          <div className="mt-3 flex items-end gap-1" aria-hidden="true">
            {[23, 31, 42, 55, 66, 76, 84, 90, 95, 98, 100].map((lvl, i) => (
              <div key={i} className="flex-1 rounded-sm bg-energy/80" style={{ height: `${Math.max(4, lvl * 0.28)}px`, opacity: 0.35 + i * 0.06 }} />
            ))}
          </div>
        </div>
      );
    case 'energy':
      return (
        <div className="rounded-lg border border-border bg-bg p-4">
          <p className="text-[11px] text-fg-subtle">Energy used today</p>
          <p className="mt-1 text-2xl font-semibold tracking-[-0.02em] text-energy">
            <Counter value={todayDemo.energyWh} fractionDigits={1} /> <span className="text-sm font-normal text-fg-muted">Wh</span>
          </p>
          <UsageChart compact className="mt-2" />
        </div>
      );
    case 'network':
      return (
        <div className="grid grid-cols-2 gap-2">
          <div className="rounded-lg border border-border bg-bg p-3">
            <p className="text-[11px] text-fg-subtle">Mobile</p>
            <p className="mt-1 text-xl font-semibold tracking-[-0.02em] text-data">
              <Counter value={todayDemo.mobileGb} fractionDigits={1} /> <span className="text-xs font-normal text-fg-muted">GB</span>
            </p>
          </div>
          <div className="rounded-lg border border-border bg-bg p-3">
            <p className="text-[11px] text-fg-subtle">Wi-Fi</p>
            <p className="mt-1 text-xl font-semibold tracking-[-0.02em] text-data">
              <Counter value={todayDemo.wifiGb} fractionDigits={1} /> <span className="text-xs font-normal text-fg-muted">GB</span>
            </p>
          </div>
        </div>
      );
    case 'cost':
      return (
        <div className="rounded-lg border border-border bg-bg p-4">
          <p className="text-[11px] text-fg-subtle">Estimated electricity cost today</p>
          <p className="mt-1 text-2xl font-semibold tracking-[-0.02em] tabular">{todayDemo.costLabel}</p>
          <p className="mt-2 text-xs text-fg-subtle">At the household price for your region</p>
        </div>
      );
    case 'ai':
      return (
        <div className="rounded-lg border border-border bg-bg p-4">
          <p className="text-[11px] font-medium text-fg-muted">Insight</p>
          <p className="mt-1.5 text-sm leading-snug">{aiDemo.answer}</p>
          <p className="mt-2 text-[11px] text-fg-subtle">{aiDemo.attribution}</p>
        </div>
      );
    case 'reports': {
      const max = Math.max(...weeklyReportDemo.dailyWh);
      return (
        <div className="rounded-lg border border-border bg-bg p-4">
          <div className="flex items-baseline justify-between text-[11px] text-fg-subtle">
            <span>This week, Wh per day</span>
            <span className="text-energy tabular">{weeklyReportDemo.trend.value}</span>
          </div>
          <div className="mt-3 flex h-14 items-end gap-1.5" aria-hidden="true">
            {weeklyReportDemo.dailyWh.map((v, i) => (
              <div key={i} className="flex-1 rounded-sm bg-energy/80" style={{ height: `${(v / max) * 100}%` }} />
            ))}
          </div>
        </div>
      );
    }
    default:
      return null;
  }
}

export function Building() {
  return (
    <Section id="building" className="scroll-mt-16 border-t border-border">
      <div className="container-x">
        <SectionHeading title={aboutBuilding.headline} copy={aboutBuilding.copy} />
        <ul className="mt-12 grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {aboutBuilding.areas.map((area, i) => (
            <li key={area.id} className="h-full">
              <Reveal delay={(i % 3) * 60} className="flex h-full flex-col rounded-xl border border-border bg-bg-elevated p-5 sm:p-6">
                <h3 className="text-lg font-semibold tracking-[-0.01em]">{area.title}</h3>
                <p className="mt-1 text-sm text-fg-muted">{area.copy}</p>
                <div className="mt-5">
                  <Fragment id={area.id} />
                </div>
                <p className="mt-4 text-pretty text-xs leading-relaxed text-fg-subtle">{area.status}</p>
                {area.comingSoon ? (
                  <p className="mt-2 inline-flex flex-wrap items-center gap-2 text-xs text-fg-subtle">
                    {area.comingSoon}
                    <ComingSoon />
                  </p>
                ) : null}
              </Reveal>
            </li>
          ))}
        </ul>
        <DemoLabel className="mt-3" />
      </div>
    </Section>
  );
}
