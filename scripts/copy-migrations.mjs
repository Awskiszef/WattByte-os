// tsc does not copy non-TypeScript files: the SQL migrations must sit next to dist/database/migrate.js,
// otherwise `node dist/database/migrate.js` (production deploys run the built output) finds no schema.
import { cpSync, existsSync, mkdirSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const from = path.join(root, 'apps', 'api', 'src', 'database', 'migrations');
const to = path.join(root, 'apps', 'api', 'dist', 'database', 'migrations');
if (!existsSync(from)) throw new Error(`missing ${from}`);
mkdirSync(to, { recursive: true });
cpSync(from, to, { recursive: true });
console.warn(`copied ${readdirSync(to).filter((f) => f.endsWith('.sql')).length} migrations to ${path.relative(root, to)}`);
