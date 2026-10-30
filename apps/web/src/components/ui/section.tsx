// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import type { ComponentProps } from 'react';
import { cn } from '@/lib/cn';

/** A page section with the standard vertical rhythm. Pass `tight` for shorter sections. */
export function Section({ className, tight, children, ...rest }: ComponentProps<'section'> & { tight?: boolean }) {
  return (
    <section className={cn(tight ? 'py-16 sm:py-20' : 'py-20 sm:py-28 lg:py-32', className)} {...rest}>
      {children}
    </section>
  );
}
