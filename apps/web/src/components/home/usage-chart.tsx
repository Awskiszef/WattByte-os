// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

'use client';

import { useId } from 'react';
import { hourTicks, hourlyEnergyWh } from '@/config/demo-data';
import { cn } from '@/lib/cn';
import { useInView } from '@/lib/use-in-view';

type Props = {
  className?: string;
  /** Compact variant for the phone mockup: no axis labels. */
  compact?: boolean;
  tone?: 'energy' | 'data';
};

const W = 600;
const H = 200;
const PAD_X = 8;
const PAD_TOP = 14;
const PAD_BOTTOM = 26;

function buildPaths(values: readonly number[]) {
  const max = Math.max(...values);
  const n = values.length;
  const innerW = W - PAD_X * 2;
  const innerH = H - PAD_TOP - PAD_BOTTOM;
  const pts = values.map((v, i) => [PAD_X + (i / (n - 1)) * innerW, PAD_TOP + innerH - (v / max) * innerH] as const);
  // Smooth with a Catmull-Rom to cubic Bezier conversion.
  let d = `M ${pts[0]![0]} ${pts[0]![1]}`;
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = pts[Math.max(0, i - 1)]!;
    const p1 = pts[i]!;
    const p2 = pts[i + 1]!;
    const p3 = pts[Math.min(pts.length - 1, i + 2)]!;
    const c1x = p1[0] + (p2[0] - p0[0]) / 6;
    const c1y = p1[1] + (p2[1] - p0[1]) / 6;
    const c2x = p2[0] - (p3[0] - p1[0]) / 6;
    const c2y = p2[1] - (p3[1] - p1[1]) / 6;
    d += ` C ${c1x.toFixed(1)} ${c1y.toFixed(1)}, ${c2x.toFixed(1)} ${c2y.toFixed(1)}, ${p2[0].toFixed(1)} ${p2[1].toFixed(1)}`;
  }
  const area = `${d} L ${pts[pts.length - 1]![0]} ${PAD_TOP + innerH} L ${pts[0]![0]} ${PAD_TOP + innerH} Z`;
  const peak = pts.reduce((best, p) => (p[1] < best[1] ? p : best), pts[0]!);
  return { line: d, area, peak };
}

const paths = buildPaths(hourlyEnergyWh);
const peakHour = (hourlyEnergyWh as readonly number[]).indexOf(Math.max(...hourlyEnergyWh));
const peakValue = Math.max(...hourlyEnergyWh);

/** Energy drawn through the day. The line draws itself when it scrolls into view. */
export function UsageChart({ className, compact, tone = 'energy' }: Props) {
  const { ref, inView } = useInView<HTMLDivElement>();
  const id = useId();
  const color = tone === 'energy' ? 'var(--energy)' : 'var(--data)';

  return (
    <div ref={ref} className={cn('w-full', className)}>
      <svg
        viewBox={`0 0 ${W} ${H}`}
        className="h-auto w-full overflow-visible"
        role="img"
        aria-label={`Energy used through the day, peaking at ${peakValue} watt-hours around ${String(peakHour).padStart(2, '0')}:00.`}
      >
        <defs>
          <linearGradient id={`${id}-fill`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={color} stopOpacity="0.28" />
            <stop offset="100%" stopColor={color} stopOpacity="0" />
          </linearGradient>
        </defs>

        {/* baseline + hour grid */}
        {hourTicks.map((label, i) => {
          const x = PAD_X + (i / (hourTicks.length - 1)) * (W - PAD_X * 2);
          return (
            <g key={label}>
              <line x1={x} x2={x} y1={PAD_TOP} y2={H - PAD_BOTTOM} stroke="var(--border)" strokeWidth="1" strokeDasharray="2 4" />
              {!compact ? (
                <text x={x} y={H - 6} textAnchor={i === 0 ? 'start' : i === hourTicks.length - 1 ? 'end' : 'middle'} fontSize="11" fill="var(--fg-subtle)" className="tabular">
                  {label}
                </text>
              ) : null}
            </g>
          );
        })}
        <line x1={PAD_X} x2={W - PAD_X} y1={H - PAD_BOTTOM} y2={H - PAD_BOTTOM} stroke="var(--border-strong)" strokeWidth="1" />

        <path
          d={paths.area}
          fill={`url(#${id}-fill)`}
          style={{ opacity: inView ? 1 : 0, transition: 'opacity 0.8s ease 0.9s' }}
        />
        <path
          d={paths.line}
          fill="none"
          stroke={color}
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          pathLength={1}
          style={{
            strokeDasharray: 1,
            strokeDashoffset: inView ? 0 : 1,
            transition: 'stroke-dashoffset 1.6s cubic-bezier(0.22, 1, 0.36, 1)',
          }}
        />
        <g style={{ opacity: inView ? 1 : 0, transition: 'opacity 0.4s ease 1.4s' }}>
          <circle cx={paths.peak[0]} cy={paths.peak[1]} r="4" fill={color} />
          <circle cx={paths.peak[0]} cy={paths.peak[1]} r="9" fill={color} fillOpacity="0.18" />
          {!compact ? (
            <text x={paths.peak[0]} y={paths.peak[1] - 12} textAnchor="middle" fontSize="11" fill="var(--fg-muted)" className="tabular">
              {peakValue.toFixed(2)} Wh
            </text>
          ) : null}
        </g>
      </svg>
    </div>
  );
}
