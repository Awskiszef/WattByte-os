import { Compass, Eye, SlidersHorizontal } from 'lucide-react';
import { Reveal } from '@/components/ui/reveal';
import { Section } from '@/components/ui/section';
import { SectionHeading } from '@/components/ui/section-heading';
import { aboutMission } from '@/config/about';

const icons = { clarity: Eye, awareness: Compass, control: SlidersHorizontal } as const;

export function Mission() {
  return (
    <Section id="mission" className="scroll-mt-16 border-t border-border bg-bg-elevated">
      <div className="container-x">
        <SectionHeading title={aboutMission.headline} copy={aboutMission.copy} />
        <ol className="mt-12 grid gap-4 md:grid-cols-3">
          {aboutMission.pillars.map((pillar, i) => {
            const Icon = icons[pillar.id];
            return (
              <li key={pillar.id} className="h-full">
                <Reveal delay={i * 70} className="group h-full rounded-xl border border-border bg-bg p-6 transition-colors hover:border-border-strong sm:p-7">
                  <span className="inline-flex h-10 w-10 items-center justify-center rounded-md border border-border bg-surface text-fg transition-transform duration-300 ease-out-quint group-hover:-translate-y-0.5">
                    <Icon className="h-5 w-5" aria-hidden="true" />
                  </span>
                  <h3 className="mt-5 text-lg font-semibold tracking-[-0.01em]">{pillar.title}</h3>
                  <p className="mt-2 text-pretty text-sm leading-relaxed text-fg-muted sm:text-base">{pillar.copy}</p>
                </Reveal>
              </li>
            );
          })}
        </ol>
      </div>
    </Section>
  );
}
