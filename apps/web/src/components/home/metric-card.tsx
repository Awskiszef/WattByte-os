import type { ReactNode } from 'react';
import { cn } from '@/lib/cn';

type Props = {
  label: string;
  value: ReactNode;
  unit?: string;
  tone?: 'energy' | 'data' | 'neutral';
  hint?: string;
  className?: string;
};

export function MetricCard({ label, value, unit, tone = 'neutral', hint, className }: Props) {
  return (
    <div className={cn('rounded-lg border border-border bg-bg-elevated p-4 sm:p-5', className)}>
      <p className="text-xs text-fg-subtle">{label}</p>
      <p
        className={cn(
          'mt-2 text-2xl font-semibold tracking-[-0.02em] sm:text-[1.75rem]',
          tone === 'energy' && 'text-energy',
          tone === 'data' && 'text-data',
        )}
      >
        {value}
        {unit ? <span className="ml-1 text-sm font-normal text-fg-muted">{unit}</span> : null}
      </p>
      {hint ? <p className="mt-2 text-xs text-fg-subtle">{hint}</p> : null}
    </div>
  );
}
