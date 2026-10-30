// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import type { ReactNode } from 'react';
import { cn } from '@/lib/cn';

type Tone = 'neutral' | 'energy' | 'data' | 'soon';

const tones: Record<Tone, string> = {
  neutral: 'bg-surface text-fg-muted hairline',
  energy: 'bg-energy-soft text-energy',
  data: 'bg-data-soft text-data',
  soon: 'bg-surface text-fg-subtle hairline border-dashed',
};

export function Badge({ tone = 'neutral', className, children }: { tone?: Tone; className?: string; children: ReactNode }) {
  return (
    <span
      className={cn(
        'inline-flex h-6 items-center rounded-full px-2.5 text-[12px] font-medium leading-none tracking-[0.01em]',
        tones[tone],
        className,
      )}
    >
      {children}
    </span>
  );
}

export function ComingSoon({ className }: { className?: string }) {
  return (
    <Badge tone="soon" className={className}>
      Coming soon
    </Badge>
  );
}
