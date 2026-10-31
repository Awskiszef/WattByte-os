// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import Link from 'next/link';
import { site } from '@/config/site';
import { cn } from '@/lib/cn';

export function LogoMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 32 32" className={cn('h-6 w-6', className)} aria-hidden="true" focusable="false">
      <rect x="2" y="2" width="28" height="28" rx="8" className="fill-fg" />
      <path d="M18.5 6.5 10 18h5.2l-1.7 7.5L22 13h-5.3z" className="fill-bg" />
    </svg>
  );
}

export function Logo({ className }: { className?: string }) {
  return (
    <Link href="/" className={cn('inline-flex items-center gap-2.5 rounded-md', className)} aria-label={`${site.name} home`}>
      <LogoMark />
      <span className="text-[17px] font-semibold tracking-[-0.02em] text-fg">{site.name}</span>
    </Link>
  );
}
