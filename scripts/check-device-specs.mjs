// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// The device catalog lives in packages/device-specs/src/devices.json; the Flutter
// app bundles a copy at apps/mobile/assets/device_specs/devices.json. They must
// be byte-identical (CI runs this after `pnpm device-specs:sync`).
import { copyFileSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = path.join(root, 'packages', 'device-specs', 'src', 'devices.json');
const copy = path.join(root, 'apps', 'mobile', 'assets', 'device_specs', 'devices.json');

if (process.argv.includes('--sync')) {
  copyFileSync(source, copy);
  console.warn(`copied ${source} -> ${copy}`);
} else if (readFileSync(source, 'utf8') !== readFileSync(copy, 'utf8')) {
  console.error(`device catalog drift: run "pnpm device-specs:sync" (${copy} differs from ${source})`);
  process.exit(1);
}
