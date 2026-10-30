// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

/**
 * The hero background: a faint grid, a few energy (amber) and data (cyan)
 * flow lines and the points travelling along them. Pure SVG and CSS, no JS;
 * the motion stops under prefers-reduced-motion (see globals.css).
 */
export function FlowField({ className }: { className?: string }) {
  const lines = [
    { d: 'M -40 420 C 240 380, 420 300, 640 320 S 1040 420, 1300 360', tone: 'var(--energy)', dur: '14s', delay: '0s' },
    { d: 'M -40 520 C 300 560, 520 440, 760 470 S 1100 560, 1300 500', tone: 'var(--data)', dur: '18s', delay: '-6s' },
    { d: 'M -40 300 C 200 260, 480 200, 700 230 S 1060 300, 1300 250', tone: 'var(--data)', dur: '22s', delay: '-11s' },
    { d: 'M -40 620 C 260 600, 500 540, 820 580 S 1120 640, 1300 600', tone: 'var(--energy)', dur: '16s', delay: '-3s' },
  ];
  return (
    <svg viewBox="0 0 1260 760" preserveAspectRatio="xMidYMid slice" className={className} aria-hidden="true" focusable="false">
      <defs>
        <pattern id="about-grid" width="48" height="48" patternUnits="userSpaceOnUse">
          <path d="M 48 0 L 0 0 0 48" fill="none" stroke="var(--border)" strokeWidth="1" />
        </pattern>
        <radialGradient id="about-fade" cx="50%" cy="45%" r="60%">
          <stop offset="0%" stopColor="white" stopOpacity="1" />
          <stop offset="100%" stopColor="white" stopOpacity="0" />
        </radialGradient>
        <mask id="about-mask">
          <rect width="1260" height="760" fill="url(#about-fade)" />
        </mask>
      </defs>
      <g mask="url(#about-mask)">
        <rect width="1260" height="760" fill="url(#about-grid)" />
        {lines.map((l, i) => (
          <g key={i}>
            <path d={l.d} fill="none" stroke={l.tone} strokeOpacity="0.28" strokeWidth="1" />
            <circle r="3" fill={l.tone}>
              <animateMotion dur={l.dur} begin={l.delay} repeatCount="indefinite" path={l.d} />
            </circle>
            <circle r="8" fill={l.tone} fillOpacity="0.16">
              <animateMotion dur={l.dur} begin={l.delay} repeatCount="indefinite" path={l.d} />
            </circle>
          </g>
        ))}
      </g>
    </svg>
  );
}
