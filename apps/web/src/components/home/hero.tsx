import { ButtonLink } from '@/components/ui/button';
import { DemoLabel } from '@/components/ui/demo-label';
import { todayDemo } from '@/config/demo-data';
import { hero } from '@/config/features';
import { AppPreview } from './app-preview';
import { Counter } from './counter';

export function Hero() {
  return (
    <section className="relative overflow-hidden pb-20 pt-14 sm:pt-20 lg:pb-28 lg:pt-24" aria-labelledby="hero-title">
      {/* one warm glow (energy) top-right, one cool glow (data) bottom-left */}
      <div className="pointer-events-none absolute inset-0 -z-10" aria-hidden="true">
        <div className="glow-energy drift absolute -right-[10%] -top-[20%] h-[60vw] max-h-[720px] w-[60vw] max-w-[720px]" />
        <div className="glow-data absolute -bottom-[30%] -left-[15%] h-[50vw] max-h-[600px] w-[50vw] max-w-[600px]" />
      </div>

      <div className="container-x grid items-center gap-14 lg:grid-cols-[1.1fr_0.9fr] lg:gap-10">
        <div className="max-w-[36rem]">
          <p className="rise rise-1 inline-flex items-center gap-2 text-sm font-medium text-fg-muted">
            <span className="pulse-dot inline-block h-1.5 w-1.5 rounded-full bg-energy" aria-hidden="true" />
            {hero.eyebrow}
          </p>
          <h1
            id="hero-title"
            className="rise-solid rise-2 mt-5 text-balance text-[2.6rem] font-semibold leading-[1.04] tracking-[-0.03em] sm:text-[3.4rem] lg:text-[4rem]"
          >
            {hero.headline}
          </h1>
          <p className="rise-solid rise-3 mt-6 max-w-[32rem] text-pretty text-lg leading-relaxed text-fg-muted">{hero.subheadline}</p>
          <div className="rise rise-3 mt-8 flex flex-col gap-3 sm:flex-row">
            <ButtonLink href={hero.primary.href} size="lg">
              {hero.primary.label}
            </ButtonLink>
            <ButtonLink href={hero.secondary.href} size="lg" variant="secondary">
              {hero.secondary.label}
            </ButtonLink>
          </div>

          {/* the idea of the product in one line: battery becomes energy becomes money */}
          <div className="rise rise-4 mt-12">
            <ol className="grid divide-y divide-border rounded-lg border border-border bg-bg-elevated/60 xs:grid-cols-3 xs:divide-x xs:divide-y-0">
              <li className="px-4 py-4 sm:px-5">
                <p className="text-[11px] text-fg-subtle">Battery used</p>
                <p className="mt-1 text-xl font-semibold tracking-[-0.02em] sm:text-2xl">
                  <Counter value={todayDemo.batteryMah} immediate />
                  <span className="ml-1 text-sm font-normal text-fg-muted">mAh</span>
                </p>
              </li>
              <li className="px-4 py-4 sm:px-5">
                <p className="text-[11px] text-fg-subtle">becomes energy</p>
                <p className="mt-1 text-xl font-semibold tracking-[-0.02em] text-energy sm:text-2xl">
                  <Counter value={todayDemo.energyWh} fractionDigits={1} immediate />
                  <span className="ml-1 text-sm font-normal text-fg-muted">Wh</span>
                </p>
              </li>
              <li className="px-4 py-4 sm:px-5">
                <p className="text-[11px] text-fg-subtle">and costs about</p>
                <p className="mt-1 text-xl font-semibold tracking-[-0.02em] sm:text-2xl tabular">{todayDemo.costLabel}</p>
              </li>
            </ol>
            <DemoLabel className="mt-2" />
          </div>
        </div>

        <div className="rise rise-3 relative">
          <AppPreview />
        </div>
      </div>
    </section>
  );
}
