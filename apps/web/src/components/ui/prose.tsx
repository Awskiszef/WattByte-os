// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import type { ReactNode } from 'react';
import { cn } from '@/lib/cn';

/** Long-form text (legal pages, support). Keeps lines under ~75 characters. */
export function Prose({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div
      className={cn(
        'max-w-[42rem] text-base leading-relaxed text-fg-muted',
        '[&_h2]:mt-12 [&_h2]:mb-3 [&_h2]:text-xl [&_h2]:font-semibold [&_h2]:tracking-[-0.01em] [&_h2]:text-fg',
        '[&_h3]:mt-8 [&_h3]:mb-2 [&_h3]:text-base [&_h3]:font-semibold [&_h3]:text-fg',
        '[&_p]:mb-4 [&_ul]:mb-4 [&_ul]:list-disc [&_ul]:pl-5 [&_li]:mb-1.5',
        '[&_a]:text-fg [&_a]:underline [&_a]:underline-offset-4 [&_a:hover]:text-fg-muted',
        '[&_strong]:font-medium [&_strong]:text-fg',
        className,
      )}
    >
      {children}
    </div>
  );
}
