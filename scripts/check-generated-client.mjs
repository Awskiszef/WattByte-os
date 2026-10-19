// Proves that the Dart client committed in apps/mobile/lib/generated/api is exactly what
// packages/contracts/openapi/openapi.json generates: nobody edited a generated file by hand and
// nobody changed the contracts without regenerating.
//
//   pnpm openapi && node scripts/check-generated-client.mjs        (or: pnpm dart-client:check)
//
// It regenerates the client into a TEMP directory, with the same generator, flags and formatting as
// scripts/generate-dart-client.mjs (keep the two in step), and compares it file by file with the
// committed one. The committed client is never touched.
//
// Exit codes: 0 identical, 1 drift (a readable summary is printed), 2 the check itself could not run
// (missing spec, Java or Dart, generator failure).
//
// Options: --full  print every differing line instead of the first lines of each file
//          --keep  keep the temp directory (its path is printed) to inspect the regenerated client
//          --spec=<file> and --committed=<dir>  compare other files than the repo's (used to test this script)
import { spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const option = (name) => process.argv.find((a) => a.startsWith(`--${name}=`))?.slice(name.length + 3);
const spec = option('spec') ?? path.join(root, 'packages', 'contracts', 'openapi', 'openapi.json');
const committed = option('committed') ?? path.join(root, 'apps', 'mobile', 'lib', 'generated', 'api');

const full = process.argv.includes('--full');
const keep = process.argv.includes('--keep');
/** Lines of unified diff shown per differing file (and files shown) unless --full. */
const LINES_PER_FILE = 40;
const FILES_SHOWN = 12;

// Same invocation as scripts/generate-dart-client.mjs.
const GENERATOR_ARGS = [
  '--yes',
  '@openapitools/openapi-generator-cli',
  'generate',
  '-i',
  'openapi.json',
  '-g',
  'dart',
  '-o',
  'out',
  '--additional-properties=pubName=wattbyte_api,pubLibrary=wattbyte_api',
  '--global-property=apis,models,supportingFiles',
];

/** A path as the repo knows it when it is inside the repo. */
const shown = (p) => (p.startsWith(root + path.sep) ? path.relative(root, p) : p);

/** The check itself could not run (as opposed to finding drift). Thrown so the temp directory is always removed. */
class CheckError extends Error {}

function fail(message) {
  throw new CheckError(message);
}

function run(command, args, cwd) {
  const res = spawnSync(command, args, { cwd, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (res.error) fail(`cannot run ${command}: ${res.error.message}`);
  return res;
}

function listFiles(dir) {
  const out = [];
  const walk = (current) => {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      if (entry.name === '.DS_Store') continue;
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (statSync(full).isFile()) out.push(path.relative(dir, full).split(path.sep).join('/'));
    }
  };
  walk(dir);
  return out.sort();
}

// The generator CLI mangles paths with spaces or non-ASCII characters, so it only ever sees an ASCII temp directory.
const work = mkdtempSync(path.join(tmpdir(), 'wattbyte-client-check-'));
let exitCode = 0;
try {
  if (!existsSync(spec)) fail(`missing ${spec}; run "pnpm openapi" first`);
  if (!existsSync(committed)) fail(`missing ${committed}; run "pnpm dart-client" first`);
  copyFileSync(spec, path.join(work, 'openapi.json'));

  const java = run('java', ['-version'], work);
  if (java.status !== 0) fail('Java is required (openapi-generator is a JVM tool) but "java -version" failed');

  const gen = run('npx', GENERATOR_ARGS, work);
  if (gen.status !== 0) fail(`openapi-generator failed (exit ${gen.status}):\n${gen.stdout}\n${gen.stderr}`);
  const regenerated = path.join(work, 'out', 'lib');
  if (!existsSync(regenerated)) fail(`the generator wrote no lib/ directory:\n${gen.stdout}\n${gen.stderr}`);

  // The committed client is formatted (so `dart format --set-exit-if-changed` stays green); format the same way.
  const fmt = run('dart', ['format', regenerated], work);
  if (fmt.status !== 0) fail(`dart format failed:\n${fmt.stdout}\n${fmt.stderr}`);

  const fresh = new Set(listFiles(regenerated));
  const old = new Set(listFiles(committed));
  const added = [...fresh].filter((f) => !old.has(f));
  const removed = [...old].filter((f) => !fresh.has(f));
  const changed = [...fresh].filter((f) => old.has(f) && !readFileSync(path.join(regenerated, f)).equals(readFileSync(path.join(committed, f))));

  if (added.length + removed.length + changed.length === 0) {
    console.warn(`generated Dart client is up to date: ${fresh.size} files identical to ${shown(committed)}`);
  } else {
    exitCode = 1;
    console.error(`generated Dart client DRIFT: ${shown(committed)} does not match ${shown(spec)}`);
    console.error(`  ${added.length} file(s) the spec generates but the repo lacks, ${removed.length} stale file(s) the spec no longer generates, ${changed.length} file(s) that differ`);
    const list = (title, files) => {
      if (files.length === 0) return;
      console.error(`\n${title}`);
      for (const f of files) console.error(`  ${f}`);
    };
    list('missing from the repo (run "pnpm dart-client"):', added);
    list('stale in the repo (run "pnpm dart-client"):', removed);
    list('differing:', changed);
    for (const f of full ? changed : changed.slice(0, FILES_SHOWN)) {
      // `diff -u` is on every machine that runs this repo's tooling; the committed file is the "-" side.
      const d = run('diff', ['-u', '--label', `committed/${f}`, '--label', `regenerated/${f}`, path.join(committed, f), path.join(regenerated, f)], work);
      const lines = d.stdout.split('\n');
      console.error(`\n--- ${f}`);
      console.error((full ? lines : lines.slice(0, LINES_PER_FILE)).join('\n'));
      if (!full && lines.length > LINES_PER_FILE) console.error(`  ... ${lines.length - LINES_PER_FILE} more diff line(s); use --full`);
    }
    if (!full && changed.length > FILES_SHOWN) console.error(`\n... and ${changed.length - FILES_SHOWN} more differing file(s); use --full`);
    console.error('\nFix: run "pnpm openapi && pnpm dart-client" and commit the result. Never edit lib/generated/api by hand.');
  }
  if (keep) console.warn(`regenerated client kept at ${regenerated}`);
} catch (e) {
  if (!(e instanceof CheckError)) throw e;
  console.error(`check-generated-client: ${e.message}`);
  exitCode = 2;
} finally {
  if (!keep) rmSync(work, { recursive: true, force: true });
}
process.exit(exitCode);
