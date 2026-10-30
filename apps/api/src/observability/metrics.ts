// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { createHash, timingSafeEqual } from 'node:crypto';

/**
 * Minimal in-process request metrics in the Prometheus text format (B-12). Label values are route TEMPLATES
 * (`/api/v1/devices/:id`), method and status code: a bounded set. Never a raw URL, query, header, user id or address.
 * One process only; with several instances the scraper adds them up.
 */

/** Seconds. Chosen around the API's typical latencies (a login hashes a password: tens of milliseconds). */
export const DURATION_BUCKETS_S = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10];

interface Histogram {
  buckets: number[];
  sum: number;
  count: number;
}

const escapeLabel = (v: string): string => v.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n');

export class Metrics {
  private readonly requests = new Map<string, number>();
  private readonly durations = new Map<string, Histogram>();
  private readonly startedAt = Date.now();

  constructor(
    private readonly options: { version: string; gauges?: () => Array<{ name: string; help: string; value: number; labels?: Record<string, string> }> },
  ) {}

  record(method: string, route: string, status: number, seconds: number): void {
    const key = `${method}\0${route}\0${status}`;
    this.requests.set(key, (this.requests.get(key) ?? 0) + 1);
    const hKey = `${method}\0${route}`;
    let h = this.durations.get(hKey);
    if (!h) {
      h = { buckets: DURATION_BUCKETS_S.map(() => 0), sum: 0, count: 0 };
      this.durations.set(hKey, h);
    }
    const hist = h;
    DURATION_BUCKETS_S.forEach((le, i) => {
      if (seconds <= le) hist.buckets[i] = (hist.buckets[i] ?? 0) + 1;
    });
    h.sum += seconds;
    h.count += 1;
  }

  render(): string {
    const out: string[] = [];
    out.push('# HELP wattbyte_build_info Version of the running build.', '# TYPE wattbyte_build_info gauge');
    out.push(`wattbyte_build_info{version="${escapeLabel(this.options.version)}"} 1`);
    out.push('# HELP wattbyte_uptime_seconds Seconds since the process started.', '# TYPE wattbyte_uptime_seconds gauge');
    out.push(`wattbyte_uptime_seconds ${Math.round((Date.now() - this.startedAt) / 1000)}`);
    out.push('# HELP wattbyte_process_resident_memory_bytes Resident set size.', '# TYPE wattbyte_process_resident_memory_bytes gauge');
    out.push(`wattbyte_process_resident_memory_bytes ${process.memoryUsage().rss}`);

    for (const g of this.options.gauges?.() ?? []) {
      out.push(`# HELP ${g.name} ${g.help}`, `# TYPE ${g.name} gauge`);
      const labels = Object.entries(g.labels ?? {}).map(([k, v]) => `${k}="${escapeLabel(v)}"`).join(',');
      out.push(`${g.name}${labels ? `{${labels}}` : ''} ${g.value}`);
    }

    out.push('# HELP wattbyte_http_requests_total Requests answered, by method, route template and status code.', '# TYPE wattbyte_http_requests_total counter');
    for (const [key, n] of [...this.requests].sort(([a], [b]) => a.localeCompare(b))) {
      const [method = '', route = '', status = ''] = key.split('\0');
      out.push(`wattbyte_http_requests_total{method="${method}",route="${escapeLabel(route)}",status="${status}"} ${n}`);
    }

    out.push('# HELP wattbyte_http_request_duration_seconds Time to answer, by method and route template.', '# TYPE wattbyte_http_request_duration_seconds histogram');
    for (const [key, h] of [...this.durations].sort(([a], [b]) => a.localeCompare(b))) {
      const [method = '', route = ''] = key.split('\0');
      const base = `method="${method}",route="${escapeLabel(route)}"`;
      DURATION_BUCKETS_S.forEach((le, i) => out.push(`wattbyte_http_request_duration_seconds_bucket{${base},le="${le}"} ${h.buckets[i]}`));
      out.push(`wattbyte_http_request_duration_seconds_bucket{${base},le="+Inf"} ${h.count}`);
      out.push(`wattbyte_http_request_duration_seconds_sum{${base}} ${h.sum}`);
      out.push(`wattbyte_http_request_duration_seconds_count{${base}} ${h.count}`);
    }
    return `${out.join('\n')}\n`;
  }
}

/** Constant-time `Authorization: Bearer <token>` check (both sides hashed first so the length does not leak). */
export function bearerMatches(header: string | undefined, token: string): boolean {
  const presented = header?.startsWith('Bearer ') ? header.slice(7) : '';
  const a = createHash('sha256').update(presented).digest();
  const b = createHash('sha256').update(token).digest();
  return timingSafeEqual(a, b) && presented.length > 0;
}
