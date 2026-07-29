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
  'browser-session',
  'fixture-state-application',
  'route-guard-verification',
  'sign-out',
]);

async function withNegativeActorFailureCategory(actor, category, operation) {
  if (!NEGATIVE_ACTORS.has(actor) || !NEGATIVE_ACTOR_FAILURE_CATEGORIES.has(category)) {
    throw new Error('negative-actor-failure-category-invalid');
  }
  try {
    return await operation();
  } catch {
    await test.step(`negative-actor-failure:${actor}:${category}`, async () => {
      throw new Error('privacy-safe-negative-actor-boundary-failure');
    });
    return undefined;
  }
}

const AMBIGUOUS_UPDATE_FAILURE_CATEGORIES = new Set([
  'isolated-setup',
  'single-update-execution',
  'ambiguous-ui',
  'interception-release',
  'fresh-rls-read',
  'postcondition',
  'sign-out',
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

        await test.step(`negative-actor-phase:${scenario.label}:browser-session`, async () => {
          await withNegativeActorFailureCategory(scenario.label, 'browser-session', async () => {
            context = await browser.newContext({ baseURL: appUrl, serviceWorkers: 'allow' });
            page = await context.newPage();
            policy = attachNetworkPolicy(page, { appUrl, supabaseUrl, anonKey });
            markers = privacyMarkers(account);
            emissions = attachSensitiveEmissionAudit(page, markers);
            await signInCustomer(page, account);
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
      } finally {
        await context?.close();
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
  const context = await browser.newContext({ baseURL: appUrl, serviceWorkers: 'allow' });
  let page;
  let policy;
  let emissions;
  let requestId;
  let cdpSession;
  let pausedUpdateHandler;
  try {
    await withAmbiguousUpdateFailureCategory('isolated-setup', async () => {
      page = await context.newPage();
      policy = attachNetworkPolicy(page, { appUrl, supabaseUrl, anonKey });
      emissions = attachSensitiveEmissionAudit(page, markers);
      await prepareSyntheticCustomerAccount(account.email, account.password);
      await signInCustomer(page, account);
      requestId = await createDraftThroughUi(page, created);
      await page.goto(`/app/customer/requests/edit/?requestId=${requestId}`);
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
          if (event.requestId !== firstUpdateRequestId) {
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
      expect(policy.getRpcCount('customer_update_draft_request')).toBe(1);
    });

    await withAmbiguousUpdateFailureCategory('ambiguous-ui', async () => {
      await expect(page.getByText('Draft updated.', { exact: true })).toHaveCount(0);
      await expect(page.locator('form[data-draft-edit-form] button[type="submit"]')).toBeDisabled();
      expect(interceptedUpdateCount).toBe(1);
    });

    await withAmbiguousUpdateFailureCategory('interception-release', async () => {
      await cdpSession.send('Fetch.disable');
      cdpSession.off('Fetch.requestPaused', pausedUpdateHandler);
      pausedUpdateHandler = undefined;
      await cdpSession.detach();
      cdpSession = undefined;
    });

    await withAmbiguousUpdateFailureCategory('fresh-rls-read', async () => {
      const readBaseline = policy.getTableReadCount('service_requests');
      await openDraftDetail(page, requestId);
      await expect.poll(() => policy.getTableReadCount('service_requests')).toBeGreaterThan(readBaseline);
      const detail = page.locator('.request-detail-card');
      const expectedRequestedStart = formatSastDateTime(`${edited.requestedStart}:00+02:00`);
      const expectedBudget = formatZarBudgetMinor(Math.round(Number(edited.budget) * 100));
      await expect(page.getByRole('heading', { name: edited.title, exact: true })).toBeVisible();
      await expect(detail.getByText('Draft', { exact: true })).toBeVisible();
      await expect(detail.getByText(ACTIVE_CATEGORY_NAME, { exact: true })).toBeVisible();
      await expect(detail.getByText(edited.description, { exact: true })).toBeVisible();
      await expect(detail.getByText(edited.suburb, { exact: true })).toBeVisible();
      await expect(detail.getByText(edited.city, { exact: true })).toBeVisible();
      await expect(detail.getByText(expectedRequestedStart, { exact: true })).toBeVisible();
      await expect(detail.getByText(expectedBudget, { exact: true })).toBeVisible();
      await expect(page.getByText('Draft updated.', { exact: true })).toHaveCount(0);
      expect(policy.getRpcCount('customer_update_draft_request')).toBe(1);
    });

    await withAmbiguousUpdateFailureCategory('postcondition', async () => {
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
    if (cdpSession) {
      if (pausedUpdateHandler) cdpSession.off('Fetch.requestPaused', pausedUpdateHandler);
      try {
        await cdpSession.send('Fetch.disable');
        await cdpSession.detach();
      } catch {
        // The context teardown below is the final fail-closed cleanup boundary.
      }
    }
    await context.close();
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
