import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  assertLocalDockerConfiguration,
  assertLoopbackUrl,
  parseLocalFixtureAdminEnv,
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

test('local fixture admin parser accepts only a loopback service-role boundary', () => {
  const serviceKey = [
    Buffer.from('{}').toString('base64url'),
    Buffer.from('{"role":"service_role"}').toString('base64url'),
    's'.repeat(48),
  ].join('.');
  const result = parseLocalFixtureAdminEnv([
    'API_URL="http://127.0.0.1:54321"',
    `SERVICE_ROLE_KEY="${serviceKey}"`,
    `ANON_KEY="${'a'.repeat(80)}"`,
    'DB_URL="postgresql://postgres:password@127.0.0.1:54322/postgres"',
  ].join('\n'));
  assert.deepEqual(Object.keys(result).sort(), ['adminKey', 'apiUrl']);
  assert.equal(result.adminKey, serviceKey);
  assert.throws(() => parseLocalFixtureAdminEnv([
    'API_URL="https://project.supabase.co"',
    `SERVICE_ROLE_KEY="${serviceKey}"`,
  ].join('\n')));
  assert.throws(() => parseLocalFixtureAdminEnv([
    'API_URL="http://127.0.0.1:54321"',
    `SERVICE_ROLE_KEY="${'a'.repeat(80)}"`,
  ].join('\n')));
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
  assert.equal((lifecycleSource.match(/test\.setTimeout\(300_000\)/gu) ?? []).length, 1);
  assert.equal((securitySource.match(/test\.setTimeout\(180_000\)/gu) ?? []).length, 3);
  assert.equal((securitySource.match(/test\.setTimeout\(600_000\)/gu) ?? []).length, 1);
  assert.match(reporterSource, /timedOut:\s*'timeout'/);
  assert.match(reporterSource, /failed:\s*'assertion-or-runtime'/);
  assert.doesNotMatch(reporterSource, /result\.(?:error|errors|stdout|stderr)|message|stack|attachment/iu);
  assert.match(reporterSource, /guard-state:\(restricted\|suspended\|closed\|provider\|missing-profile\)/);
  assert.match(reporterSource, /guard-phase:\(restricted\|suspended\|closed\|provider\|missing-profile\)/);
  assert.match(reporterSource, /lifecycle-phase:\(registration\|reauthentication\|category-dashboard\|create\|list-detail\|update\|cancel\|postcondition\|sign-out\)/);
  assert.match(reporterSource, /registration-phase:\(signup-request\|auth-session\|profile-ready\|dashboard\)/);
  assert.match(reporterSource, /registration-failure:\(signup-http-429\|signup-http-conflict\|signup-http-other\|signup-session-missing\|profile-readiness-timeout\|signup-network-failure\)/);
  assert.doesNotMatch(reporterSource, /step\.error\.(?:message|stack|name|cause)/iu);
});

test('local Auth registration uses run-scoped identity and explicit readiness conditions', async () => {
  const helperSource = await readFile(join(here, 'e2e/support/journey-helpers.mjs'), 'utf8');
  const runnerSource = await readFile(join(frontendRoot, 'scripts/e2e/run-local.mjs'), 'utf8');
  const authConfig = await readFile(
    join(repositoryRoot, 'outputs/marketplace-production-foundation/supabase/config.toml'),
    'utf8',
  );
  assert.match(runnerSource, /const runId = randomBytes\(8\)\.toString\('hex'\)/);
  assert.match(runnerSource, /E2E_RUN_ID:\s*runId/);
  assert.match(runnerSource, /\['db', 'reset'\]/);
  assert.match(runnerSource, /\['stop', '--no-backup'\]/);
  assert.match(runnerSource, /e2e-refuses-preexisting-supabase-stack/);
  assert.match(helperSource, /process\.env\.E2E_RUN_ID/);
  assert.match(helperSource, /registration-phase:signup-request/);
  assert.match(helperSource, /registration-phase:auth-session/);
  assert.match(helperSource, /registration-phase:profile-ready/);
  assert.match(helperSource, /registration-phase:dashboard/);
  assert.match(helperSource, /waitForResponse/);
  assert.match(helperSource, /expect\.poll/);
  assert.match(helperSource, /waitForProvisionedCustomerProfile/);
  assert.doesNotMatch(helperSource, /lastRegistration(?:At|CompletedAt)|respectLocalSignupRateLimit/);
  assert.match(authConfig, /\[auth\.email\][\s\S]*enable_confirmations\s*=\s*false/u);
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
  assert.match(fixtureSource, /synthetic profile post-route mismatch/);
  assert.match(fixtureSource, /synthetic missing-profile invariant failed/);
  assert.match(fixtureSource, /synthetic missing-profile post-route mismatch/);
  assert.match(fixtureSource, /ticket-9b-profile-readiness-timeout/);
  assert.match(fixtureSource, /\/auth\/v1\/admin\/users/);
  assert.match(fixtureSource, /E2E_LOCAL_FIXTURE_ADMIN_KEY/);
  assert.match(fixtureSource, /waitForProvisionedCustomerProfile\(email\)/);
  assert.match(fixtureSource, /synthetic request ownership invariant failed/);
  assert.match(fixtureSource, /synthetic Auth users are not distinct/);
  assert.doesNotMatch(fixtureSource, /SERVICE_ROLE_KEY|supabase\.co|postgresql:\/\//iu);
});

test('only lifecycle and cross-customer B use UI signup; setup-only actors use fixture sign-in', async () => {
  const blockedSource = await readFile(join(here, 'e2e/blocked-features.spec.mjs'), 'utf8');
  const lifecycleSource = await readFile(join(here, 'e2e/customer-draft-lifecycle.spec.mjs'), 'utf8');
  const securitySource = await readFile(join(here, 'e2e/security-boundaries.spec.mjs'), 'utf8');
  assert.equal((
    `${blockedSource}\n${lifecycleSource}\n${securitySource}`.match(/registerCustomer\(/gu) ?? []
  ).length, 2);
  assert.match(
    securitySource,
    /prepareSyntheticCustomerAccount\(customerA\.email, customerA\.password\)[\s\S]*signInCustomer\(pageA, customerA\)[\s\S]*registerCustomer\(pageB, customerB\)/u,
  );
  assert.match(
    securitySource,
    /guard-phase:\$\{scenario\.label\}:registration[\s\S]*prepareSyntheticCustomerAccount\(account\.email, account\.password\)[\s\S]*signInCustomer\(page, account\)/u,
  );
  assert.match(
    securitySource,
    /an executed update with an aborted response[\s\S]*prepareSyntheticCustomerAccount\(account\.email, account\.password\)[\s\S]*signInCustomer\(page, account\)[\s\S]*createDraftThroughUi/u,
  );
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
