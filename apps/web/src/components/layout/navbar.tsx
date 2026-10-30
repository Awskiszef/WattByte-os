// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

'use client';

import { Menu, X } from 'lucide-react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useEffect, useId, useState } from 'react';
import { mainNav, navActions } from '@/config/navigation';
import { cn } from '@/lib/cn';
import { Logo } from './logo';
import { ThemeToggle } from './theme-toggle';
import { ButtonLink } from '@/components/ui/button';

export function Navbar() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);
  const pathname = usePathname();
  const menuId = useId();

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  // Lock body scroll while the menu is open; links close it themselves.
  useEffect(() => {
    document.body.style.overflow = open ? 'hidden' : '';
    return () => {
      document.body.style.overflow = '';
    };
  }, [open]);
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false);
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open]);

  const isActive = (href: string) => (href.startsWith('/#') ? false : pathname === href);

  return (
    <header
      className={cn(
        'fixed inset-x-0 top-0 z-50 transition-[background-color,border-color,backdrop-filter] duration-300',
        scrolled || open ? 'border-b border-border bg-bg/80 backdrop-blur-xl' : 'border-b border-transparent bg-transparent',
      )}
    >
      <nav className="container-x flex h-16 items-center justify-between" aria-label="Main">
        <Logo />

        <ul className="hidden items-center gap-1 lg:flex">
          {mainNav.map((item) => (
            <li key={item.label}>
              <Link
                href={item.href}
                aria-current={isActive(item.href) ? 'page' : undefined}
                className={cn(
                  'rounded-md px-3 py-2 text-sm transition-colors hover:text-fg',
                  isActive(item.href) ? 'text-fg' : 'text-fg-muted',
                )}
              >
                {item.label}
              </Link>
            </li>
          ))}
        </ul>

        <div className="hidden items-center gap-2 lg:flex">
          <ThemeToggle />
          <ButtonLink href={navActions.signIn.href} variant="ghost">
            {navActions.signIn.label}
          </ButtonLink>
          <ButtonLink href={navActions.download.href}>{navActions.download.label}</ButtonLink>
        </div>

        <div className="flex items-center gap-1 lg:hidden">
          <ThemeToggle />
          <button
            type="button"
            className="inline-flex h-10 w-10 items-center justify-center rounded-md text-fg"
            aria-expanded={open}
            aria-controls={menuId}
            aria-label={open ? 'Close menu' : 'Open menu'}
            onClick={() => setOpen((v) => !v)}
          >
            {open ? <X className="h-5 w-5" aria-hidden="true" /> : <Menu className="h-5 w-5" aria-hidden="true" />}
          </button>
        </div>
      </nav>

      <div
        id={menuId}
        className={cn(
          'lg:hidden overflow-hidden transition-[max-height,opacity] duration-300 ease-out-quint',
          open ? 'max-h-[calc(100dvh-4rem)] opacity-100' : 'pointer-events-none max-h-0 opacity-0',
        )}
        aria-hidden={!open}
      >
        <div className="container-x flex max-h-[calc(100dvh-4rem)] flex-col overflow-y-auto pb-6 pt-2">
          <ul className="flex flex-col">
            {mainNav.map((item, i) => (
              <li
                key={item.label}
                className={cn('transition-[opacity,transform] duration-300 ease-out-quint', open ? 'translate-y-0 opacity-100' : '-translate-y-1 opacity-0')}
                style={{ transitionDelay: open ? `${40 + i * 30}ms` : '0ms' }}
              >
                <Link
                  href={item.href}
                  tabIndex={open ? 0 : -1}
                  onClick={() => setOpen(false)}
                  className="block rounded-md px-2 py-3 text-lg font-medium text-fg hover:bg-surface"
                >
                  {item.label}
                </Link>
              </li>
            ))}
          </ul>
          <div className="mt-4 flex flex-col gap-2 border-t border-border pt-4">
            <ButtonLink href={navActions.download.href} size="lg" tabIndex={open ? 0 : -1} onClick={() => setOpen(false)}>
              {navActions.download.label}
            </ButtonLink>
            <ButtonLink href={navActions.signIn.href} variant="secondary" size="lg" tabIndex={open ? 0 : -1} onClick={() => setOpen(false)}>
              {navActions.signIn.label}
            </ButtonLink>
          </div>
        </div>
      </div>
    </header>
  );
}
