import { expect, test } from '@playwright/test';
import { formatSastDateTime, formatZarBudgetMinor } from '../../customer-requests.js';
import {
  ACTIVE_CATEGORY_NAME,
  assertCustomerLifecyclePostconditions,
  assertDistinctSyntheticUsers,
  assertSyntheticProfileAbsent,
  assertSyntheticProviderFixtureIsIsolated,
  assertSyntheticRequestOwner,
  assertSyntheticProfileState,
  createSyntheticLocalAuthUser,
  prepareSyntheticCustomerAccount,
  removeSyntheticProfile,
  setSyntheticProfileState,
  waitForProvisionedCustomerProfile,
} from './support/local-fixtures.mjs';
import {
  createDraftThroughUi,
  editedDraftValues,
  fillDraftForm,
  mainDraftValues,
  openDraftDetail,
  privacyMarkers,
  privacySafeSignInFailureStage,
  registerCustomer,
  signInCustomer,
  signOutCustomer,
  syntheticAccount,
} from './support/journey-helpers.mjs';
import { attachNetworkPolicy } from './support/network-policy.mjs';
import { assertBrowserPrivacy, attachSensitiveEmissionAudit } from './support/privacy-audit.mjs';

const appUrl = process.env.E2E_APP_URL;
const supabaseUrl = process.env.E2E_SUPABASE_URL;
const anonKey = process.env.E2E_ANON_KEY;

test.beforeAll(() => {
  if (process.env.E2E_LOCAL_STACK_READY !== '1') throw new Error('local-e2e-stack-not-ready');
});

const NEGATIVE_ACTORS = new Set([
  'restricted',
  'suspended',
  'closed',
  'provider',
  'missing-profile',
]);
const NEGATIVE_ACTOR_FAILURE_CATEGORIES = new Set([
  'auth-creation',
  'ticket-9b-profile-readiness',
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
  'fixture-state-application',
  'route-guard-verification',
  'sign-out',
]);

async function reportNegativeActorFailure(actor, category) {
  if (!NEGATIVE_ACTORS.has(actor) || !NEGATIVE_ACTOR_FAILURE_CATEGORIES.has(category)) {
    throw new Error('negative-actor-failure-category-invalid');
  }
  await test.step(`negative-actor-failure:${actor}:${category}`, async () => {
    throw new Error('privacy-safe-negative-actor-boundary-failure');
  });
}

async function withNegativeActorFailureCategory(actor, category, operation) {
  try {
    return await operation();
  } catch {
    await reportNegativeActorFailure(actor, category);
    return undefined;
  }
}

async function withNegativeActorSignInFailureCategory(actor, operation) {
  try {
    return await operation();
  } catch (error) {
    await reportNegativeActorFailure(actor, privacySafeSignInFailureStage(error));
    return undefined;
  }
}

const AMBIGUOUS_UPDATE_FAILURE_CATEGORIES = new Set([
  'isolated-setup',
  'single-update-execution',
  'ambiguous-ui',
  'interception-release',
  'detail-navigation',
  'fresh-rls-read',
  'canonical-values',
  'postcondition',
  'sign-out',
  'cleanup',
]);
const AMBIGUOUS_UPDATE_PROGRESS_PHASES = new Set([
  'mutation-executed',
  'interceptor-release-start',
  'fetch-disabled',
  'response-listener-removed',
  'cdp-detached',
  'detail-navigation',
  'rls-read-observed',
  'canonical-values-verified',
  'cleanup',
]);
const AMBIGUOUS_SETUP_FAILURE_CATEGORIES = new Set([
  'browser-context',
  'fixture-account',
  'browser-session',
  'draft-create',
  'edit-route',
]);
const CANONICAL_VALUE_FIELDS = new Set([
  'status',
  'category',
  'title',
  'description',
  'suburb',
  'city',
  'start',
  'budget',
]);

async function withAmbiguousUpdateFailureCategory(category, operation) {
  if (!AMBIGUOUS_UPDATE_FAILURE_CATEGORIES.has(category)) {
    throw new Error('ambiguous-update-failure-category-invalid');
  }
  try {
    return await operation();
  } catch {
    await test.step(`ambiguous-update-failure:${category}`, async () => {
      throw new Error('privacy-safe-ambiguous-update-boundary-failure');
    });
    return undefined;
  }
}

async function withAmbiguousSetupFailureCategory(category, operation) {
  if (!AMBIGUOUS_SETUP_FAILURE_CATEGORIES.has(category)) {
    throw new Error('ambiguous-setup-failure-category-invalid');
  }
  try {
    return await operation();
  } catch {
    await test.step(`ambiguous-setup-failure:${category}`, async () => {
      throw new Error('privacy-safe-ambiguous-setup-boundary-failure');
    });
    return undefined;
  }
}

async function markAmbiguousUpdateProgress(phase) {
  if (!AMBIGUOUS_UPDATE_PROGRESS_PHASES.has(phase)) {
    throw new Error('ambiguous-update-progress-phase-invalid');
  }
  await test.step(`ambiguous-update:${phase}`, async () => {});
}

async function markCanonicalValuePass(field) {
  if (!CANONICAL_VALUE_FIELDS.has(field)) {
    throw new Error('canonical-value-field-invalid');
  }
  await test.step(`canonical-values:${field}-pass`, async () => {});
}

test('cross-customer request IDs remain RLS-hidden and non-actionable', async ({ browser }) => {
  test.setTimeout(180_000);
  const customerA = syntheticAccount('customer-rls-a');
  const customerB = syntheticAccount('customer-rls-b');
  const bDraft = {
    ...mainDraftValues(),
    title: 'Prepare synthetic utility room',
    description: 'Prepare and paint the utility room using a neutral finish.',
  };
  const contextA = await browser.newContext({ baseURL: appUrl, serviceWorkers: 'allow' });
  const contextB = await browser.newContext({ baseURL: appUrl, serviceWorkers: 'allow' });
  try {
    const pageA = await contextA.newPage();
    const pageB = await contextB.newPage();
    const policyA = attachNetworkPolicy(pageA, { appUrl, supabaseUrl, anonKey });
    const policyB = attachNetworkPolicy(pageB, { appUrl, supabaseUrl, anonKey });
    const emissionsA = attachSensitiveEmissionAudit(pageA, privacyMarkers(customerA, bDraft));
    const emissionsB = attachSensitiveEmissionAudit(pageB, privacyMarkers(customerB, bDraft));

    await prepareSyntheticCustomerAccount(customerA.email, customerA.password);
    await signInCustomer(pageA, customerA);
    await registerCustomer(pageB, customerB);
    await assertDistinctSyntheticUsers(customerA.email, customerB.email);
    const requestIdB = await createDraftThroughUi(pageB, bDraft);
    await assertSyntheticRequestOwner(customerB.email, requestIdB);
    expect(contextA).not.toBe(contextB);
    expect(pageA.context()).toBe(contextA);
    expect(pageB.context()).toBe(contextB);

    await pageA.goto('/app/customer/requests');
    await expect(pageA.getByRole('heading', { name: bDraft.title })).toHaveCount(0);
    await pageA.goto(`/app/customer/requests/detail/?requestId=${requestIdB}`);
    await expect(pageA.getByText('Request not found or unavailable')).toBeVisible();
    await expect(pageA.locator('.request-detail-card')).toHaveCount(0);
    await expect(pageA.getByText(bDraft.title)).toHaveCount(0);
    await expect(pageA.getByText(bDraft.description)).toHaveCount(0);
    await expect(pageA.getByText('Synthetic home maintenance')).toHaveCount(0);
    await expect(pageA.getByText('Draft', { exact: true })).toHaveCount(0);
    await expect(pageA.getByRole('button', { name: 'Cancel draft' })).toHaveCount(0);
    await pageA.goto('/app/customer/requests/detail/?requestId=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    await expect(pageA.getByText('Request not found or unavailable')).toBeVisible();
    await expect(pageA.locator('.request-detail-card')).toHaveCount(0);
    await pageA.goto(`/app/customer/requests/edit/?requestId=${requestIdB}`);
    await expect(pageA.getByText('Draft not found or unavailable')).toBeVisible();
    await expect(pageA.locator('form[data-draft-edit-form]')).toHaveCount(0);
    await pageA.goto('/app/customer/requests/edit/?requestId=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    await expect(pageA.getByText('Draft not found or unavailable')).toBeVisible();
    await expect(pageA.locator('form[data-draft-edit-form]')).toHaveCount(0);

    expect(policyA.getRpcCount('customer_update_draft_request')).toBe(0);
    expect(policyA.getRpcCount('customer_cancel_draft_request')).toBe(0);
    expect(policyB.getRpcCount('customer_create_draft_request')).toBe(1);
    await assertBrowserPrivacy(pageA, { markers: privacyMarkers(customerA, bDraft), expectAuthSession: true });
    await assertBrowserPrivacy(pageB, { markers: privacyMarkers(customerB, bDraft), expectAuthSession: true });
    policyA.assertClean();
    policyB.assertClean();
    emissionsA.assertClean();
    emissionsB.assertClean();

    await signOutCustomer(pageA);
    await signOutCustomer(pageB);
    await assertBrowserPrivacy(pageA, { markers: privacyMarkers(customerA, bDraft), expectAuthSession: false });
    await assertBrowserPrivacy(pageB, { markers: privacyMarkers(customerB, bDraft), expectAuthSession: false });
  } finally {
    await contextA.close();
    await contextB.close();
  }
});

test('restricted suspended closed missing-profile and wrong-role actors fail closed', async ({ browser }) => {
  test.setTimeout(600_000);
  const cases = [
    { label: 'restricted', state: { accountStatus: 'restricted' }, message: 'Account access is restricted', uiState: 'restricted' },
    { label: 'suspended', state: { accountStatus: 'suspended' }, message: 'Account access is restricted', uiState: 'restricted' },
    { label: 'closed', state: { accountStatus: 'closed' }, message: 'Account access is restricted', uiState: 'restricted' },
    { label: 'provider', state: { role: 'provider' }, message: 'Access denied', uiState: 'error' },
    { label: 'missing-profile', removeProfile: true, message: 'Account setup unavailable', uiState: 'error' },
  ];

  for (const scenario of cases) {
    await test.step(`guard-state:${scenario.label}`, async () => {
      const account = syntheticAccount(`account-${scenario.label}`);
      let context;
      let page;
      let policy;
      let markers;
      let emissions;
      let primaryFailure;
      try {
        await test.step(`negative-actor-phase:${scenario.label}:auth-creation`, async () => {
          await withNegativeActorFailureCategory(scenario.label, 'auth-creation', () => (
            createSyntheticLocalAuthUser(account.email, account.password)
          ));
        });

        await test.step(`negative-actor-phase:${scenario.label}:ticket-9b-profile-readiness`, async () => {
          await withNegativeActorFailureCategory(
            scenario.label,
            'ticket-9b-profile-readiness',
            () => waitForProvisionedCustomerProfile(account.email, { timeoutMs: 60_000 }),
          );
        });

        await test.step(`negative-actor-phase:${scenario.label}:context-creation`, async () => {
          context = await withNegativeActorFailureCategory(
            scenario.label,
            'context-creation',
            () => browser.newContext({ baseURL: appUrl, serviceWorkers: 'allow' }),
          );
        });

        await test.step(`negative-actor-phase:${scenario.label}:page-creation`, async () => {
          page = await withNegativeActorFailureCategory(
            scenario.label,
            'page-creation',
            () => context.newPage(),
          );
        });

        await test.step(`negative-actor-phase:${scenario.label}:sign-in`, async () => {
          await withNegativeActorFailureCategory(scenario.label, 'unknown', async () => {
            policy = attachNetworkPolicy(page, { appUrl, supabaseUrl, anonKey });
            markers = privacyMarkers(account);
            emissions = attachSensitiveEmissionAudit(page, markers);
          });
          await withNegativeActorSignInFailureCategory(scenario.label, () => (
            signInCustomer(page, account, { requireAnonymousStorage: true })
          ));
        });

        await test.step(`negative-actor-phase:${scenario.label}:authenticated-privacy`, async () => {
          await withNegativeActorFailureCategory(scenario.label, 'authenticated-privacy', async () => {
            await assertBrowserPrivacy(page, { markers, expectAuthSession: true });
          });
        });

        await test.step(`negative-actor-phase:${scenario.label}:fixture-state-application`, async () => {
          await withNegativeActorFailureCategory(
            scenario.label,
            'fixture-state-application',
            async () => {
              if (scenario.removeProfile) {
                await removeSyntheticProfile(account.email);
                await assertSyntheticProfileAbsent(account.email);
                return;
              }
              await setSyntheticProfileState(account.email, scenario.state);
              await assertSyntheticProfileState(account.email, scenario.state);
              if (scenario.label === 'provider') {
                await assertSyntheticProviderFixtureIsIsolated(account.email);
              }
            },
          );
        });

        const requestReadBaseline = Object.fromEntries(
          ['service_requests', 'bookings', 'payments']
            .map((table) => [table, policy.getTableReadCount(table)]),
        );
        const requestMutationBaseline = Object.fromEntries(
          [
            'customer_create_draft_request',
            'customer_update_draft_request',
            'customer_cancel_draft_request',
          ].map((functionName) => [functionName, policy.getRpcCount(functionName)]),
        );

        await test.step(`negative-actor-phase:${scenario.label}:route-guard-verification`, async () => {
          await withNegativeActorFailureCategory(
            scenario.label,
            'route-guard-verification',
            async () => {
              await page.goto('/app/customer');
              await expect(page.getByText(scenario.message)).toBeVisible();
              await expect(page.locator(`[data-state="${scenario.uiState}"]`)).toBeVisible();
              await expect(page.getByRole('link', { name: 'Create request draft' })).toHaveCount(0);

              if (scenario.removeProfile) {
                await assertSyntheticProfileAbsent(account.email);
              } else {
                await assertSyntheticProfileState(account.email, scenario.state);
              }
              if (scenario.label === 'provider') {
                await assertSyntheticProviderFixtureIsIsolated(account.email);
              }
              for (const [functionName, count] of Object.entries(requestMutationBaseline)) {
                expect(policy.getRpcCount(functionName)).toBe(count);
              }
              for (const [table, count] of Object.entries(requestReadBaseline)) {
                expect(policy.getTableReadCount(table)).toBe(count);
              }
              await assertBrowserPrivacy(page, { markers, expectAuthSession: true });
              policy.assertClean();
              emissions.assertClean();
            },
          );
        });

        await test.step(`negative-actor-phase:${scenario.label}:sign-out`, async () => {
          await withNegativeActorFailureCategory(scenario.label, 'sign-out', async () => {
            await signOutCustomer(page);
            await assertBrowserPrivacy(page, { markers, expectAuthSession: false });
          });
        });
      } catch (error) {
        primaryFailure = error;
        throw error;
      } finally {
        try {
          await context?.close();
        } catch {
          try {
            await reportNegativeActorFailure(scenario.label, 'context-cleanup');
          } catch (cleanupFailure) {
            if (!primaryFailure) throw cleanupFailure;
          }
        }
      }
    });
  }
});

test('a stale edit is rejected after another tab cancels the draft', async ({ context, page }) => {
  test.setTimeout(180_000);
  const account = syntheticAccount('customer-stale');
  const created = mainDraftValues();
  const edited = editedDraftValues();
  const markers = privacyMarkers(account, created, edited);
  const policyEdit = attachNetworkPolicy(page, { appUrl, supabaseUrl, anonKey });
  const emissionsEdit = attachSensitiveEmissionAudit(page, markers);
  await prepareSyntheticCustomerAccount(account.email, account.password);
  await signInCustomer(page, account);
  const requestId = await createDraftThroughUi(page, created);
  await page.goto(`/app/customer/requests/edit/?requestId=${requestId}`);
  await expect(page.locator('form[data-draft-edit-form]')).toBeVisible();

  const cancellationPage = await context.newPage();
  const policyCancel = attachNetworkPolicy(cancellationPage, { appUrl, supabaseUrl, anonKey });
  const emissionsCancel = attachSensitiveEmissionAudit(cancellationPage, markers);
  await openDraftDetail(cancellationPage, requestId);
  await cancellationPage.getByRole('button', { name: 'Cancel draft' }).click();
  await cancellationPage.locator('[data-cancel-draft-form]').getByRole('button', { name: 'Cancel draft' }).click();
  await expect(cancellationPage.getByText('Draft cancelled.', { exact: true })).toBeVisible();

  const editForm = await fillDraftForm(page, edited);
  await editForm.getByRole('button', { name: 'Save draft changes' }).click();
  await expect(page.getByText('This draft is not available for editing.', { exact: true })).toBeVisible();
  expect(policyEdit.getRpcCount('customer_update_draft_request')).toBe(1);
  expect(policyCancel.getRpcCount('customer_cancel_draft_request')).toBe(1);
  policyEdit.assertClean();
  policyCancel.assertClean();
  emissionsEdit.assertClean();
  emissionsCancel.assertClean();
  await cancellationPage.close();
  await signOutCustomer(page);
  await assertBrowserPrivacy(page, { markers, expectAuthSession: false });
});

test('an executed update with an aborted response is not retried and requires a fresh read', async ({ browser }) => {
  test.setTimeout(180_000);
  const account = syntheticAccount('customer-ambiguous');
  const created = mainDraftValues();
  const edited = editedDraftValues();
  const markers = privacyMarkers(account, created, edited);
  let context;
  let page;
  let policy;
  let emissions;
  let requestId;
  let cdpSession;
  let pausedUpdateHandler;
  let interceptionReleased = false;
  let executedUpdateRpcCount;
  try {
    await withAmbiguousUpdateFailureCategory('isolated-setup', async () => {
      await withAmbiguousSetupFailureCategory('browser-context', async () => {
        context = await browser.newContext({ baseURL: appUrl, serviceWorkers: 'allow' });
        page = await context.newPage();
        policy = attachNetworkPolicy(page, { appUrl, supabaseUrl, anonKey });
        emissions = attachSensitiveEmissionAudit(page, markers);
      });
      await withAmbiguousSetupFailureCategory('fixture-account', async () => {
        await prepareSyntheticCustomerAccount(account.email, account.password);
      });
      await withAmbiguousSetupFailureCategory('browser-session', async () => {
        await signInCustomer(page, account);
      });
      await withAmbiguousSetupFailureCategory('draft-create', async () => {
        requestId = await createDraftThroughUi(page, created);
      });
      await withAmbiguousSetupFailureCategory('edit-route', async () => {
        await page.goto(`/app/customer/requests/edit/?requestId=${requestId}`);
        await expect(page.locator('form[data-draft-edit-form]')).toBeVisible();
      });
    });

    let interceptedUpdateCount = 0;
    let interceptedResponseCount = 0;
    let updateExecuted = false;
    let responseAborted = false;
    let interceptionFailure = false;
    let firstUpdateRequestId;
    cdpSession = await context.newCDPSession(page);
    pausedUpdateHandler = async (event) => {
      const isResponseStage = Object.hasOwn(event, 'responseStatusCode')
        || Object.hasOwn(event, 'responseErrorReason');
      try {
        if (isResponseStage) {
          interceptedResponseCount += 1;
          if (event.request.method !== 'POST' || event.requestId !== firstUpdateRequestId) {
            interceptionFailure = true;
          }
          updateExecuted = Number.isInteger(event.responseStatusCode)
            && event.responseStatusCode >= 200
            && event.responseStatusCode < 300;
          await cdpSession.send('Fetch.failRequest', {
            requestId: event.requestId,
            errorReason: 'Aborted',
          });
          responseAborted = true;
          return;
        }

        if (event.request.method !== 'POST') {
          await cdpSession.send('Fetch.continueRequest', {
            requestId: event.requestId,
          });
          return;
        }

        interceptedUpdateCount += 1;
        if (interceptedUpdateCount === 1) {
          firstUpdateRequestId = event.requestId;
          await cdpSession.send('Fetch.continueRequest', {
            requestId: event.requestId,
            interceptResponse: true,
          });
          return;
        }
        await cdpSession.send('Fetch.failRequest', {
          requestId: event.requestId,
          errorReason: 'Aborted',
        });
      } catch {
        interceptionFailure = true;
        try {
          await cdpSession.send('Fetch.failRequest', {
            requestId: event.requestId,
            errorReason: 'Aborted',
          });
        } catch {
          // Cleanup remains privacy-safe; the fixed category reports the boundary.
        }
      }
    };
    cdpSession.on('Fetch.requestPaused', pausedUpdateHandler);
    await cdpSession.send('Fetch.enable', {
      patterns: [{
        urlPattern: '*customer_update_draft_request*',
        requestStage: 'Request',
      }],
    });

    await withAmbiguousUpdateFailureCategory('single-update-execution', async () => {
      const editForm = await fillDraftForm(page, edited);
      await editForm.getByRole('button', { name: 'Save draft changes' }).click();
      await expect(page.getByText(
        'The update could not be confirmed. Refresh the draft before trying again.',
        { exact: true },
      )).toBeVisible();
      expect(interceptedUpdateCount).toBe(1);
      expect(interceptedResponseCount).toBe(1);
      expect(updateExecuted).toBe(true);
      expect(responseAborted).toBe(true);
      expect(interceptionFailure).toBe(false);
      executedUpdateRpcCount = policy.getRpcCount('customer_update_draft_request');
      expect(executedUpdateRpcCount).toBe(1);
      await markAmbiguousUpdateProgress('mutation-executed');
    });

    await withAmbiguousUpdateFailureCategory('ambiguous-ui', async () => {
      await expect(page.getByText('Draft updated.', { exact: true })).toHaveCount(0);
      await expect(page.locator('form[data-draft-edit-form] button[type="submit"]')).toBeDisabled();
      expect(interceptedUpdateCount).toBe(1);
      expect(policy.getRpcCount('customer_update_draft_request')).toBe(executedUpdateRpcCount);
    });

    await withAmbiguousUpdateFailureCategory('interception-release', async () => {
      await markAmbiguousUpdateProgress('interceptor-release-start');
      await cdpSession.send('Fetch.disable');
      await markAmbiguousUpdateProgress('fetch-disabled');
      cdpSession.off('Fetch.requestPaused', pausedUpdateHandler);
      expect(cdpSession.listenerCount('Fetch.requestPaused')).toBe(0);
      pausedUpdateHandler = undefined;
      await markAmbiguousUpdateProgress('response-listener-removed');
      await cdpSession.detach();
      cdpSession = undefined;
      interceptionReleased = true;
      await markAmbiguousUpdateProgress('cdp-detached');
      expect(policy.getRpcCount('customer_update_draft_request')).toBe(executedUpdateRpcCount);
    });

    let readBaseline;
    await withAmbiguousUpdateFailureCategory('detail-navigation', async () => {
      expect(interceptionReleased).toBe(true);
      expect(cdpSession).toBeUndefined();
      expect(pausedUpdateHandler).toBeUndefined();
      readBaseline = policy.getTableReadCount('service_requests');
      await openDraftDetail(page, requestId);
      await markAmbiguousUpdateProgress('detail-navigation');
    });

    await withAmbiguousUpdateFailureCategory('fresh-rls-read', async () => {
      await expect.poll(() => policy.getTableReadCount('service_requests')).toBe(readBaseline + 1);
      expect(policy.getRpcCount('customer_update_draft_request')).toBe(executedUpdateRpcCount);
      await markAmbiguousUpdateProgress('rls-read-observed');
    });

    await withAmbiguousUpdateFailureCategory('canonical-values', async () => {
      const detail = page.locator('.request-detail-card');
      const expectedRequestedStart = formatSastDateTime(`${edited.requestedStart}:00+02:00`);
      const expectedBudget = formatZarBudgetMinor(Math.round(Number(edited.budget) * 100));
      await expect(detail).toBeVisible();
      await expect(page.locator('form[data-draft-edit-form]')).toHaveCount(0);
      await expect(detail.locator('.request-detail-status .status-chip')).toHaveText('Draft');
      await markCanonicalValuePass('status');
      await expect(detail.locator('.request-detail-status span:not(.status-chip)'))
        .toHaveText(ACTIVE_CATEGORY_NAME);
      await markCanonicalValuePass('category');
      await expect(page.locator('.dashboard-heading h1')).toHaveText(edited.title);
      await markCanonicalValuePass('title');
      await expect(detail.getByText(edited.description, { exact: true })).toBeVisible();
      await markCanonicalValuePass('description');
      await expect(detail.getByText(edited.suburb, { exact: true })).toBeVisible();
      await markCanonicalValuePass('suburb');
      await expect(detail.getByText(edited.city, { exact: true })).toBeVisible();
      await markCanonicalValuePass('city');
      await expect(detail.getByText(expectedRequestedStart, { exact: true })).toBeVisible();
      await markCanonicalValuePass('start');
      await expect(detail.getByText(expectedBudget, { exact: true })).toBeVisible();
      await markCanonicalValuePass('budget');
      await expect(page.getByText('Draft updated.', { exact: true })).toHaveCount(0);
      expect(executedUpdateRpcCount).toBe(1);
      expect(policy.getRpcCount('customer_update_draft_request')).toBe(executedUpdateRpcCount);
      await markAmbiguousUpdateProgress('canonical-values-verified');
    });

    await withAmbiguousUpdateFailureCategory('postcondition', async () => {
      expect(interceptionReleased).toBe(true);
      expect(policy.getRpcCount('customer_update_draft_request')).toBe(executedUpdateRpcCount);
      await page.getByRole('button', { name: 'Cancel draft' }).click();
      await page.locator('[data-cancel-draft-form]').getByRole('button', { name: 'Cancel draft' }).click();
      await expect(page.getByText('Draft cancelled.', { exact: true })).toBeVisible();
      await assertCustomerLifecyclePostconditions(account.email, requestId);
      policy.assertClean();
      emissions.assertClean();
    });

    await withAmbiguousUpdateFailureCategory('sign-out', async () => {
      await signOutCustomer(page);
      await assertBrowserPrivacy(page, { markers, expectAuthSession: false });
    });
  } finally {
    let interceptionCleanupFailed = false;
    let contextCleanupFailed = false;
    if (cdpSession) {
      if (pausedUpdateHandler) {
        cdpSession.off('Fetch.requestPaused', pausedUpdateHandler);
        pausedUpdateHandler = undefined;
      }
      try {
        await cdpSession.send('Fetch.disable');
        await cdpSession.detach();
      } catch {
        interceptionCleanupFailed = true;
      }
    }
    try {
      await context?.close();
    } catch {
      contextCleanupFailed = true;
    }
    const cleanupFailureCategory = interceptionCleanupFailed ? 'interception-release' : 'cleanup';
    if (interceptionCleanupFailed || contextCleanupFailed) {
      await test.step(`ambiguous-update-failure:${cleanupFailureCategory}`, async () => {
        throw new Error('privacy-safe-ambiguous-update-boundary-failure');
      });
    } else {
      await markAmbiguousUpdateProgress('cleanup');
    }
  }
});

test('recovery routes fail closed without persisting a PKCE verifier', async ({ page }) => {
  const policy = attachNetworkPolicy(page, { appUrl, supabaseUrl, anonKey });
  const emissions = attachSensitiveEmissionAudit(page);
  await page.goto('/auth/reset-password');
  await expect(page.getByText('Recovery session required')).toBeVisible();
  await expect(page.locator('form[data-auth-form="reset-password"]')).toBeHidden();
  await page.goto('/auth/forgot-password');
  await expect(page.getByRole('heading', { name: 'Reset access safely.' })).toBeVisible();
  await assertBrowserPrivacy(page, { expectAuthSession: false });
  policy.assertClean();
  emissions.assertClean();
});
