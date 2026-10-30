'use client';

import type { ReactNode } from 'react';
import { cn } from '@/lib/cn';
import { useInView } from '@/lib/use-in-view';

/** Fades a block in once, the first time it scrolls into view. */
export function Reveal({ children, className, delay = 0 }: { children: ReactNode; className?: string; delay?: number }) {
  const { ref, inView } = useInView<HTMLDivElement>();
  return (
    <div ref={ref} className={cn('reveal', inView && 'is-visible', className)} style={delay ? { transitionDelay: `${delay}ms` } : undefined}>
      {children}
    </div>
  );
}
