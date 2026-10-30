// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { cn } from '@/lib/cn';

/** The small capitalised line the About brief asks for above three of its headings. */
export function Eyebrow({ children, className }: { children: string; className?: string }) {
  return <p className={cn('text-[12px] font-medium uppercase tracking-[0.12em] text-fg-subtle', className)}>{children}</p>;
}
