import { expect, test } from '@playwright/test';
import { prepareSyntheticCustomerAccount } from './support/local-fixtures.mjs';
import {
  privacyMarkers,
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

test('blocked marketplace and privileged controls remain absent from the customer shell', async ({ page }) => {
  const account = syntheticAccount('customer-blocked');
  const markers = privacyMarkers(account);
  const policy = attachNetworkPolicy(page, { appUrl, supabaseUrl, anonKey });
  const emissions = attachSensitiveEmissionAudit(page, markers);
  await page.goto('/');
  await assertBrowserPrivacy(page, { markers, expectAuthSession: false });
  await prepareSyntheticCustomerAccount(account.email, account.password);
  await signInCustomer(page, account);

  await page.goto('/app/customer/requests/new/');
  await expect(page.locator('form[data-draft-request-form]')).toBeVisible();
  const allowedNames = await page.locator('form[data-draft-request-form] [name]').evaluateAll((elements) => (
    elements.map((element) => element.getAttribute('name')).sort()
  ));
  expect(allowedNames).toEqual([
    'budget', 'category', 'city', 'description', 'requested-start', 'suburb', 'title',
  ]);
  await expect(page.getByRole('button', { name: /publish|bid|book|pay|checkout|refund|payout|dispute|admin|profile/iu })).toHaveCount(0);
  await expect(page.locator('[name*="address" i], [name*="street" i], [name*="unit" i], [name*="room" i], [name*="phone" i], [name*="email" i], [name*="gps" i], [name*="latitude" i], [name*="longitude" i], [name*="card" i], [name*="cvv" i], [name*="payment" i]')).toHaveCount(0);

  await page.goto('/app/settings');
  await expect(page.getByRole('heading', { name: 'Read-only account view.' })).toBeVisible();
  await expect(page.locator('form')).toHaveCount(0);
  await expect(page.getByText('Editing is unavailable')).toBeVisible();

  await page.goto('/app/provider');
  await expect(page.getByText('Access denied')).toBeVisible();
  await page.goto('/admin');
  await expect(page.getByRole('heading', { name: 'That page is not available.' })).toBeVisible();

  expect(policy.getRpcCount('customer_create_draft_request')).toBe(0);
  expect(policy.getRpcCount('customer_update_draft_request')).toBe(0);
  expect(policy.getRpcCount('customer_cancel_draft_request')).toBe(0);
  expect(policy.getRpcCount('customer_publish_draft_request')).toBe(0);
  await assertBrowserPrivacy(page, { markers, expectAuthSession: true });
  policy.assertClean();
  emissions.assertClean();
  await signOutCustomer(page);
  await assertBrowserPrivacy(page, { markers, expectAuthSession: false });
});
