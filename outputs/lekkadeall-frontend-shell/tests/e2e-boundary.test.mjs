import test from 'node:test';
import assert from 'node:assert/strict';
import { access, readFile } from 'node:fs/promises';
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
  assert.match(reporterSource, /negative-actor-phase:\(restricted\|suspended\|closed\|provider\|missing-profile\)/);
  assert.match(reporterSource, /negative-actor-failure:\(restricted\|suspended\|closed\|provider\|missing-profile\)/);
  assert.match(reporterSource, /auth-creation\|ticket-9b-profile-readiness\|browser-session\|fixture-state-application\|route-guard-verification\|sign-out/);
  assert.match(reporterSource, /lifecycle-phase:\(registration\|reauthentication\|category-dashboard\|create\|list-detail\|update\|cancel\|postcondition\|sign-out\)/);
  assert.match(reporterSource, /registration-phase:\(identity-precondition\|signup-request\|auth-session\|profile-ready\|dashboard\)/);
  assert.match(reporterSource, /signup-http-429\|signup-http-conflict\|signup-http-other/);
  assert.match(reporterSource, /signup-network-failure\|signup-duplicate-request\|signup-unexpected-collision\|signup-reconciliation-invalid\|signup-reconciliation-session-failure/);
  assert.match(reporterSource, /ambiguous-update-failure:\(isolated-setup\|single-update-execution\|ambiguous-ui\|interception-release\|detail-navigation\|fresh-rls-read\|canonical-values\|postcondition\|sign-out\|cleanup\)/);
  assert.match(
    reporterSource,
    /ambiguous-update:\(\?:mutation-executed\|interceptor-release-start\|fetch-disabled\|cdp-detached\|detail-navigation\|rls-read-observed\|canonical-values-verified\|cleanup\)/,
  );
  assert.match(reporterSource, /if \(!step\.error && SAFE_PROGRESS_PHASE\.test\(step\.title\)\)/);
  assert.doesNotMatch(reporterSource, /step\.error\.(?:message|stack|name|cause)/iu);
});

test('local Auth registration uses run-scoped identity and explicit readiness conditions', async () => {
  const helperSource = await readFile(join(here, 'e2e/support/journey-helpers.mjs'), 'utf8');
  const runnerSource = await readFile(join(frontendRoot, 'scripts/e2e/run-local.mjs'), 'utf8');
  const appSource = await readFile(join(frontendRoot, 'app.js'), 'utf8');
  const authConfig = await readFile(
    join(repositoryRoot, 'outputs/marketplace-production-foundation/supabase/config.toml'),
    'utf8',
  );
  assert.match(runnerSource, /GITHUB_RUN_ID/);
  assert.match(runnerSource, /GITHUB_RUN_ATTEMPT/);
  assert.match(runnerSource, /randomBytes\(4\)\.toString\('hex'\)/);
  assert.match(runnerSource, /E2E_TEST_SCOPE/);
  assert.match(runnerSource, /E2E_RUN_ID:\s*runId/);
  assert.match(runnerSource, /\['db', 'reset'\]/);
  assert.match(runnerSource, /\['stop', '--no-backup'\]/);
  assert.match(runnerSource, /e2e-refuses-preexisting-supabase-stack/);
  assert.match(helperSource, /process\.env\.E2E_RUN_ID/);
  assert.match(helperSource, /test\.info\(\)\.title/);
  assert.match(helperSource, /createHash\('sha256'\)/);
  assert.equal((helperSource.match(/digest\('hex'\)\.slice\(0, 6\)/gu) ?? []).length, 2);
  assert.match(helperSource, /randomBytes\(5\)\.toString\('hex'\)/);
  assert.match(helperSource, /EMAIL_LOCAL_PART_MAX_LENGTH\s*=\s*64/);
  assert.match(
    helperSource,
    /`\$\{runId\}\.\$\{testComponent\}\.\$\{actorComponent\}\.\$\{actorSuffix\}`/u,
  );
  const longestRunId = `r${'9'.repeat(20)}-a${'9'.repeat(6)}-${'a'.repeat(8)}`;
  const longestLocalPart = [
    longestRunId,
    'b'.repeat(6),
    'c'.repeat(6),
    'd'.repeat(10),
  ].join('.');
  assert.equal(longestLocalPart.length, 63);
  assert.match(helperSource, /assertSyntheticAccountAbsent/);
  assert.match(helperSource, /reconcileAmbiguousUiSignup/);
  assert.match(helperSource, /signupRequestCount !== 1/);
  assert.equal((helperSource.match(/await reconcileSingleUiSignup\(/gu) ?? []).length, 1);
  assert.equal((helperSource.match(/name: 'Create account' \}\)\.click\(\)/gu) ?? []).length, 1);
  assert.match(
    helperSource,
    /\[409, 422\]\.includes\(response\.status\(\)\)[\s\S]*failRegistration\('signup-http-conflict'\)/u,
  );
  assert.match(appSource, /if \(authSubmissionInFlight\) return;/);
  assert.match(appSource, /authSubmissionInFlight = true;[\s\S]*await submitAuthFormOnce\(form\);[\s\S]*authSubmissionInFlight = false;/u);
  assert.match(helperSource, /registration-phase:signup-request/);
  assert.match(helperSource, /registration-phase:auth-session/);
  assert.match(helperSource, /registration-phase:profile-ready/);
  assert.match(helperSource, /registration-phase:dashboard/);
  assert.match(helperSource, /waitForResponse/);
  assert.match(helperSource, /expect\.poll/);
  assert.match(helperSource, /waitForProvisionedCustomerProfile/);
  assert.match(helperSource, /grant_type'\)\s*===\s*'password'/);
  assert.match(helperSource, /response\.status\(\)\s*===\s*429/);
  assert.match(helperSource, /authStorageEntryCount/);
  assert.doesNotMatch(helperSource, /lastRegistration(?:At|CompletedAt)|respectLocalSignupRateLimit/);
  assert.match(authConfig, /\[auth\.email\][\s\S]*enable_confirmations\s*=\s*false/u);
  assert.match(authConfig, /\[auth\.rate_limit\][\s\S]*sign_in_sign_ups\s*=\s*120/u);
  assert.match(authConfig, /local-only quota is not production configuration/u);
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
  assert.match(fixtureSource, /FIXTURE_STATES = new Set\(\['absent', 'auth-only', 'ready', 'invalid'\]\)/);
  assert.match(fixtureSource, /readSyntheticAccountFixtureState/);
  assert.match(fixtureSource, /synthetic-ui-signup-identity-not-absent/);
  assert.match(fixtureSource, /synthetic-ui-signup-reconciliation-absent/);
  assert.match(fixtureSource, /synthetic-ui-signup-reconciliation-invalid/);
  assert.match(fixtureSource, /synthetic-auth-fixture-ambiguous-absent/);
  assert.match(fixtureSource, /synthetic-auth-fixture-ambiguous-invalid/);
  assert.match(
    fixtureSource,
    /catch \{[\s\S]*await reconcileAmbiguousSyntheticAuthCreation\(email\);[\s\S]*return;/u,
  );
  assert.equal((fixtureSource.match(/fetch\(new URL\('\/auth\/v1\/admin\/users'/gu) ?? []).length, 1);
  assert.match(fixtureSource, /\/auth\/v1\/admin\/users/);
  assert.match(fixtureSource, /createSyntheticLocalAuthUser/);
  assert.match(fixtureSource, /E2E_LOCAL_FIXTURE_ADMIN_KEY/);
  assert.match(fixtureSource, /waitForProvisionedCustomerProfile\(email\)/);
  assert.match(fixtureSource, /synthetic request ownership invariant failed/);
  assert.match(fixtureSource, /synthetic Auth users are not distinct/);
  assert.match(fixtureSource, /synthetic provider fixture isolation failed/);
  assert.match(fixtureSource, /p\.role = 'provider'::public\.user_role/);
  assert.doesNotMatch(fixtureSource, /SERVICE_ROLE_KEY|supabase\.co|postgresql:\/\//iu);
});

test('only lifecycle and cross-customer B use UI signup; setup-only actors use fixture sign-in', async () => {
  const blockedSource = await readFile(join(here, 'e2e/blocked-features.spec.mjs'), 'utf8');
  const lifecycleSource = await readFile(join(here, 'e2e/customer-draft-lifecycle.spec.mjs'), 'utf8');
  const securitySource = await readFile(join(here, 'e2e/security-boundaries.spec.mjs'), 'utf8');
  assert.equal((
    `${blockedSource}\n${lifecycleSource}\n${securitySource}`.match(/registerCustomer\(/gu) ?? []
  ).length, 2);
  assert.equal((lifecycleSource.match(/registerCustomer\(page, account\)/gu) ?? []).length, 1);
  assert.doesNotMatch(lifecycleSource, /prepareSyntheticCustomerAccount|createSyntheticLocalAuthUser/u);
  assert.match(
    securitySource,
    /prepareSyntheticCustomerAccount\(customerA\.email, customerA\.password\)[\s\S]*signInCustomer\(pageA, customerA\)[\s\S]*registerCustomer\(pageB, customerB\)/u,
  );
  assert.match(
    securitySource,
    /negative-actor-phase:\$\{scenario\.label\}:auth-creation[\s\S]*createSyntheticLocalAuthUser\(account\.email, account\.password\)[\s\S]*negative-actor-phase:\$\{scenario\.label\}:ticket-9b-profile-readiness[\s\S]*waitForProvisionedCustomerProfile\(account\.email, \{ timeoutMs: 60_000 \}\)[\s\S]*negative-actor-phase:\$\{scenario\.label\}:browser-session[\s\S]*browser\.newContext[\s\S]*attachNetworkPolicy[\s\S]*signInCustomer\(page, account\)[\s\S]*negative-actor-phase:\$\{scenario\.label\}:fixture-state-application[\s\S]*negative-actor-phase:\$\{scenario\.label\}:route-guard-verification/u,
  );
  for (const actor of ['restricted', 'suspended', 'closed', 'provider', 'missing-profile']) {
    assert.match(securitySource, new RegExp(`label: '${actor}'`));
  }
  for (const phase of [
    'auth-creation',
    'ticket-9b-profile-readiness',
    'browser-session',
    'fixture-state-application',
    'route-guard-verification',
  ]) {
    assert.match(securitySource, new RegExp(`negative-actor-phase:\\$\\{scenario\\.label\\}:${phase}`));
    assert.match(securitySource, new RegExp(`scenario\\.label,\\s*'${phase}'`));
  }
  assert.match(securitySource, /const requestReadBaseline[\s\S]*getTableReadCount[\s\S]*expect\(policy\.getTableReadCount\(table\)\)\.toBe\(count\)/u);
  assert.match(securitySource, /const requestMutationBaseline[\s\S]*getRpcCount[\s\S]*expect\(policy\.getRpcCount\(functionName\)\)\.toBe\(count\)/u);
  assert.match(securitySource, /finally \{[\s\S]*await context\?\.close\(\)/u);
  assert.match(
    securitySource,
    /an executed update with an aborted response[\s\S]*prepareSyntheticCustomerAccount\(account\.email, account\.password\)[\s\S]*signInCustomer\(page, account\)[\s\S]*createDraftThroughUi/u,
  );
  assert.match(securitySource, /browser\.newContext\(\{ baseURL: appUrl, serviceWorkers: 'allow' \}\)/);
  assert.match(securitySource, /context\.newCDPSession\(page\)/);
  assert.match(
    securitySource,
    /Fetch\.continueRequest[\s\S]*interceptResponse:\s*true[\s\S]*Fetch\.failRequest/u,
  );
  assert.match(
    securitySource,
    /interceptedUpdateCount === 1[\s\S]*Fetch\.continueRequest[\s\S]*Fetch\.failRequest/u,
  );
  assert.doesNotMatch(securitySource, /route\.fetch\(/u);
  assert.match(securitySource, /getByText\('Draft updated\.', \{ exact: true \}\)\)\.toHaveCount\(0\)/);
  assert.match(
    securitySource,
    /ambiguous-ui[\s\S]*interceptor-release-start[\s\S]*Fetch\.disable[\s\S]*fetch-disabled[\s\S]*Fetch\.requestPaused[\s\S]*listenerCount\('Fetch\.requestPaused'\)[\s\S]*cdpSession\.detach\(\)[\s\S]*cdp-detached/u,
  );
  assert.match(
    securitySource,
    /detail-navigation[\s\S]*getTableReadCount\('service_requests'\)[\s\S]*openDraftDetail\(page, requestId\)[\s\S]*fresh-rls-read[\s\S]*toBe\(readBaseline \+ 1\)[\s\S]*rls-read-observed/u,
  );
  assert.match(
    securitySource,
    /getByRole\('heading', \{ name: edited\.title, exact: true \}\)[\s\S]*ACTIVE_CATEGORY_NAME[\s\S]*edited\.description[\s\S]*edited\.suburb[\s\S]*edited\.city[\s\S]*expectedRequestedStart[\s\S]*expectedBudget/u,
  );
  assert.match(
    securitySource,
    /canonical-values[\s\S]*getRpcCount\('customer_update_draft_request'\)\)\.toBe\(1\)[\s\S]*canonical-values-verified[\s\S]*postcondition[\s\S]*getByRole\('button', \{ name: 'Cancel draft' \}\)\.click\(\)/u,
  );
  assert.match(securitySource, /mutation-executed/);
  assert.match(securitySource, /ambiguous-update-failure:cleanup[\s\S]*markAmbiguousUpdateProgress\('cleanup'\)/u);
  assert.doesNotMatch(securitySource, /page\.reload\(\)|name: 'Back to draft'/u);
});

test('CI E2E job is isolated behind the complete database security job', async () => {
  const workflow = await readFile(join(repositoryRoot, '.github/workflows/database-tests.yml'), 'utf8');
  assert.match(
    workflow,
    /database-tests:[\s\S]*defaults:[\s\S]*run:[\s\S]*working-directory:\s*outputs\/marketplace-production-foundation/u,
  );
  assert.match(
    workflow,
    /Verify committed local Supabase config[\s\S]*working-directory:\s*\.[\s\S]*test -f outputs\/marketplace-production-foundation\/supabase\/config\.toml/u,
  );
  assert.equal(
    workflow.includes("grep -Ev '^[[:space:]]*(#|$)' outputs/marketplace-production-foundation/supabase/config.toml"),
    true,
  );
  assert.match(
    workflow,
    /grep -Eiq '\(database_password\|db_password\|service_role\|jwt_secret\|secret\|payment\|identity\|api_key\|access_token\|supabase\\\\\.co\|project_ref\|db_url\|production\|prod_\)'/u,
  );
  assert.match(
    workflow,
    /Start Supabase local stack[\s\S]*run:\s*supabase start[\s\S]*Apply migrations with database reset[\s\S]*run:\s*supabase db reset[\s\S]*Run role escalation pgTAP tests/u,
  );
  await access(join(
    repositoryRoot,
    'outputs/marketplace-production-foundation/supabase/config.toml',
  ));
  await assert.rejects(access(join(repositoryRoot, 'supabase/config.toml')));
  assert.match(workflow, /customer-draft-lifecycle-e2e:/);
  assert.match(workflow, /needs:\s*database-tests/);
  assert.match(workflow, /pnpm run test:e2e:local/);
  for (const scope of ['lifecycle', 'aborted', 'affected', 'full']) {
    assert.match(workflow, new RegExp(`E2E_TEST_SCOPE:\\s*${scope}`));
  }
  assert.equal((workflow.match(/uses: supabase\/setup-cli@v2/gu) ?? []).length, 2);
  assert.equal((workflow.match(/version: 2\.110\.0/gu) ?? []).length, 2);
  assert.doesNotMatch(workflow, /version:\s*latest/u);
  assert.match(workflow, /playwright install --with-deps chromium/);
  assert.doesNotMatch(workflow, /upload-artifact/);
});

test('E2E sign-out follows the implemented fail-closed sign-in redirect', async () => {
  const helperSource = await readFile(join(here, 'e2e/support/journey-helpers.mjs'), 'utf8');
  assert.equal(helperSource.includes('toHaveURL(/\\/auth\\/sign-in\\/?$/u)'), true);
  assert.match(helperSource, /getByRole\('heading', \{ name: 'Sign in to your workspace\.' \}\)/);
  assert.equal(helperSource.includes('toHaveURL(/\\/$/u)'), false);
});
