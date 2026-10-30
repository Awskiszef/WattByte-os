// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { Sparkles } from 'lucide-react';
import { aiDemo, todayDemo } from '@/config/demo-data';
import { cn } from '@/lib/cn';
import { Counter } from './counter';
import { Tilt } from './tilt';
import { UsageChart } from './usage-chart';

/**
 * The phone in the hero: a real-looking WattByte dashboard, built from HTML so
 * it can animate and respond to the theme instead of being a flat picture.
 */
export function AppPreview({ className }: { className?: string }) {
  return (
    <div className={cn('relative mx-auto w-full max-w-[300px] sm:max-w-[320px]', className)}>
      <Tilt>
        <div
          className="relative rounded-[2.6rem] border border-border-strong bg-phone p-[10px] shadow-[0_30px_80px_-30px_rgb(0_0_0/0.6)] dark:shadow-[0_40px_100px_-30px_rgb(240_179_91/0.12)]"
          aria-label="WattByte dashboard preview with example data"
          role="img"
        >
          {/* notch */}
          <div className="absolute left-1/2 top-[10px] z-10 h-[26px] w-[96px] -translate-x-1/2 rounded-b-[14px] bg-phone" />
          <div className="relative overflow-hidden rounded-[2rem] bg-bg text-fg">
            <div className="px-5 pb-5 pt-11">
              <div className="flex items-center justify-between text-[11px] text-fg-subtle">
                <span>Today</span>
                <span className="inline-flex items-center gap-1.5">
                  <span className="pulse-dot inline-block h-1.5 w-1.5 rounded-full bg-energy" aria-hidden="true" />
                  Collecting
                </span>
              </div>

              <div className="mt-4">
                <p className="text-[11px] font-medium text-fg-muted">Energy used</p>
                <p className="mt-1 text-[2.4rem] font-semibold leading-none tracking-[-0.03em]">
                  <Counter value={todayDemo.energyWh} fractionDigits={1} immediate /> <span className="text-xl text-fg-muted">Wh</span>
                </p>
                <p className="mt-2 text-xs text-fg-muted">
                  <Counter value={todayDemo.batteryMah} immediate /> mAh of battery, about <span className="text-fg">{todayDemo.costLabel}</span>
                </p>
              </div>

              <div className="mt-4 rounded-lg border border-border bg-surface/60 p-2.5">
                <UsageChart compact />
                <div className="mt-1 flex justify-between text-[9px] text-fg-subtle tabular">
                  <span>00:00</span>
                  <span>12:00</span>
                  <span>24:00</span>
                </div>
              </div>

              <div className="mt-3 grid grid-cols-2 gap-2">
                <div className="rounded-lg border border-border p-3">
                  <p className="text-[10px] text-fg-subtle">Mobile data</p>
                  <p className="mt-1 text-lg font-semibold tracking-[-0.02em]">
                    <Counter value={todayDemo.mobileGb} fractionDigits={1} immediate /> <span className="text-xs text-fg-muted">GB</span>
                  </p>
                  <div className="mt-2 h-1 overflow-hidden rounded-full bg-surface-2">
                    <div className="h-full w-[13%] rounded-full bg-data" />
                  </div>
                </div>
                <div className="rounded-lg border border-border p-3">
                  <p className="text-[10px] text-fg-subtle">Wi-Fi</p>
                  <p className="mt-1 text-lg font-semibold tracking-[-0.02em]">
                    <Counter value={todayDemo.wifiGb} fractionDigits={1} immediate /> <span className="text-xs text-fg-muted">GB</span>
                  </p>
                  <div className="mt-2 h-1 overflow-hidden rounded-full bg-surface-2">
                    <div className="h-full w-[87%] rounded-full bg-data" />
                  </div>
                </div>
              </div>

              <div className="mt-3 rounded-lg border border-border bg-surface/60 p-3">
                <p className="inline-flex items-center gap-1.5 text-[10px] font-medium text-fg-muted">
                  <Sparkles className="h-3 w-3 text-energy" aria-hidden="true" />
                  Insight
                </p>
                <p className="mt-1.5 text-[11.5px] leading-snug text-fg">{aiDemo.answer}</p>
              </div>

              <div className="mt-4 flex items-center justify-around border-t border-border pt-3 text-[9px] text-fg-subtle">
                <span className="text-fg">Dashboard</span>
                <span>History</span>
                <span>Insights</span>
                <span>Settings</span>
              </div>
            </div>
          </div>
        </div>
      </Tilt>
    </div>
  );
}
