import { Section } from '@/components/ui/section';
import { aboutVision } from '@/config/about';

export function Vision() {
  return (
    <Section id="vision" className="relative scroll-mt-16 overflow-hidden border-t border-border">
      <div className="pointer-events-none absolute inset-0 -z-10" aria-hidden="true">
        <div className="glow-data absolute -left-[20%] top-1/2 h-[60vw] max-h-[700px] w-[60vw] max-w-[700px] -translate-y-1/2" />
      </div>
      <div className="container-x">
        <h2 className="max-w-[14ch] text-balance text-[2.75rem] font-semibold leading-[1] tracking-[-0.035em] sm:text-[3.75rem] lg:text-[5rem]">
          {aboutVision.headline}
        </h2>
        <p className="mt-8 max-w-[38rem] text-pretty text-lg leading-relaxed text-fg-muted sm:text-xl">{aboutVision.copy}</p>
        <ul className="mt-12 grid gap-x-10 gap-y-4 border-t border-border pt-8 sm:grid-cols-2">
          {aboutVision.directions.map((d) => (
            <li key={d} className="flex gap-3 text-base text-fg">
              <span className="mt-[11px] h-1 w-4 shrink-0 rounded-full bg-data" aria-hidden="true" />
              {d}
            </li>
          ))}
        </ul>
        <p className="mt-8 text-sm text-fg-subtle">{aboutVision.note}</p>
      </div>
    </Section>
  );
}
