// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// Post-processing shared by scripts/generate-dart-client.mjs and scripts/check-generated-client.mjs (the two must produce
// the same bytes).
//
// The generator can add an `unknownDefaultOpenApi` member to every enum (`enumUnknownDefaultCase=true`) but its decoder
// still returns null for a value it does not know, and the models read required enums with `!`: an installed app that
// meets a member added by a newer server (a new plan, a new source) died with a TypeError that is no Exception, in the
// middle of /auth/refresh among other places (audit E-03, G-08). Here an unknown value decodes to that member, so the
// response is read and the app decides what an unknown member means (see docs/API_COMPATIBILITY.md).
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const UNKNOWN_DEFAULT = /(return\s+)(\w+)(\.unknownDefaultOpenApi;)(\s*)default:\s*if \(!allowNull\) \{\s*throw ArgumentError\('Unknown enum value to decode: \$data'\);\s*\}/g;

/** Rewrites the enum decoders of every model under `<libDir>/model`; returns how many decoders were changed. */
export function postProcessClient(libDir) {
  const modelDir = path.join(libDir, 'model');
  let changed = 0;
  for (const name of readdirSync(modelDir)) {
    if (!name.endsWith('.dart')) continue;
    const file = path.join(modelDir, name);
    const before = readFileSync(file, 'utf8');
    const after = before.replace(UNKNOWN_DEFAULT, (_m, ret, type, tail, ws) => {
      changed += 1;
      return `${ret}${type}${tail}${ws}default:\n          // A member this client does not know (added by a newer server).\n          return ${type}.unknownDefaultOpenApi;`;
    });
    if (after !== before) writeFileSync(file, after);
  }
  return changed;
}
