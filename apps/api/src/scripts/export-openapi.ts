import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { AI_PROVIDER_IDS, AIGateway, MockProvider, ProviderRouter } from '@wattbyte/ai';

import { buildApp } from '../app.js';
import { loadEnv } from '../config/env.js';
import { MemoryRepositories } from '../database/memory.js';

/**
 * Writes packages/contracts/openapi/openapi.json from the live route schemas.
 * The Dart client is generated from that file (scripts/generate-dart-client.mjs).
 */
async function main(): Promise<void> {
  const env = loadEnv({ NODE_ENV: 'test', JWT_SECRET: 'openapi-export-only-secret-not-used-anywhere' });
  const providers = AI_PROVIDER_IDS.map((id) => new MockProvider(id));
  const app = await buildApp({
    env,
    repos: new MemoryRepositories(),
    gateway: new AIGateway({ router: new ProviderRouter(providers) }),
    providerIds: [],
    logger: false,
  });
  await app.ready();
  const spec = app.swagger();
  await app.close();

  const here = path.dirname(fileURLToPath(import.meta.url));
  const out = path.resolve(here, '../../../../packages/contracts/openapi/openapi.json');
  await mkdir(path.dirname(out), { recursive: true });
  await writeFile(out, JSON.stringify(spec, null, 2) + '\n');
  console.warn(`wrote ${out} (${Object.keys(spec.paths ?? {}).length} paths)`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
