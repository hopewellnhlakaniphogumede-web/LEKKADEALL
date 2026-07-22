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
