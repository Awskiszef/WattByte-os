import { ChevronDown } from 'lucide-react';
import { Section } from '@/components/ui/section';
import { SectionHeading } from '@/components/ui/section-heading';
import { faq, type FaqItem } from '@/config/faq';

/** Native disclosure elements: keyboard and screen-reader support for free, no JS. */
export function FAQ({ items = faq, withHeading = true, limit }: { items?: readonly FaqItem[]; withHeading?: boolean; limit?: number }) {
  const shown = limit ? items.slice(0, limit) : items;
  return (
    <Section id="faq" className="scroll-mt-16 border-t border-border">
      <div className="container-x">
        {withHeading ? <SectionHeading title="Questions people ask before installing." /> : null}
        <div className="mt-10 max-w-[44rem] divide-y divide-border border-y border-border">
          {shown.map((item) => (
            <details key={item.id} id={item.id} className="group scroll-mt-20">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-6 py-5 text-left text-base font-medium marker:hidden [&::-webkit-details-marker]:hidden">
                {item.question}
                <ChevronDown className="h-4 w-4 shrink-0 text-fg-subtle transition-transform duration-300 group-open:rotate-180" aria-hidden="true" />
              </summary>
              <p className="pb-5 pr-10 text-pretty text-sm leading-relaxed text-fg-muted sm:text-base">{item.answer}</p>
            </details>
          ))}
        </div>
      </div>
    </Section>
  );
}
