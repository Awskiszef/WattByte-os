'use client';

import type { ReactNode } from 'react';
import { useEffect, useRef } from 'react';
import { prefersReducedMotion } from '@/lib/use-in-view';

/**
 * Tilts its child a few degrees toward the pointer. Desktop only (fine
 * pointer), nothing under reduced motion, and the transform is written to a
 * CSS variable so React does not re-render on every move.
 */
export function Tilt({ children, className }: { children: ReactNode; className?: string }) {
  const ref = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    if (prefersReducedMotion() || !window.matchMedia('(pointer: fine)').matches) return;

    const parent = el.parentElement ?? el;
    let raf = 0;
    const move = (e: PointerEvent) => {
      const r = parent.getBoundingClientRect();
      const x = (e.clientX - r.left) / r.width - 0.5;
      const y = (e.clientY - r.top) / r.height - 0.5;
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(() => {
        el.style.setProperty('--ry', `${(x * 8).toFixed(2)}deg`);
        el.style.setProperty('--rx', `${(-y * 8).toFixed(2)}deg`);
      });
    };
    const leave = () => {
      cancelAnimationFrame(raf);
      el.style.setProperty('--ry', '0deg');
      el.style.setProperty('--rx', '0deg');
    };
    parent.addEventListener('pointermove', move);
    parent.addEventListener('pointerleave', leave);
    return () => {
      parent.removeEventListener('pointermove', move);
      parent.removeEventListener('pointerleave', leave);
      cancelAnimationFrame(raf);
    };
  }, []);

  return (
    <div
      ref={ref}
      className={className}
      style={{
        transform: 'perspective(1200px) rotateX(var(--rx, 0deg)) rotateY(var(--ry, 0deg))',
        transition: 'transform 0.4s cubic-bezier(0.22, 1, 0.36, 1)',
        willChange: 'transform',
      }}
    >
      {children}
    </div>
  );
}
