// node --test scripts/ci-changes.test.mjs
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { decide, factsFor, TZ_SENSITIVE } from './ci-changes.mjs';

const pr = (files, extra = {}) => decide(files, { event: 'pull_request', ...extra });
const JOBS = ['ts', 'web', 'api_production', 'contracts', 'flutter_static', 'flutter_test', 'e2e', 'android', 'kotlin', 'ios'];
const on = (d) => JOBS.filter((j) => d[j]);

describe('documentation-only changes', () => {
  it('need nothing beyond hygiene', () => {
    const d = pr(['docs/CI_CD.md', 'README.md', 'LICENSE', 'apps/mobile/README.md', 'apps/web/README.md', '.github/CODEOWNERS']);
    assert.equal(d.docs_only, true);
    assert.deepEqual(on(d), []);
  });
  it('a markdown file inside an app does not switch the app on', () => {
    assert.deepEqual(on(pr(['apps/mobile/README.md'])), []);
  });
  it('scripts that hygiene unit-tests need nothing more; the Dart client generator reaches the app', () => {
    assert.deepEqual(on(pr(['scripts/check-docs.mjs', 'scripts/is-main.mjs'])), []);
    assert.equal(pr(['scripts/dart-client-postprocess.mjs']).flutter_static, true);
  });
  it('the public-release tooling and its overlay need nothing beyond hygiene and the Public Configuration Security Gate', () => {
    const d = pr(['scripts/check-public-config.mjs', 'scripts/public-config.allowlist.json', 'scripts/public-export.mjs', 'infrastructure/public-overlay/docs/README.md', 'infrastructure/public-overlay/apps/web/wrangler.example.jsonc']);
    assert.equal(d.docs_only, false, 'the web overlay is code');
    assert.deepEqual(on(d), ['web'], 'only the website overlay switches a job on');
    assert.deepEqual(on(pr(['scripts/check-public-config.test.mjs', 'infrastructure/public-overlay/docs/README.md', 'infrastructure/public-overlay/apps/web/.gitignore.append'])), ['web']);
    assert.deepEqual(on(pr(['scripts/check-public-config.mjs', 'infrastructure/public-overlay/docs/README.md'])), []);
    assert.equal(pr(['infrastructure/docker/docker-compose.yml']).ts_api, true, 'the rest of infrastructure/ still reaches the API');
  });
  it('one code file next to the docs is not documentation-only', () => {
    const d = pr(['docs/a.md', 'apps/web/src/x.tsx']);
    assert.equal(d.docs_only, false);
    assert.deepEqual(on(d), ['web']);
  });
});

describe('scoped (FAST) pull requests', () => {
  it('web only: web job, no Android, no iOS, no PostgreSQL work', () => {
    assert.deepEqual(on(pr(['apps/web/src/app/page.tsx'])), ['web']);
  });
  it('api only: TypeScript chain, API production build, contracts drift check, e2e; no mobile builds', () => {
    const d = pr(['apps/api/src/modules/auth/routes.ts']);
    assert.deepEqual(on(d), ['ts', 'api_production', 'contracts', 'e2e']);
    assert.match(d.ts_filters, /@wattbyte\/api/);
    assert.doesNotMatch(d.ts_filters, /@wattbyte\/ai/);
  });
  it('ai change reaches its dependents: contracts and api', () => {
    const d = pr(['apps/ai/src/gateway.ts']);
    for (const p of ['@wattbyte/ai', '@wattbyte/contracts', '@wattbyte/api']) assert.match(d.ts_filters, new RegExp(p));
    assert.equal(d.contracts, true);
  });
  it('device catalog reaches the API and the app', () => {
    const d = pr(['packages/device-specs/src/devices.json']);
    assert.equal(d.ts_api, true);
    assert.equal(d.flutter_test, true);
    assert.equal(d.android, true);
    assert.equal(d.contracts, true);
  });
  it('an OpenAPI change reaches the generated client and the app', () => {
    const d = pr(['packages/contracts/openapi/openapi.json']);
    assert.equal(d.contracts, true);
    assert.equal(d.flutter_static, true);
  });
  it('mobile Dart code: Flutter jobs and the Android debug build, one time zone, no macOS, no Kotlin', () => {
    const d = pr(['apps/mobile/lib/ui/home.dart']);
    assert.deepEqual(on(d), ['flutter_static', 'flutter_test', 'e2e', 'android']);
    assert.deepEqual(JSON.parse(d.tz_matrix), ['Europe/Warsaw']);
    assert.equal(d.android_full, false);
  });
  it('date and time code switches the whole time-zone matrix on', () => {
    const d = pr(['apps/mobile/lib/core/period.dart'], { tzTouched: true });
    assert.deepEqual(JSON.parse(d.tz_matrix), ['UTC', 'Europe/Warsaw', 'America/New_York']);
  });
  it('the time-zone heuristic matches date arithmetic and ignores plain UI code', () => {
    assert.match('final d = DateTime.now().toUtc();', TZ_SENSITIVE);
    assert.match('  tz: America/New_York  DST', TZ_SENSITIVE);
    assert.doesNotMatch('Text(label, style: theme.titleLarge)', TZ_SENSITIVE);
  });
  it('native Android files: full Android build and Kotlin tests', () => {
    const d = pr(['apps/mobile/packages/wattbyte_system/android/src/main/kotlin/A.kt']);
    assert.equal(d.android_full, true);
    assert.equal(d.kotlin, true);
    assert.equal(d.ios, false);
  });
  it('iOS files and the app dependencies: macOS runs, and Android native is rechecked for pubspec', () => {
    assert.equal(pr(['apps/mobile/ios/Runner/AppDelegate.swift']).ios, true);
    const d = pr(['apps/mobile/pubspec.lock']);
    assert.equal(d.ios, true);
    assert.equal(d.kotlin, true);
  });
  it('macOS never runs for a change that cannot reach iOS', () => {
    for (const f of ['apps/mobile/lib/a.dart', 'apps/api/src/a.ts', 'apps/web/src/a.tsx', 'docs/a.md']) assert.equal(pr([f]).ios, false, f);
  });
});

describe('shared inputs widen the scope', () => {
  it('the lockfile runs every TypeScript package on both Node versions', () => {
    const d = pr(['pnpm-lock.yaml']);
    assert.equal(d.web, true);
    assert.equal(d.ts_api, true);
    assert.deepEqual(JSON.parse(d.node_matrix), ['22', '24']);
    assert.equal(d.flutter_test, false);
  });
  it('a workflow change runs everything, including macOS', () => {
    const d = pr(['.github/workflows/ci.yml']);
    assert.equal(d.full, false);
    for (const j of JOBS) assert.equal(d[j], true, j);
  });
  it('a path no rule knows runs everything except macOS', () => {
    const d = pr(['brand-new-dir/file.txt']);
    for (const j of JOBS.filter((x) => x !== 'ios')) assert.equal(d[j], true, j);
    assert.equal(d.ios, false);
  });
  it('an unknown change set (no base commit) is not guessed at', () => {
    for (const j of JOBS.filter((x) => x !== 'ios')) assert.equal(decide(['<unknown change set>'], { event: 'push' })[j], true, j);
  });
});

describe('FULL pipeline', () => {
  it('schedule and manual runs are FULL: everything, three zones, two Node versions, macOS', () => {
    for (const event of ['schedule', 'workflow_dispatch']) {
      const d = decide(['x'], { event });
      assert.equal(d.full, true);
      for (const j of JOBS) assert.equal(d[j], true, `${event} ${j}`);
      assert.equal(JSON.parse(d.tz_matrix).length, 3);
      assert.deepEqual(JSON.parse(d.node_matrix), ['22', '24']);
      assert.equal(d.android_full, true);
    }
  });
  it('a single-component push to main still runs Node 24 and all time zones for what it touched (post-merge coverage)', () => {
    const app = decide(['apps/mobile/lib/ui/home.dart'], { event: 'push' });
    assert.equal(app.full, false);
    assert.equal(JSON.parse(app.tz_matrix).length, 3);
    assert.equal(app.ios, false);
    const ts = decide(['apps/api/src/a.ts'], { event: 'push' });
    assert.deepEqual(JSON.parse(ts.node_matrix), ['22', '24']);
    assert.deepEqual(JSON.parse(decide(['apps/web/src/a.tsx'], { event: 'push' }).tz_matrix), ['Europe/Warsaw']);
  });
  it('a push to main that spans components is FULL, a single-component push is not', () => {
    assert.equal(decide(['apps/api/src/a.ts', 'apps/mobile/lib/a.dart'], { event: 'push' }).full, true);
    assert.equal(decide(['apps/web/src/a.tsx'], { event: 'push' }).full, false);
  });
});

describe('facts', () => {
  it('an iOS file is also a mobile file; a markdown file is only documentation', () => {
    assert.deepEqual([...factsFor(['apps/mobile/ios/Runner/x.swift'])].sort(), ['ios', 'mobile']);
    assert.deepEqual([...factsFor(['apps/mobile/README.md'])], ['docs']);
  });
});
