import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  assertLocalDockerConfiguration,
  assertLoopbackUrl,
  parseSupabaseStatusEnv,
} from './e2e/support/local-environment.mjs';
import { LOCAL_SIGNUP_COMPLETION_INTERVAL_MS } from './e2e/support/journey-helpers.mjs';
import { ALLOWED_MARKETPLACE_RPCS } from './e2e/support/network-policy.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const frontendRoot = resolve(here, '..');
const repositoryRoot = resolve(frontendRoot, '../..');

test('Ticket 9A-9 dependency is exact and existing Node test command remains', async () => {
  const packageJson = JSON.parse(await readFile(join(frontendRoot, 'package.json'), 'utf8'));
  assert.equal(packageJson.scripts.test, 'node --test tests/*.test.mjs');
  assert.equal(packageJson.scripts['test:e2e'], 'playwright test');
  assert.equal(packageJson.scripts['test:e2e:local'], 'node scripts/e2e/run-local.mjs');
  assert.equal(packageJson.devDependencies['@playwright/test'], '1.61.1');
});

test('loopback gate rejects remote URLs, embedded credentials, and remote Docker', () => {
  assert.equal(assertLoopbackUrl('http://127.0.0.1:54321', 'supabase').hostname, '127.0.0.1');
  assert.equal(assertLoopbackUrl('http://localhost:4173', 'frontend').hostname, 'localhost');
  assert.throws(() => assertLoopbackUrl('https://project.supabase.co', 'supabase'));
  assert.throws(() => assertLoopbackUrl('http://user:password@127.0.0.1:54322', 'database'));
  assert.throws(() => assertLocalDockerConfiguration({ DOCKER_HOST: 'ssh://remote.example.test' }));
  assert.doesNotThrow(() => assertLocalDockerConfiguration({ DOCKER_HOST: 'unix:///var/run/docker.sock' }));
});

test('Supabase status parser retains only local public values', () => {
  const result = parseSupabaseStatusEnv([
    'API_URL="http://127.0.0.1:54321"',
    'INBUCKET_URL="http://127.0.0.1:54324"',
    `ANON_KEY="${'a'.repeat(80)}"`,
    `SERVICE_ROLE_KEY="${'b'.repeat(80)}"`,
    'DB_URL="postgresql://postgres:password@127.0.0.1:54322/postgres"',
  ].join('\n'));
  assert.deepEqual(Object.keys(result).sort(), ['anonKey', 'apiUrl', 'inbucketUrl']);
  assert.equal(Object.values(result).some((value) => String(value).includes('postgresql://')), false);
  assert.equal(Object.values(result).some((value) => String(value).includes('b'.repeat(40))), false);
});

test('Playwright is Chromium-only, serial, retry-free, and artifact-free', async () => {
  const source = await readFile(join(frontendRoot, 'playwright.config.mjs'), 'utf8');
  assert.match(source, /workers:\s*1/);
  assert.match(source, /retries:\s*0/);
  assert.match(source, /browserName:\s*'chromium'/);
  assert.match(source, /screenshot:\s*'off'/);
  assert.match(source, /video:\s*'off'/);
  assert.match(source, /trace:\s*'off'/);
  assert.match(source, /preserveOutput:\s*'never'/);
  assert.doesNotMatch(source, /firefox|webkit|storageState|html|junit|har/iu);
});

test('long E2E security journeys have bounded time without retries or verbose diagnostics', async () => {
  const lifecycleSource = await readFile(join(here, 'e2e/customer-draft-lifecycle.spec.mjs'), 'utf8');
  const securitySource = await readFile(join(here, 'e2e/security-boundaries.spec.mjs'), 'utf8');
  const reporterSource = await readFile(join(here, 'e2e/support/privacy-safe-reporter.mjs'), 'utf8');
  assert.equal((lifecycleSource.match(/test\.setTimeout\(180_000\)/gu) ?? []).length, 1);
  assert.equal((securitySource.match(/test\.setTimeout\(180_000\)/gu) ?? []).length, 1);
  assert.equal((securitySource.match(/test\.setTimeout\(300_000\)/gu) ?? []).length, 1);
  assert.match(reporterSource, /timedOut:\s*'timeout'/);
  assert.match(reporterSource, /failed:\s*'assertion-or-runtime'/);
  assert.doesNotMatch(reporterSource, /result\.(?:error|errors|stdout|stderr)|message|stack|attachment/iu);
  assert.match(reporterSource, /guard-state:\(restricted\|suspended\|closed\|provider\|missing-profile\)/);
  assert.doesNotMatch(reporterSource, /step\.error\.(?:message|stack|name|cause)/iu);
});

test('local Auth signup pacing is measured after completed registration', async () => {
  const helperSource = await readFile(join(here, 'e2e/support/journey-helpers.mjs'), 'utf8');
  assert.equal(LOCAL_SIGNUP_COMPLETION_INTERVAL_MS, 1_500);
  assert.match(helperSource, /lastRegistrationCompletedAt = Date\.now\(\);/);
  assert.equal(
    helperSource.indexOf('lastRegistrationCompletedAt = Date.now();')
      > helperSource.indexOf("name: 'Your safe account view.'"),
    true,
  );
  assert.doesNotMatch(helperSource, /lastRegistrationAt/);
});

test('browser mutation and fixture boundaries are narrowly allowlisted', async () => {
  assert.deepEqual(ALLOWED_MARKETPLACE_RPCS, [
    'customer_create_draft_request',
    'customer_update_draft_request',
    'customer_cancel_draft_request',
  ]);
  const networkSource = await readFile(join(here, 'e2e/support/network-policy.mjs'), 'utf8');
  for (const token of [
    'direct-application-table-dml',
    'broad-column-select',
    'rpc-not-allowlisted',
    'non-loopback-request',
    'service-role-authorization',
  ]) assert.match(networkSource, new RegExp(token));

  const fixtureSource = await readFile(join(here, 'e2e/support/local-fixtures.mjs'), 'utf8');
  assert.match(fixtureSource, /supabase_db_lekkadeall-local/);
  assert.match(fixtureSource, /docker[\s\S]*exec/);
  assert.match(fixtureSource, /synthetic profile state mismatch/);
  assert.match(fixtureSource, /synthetic missing-profile invariant failed/);
  assert.match(fixtureSource, /synthetic request ownership invariant failed/);
  assert.match(fixtureSource, /synthetic Auth users are not distinct/);
  assert.doesNotMatch(fixtureSource, /SERVICE_ROLE_KEY|supabase\.co|postgresql:\/\//iu);
});

test('CI E2E job is isolated behind the complete database security job', async () => {
  const workflow = await readFile(join(repositoryRoot, '.github/workflows/database-tests.yml'), 'utf8');
  assert.match(workflow, /customer-draft-lifecycle-e2e:/);
  assert.match(workflow, /needs:\s*database-tests/);
  assert.match(workflow, /pnpm run test:e2e:local/);
  assert.match(workflow, /playwright install --with-deps chromium/);
  assert.doesNotMatch(workflow, /upload-artifact/);
});

test('E2E sign-out follows the implemented fail-closed sign-in redirect', async () => {
  const helperSource = await readFile(join(here, 'e2e/support/journey-helpers.mjs'), 'utf8');
  assert.equal(helperSource.includes('toHaveURL(/\\/auth\\/sign-in\\/?$/u)'), true);
  assert.match(helperSource, /getByRole\('heading', \{ name: 'Sign in to your workspace\.' \}\)/);
  assert.equal(helperSource.includes('toHaveURL(/\\/$/u)'), false);
});
