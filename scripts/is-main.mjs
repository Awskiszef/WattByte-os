// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// True when the module whose `import.meta.url` is passed in is the entry point of this process.
//
// Both sides go through realpath: `process.argv[1]` is the path as typed (a symlink, a relative path, a path
// through /var -> /private/var on macOS) while `import.meta.url` is already the resolved file, so comparing them
// textually made a script launched through a symlink silently do nothing and exit 0 (C-10, E-13).
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export function isMainModule(importMetaUrl, argv1 = process.argv[1]) {
  if (!argv1) return false;
  try {
    return realpathSync(argv1) === realpathSync(fileURLToPath(importMetaUrl));
  } catch {
    return false;
  }
}
