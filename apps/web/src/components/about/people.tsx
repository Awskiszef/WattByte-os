import { Section } from '@/components/ui/section';
import { SectionHeading } from '@/components/ui/section-heading';
import { aboutPeople } from '@/config/about';

function initials(name: string) {
  return name
    .split(' ')
    .map((p) => p[0])
    .join('')
    .slice(0, 2);
}

export function People() {
  const { founder } = aboutPeople;
  return (
    <Section id="people" className="scroll-mt-16 border-t border-border">
      <div className="container-x grid gap-12 lg:grid-cols-[1fr_1fr] lg:gap-16">
        <div>
          <SectionHeading title={aboutPeople.headline} copy={aboutPeople.copy} />
          <ul className="mt-8 space-y-4 text-sm leading-relaxed text-fg-muted sm:text-base">
            {aboutPeople.philosophy.map((p) => (
              <li key={p.slice(0, 20)} className="border-l-2 border-border pl-4">
                {p}
              </li>
            ))}
          </ul>
        </div>
        <article className="self-start rounded-xl border border-border bg-bg-elevated p-6 sm:p-8" aria-labelledby="founder-name">
          <div className="flex items-center gap-4">
            <span
              className="inline-flex h-14 w-14 shrink-0 items-center justify-center rounded-full border border-border-strong bg-surface text-lg font-semibold tracking-[-0.02em]"
              aria-hidden="true"
            >
              {initials(founder.name)}
            </span>
            <div>
              <h3 id="founder-name" className="text-lg font-semibold tracking-[-0.01em]">
                {founder.name}
              </h3>
              <p className="text-sm text-fg-muted">{founder.role}</p>
            </div>
          </div>
          <p className="mt-5 text-pretty text-sm leading-relaxed text-fg-muted sm:text-base">{founder.copy}</p>
        </article>
      </div>
    </Section>
  );
}
