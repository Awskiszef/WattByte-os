import type { ReactNode } from 'react';
import { cn } from '@/lib/cn';

type Props = {
  title: string;
  copy?: ReactNode;
  /** Short line above the title. Sentence case, used only when it carries information. */
  kicker?: string;
  align?: 'left' | 'center';
  as?: 'h1' | 'h2' | 'h3';
  className?: string;
  size?: 'lg' | 'md';
};

export function SectionHeading({ title, copy, kicker, align = 'left', as: Tag = 'h2', className, size = 'lg' }: Props) {
  return (
    <div className={cn('max-w-[40rem]', align === 'center' && 'mx-auto text-center', className)}>
      {kicker ? <p className="mb-3 text-sm font-medium text-fg-subtle">{kicker}</p> : null}
      <Tag
        className={cn(
          'text-balance font-semibold tracking-[-0.02em] text-fg',
          size === 'lg' ? 'text-[2rem] leading-[1.1] sm:text-[2.5rem] lg:text-[2.875rem]' : 'text-2xl leading-tight sm:text-[1.75rem]',
        )}
      >
        {title}
      </Tag>
      {copy ? <p className="mt-4 text-pretty text-base leading-relaxed text-fg-muted sm:text-lg">{copy}</p> : null}
    </div>
  );
}
