import { expect, test } from '@playwright/test';
import {
  ACTIVE_CATEGORY_NAME,
  assertCustomerLifecyclePostconditions,
  assertProvisionedCustomerProfile,
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

test('signed-out customer routes and absent admin route fail closed', async ({ page }) => {
  const policy = attachNetworkPolicy(page, { appUrl, supabaseUrl, anonKey });
  const emissions = attachSensitiveEmissionAudit(page);
  for (const route of [
    '/app/customer',
    '/app/customer/requests',
    '/app/customer/requests/new/',
    '/app/customer/requests/detail/?requestId=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    '/app/customer/requests/edit/?requestId=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  ]) {
    await page.goto(route);
    await expect(page.getByText('Sign in required')).toBeVisible();
  }
  await page.goto('/admin');
  await expect(page.getByRole('heading', { name: 'That page is not available.' })).toBeVisible();
  await assertBrowserPrivacy(page, { expectAuthSession: false });
  policy.assertClean();
  emissions.assertClean();
});

test('customer registration through cancelled draft completes against real local RLS and RPCs', async ({ page }) => {
  test.setTimeout(300_000);
  const account = syntheticAccount('customer-lifecycle');
  const created = mainDraftValues();
  const edited = editedDraftValues();
  const markers = privacyMarkers(account, created, edited);
  const policy = attachNetworkPolicy(page, { appUrl, supabaseUrl, anonKey });
  const emissions = attachSensitiveEmissionAudit(page, markers);
  let requestId;

  await test.step('lifecycle-phase:registration', async () => {
  await registerCustomer(page, account);
  expect(policy.getSignupCount()).toBe(1);
  await assertProvisionedCustomerProfile(account.email);
  await assertBrowserPrivacy(page, { markers, expectAuthSession: true });
  });

  await test.step('lifecycle-phase:reauthentication', async () => {
  await signOutCustomer(page);
  await assertBrowserPrivacy(page, { markers, expectAuthSession: false });
  await signInCustomer(page, account);
  await assertBrowserPrivacy(page, { markers, expectAuthSession: true });
  });

  await test.step('lifecycle-phase:category-dashboard', async () => {
  await page.goto('/services');
  await expect(page.getByText(ACTIVE_CATEGORY_NAME)).toBeVisible();
  await expect(page.getByText('Synthetic inactive category')).toHaveCount(0);
  await page.goto('/app/customer');
  await expect(page.getByRole('heading', { name: 'Your safe account view.' })).toBeVisible();
  await expect(page.getByText('Mock/sandbox — no real money moved')).toBeVisible();
  });

  await test.step('lifecycle-phase:create', async () => {
  requestId = await createDraftThroughUi(page, created);
  expect(policy.getRpcCount('customer_create_draft_request')).toBe(1);
  await assertBrowserPrivacy(page, { markers, expectAuthSession: true });
  });

  await test.step('lifecycle-phase:list-detail', async () => {
  await page.getByRole('link', { name: 'View all requests' }).click();
  await expect(page).toHaveURL(/\/app\/customer\/requests\/?$/u);
  await expect(page.getByRole('heading', { name: created.title })).toBeVisible();
  await expect(page.getByText('Draft', { exact: true })).toBeVisible();

  await openDraftDetail(page, requestId);
  await expect(page.getByRole('heading', { name: created.title })).toBeVisible();
  await expect(page.getByText(created.description)).toBeVisible();
  await expect(page.getByRole('link', { name: 'Edit draft' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Cancel draft' })).toBeVisible();
  await expect(page.getByRole('button', { name: /publish/iu })).toHaveCount(0);
  });

  await test.step('lifecycle-phase:update', async () => {
  await page.getByRole('link', { name: 'Edit draft' }).click();
  await expect(page.getByRole('heading', { name: 'Edit your private draft.' })).toBeVisible();
  const editForm = await fillDraftForm(page, edited);
  await editForm.getByRole('button', { name: 'Save draft changes' }).click();
  await expect(page.getByText('Draft updated.', { exact: true })).toBeVisible();
  expect(policy.getRpcCount('customer_update_draft_request')).toBe(1);
  await expect(page.locator('input[name="title"]')).toHaveValue(edited.title);
  await assertBrowserPrivacy(page, { markers, expectAuthSession: true });
  });

  await test.step('lifecycle-phase:cancel', async () => {
  await page.getByRole('link', { name: 'Back to draft' }).click();
  await expect(page.getByRole('heading', { name: edited.title })).toBeVisible();
  await expect(page.getByText(edited.description)).toBeVisible();
  await page.getByRole('button', { name: 'Cancel draft' }).click();
  await expect(page.getByRole('heading', { name: 'Cancel this draft?' })).toBeVisible();
  await expect(page.locator('[data-cancel-draft-form] input, [data-cancel-draft-form] textarea')).toHaveCount(0);
  await page.locator('[data-cancel-draft-form]').getByRole('button', { name: 'Cancel draft' }).click();
  await expect(page.getByText('Draft cancelled.', { exact: true })).toBeVisible();
  await expect(page.getByText('Cancelled', { exact: true })).toBeVisible();
  expect(policy.getRpcCount('customer_cancel_draft_request')).toBe(1);
  await expect(page.getByRole('link', { name: 'Edit draft' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Cancel draft' })).toHaveCount(0);
  });

  await test.step('lifecycle-phase:postcondition', async () => {
  await page.getByRole('link', { name: 'View all requests' }).click();
  await expect(page.getByRole('heading', { name: edited.title })).toBeVisible();
  await expect(page.getByText('Cancelled', { exact: true })).toBeVisible();
  await assertCustomerLifecyclePostconditions(account.email, requestId);
  await assertBrowserPrivacy(page, { markers, expectAuthSession: true });

  policy.assertClean();
  emissions.assertClean();
  });
  await test.step('lifecycle-phase:sign-out', async () => {
  await signOutCustomer(page);
  await assertBrowserPrivacy(page, { markers, expectAuthSession: false });
  });
});
