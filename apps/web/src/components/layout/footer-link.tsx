'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import type { ReactNode } from 'react';
import { cn } from '@/lib/cn';

/** A footer link that marks the page it points at as current. */
export function FooterLink({ href, children }: { href: string; children: ReactNode }) {
  const pathname = usePathname();
  const active = pathname === href.split('#')[0];
  return (
    <Link
      href={href}
      aria-current={active ? 'page' : undefined}
      className={cn('transition-colors hover:text-fg', active ? 'text-fg font-medium' : 'text-fg-muted')}
    >
      {children}
    </Link>
  );
}
