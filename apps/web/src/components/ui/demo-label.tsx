// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { demoDisclaimer } from '@/config/site';
import { cn } from '@/lib/cn';

/** Every mockup carries this so no reader mistakes the numbers for a real account. */
export function DemoLabel({ className }: { className?: string }) {
  return <p className={cn('text-xs text-fg-subtle', className)}>{demoDisclaimer}</p>;
}
