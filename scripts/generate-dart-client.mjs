// Generates the Dart API client from packages/contracts/openapi/openapi.json
// into apps/mobile/lib/generated/api (plain Dart sources, no codegen step in
// the Flutter app). Requires Java (openapi-generator is a JVM tool).
//
//   pnpm openapi && pnpm dart-client
import { execSync } from 'node:child_process';
import { copyFileSync, cpSync, existsSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { postProcessClient } from './dart-client-postprocess.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const spec = path.join(root, 'packages', 'contracts', 'openapi', 'openapi.json');
const mobile = path.join(root, 'apps', 'mobile');
const target = path.join(mobile, 'lib', 'generated', 'api');

if (!existsSync(spec)) {
  console.error(`missing ${spec}; run "pnpm openapi" first`);
  process.exit(1);
}

// The generator CLI mangles paths with spaces or non-ASCII characters, so it
// only ever sees files inside an ASCII temp directory.
const work = mkdtempSync(path.join(tmpdir(), 'wattbyte-openapi-'));
const run = (cmd, cwd = work) => execSync(cmd, { stdio: 'inherit', cwd, shell: true });
try {
  const specCopy = path.join(work, 'openapi.json');
  copyFileSync(spec, specCopy);
  const out = path.join(work, 'out');
  run(
    `npx --yes @openapitools/openapi-generator-cli generate -i openapi.json -g dart -o out ` +
      '--additional-properties=pubName=wattbyte_api,pubLibrary=wattbyte_api,enumUnknownDefaultCase=true --global-property=apis,models,supportingFiles',
  );
  const rewritten = postProcessClient(path.join(out, 'lib'));
  console.warn(`enum decoders made tolerant: ${rewritten}`);
  rmSync(target, { recursive: true, force: true });
  cpSync(path.join(out, 'lib'), target, { recursive: true });
  // Generated code is formatted so `dart format --set-exit-if-changed` stays green.
  run('dart format lib/generated/api', mobile);
  console.warn(`generated Dart client in ${target}`);
} finally {
  rmSync(work, { recursive: true, force: true });
}
