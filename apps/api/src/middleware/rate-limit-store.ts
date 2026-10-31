// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

interface Entry {
  current: number;
  ttl: number;
  iterationStartMs: number;
}

type IncrCallback = (error: Error | null, result: { current: number; ttl: number }) => void;

/**
 * In-process fixed-window counter store for @fastify/rate-limit that, unlike its built-in one, can share ONE bucket
 * between several routes: routes whose rate-limit config carries the same `groupId` are served by the same counters,
 * so a client does not get a separate budget per route (A-02: register, login and the OAuth stubs are one budget).
 * Routes without a `groupId` keep a private bucket, as before.
 *
 * The state lives in this process: with several API instances each has its own counters, so the per-IP limit is per
 * instance. The brute-force defence that must hold across instances is the per-account throttle in the database
 * (modules/auth/login-throttle.ts); a limit shared by all instances for everything else needs an edge limiter or a
 * shared store (docs/CONFIGURATION.md).
 */
export class GroupedLocalStore {
  private readonly hits = new Map<string, Entry>();

  constructor(
    private readonly maxKeys = 50_000,
    private readonly groups: Map<string, GroupedLocalStore> = new Map(),
  ) {}

  incr(key: string, cb: IncrCallback, timeWindow: number): void {
    const now = Date.now();
    let entry = this.hits.get(key);
    if (!entry || entry.iterationStartMs + timeWindow <= now) {
      entry = { current: 1, ttl: timeWindow, iterationStartMs: now };
    } else {
      entry.current += 1;
      entry.ttl = timeWindow - (now - entry.iterationStartMs);
    }
    // Delete first so the key moves to the end of the insertion order (oldest-first eviction below).
    this.hits.delete(key);
    this.hits.set(key, entry);
    if (this.hits.size > this.maxKeys) this.evict(now, timeWindow);
    cb(null, { current: entry.current, ttl: entry.ttl });
  }

  /** Called by the plugin once per route that has its own rate-limit config. */
  child(routeOptions: { groupId?: string }): GroupedLocalStore {
    const group = routeOptions.groupId;
    if (!group) return new GroupedLocalStore(this.maxKeys, this.groups);
    let store = this.groups.get(group);
    if (!store) {
      store = new GroupedLocalStore(this.maxKeys, this.groups);
      this.groups.set(group, store);
    }
    return store;
  }

  /** Over the cap: drop expired counters first, then the oldest ones. Memory stays bounded whatever the key churn. */
  private evict(now: number, timeWindow: number): void {
    for (const [key, entry] of this.hits) {
      if (entry.iterationStartMs + timeWindow <= now) this.hits.delete(key);
    }
    for (const key of this.hits.keys()) {
      if (this.hits.size <= this.maxKeys) break;
      this.hits.delete(key);
    }
  }

  get size(): number {
    return this.hits.size;
  }
}
