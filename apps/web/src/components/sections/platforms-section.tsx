import { ButtonLink } from '@/components/ui/button';
import { Section } from '@/components/ui/section';
import { SectionHeading } from '@/components/ui/section-heading';
import { platformsSection } from '@/config/features';
import { site } from '@/config/site';
import { StoreBadges } from './store-badges';

export function PlatformsSection() {
  return (
    <Section className="border-t border-border">
      <div className="container-x">
        <SectionHeading align="center" title={platformsSection.headline} copy={platformsSection.copy} />
        <div className="mx-auto mt-10 grid max-w-[40rem] gap-4 sm:grid-cols-2">
          {site.platforms.map((p) => (
            <div key={p.id} className="rounded-xl border border-border bg-bg-elevated p-6 text-center">
              <p className="text-lg font-semibold">{p.name}</p>
              <p className="mt-1 text-sm text-fg-muted">{p.requirement}</p>
            </div>
          ))}
        </div>
        <div className="mt-8 flex flex-col items-center gap-6">
          <StoreBadges />
          <ButtonLink href="/download" variant="secondary">
            Join the launch list
          </ButtonLink>
        </div>
      </div>
    </Section>
  );
}
