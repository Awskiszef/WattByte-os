// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { defineCloudflareConfig } from '@opennextjs/cloudflare';
import kvIncrementalCache from '@opennextjs/cloudflare/overrides/incremental-cache/kv-incremental-cache';
import memoryQueue from '@opennextjs/cloudflare/overrides/queue/memory-queue';

/**
 * Cloudflare Workers build of the site (see README "Deployment").
 * The home page is ISR (the Eurostat price is fetched with `revalidate: 86400`),
 * so the prerendered pages and the fetch cache live in the Workers KV namespace
 * bound as NEXT_INC_CACHE_KV; revalidations run through the in-memory queue,
 * which calls the Worker back over the WORKER_SELF_REFERENCE service binding.
 */
export default defineCloudflareConfig({
  incrementalCache: kvIncrementalCache,
  queue: memoryQueue,
});
