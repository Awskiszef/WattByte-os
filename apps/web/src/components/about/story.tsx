// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { Reveal } from '@/components/ui/reveal';
import { Section } from '@/components/ui/section';
import { aboutStory } from '@/config/about';

export function Story() {
  return (
    <Section id="story" className="scroll-mt-16 border-t border-border">
      <div className="container-x grid gap-10 lg:grid-cols-[0.8fr_1.2fr] lg:gap-16">
        <div>
          <h2 className="text-balance text-[2rem] font-semibold leading-[1.1] tracking-[-0.02em] sm:text-[2.5rem]">{aboutStory.headline}</h2>
        </div>
        <Reveal>
          <blockquote className="border-l-2 border-energy pl-6 text-pretty text-xl font-medium leading-snug tracking-[-0.01em] sm:text-2xl">
            {aboutStory.pull}
          </blockquote>
          <div className="mt-10 max-w-[38rem] space-y-5 text-base leading-relaxed text-fg-muted sm:text-lg">
            {aboutStory.paragraphs.map((p) => (
              <p key={p.slice(0, 24)}>{p}</p>
            ))}
          </div>
        </Reveal>
      </div>
    </Section>
  );
}
