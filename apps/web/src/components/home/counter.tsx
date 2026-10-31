// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

'use client';

import { useEffect, useState } from 'react';
import { formatNumber } from '@/lib/format';
import { prefersReducedMotion, useInView } from '@/lib/use-in-view';

type Props = {
  value: number;
  fractionDigits?: number;
  /** Rendered before/after the number, outside the animated span. */
  prefix?: string;
  suffix?: string;
  durationMs?: number;
  className?: string;
  /** Start immediately instead of waiting for the viewport (hero). */
  immediate?: boolean;
};

/** Counts from 0 to `value` once, the first time it is seen. Static under reduced motion. */
export function Counter({ value, fractionDigits = 0, prefix, suffix, durationMs = 1100, className, immediate }: Props) {
  const { ref, inView } = useInView<HTMLSpanElement>();
  const [shown, setShown] = useState(0);
  const start = immediate || inView;

  useEffect(() => {
    if (!start) return;
    if (prefersReducedMotion()) {
      const timer = setTimeout(() => setShown(value), 0);
      return () => clearTimeout(timer);
    }
    let frame = 0;
    const t0 = performance.now();
    const tick = (now: number) => {
      const p = Math.min(1, (now - t0) / durationMs);
      const eased = 1 - Math.pow(1 - p, 4);
      setShown(value * eased);
      if (p < 1) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [start, value, durationMs]);

  return (
    <span ref={ref} className={className}>
      {prefix}
      <span className="tabular">{formatNumber(shown, fractionDigits)}</span>
      {suffix}
    </span>
  );
}
