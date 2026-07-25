import { expect, test } from '@playwright/test';
import {
  assertCustomerLifecyclePostconditions,
  assertDistinctSyntheticUsers,
  assertSyntheticRequestOwner,
  removeSyntheticProfile,
  setSyntheticProfileState,
} from './support/local-fixtures.mjs';
import {
  createDraftThroughUi,
  editedDraftValues,
  fillDraftForm,
  mainDraftValues,
  openDraftDetail,
  privacyMarkers,
  registerCustomer,
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

    await registerCustomer(pageA, customerA);
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
      const context = await browser.newContext({ baseURL: appUrl, serviceWorkers: 'allow' });
      try {
        const page = await context.newPage();
        const policy = attachNetworkPolicy(page, { appUrl, supabaseUrl, anonKey });
        const markers = privacyMarkers(account);
        const emissions = attachSensitiveEmissionAudit(page, markers);
        await registerCustomer(page, account);
        if (scenario.removeProfile) await removeSyntheticProfile(account.email);
        else await setSyntheticProfileState(account.email, scenario.state);

        const guardedReadBaseline = Object.fromEntries(
          ['service_requests', 'bookings', 'payments']
            .map((table) => [table, policy.getTableReadCount(table)]),
        );
        await page.goto('/app/customer');
        await expect(page.getByText(scenario.message)).toBeVisible();
        await expect(page.locator(`[data-state="${scenario.uiState}"]`)).toBeVisible();
        await expect(page.getByRole('link', { name: 'Create request draft' })).toHaveCount(0);
        expect(policy.getRpcCount('customer_create_draft_request')).toBe(0);
        for (const [table, count] of Object.entries(guardedReadBaseline)) {
          expect(policy.getTableReadCount(table)).toBe(count);
        }
        await assertBrowserPrivacy(page, { markers, expectAuthSession: true });
        policy.assertClean();
        emissions.assertClean();
        await signOutCustomer(page);
        await assertBrowserPrivacy(page, { markers, expectAuthSession: false });
      } finally {
        await context.close();
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
  await registerCustomer(page, account);
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

test('an executed update with an aborted response is not retried and requires a fresh read', async ({ page }) => {
  test.setTimeout(180_000);
  const account = syntheticAccount('customer-ambiguous');
  const created = mainDraftValues();
  const edited = editedDraftValues();
  const markers = privacyMarkers(account, created, edited);
  const policy = attachNetworkPolicy(page, { appUrl, supabaseUrl, anonKey });
  const emissions = attachSensitiveEmissionAudit(page, markers);
  await registerCustomer(page, account);
  const requestId = await createDraftThroughUi(page, created);
  await page.goto(`/app/customer/requests/edit/?requestId=${requestId}`);
  const editForm = await fillDraftForm(page, edited);

  const rpcPattern = '**/rest/v1/rpc/customer_update_draft_request';
  await page.route(rpcPattern, async (route) => {
    await route.fetch();
    await route.abort('failed');
  }, { times: 1 });
  await editForm.getByRole('button', { name: 'Save draft changes' }).click();
  await expect(page.getByText('The update could not be confirmed. Refresh the draft before trying again.', { exact: true })).toBeVisible();
  await expect(page.locator('form[data-draft-edit-form] button[type="submit"]')).toBeDisabled();
  expect(policy.getRpcCount('customer_update_draft_request')).toBe(1);

  await page.unroute(rpcPattern);
  await page.reload();
  await expect(page.locator('input[name="title"]')).toHaveValue(edited.title);
  expect(policy.getRpcCount('customer_update_draft_request')).toBe(1);
  await page.getByRole('link', { name: 'Back to draft' }).click();
  await page.getByRole('button', { name: 'Cancel draft' }).click();
  await page.locator('[data-cancel-draft-form]').getByRole('button', { name: 'Cancel draft' }).click();
  await expect(page.getByText('Draft cancelled.', { exact: true })).toBeVisible();
  await assertCustomerLifecyclePostconditions(account.email, requestId);
  policy.assertClean();
  emissions.assertClean();
  await signOutCustomer(page);
  await assertBrowserPrivacy(page, { markers, expectAuthSession: false });
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
