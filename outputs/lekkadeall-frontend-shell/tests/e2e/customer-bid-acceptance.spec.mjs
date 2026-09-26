import { expect, test } from '@playwright/test';
import {
  CUSTOMER_BID_ACCEPTANCE_REQUEST_ID,
  CUSTOMER_BID_VIEWING_REQUEST_ID,
  assertSyntheticCustomerBidAcceptancePostconditions,
  prepareSyntheticCustomerBidAcceptance,
  staleSyntheticCustomerBidAcceptanceRequest,
} from './support/local-fixtures.mjs';
import {
  openDraftDetail,
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

test('customer accepts one current bid and reconciles one executed ambiguous response', async ({ page }) => {
  test.setTimeout(240_000);
  const owner = syntheticAccount('bid-accept-owner');
  const otherCustomer = syntheticAccount('bid-accept-other');
  const providers = [1, 2, 3, 4, 5, 6]
    .map((number) => syntheticAccount(`bid-accept-provider-${number}`));
  const markers = [
    ...privacyMarkers(owner),
    ...privacyMarkers(otherCustomer),
    ...providers.flatMap((provider) => privacyMarkers(provider)),
  ];
  const policy = attachNetworkPolicy(page, { appUrl, supabaseUrl, anonKey });
  const emissions = attachSensitiveEmissionAudit(page, markers);
  let directBidId;
  let recoveredBidId;

  await test.step('customer-bid-acceptance-failure:fixture-setup', async () => {
    ({ directBidId, recoveredBidId } = await prepareSyntheticCustomerBidAcceptance({
      owner, otherCustomer, providers,
    }));
  });

  await test.step('customer-bid-acceptance-failure:owner-session', async () => {
    await signInCustomer(page, owner, { requireAnonymousStorage: true });
    await assertBrowserPrivacy(page, { markers, expectAuthSession: true });
  });

  await test.step('customer-bid-acceptance-failure:direct-confirmation', async () => {
    await openDraftDetail(page, CUSTOMER_BID_VIEWING_REQUEST_ID);
    await expect(page.getByRole('button', { name: 'View current bids' })).toBeVisible();
    expect(policy.getRpcCount('customer_accept_current_bid')).toBe(0);
    await page.getByRole('button', { name: 'View current bids' }).click();
    await expect(page.locator('[data-customer-bid-card]')).toHaveCount(3);
    await page.getByRole('button', { name: 'Accept bid' }).first().click();
    await expect(page.getByRole('alertdialog')).toBeVisible();
    expect(policy.getRpcCount('customer_accept_current_bid')).toBe(0);
    await page.getByRole('button', { name: 'Cancel', exact: true }).click();
    expect(policy.getRpcCount('customer_accept_current_bid')).toBe(0);
    expect(policy.getRpcCount('customer_reconcile_bid_acceptance')).toBe(0);
  });

  await test.step('customer-bid-acceptance-failure:stale-version', async () => {
    await staleSyntheticCustomerBidAcceptanceRequest();
    await page.getByRole('button', { name: 'Accept bid' }).first().click();
    await page.getByRole('button', { name: 'Confirm acceptance' }).click();
    await expect(page.getByText('Bid acceptance is unavailable. Refresh the request and bids before trying again.', { exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Accept bid' })).toHaveCount(0);
    await expect(page.getByRole('heading', { name: 'Bid accepted. This request is now awarded.' })).toHaveCount(0);
    expect(policy.getRpcCount('customer_accept_current_bid')).toBe(1);
    expect(policy.getRpcCount('customer_reconcile_bid_acceptance')).toBe(1);
  });

  await test.step('customer-bid-acceptance-failure:direct-success', async () => {
    await page.getByRole('button', { name: 'Refresh request' }).click();
    await page.getByRole('button', { name: 'View current bids' }).click();
    await expect(page.locator('[data-customer-bid-card]')).toHaveCount(3);
    await page.getByRole('button', { name: 'Accept bid' }).first().click();
    await page.getByRole('button', { name: 'Confirm acceptance' }).click();
    await expect(page.getByRole('heading', { name: 'Bid accepted. This request is now awarded.' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Accept bid' })).toHaveCount(0);
    expect(policy.getRpcCount('customer_accept_current_bid')).toBe(2);
    expect(policy.getRpcCount('customer_reconcile_bid_acceptance')).toBe(1);
    expect(policy.getTableReadCount('bids')).toBe(0);
  });

  await test.step('customer-bid-acceptance-failure:ambiguous-reconciliation', async () => {
    await openDraftDetail(page, CUSTOMER_BID_ACCEPTANCE_REQUEST_ID);
    await page.getByRole('button', { name: 'View current bids' }).click();
    await expect(page.locator('[data-customer-bid-card]')).toHaveCount(1);
    let acceptedKey = null;
    let reconciledKey = null;
    await page.route('**/rest/v1/rpc/customer_accept_current_bid', async (route) => {
      if (route.request().method() !== 'POST') {
        await route.continue();
        return;
      }
      acceptedKey = route.request().postDataJSON()?.p_idempotency_key ?? null;
      await route.fetch();
      await route.abort('failed');
    });
    await page.route('**/rest/v1/rpc/customer_reconcile_bid_acceptance', async (route) => {
      reconciledKey = route.request().postDataJSON()?.p_idempotency_key ?? null;
      await route.continue();
    });
    await page.getByRole('button', { name: 'Accept bid' }).click();
    await page.getByRole('button', { name: 'Confirm acceptance' }).click();
    await expect(page.getByRole('heading', { name: 'Bid accepted. This request is now awarded.' })).toBeVisible();
    expect(acceptedKey).toMatch(/^[0-9a-f-]{36}$/iu);
    expect(reconciledKey).toBe(acceptedKey);
    expect(policy.getRpcCount('customer_accept_current_bid')).toBe(3);
    expect(policy.getRpcCount('customer_reconcile_bid_acceptance')).toBe(2);
    await expect(page.getByRole('button', { name: 'Accept bid' })).toHaveCount(0);
    await page.unroute('**/rest/v1/rpc/customer_accept_current_bid');
    await page.unroute('**/rest/v1/rpc/customer_reconcile_bid_acceptance');
  });

  await test.step('customer-bid-acceptance-failure:postcondition', async () => {
    await assertSyntheticCustomerBidAcceptancePostconditions(owner.email, directBidId, recoveredBidId);
    expect(policy.getTableReadCount('bids')).toBe(0);
    expect(policy.getTableReadCount('customer_bid_acceptance_receipts')).toBe(0);
  });

  await test.step('customer-bid-acceptance-failure:foreign-denial', async () => {
    await signOutCustomer(page);
    await signInCustomer(page, otherCustomer, { requireAnonymousStorage: true });
    await openDraftDetail(page, CUSTOMER_BID_VIEWING_REQUEST_ID);
    await expect(page.getByRole('heading', { name: 'Request not found or unavailable' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Accept bid' })).toHaveCount(0);
    expect(policy.getRpcCount('customer_accept_current_bid')).toBe(3);
  });

  await test.step('customer-bid-acceptance-failure:privacy', async () => {
    policy.assertClean();
    emissions.assertClean();
    await assertBrowserPrivacy(page, { markers, expectAuthSession: true });
    await signOutCustomer(page);
    await assertBrowserPrivacy(page, { markers, expectAuthSession: false });
  });
});
