import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
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
  assert.equal((securitySource.match(/test\.setTimeout\(180_000\)/gu) ?? []).length, 4);
  assert.equal((securitySource.match(/test\.setTimeout\(600_000\)/gu) ?? []).length, 1);
  assert.match(reporterSource, /timedOut:\s*'timeout'/);
  assert.match(reporterSource, /failed:\s*'assertion-or-runtime'/);
  assert.doesNotMatch(reporterSource, /result\.(?:error|errors|stdout|stderr)|message|stack|attachment/iu);
  assert.match(reporterSource, /guard-state:\(restricted\|suspended\|closed\|provider\|missing-profile\)/);
  assert.match(reporterSource, /negative-actor-phase:\(restricted\|suspended\|closed\|provider\|missing-profile\)/);
  assert.match(reporterSource, /negative-actor-failure:\(restricted\|suspended\|closed\|provider\|missing-profile\)/);
  assert.match(reporterSource, /auth-creation\|ticket-9b-profile-readiness\|context-creation\|page-creation\|sign-in\|authenticated-privacy\|fixture-state-application\|route-guard-verification\|sign-out/);
  assert.match(
    reporterSource,
    /context-creation\|page-creation\|anonymous-storage-precondition\|sign-in-network\|sign-in-http-429\|sign-in-http-4xx\|sign-in-http-5xx\|sign-in-http-unexpected\|auth-session-missing\|customer-route\|active-profile-readiness\|authenticated-privacy\|context-cleanup\|unknown/,
  );
  assert.match(reporterSource, /lifecycle-phase:\(registration\|reauthentication\|category-dashboard\|create\|list-detail\|publish\|update\|cancel\|postcondition\|sign-out\)/);
  assert.match(reporterSource, /provider-discovery-failure:\(fixture-setup\|browser-session\|initial-discovery\|revocation\|fresh-discovery\|privacy\|sign-out\)/);
  assert.match(reporterSource, /registration-phase:\(identity-precondition\|signup-request\|auth-session\|profile-ready\|dashboard\)/);
  assert.match(
    reporterSource,
    /signup-http-409\|signup-http-422-\(\?:weak-password\|signup-disabled\|user-already-exists\|validation-failed\|unknown\)\|signup-http-429\|signup-http-other/,
  );
  assert.match(reporterSource, /signup-network-failure\|signup-duplicate-request\|signup-unexpected-collision\|signup-reconciliation-invalid\|signup-reconciliation-session-failure/);
  assert.match(reporterSource, /ambiguous-update-failure:\(isolated-setup\|single-update-execution\|ambiguous-ui\|interception-release\|detail-navigation\|fresh-rls-read\|canonical-values\|postcondition\|sign-out\|cleanup\)/);
  assert.match(reporterSource, /ambiguous-publication-failure:\(isolated-setup\|single-publication-execution\|ambiguous-ui\|interception-release\|detail-navigation\|fresh-rls-read\|postcondition\|sign-out\|cleanup\)/);
  assert.match(reporterSource, /ambiguous-setup-failure:\(browser-context\|fixture-account\|browser-session\|draft-create\|edit-route\)/);
  assert.match(
    reporterSource,
    /ambiguous-update:\(\?:mutation-executed\|interceptor-release-start\|fetch-disabled\|response-listener-removed\|cdp-detached\|detail-navigation\|rls-read-observed\|canonical-values-verified\|cleanup\)/,
  );
  assert.match(
    reporterSource,
    /canonical-values:\(\?:status\|category\|title\|description\|suburb\|city\|start\|budget\)-pass/,
  );
  assert.match(
    reporterSource,
    /if \(!step\.error && \(SAFE_PROGRESS_PHASE\.test\(step\.title\)[\s\S]*SAFE_CANONICAL_VALUE_PHASE\.test\(step\.title\)\)\)/u,
  );
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
  assert.match(runnerSource, /E2E_TEST_SCOPE/);
  assert.doesNotMatch(runnerSource, /GITHUB_(?:REF|HEAD_REF|EVENT_NAME)/u);
  assert.match(
    runnerSource,
    /update\(`\$\{workflowRun\}:\$\{workflowAttempt\}:\$\{scope\}`\)[\s\S]*digest\('hex'\)[\s\S]*slice\(0, 8\)/u,
  );
  assert.match(runnerSource, /const runId = buildRunId\(testScope\)/);
  assert.doesNotMatch(runnerSource, /randomBytes/u);
  assert.match(runnerSource, /E2E_RUN_ID:\s*runId/);
  assert.match(runnerSource, /\['db', 'reset'\]/);
  assert.match(runnerSource, /\['stop', '--no-backup'\]/);
  assert.match(runnerSource, /e2e-refuses-preexisting-supabase-stack/);
  assert.match(helperSource, /process\.env\.E2E_RUN_ID/);
  assert.match(helperSource, /test\.info\(\)\.title/);
  assert.match(helperSource, /createHash\('sha256'\)/);
  assert.equal((helperSource.match(/digest\('hex'\)\.slice\(0, 6\)/gu) ?? []).length, 2);
  assert.match(
    helperSource,
    /update\(`\$\{runId\}:\$\{testComponent\}:\$\{actor\}`\)[\s\S]*digest\('hex'\)[\s\S]*slice\(0, 10\)/u,
  );
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
    /response\.status\(\) === 409[\s\S]*failRegistration\('signup-http-409'\)[\s\S]*response\.status\(\) === 422[\s\S]*failRegistration\(await signupHttp422Category\(response\)\)/u,
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

test('signup 422 classification reads only the privacy-safe Auth error header', async () => {
  const helperSource = await readFile(join(here, 'e2e/support/journey-helpers.mjs'), 'utf8');
  const reporterSource = await readFile(join(here, 'e2e/support/privacy-safe-reporter.mjs'), 'utf8');
  const expectedCategories = new Map([
    ['weak_password', 'signup-http-422-weak-password'],
    ['signup_disabled', 'signup-http-422-signup-disabled'],
    ['user_already_exists', 'signup-http-422-user-already-exists'],
    ['validation_failed', 'signup-http-422-validation-failed'],
  ]);

  for (const [errorCode, category] of expectedCategories) {
    assert.match(helperSource, new RegExp(`\\['${errorCode}', '${category}'\\]`, 'u'));
    assert.match(reporterSource, new RegExp(category.replace('signup-http-422-', ''), 'u'));
  }
  for (const errorCode of [null, '', 'unknown_code']) {
    assert.equal(expectedCategories.get(errorCode) ?? 'signup-http-422-unknown', 'signup-http-422-unknown');
  }

  assert.equal((helperSource.match(/headerValue\('x-sb-error-code'\)/gu) ?? []).length, 1);
  assert.match(
    helperSource,
    /async function signupHttp422Category\(response\)[\s\S]*headerValue\('x-sb-error-code'\)[\s\S]*SIGNUP_HTTP_422_CATEGORIES\.get\(errorCode\) \?\? 'signup-http-422-unknown'/u,
  );
  assert.doesNotMatch(helperSource, /response\.(?:body|json|text)\b/u);
  assert.doesNotMatch(helperSource, /response\.headers\(\)/u);
  assert.doesNotMatch(helperSource, /console\.|process\.(?:stdout|stderr)|JSON\.stringify/u);
  assert.equal((helperSource.match(/name: 'Create account' \}\)\.click\(\)/gu) ?? []).length, 1);
  assert.equal((helperSource.match(/await reconcileSingleUiSignup\(/gu) ?? []).length, 1);
  assert.match(
    helperSource,
    /catch \{[\s\S]*await reconcileSingleUiSignup\(page, account, signupRequestCount\);[\s\S]*return;[\s\S]*finally \{[\s\S]*page\.off\('request', countSignupRequest\);[\s\S]*response\.status\(\) === 422[\s\S]*failRegistration\(await signupHttp422Category\(response\)\)/u,
  );
});

test('negative actors report fixed privacy-safe browser-session boundaries', async () => {
  const helperSource = await readFile(join(here, 'e2e/support/journey-helpers.mjs'), 'utf8');
  const securitySource = await readFile(join(here, 'e2e/security-boundaries.spec.mjs'), 'utf8');
  const reporterSource = await readFile(join(here, 'e2e/support/privacy-safe-reporter.mjs'), 'utf8');
  const stages = [
    'context-creation',
    'page-creation',
    'anonymous-storage-precondition',
    'sign-in-network',
    'sign-in-http-429',
    'sign-in-http-4xx',
    'sign-in-http-5xx',
    'sign-in-http-unexpected',
    'auth-session-missing',
    'customer-route',
    'active-profile-readiness',
    'authenticated-privacy',
    'context-cleanup',
    'unknown',
  ];

  for (const stage of stages) {
    assert.match(securitySource, new RegExp(`'${stage}'`, 'u'));
    assert.match(reporterSource, new RegExp(stage, 'u'));
  }
  assert.match(
    helperSource,
    /privacySafeSignInFailureStage\(error\)[\s\S]*error instanceof PrivacySafeSignInError[\s\S]*: 'unknown'/u,
  );
  assert.match(
    securitySource,
    /withNegativeActorSignInFailureCategory[\s\S]*privacySafeSignInFailureStage\(error\)[\s\S]*reportNegativeActorFailure/u,
  );
  assert.doesNotMatch(
    reporterSource,
    /negative-actor-failure:\(restricted\|suspended\|closed\|provider\|missing-profile\):\([^)]*browser-session/u,
  );
  assert.match(
    reporterSource,
    /step\.error && SAFE_CONTEXT_CLEANUP_FAILURE\.test\(step\.title\)[\s\S]*CLEANUP \$\{step\.title\}/u,
  );
  assert.doesNotMatch(reporterSource, /step\.error\.(?:message|stack|name|cause)/iu);

  const signInStart = helperSource.indexOf('export async function signInCustomer');
  const signInEnd = helperSource.indexOf('export function futureSastInput');
  assert.ok(signInStart >= 0);
  assert.ok(signInEnd > signInStart);
  const signInSource = helperSource.slice(signInStart, signInEnd);
  assert.equal((signInSource.match(/\/auth\/v1\/token/gu) ?? []).length, 1);
  assert.equal((signInSource.match(/grant_type/gu) ?? []).length, 1);
  assert.equal((signInSource.match(/name: 'Sign in' \}\)\.click\(\)/gu) ?? []).length, 1);
  assert.equal((signInSource.match(/timeout:\s*30_000/gu) ?? []).length, 4);
  assert.match(signInSource, /candidate\.request\(\)\.method\(\) === 'POST'/u);
  assert.doesNotMatch(signInSource, /retry|setTimeout|waitForTimeout|sleep/iu);
  assert.match(signInSource, /status === 429[\s\S]*sign-in-http-429/u);
  assert.match(signInSource, /status >= 400 && status < 500[\s\S]*sign-in-http-4xx/u);
  assert.match(signInSource, /status >= 500 && status < 600[\s\S]*sign-in-http-5xx/u);
  assert.match(signInSource, /!response\.ok\(\)[\s\S]*sign-in-http-unexpected/u);
  assert.doesNotMatch(signInSource, /response\.(?:body|json|text|headers|headerValue)\b/u);
  assert.doesNotMatch(
    signInSource,
    /console\.|process\.(?:stdout|stderr)|document\.cookie|context\.cookies|localStorage\.getItem|sessionStorage/u,
  );

  const scenarioStart = securitySource.indexOf(
    "test('restricted suspended closed missing-profile and wrong-role actors fail closed'",
  );
  const scenarioEnd = securitySource.indexOf(
    "test('a stale edit is rejected after another tab cancels the draft'",
  );
  assert.ok(scenarioStart >= 0);
  assert.ok(scenarioEnd > scenarioStart);
  const scenarioSource = securitySource.slice(scenarioStart, scenarioEnd);
  assert.equal((scenarioSource.match(/browser\.newContext\(/gu) ?? []).length, 1);
  assert.equal((scenarioSource.match(/context\.newPage\(\)/gu) ?? []).length, 1);
  assert.doesNotMatch(scenarioSource, /storageState/u);
  assert.match(
    scenarioSource,
    /for \(const scenario of cases\)[\s\S]*browser\.newContext[\s\S]*context\.newPage\(\)/u,
  );
  assert.match(scenarioSource, /finally \{[\s\S]*await context\?\.close\(\)/u);
  assert.match(
    scenarioSource,
    /catch \(error\) \{[\s\S]*primaryFailure = error;[\s\S]*throw error;[\s\S]*finally \{[\s\S]*context-cleanup[\s\S]*if \(!primaryFailure\) throw cleanupFailure;/u,
  );

  assert.equal((helperSource.match(/headerValue\('x-sb-error-code'\)/gu) ?? []).length, 1);
  assert.match(
    securitySource,
    /event\.request\.method !== 'POST'[\s\S]*Fetch\.continueRequest[\s\S]*interceptedUpdateCount \+= 1/u,
  );
  assert.match(securitySource, /expect\(executedUpdateRpcCount\)\.toBe\(1\)/u);
  assert.match(securitySource, /openDraftDetail\(page, requestId\)[\s\S]*fresh-rls-read/u);
});

test('push and pull-request contexts retain valid distinct run-scoped actor properties', async () => {
  const runnerSource = await readFile(join(frontendRoot, 'scripts/e2e/run-local.mjs'), 'utf8');
  const actor = 'customer-lifecycle';
  const testTitle = 'customer registration through cancelled draft completes against real local RLS and RPCs';
  const buildProperties = ({ workflowRun, workflowAttempt, scope }) => {
    const scopeComponent = createHash('sha256')
      .update(`${workflowRun}:${workflowAttempt}:${scope}`)
      .digest('hex')
      .slice(0, 8);
    const runId = `r${workflowRun}-a${workflowAttempt}-${scopeComponent}`;
    const testComponent = createHash('sha256').update(testTitle).digest('hex').slice(0, 6);
    const actorComponent = createHash('sha256').update(actor).digest('hex').slice(0, 6);
    const actorSuffix = createHash('sha256')
      .update(`${runId}:${testComponent}:${actor}`)
      .digest('hex')
      .slice(0, 10);
    const localPart = `${runId}.${testComponent}.${actorComponent}.${actorSuffix}`;
    return {
      email: `${localPart}@lekkadeall.invalid`,
      localPart,
      runId,
    };
  };
  const pushContext = {
    eventName: 'push',
    headRef: '',
    ref: 'refs/heads/fix/example-branch',
    workflowAttempt: '1',
    workflowRun: '12345678901',
    scope: 'lifecycle',
  };
  const pullRequestContext = {
    eventName: 'pull_request',
    headRef: 'fix/example-branch',
    ref: 'refs/pull/1/merge',
    workflowAttempt: '1',
    workflowRun: '12345678902',
    scope: 'lifecycle',
  };
  const push = buildProperties(pushContext);
  const pullRequest = buildProperties(pullRequestContext);

  for (const properties of [push, pullRequest]) {
    assert.equal(properties.runId.length, 24);
    assert.equal(properties.localPart.length, 49);
    assert.equal(properties.email.length, 68);
    assert.match(properties.email, /^[a-z0-9][a-z0-9.-]{0,63}@lekkadeall\.invalid$/u);
  }
  assert.notEqual(push.email, pullRequest.email);
  assert.equal(actor.length, 18);
  assert.doesNotMatch(push.email, /refs|push|example-branch/u);
  assert.doesNotMatch(pullRequest.email, /refs|pull|merge|example-branch/u);
  assert.doesNotMatch(runnerSource, /GITHUB_(?:REF|HEAD_REF|EVENT_NAME)/u);
});

test('browser mutation and fixture boundaries are narrowly allowlisted', async () => {
  assert.deepEqual(ALLOWED_MARKETPLACE_RPCS, [
    'customer_submit_provider_application',
    'customer_create_draft_request',
    'customer_update_draft_request',
    'customer_cancel_draft_request',
    'customer_publish_draft_request',
    'provider_list_discoverable_requests',
  ]);
  const networkSource = await readFile(join(here, 'e2e/support/network-policy.mjs'), 'utf8');
  for (const token of [
    'direct-application-table-dml',
    'broad-column-select',
    'rpc-not-allowlisted',
    'non-loopback-request',
    'service-role-authorization',
  ]) assert.match(networkSource, new RegExp(token));
  assert.match(
    networkSource,
    /customer_submit_provider_application:\s*\[\s*'p_business_name', 'p_category_ids', 'p_service_radius_km', 'p_terms_version'/u,
  );
  assert.match(
    networkSource,
    /provider_list_discoverable_requests:\s*\[\s*'p_cursor_published_at', 'p_cursor_request_id', 'p_page_size'/u,
  );

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
  assert.match(blockedSource, /syntheticAccount\('customer-blocked'\)/);
  assert.doesNotMatch(blockedSource, /customer-blocked-features/u);
  assert.match(
    blockedSource,
    /page\.goto\('\/'\)[\s\S]*expectAuthSession:\s*false[\s\S]*prepareSyntheticCustomerAccount/u,
  );
  assert.match(
    securitySource,
    /prepareSyntheticCustomerAccount\(customerA\.email, customerA\.password\)[\s\S]*signInCustomer\(pageA, customerA\)[\s\S]*registerCustomer\(pageB, customerB\)/u,
  );
  assert.match(
    securitySource,
    /negative-actor-phase:\$\{scenario\.label\}:auth-creation[\s\S]*createSyntheticLocalAuthUser\(account\.email, account\.password\)[\s\S]*negative-actor-phase:\$\{scenario\.label\}:ticket-9b-profile-readiness[\s\S]*waitForProvisionedCustomerProfile\(account\.email, \{ timeoutMs: 60_000 \}\)[\s\S]*negative-actor-phase:\$\{scenario\.label\}:context-creation[\s\S]*browser\.newContext[\s\S]*negative-actor-phase:\$\{scenario\.label\}:page-creation[\s\S]*context\.newPage[\s\S]*attachNetworkPolicy[\s\S]*signInCustomer\(page, account, \{ requireAnonymousStorage: true \}\)[\s\S]*negative-actor-phase:\$\{scenario\.label\}:authenticated-privacy[\s\S]*negative-actor-phase:\$\{scenario\.label\}:fixture-state-application[\s\S]*negative-actor-phase:\$\{scenario\.label\}:route-guard-verification/u,
  );
  for (const actor of ['restricted', 'suspended', 'closed', 'provider', 'missing-profile']) {
    assert.match(securitySource, new RegExp(`label: '${actor}'`));
  }
  for (const phase of [
    'auth-creation',
    'ticket-9b-profile-readiness',
    'context-creation',
    'page-creation',
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
  for (const phase of [
    'browser-context', 'fixture-account', 'browser-session', 'draft-create', 'edit-route',
  ]) {
    assert.match(securitySource, new RegExp(`withAmbiguousSetupFailureCategory\\('${phase}'`));
  }
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
  assert.match(
    securitySource,
    /event\.request\.method !== 'POST'[\s\S]*Fetch\.continueRequest[\s\S]*interceptedUpdateCount \+= 1/u,
  );
  assert.match(
    securitySource,
    /isResponseStage[\s\S]*event\.request\.method !== 'POST'[\s\S]*event\.requestId !== firstUpdateRequestId/u,
  );
  assert.doesNotMatch(securitySource, /route\.fetch\(/u);
  assert.match(securitySource, /getByText\('Draft updated\.', \{ exact: true \}\)\)\.toHaveCount\(0\)/);
  const ambiguousScenarioStart = securitySource.indexOf(
    "test('an executed update with an aborted response is not retried and requires a fresh read'",
  );
  const ambiguousScenarioEnd = securitySource.indexOf(
    "test('recovery routes fail closed without persisting a PKCE verifier'",
  );
  assert.ok(ambiguousScenarioStart >= 0);
  assert.ok(ambiguousScenarioEnd > ambiguousScenarioStart);
  const ambiguousScenarioSource = securitySource.slice(ambiguousScenarioStart, ambiguousScenarioEnd);
  let previousReleaseStep = -1;
  for (const releaseStep of [
    "withAmbiguousUpdateFailureCategory('interception-release'",
    "cdpSession.send('Fetch.disable')",
    "cdpSession.off('Fetch.requestPaused', pausedUpdateHandler)",
    "markAmbiguousUpdateProgress('response-listener-removed')",
    'cdpSession.detach()',
    'interceptionReleased = true',
    "readBaseline = policy.getTableReadCount('service_requests')",
    'openDraftDetail(page, requestId)',
    "withAmbiguousUpdateFailureCategory('fresh-rls-read'",
  ]) {
    const releaseStepIndex = ambiguousScenarioSource.indexOf(releaseStep);
    assert.ok(releaseStepIndex > previousReleaseStep, `${releaseStep} must follow interceptor release order`);
    previousReleaseStep = releaseStepIndex;
  }
  assert.match(
    securitySource,
    /ambiguous-ui[\s\S]*interceptor-release-start[\s\S]*Fetch\.disable[\s\S]*fetch-disabled[\s\S]*Fetch\.requestPaused[\s\S]*listenerCount\('Fetch\.requestPaused'\)[\s\S]*response-listener-removed[\s\S]*cdpSession\.detach\(\)[\s\S]*interceptionReleased = true[\s\S]*cdp-detached/u,
  );
  assert.match(
    securitySource,
    /detail-navigation[\s\S]*expect\(interceptionReleased\)\.toBe\(true\)[\s\S]*getTableReadCount\('service_requests'\)[\s\S]*openDraftDetail\(page, requestId\)[\s\S]*fresh-rls-read[\s\S]*toBe\(readBaseline \+ 1\)[\s\S]*rls-read-observed/u,
  );
  assert.match(
    securitySource,
    /request-detail-card[\s\S]*form\[data-draft-edit-form\][\s\S]*request-detail-status \.status-chip[\s\S]*ACTIVE_CATEGORY_NAME[\s\S]*dashboard-heading h1[\s\S]*edited\.description[\s\S]*edited\.suburb[\s\S]*edited\.city[\s\S]*expectedRequestedStart[\s\S]*expectedBudget/u,
  );
  let previousCanonicalMarker = -1;
  for (const field of [
    'status', 'category', 'title', 'description', 'suburb', 'city', 'start', 'budget',
  ]) {
    const markerIndex = ambiguousScenarioSource.indexOf(`markCanonicalValuePass('${field}')`);
    assert.ok(markerIndex > previousCanonicalMarker, `${field} marker must follow its strict assertion`);
    previousCanonicalMarker = markerIndex;
  }
  assert.match(
    securitySource,
    /canonical-values[\s\S]*expect\(executedUpdateRpcCount\)\.toBe\(1\)[\s\S]*getRpcCount\('customer_update_draft_request'\)\)\.toBe\(executedUpdateRpcCount\)[\s\S]*canonical-values-verified[\s\S]*postcondition[\s\S]*getByRole\('button', \{ name: 'Cancel draft' \}\)\.click\(\)/u,
  );
  assert.ok((
    ambiguousScenarioSource
      .match(/getRpcCount\('customer_update_draft_request'\)\)\.toBe\(executedUpdateRpcCount\)/gu) ?? []
  ).length >= 4);
  assert.match(securitySource, /mutation-executed/);
  assert.match(
    securitySource,
    /const cleanupFailureCategory = interceptionCleanupFailed \? 'interception-release' : 'cleanup'/u,
  );
  assert.match(
    securitySource,
    /ambiguous-update-failure:\$\{cleanupFailureCategory\}[\s\S]*markAmbiguousUpdateProgress\('cleanup'\)/u,
  );
  assert.doesNotMatch(securitySource, /page\.reload\(\)|name: 'Back to draft'/u);
});

test('customer publication E2E is RPC-only, server-confirmed, non-retryable and privacy-safe', async () => {
  const lifecycleSource = await readFile(join(here, 'e2e/customer-draft-lifecycle.spec.mjs'), 'utf8');
  const securitySource = await readFile(join(here, 'e2e/security-boundaries.spec.mjs'), 'utf8');
  const networkSource = await readFile(join(here, 'e2e/support/network-policy.mjs'), 'utf8');
  const fixtureSource = await readFile(join(here, 'e2e/support/local-fixtures.mjs'), 'utf8');

  const listDetailStart = lifecycleSource.indexOf("test.step('lifecycle-phase:list-detail'");
  const publishStart = lifecycleSource.indexOf("test.step('lifecycle-phase:publish'");
  const secondCreateStart = lifecycleSource.indexOf("test.step('lifecycle-phase:create'", publishStart);
  assert.ok(listDetailStart >= 0);
  assert.ok(publishStart > listDetailStart);
  assert.ok(secondCreateStart > publishStart);
  const listDetailSource = lifecycleSource.slice(listDetailStart, publishStart);
  const publishSource = lifecycleSource.slice(publishStart, secondCreateStart);
  assert.match(listDetailSource, /getByRole\('button', \{ name: 'Publish request' \}\)\)\.toBeVisible\(\)/u);
  assert.doesNotMatch(listDetailSource, /name: \/publish\/iu\s*\}\)\)\.toHaveCount\(0\)/u);
  assert.match(publishSource, /name: 'Publish this request\?'/u);
  assert.match(publishSource, /data-publish-draft-form/u);
  assert.match(publishSource, /getByText\('Draft', \{ exact: true \}\)\)\.toBeVisible\(\)/u);
  assert.match(publishSource, /getByText\('Request published\.', \{ exact: true \}\)\)\.toHaveCount\(0\)/u);
  assert.match(
    publishSource,
    /readBaseline = policy\.getTableReadCount\('service_requests'\)[\s\S]*data-publish-draft-form[\s\S]*Request published\.[\s\S]*getTableReadCount\('service_requests'\)\)\.toBe\(readBaseline \+ 1\)/u,
  );
  assert.equal((publishSource.match(/getRpcCount\('customer_publish_draft_request'\)\)\.toBe\(1\)/gu) ?? []).length, 2);
  assert.match(publishSource, /Open[\s\S]*Edit draft[\s\S]*Cancel draft[\s\S]*Publish request/u);
  assert.match(publishSource, /openDraftDetail\(page, publishedRequestId\)[\s\S]*getRpcCount\('customer_publish_draft_request'\)\)\.toBe\(1\)/u);
  assert.match(publishSource, /assertCustomerPublicationPostconditions\(account\.email, publishedRequestId\)/u);
  assert.match(lifecycleSource, /getRpcCount\('customer_create_draft_request'\)\)\.toBe\(2\)/u);
  assert.match(lifecycleSource, /getRpcCount\('customer_update_draft_request'\)\)\.toBe\(1\)/u);
  assert.match(lifecycleSource, /getRpcCount\('customer_cancel_draft_request'\)\)\.toBe\(1\)/u);

  assert.match(networkSource, /customer_publish_draft_request:\s*\['p_request_id'\]/u);
  assert.match(securitySource, /pageA[\s\S]*name: 'Publish request'[\s\S]*policyA\.getRpcCount\('customer_publish_draft_request'\)\)\.toBe\(0\)/u);
  assert.match(
    securitySource,
    /requestMutationBaseline[\s\S]*'customer_publish_draft_request'[\s\S]*\/app\/customer\/requests\/detail\/\?requestId=[\s\S]*name: 'Publish request'[\s\S]*getRpcCount\(functionName\)\)\.toBe\(count\)/u,
  );

  const ambiguousStart = securitySource.indexOf(
    "test('an executed publication with an aborted response is not retried and requires a fresh read'",
  );
  const ambiguousEnd = securitySource.indexOf(
    "test('recovery routes fail closed without persisting a PKCE verifier'",
  );
  assert.ok(ambiguousStart >= 0);
  assert.ok(ambiguousEnd > ambiguousStart);
  const ambiguousSource = securitySource.slice(ambiguousStart, ambiguousEnd);
  assert.match(ambiguousSource, /urlPattern: '\*customer_publish_draft_request\*'/u);
  assert.match(
    ambiguousSource,
    /event\.request\.method !== 'POST'[\s\S]*Fetch\.continueRequest[\s\S]*interceptedPublicationCount \+= 1/u,
  );
  assert.match(
    ambiguousSource,
    /isResponseStage[\s\S]*event\.request\.method !== 'POST'[\s\S]*event\.requestId !== firstPublicationRequestId/u,
  );
  assert.match(ambiguousSource, /interceptedPublicationCount\)\.toBe\(1\)[\s\S]*interceptedResponseCount\)\.toBe\(1\)/u);
  assert.match(ambiguousSource, /Publication could not be confirmed[\s\S]*Request published\.[\s\S]*toHaveCount\(0\)/u);
  let previousBoundary = -1;
  for (const boundary of [
    "cdpSession.send('Fetch.disable')",
    "cdpSession.off('Fetch.requestPaused', pausedPublicationHandler)",
    "listenerCount('Fetch.requestPaused')",
    'cdpSession.detach()',
    "readBaseline = policy.getTableReadCount('service_requests')",
    'openDraftDetail(page, requestId)',
    "getTableReadCount('service_requests')).toBe(readBaseline + 1)",
  ]) {
    const index = ambiguousSource.indexOf(boundary, previousBoundary + 1);
    assert.ok(index > previousBoundary, `${boundary} must retain publication reconciliation order`);
    previousBoundary = index;
  }
  assert.ok((
    ambiguousSource.match(/getRpcCount\('customer_publish_draft_request'\)\)\.toBe\(1\)/gu) ?? []
  ).length >= 4);
  assert.match(ambiguousSource, /getByText\('Open', \{ exact: true \}\)\)\.toBeVisible\(\)/u);
  assert.match(ambiguousSource, /assertCustomerPublicationPostconditions\(account\.email, requestId\)/u);
  assert.doesNotMatch(ambiguousSource, /route\.fetch\(|setInterval|maxRetries|new Promise|\bretry\s*\(/iu);
  assert.match(ambiguousSource, /cleanupFailed && !primaryFailure/u);

  assert.match(fixtureSource, /assertCustomerPublicationPostconditions/u);
  assert.match(fixtureSource, /private\.service_request_addresses[\s\S]*publication boundary row was created/u);
  assert.match(fixtureSource, /customer\.service_request_draft_published/u);
  assert.doesNotMatch(`${lifecycleSource}\n${securitySource}`, /\.insert\(|\.update\(|\.upsert\(|\.delete\(/u);
});

test('provider discovery E2E is isolated, RPC-only, revocable and privacy-safe', async () => {
  const specSource = await readFile(join(here, 'e2e/provider-discovery.spec.mjs'), 'utf8');
  const fixtureSource = await readFile(join(here, 'e2e/support/local-fixtures.mjs'), 'utf8');
  const networkSource = await readFile(join(here, 'e2e/support/network-policy.mjs'), 'utf8');
  const runnerSource = await readFile(join(frontendRoot, 'scripts/e2e/run-local.mjs'), 'utf8');

  assert.match(specSource, /test\.setTimeout\(180_000\)/u);
  assert.match(specSource, /prepareSyntheticProviderDiscovery/u);
  assert.match(specSource, /signInProvider\(page, provider\)/u);
  assert.match(specSource, /PROVIDER_DISCOVERY_MATCHING_TITLE[\s\S]*toBeVisible/u);
  assert.match(specSource, /PROVIDER_DISCOVERY_NONMATCHING_TITLE[\s\S]*toHaveCount\(0\)/u);
  assert.equal((
    specSource.match(/getRpcCount\('provider_list_discoverable_requests'\)\)\.toBe\(/gu) ?? []
  ).length, 2);
  assert.match(specSource, /getTableReadCount\('service_requests'\)\)\.toBe\(0\)/u);
  assert.match(specSource, /suspendSyntheticProviderDiscovery[\s\S]*Refresh requests[\s\S]*Request discovery unavailable[\s\S]*toHaveCount\(0\)/u);
  assert.match(specSource, /data-provider-discovery[\s\S]*customer_id[\s\S]*precise_address[\s\S]*payment_id[\s\S]*created_at/u);
  assert.doesNotMatch(specSource, /waitForTimeout|await new Promise|\bretry\b|service_role|response\.(?:body|json|text)/iu);

  assert.match(fixtureSource, /NONMATCHING_CATEGORY_ID/u);
  assert.match(fixtureSource, /provider_services[\s\S]*set active = true[\s\S]*ACTIVE_CATEGORY_ID/u);
  assert.match(fixtureSource, /admin_transition_provider_marketplace_review[\s\S]*approve_manual_pilot/u);
  assert.match(fixtureSource, /admin_transition_provider_marketplace_review[\s\S]*'suspend'[\s\S]*'approved'/u);
  assert.match(fixtureSource, /allow_marketplace_state_transition[\s\S]*PROVIDER_DISCOVERY_MATCHING_TITLE[\s\S]*PROVIDER_DISCOVERY_NONMATCHING_TITLE/u);
  assert.match(networkSource, /provider_list_discoverable_requests/u);
  assert.match(runnerSource, /discovery:\s*\['--grep', 'eligible provider discovers one safe matching request and loses it after revocation'\]/u);
  assert.match(runnerSource, /full:\s*\['--grep-invert', 'eligible provider discovers one safe matching request and loses it after revocation'\]/u);
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
  for (const scope of ['discovery', 'lifecycle', 'aborted', 'affected', 'full']) {
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
