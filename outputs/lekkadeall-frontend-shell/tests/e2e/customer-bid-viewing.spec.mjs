import { expect, test } from '@playwright/test';
import {
  CUSTOMER_BID_VIEWING_AWARDED_REQUEST_ID,
  CUSTOMER_BID_VIEWING_CANCELLED_REQUEST_ID,
  CUSTOMER_BID_VIEWING_DRAFT_REQUEST_ID,
  CUSTOMER_BID_VIEWING_PAST_CLOSE_REQUEST_ID,
  CUSTOMER_BID_VIEWING_REQUEST_ID,
  CUSTOMER_BID_VIEWING_TITLE,
  assertSyntheticCustomerBidViewingPostconditions,
  prepareSyntheticCustomerBidViewing,
  revokeSyntheticCustomerBidViewingService,
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
const ADJACENT_READ_TABLES = Object.freeze([
  'bids', 'bookings', 'payments', 'service_request_addresses', 'messages', 'contacts',
]);

test.beforeAll(() => {
  if (process.env.E2E_LOCAL_STACK_READY !== '1') throw new Error('local-e2e-stack-not-ready');
});

test('customer deliberately views only current bids for an owned live request', async ({ page }) => {
  test.setTimeout(240_000);
  const owner = syntheticAccount('bid-view-owner');
  const otherCustomer = syntheticAccount('bid-view-other');
  const providers = [1, 2, 3, 4, 5, 6]
    .map((number) => syntheticAccount(`bid-view-provider-${number}`));
  const markers = [
    ...privacyMarkers(owner),
    ...privacyMarkers(otherCustomer),
    ...providers.flatMap((provider) => privacyMarkers(provider)),
  ];
  const policy = attachNetworkPolicy(page, { appUrl, supabaseUrl, anonKey });
  const emissions = attachSensitiveEmissionAudit(page, markers);
  const adjacentReadBaseline = new Map();

  await test.step('customer-bid-viewing-failure:fixture-setup', async () => {
    await prepareSyntheticCustomerBidViewing({ owner, otherCustomer, providers });
  });

  await test.step('customer-bid-viewing-failure:owner-session', async () => {
    await signInCustomer(page, owner, { requireAnonymousStorage: true });
    await assertBrowserPrivacy(page, { markers, expectAuthSession: true });
  });

  await test.step('customer-bid-viewing-failure:deliberate-view', async () => {
    await openDraftDetail(page, CUSTOMER_BID_VIEWING_REQUEST_ID);
    await expect(page.getByRole('heading', { name: CUSTOMER_BID_VIEWING_TITLE })).toBeVisible();
    await expect(page.getByRole('button', { name: 'View current bids' })).toBeVisible();
    expect(policy.getRpcCount('customer_list_current_bids')).toBe(0);
    expect(policy.getTableReadCount('bids')).toBe(0);
    for (const table of ADJACENT_READ_TABLES) {
      adjacentReadBaseline.set(table, policy.getTableReadCount(table));
    }

    await page.getByRole('button', { name: 'View current bids' }).click();
    const cards = page.locator('[data-customer-bid-card]');
    await expect(cards).toHaveCount(3);
    await expect(cards.nth(0)).toContainText('ZAR 1 000.50');
    await expect(cards.nth(1)).toContainText('ZAR 1 100.00');
    await expect(cards.nth(2)).toContainText('ZAR 1 300.00');
    expect(policy.getRpcCount('customer_list_current_bids')).toBe(1);
    expect(policy.getTableReadCount('bids')).toBe(0);
  });

  await test.step('customer-bid-viewing-failure:filtered-bids', async () => {
    const panel = page.locator('[data-customer-bid-viewing]');
    await expect(panel.getByText('ZAR 1 200.00', { exact: true })).toHaveCount(0);
    await expect(panel.getByText('ZAR 1 400.00', { exact: true })).toHaveCount(0);
    await expect(panel.getByText('ZAR 1 500.00', { exact: true })).toHaveCount(0);
    await expect(panel.getByRole('button', { name: 'Accept bid' })).toHaveCount(3);
    await expect(panel.getByRole('button', { name: /Choose|Select|Book|Pay|Contact|Message/iu })).toHaveCount(0);
    const text = await panel.textContent();
    expect(text).not.toMatch(/provider|business|email|phone|message|perk|address|booking|payment|payout|audit/iu);
    for (const functionName of [
      'customer_accept_bid',
      'reveal_confirmed_booking_address',
      'create_booking',
      'create_payment',
    ]) {
      expect(policy.getRpcCount(functionName)).toBe(0);
    }
    for (const table of ADJACENT_READ_TABLES) {
      expect(policy.getTableReadCount(table)).toBe(adjacentReadBaseline.get(table));
    }
  });

  await test.step('customer-bid-viewing-failure:service-revocation', async () => {
    await revokeSyntheticCustomerBidViewingService(providers[3].email);
    await page.getByRole('button', { name: 'Refresh bids' }).click();
    const cards = page.locator('[data-customer-bid-card]');
    await expect(cards).toHaveCount(2);
    await expect(cards.nth(0)).toContainText('ZAR 1 000.50');
    await expect(cards.nth(1)).toContainText('ZAR 1 100.00');
    await expect(page.getByText('ZAR 1 300.00', { exact: true })).toHaveCount(0);
    expect(policy.getRpcCount('customer_list_current_bids')).toBe(2);
  });

  await test.step('customer-bid-viewing-failure:request-states', async () => {
    for (const requestId of [
      CUSTOMER_BID_VIEWING_DRAFT_REQUEST_ID,
      CUSTOMER_BID_VIEWING_CANCELLED_REQUEST_ID,
    ]) {
      await openDraftDetail(page, requestId);
      await expect(page.locator('[data-customer-bid-viewing]')).toHaveCount(0);
      await expect(page.locator('[data-customer-bid-card]')).toHaveCount(0);
    }

    await page.goto(`/app/customer/requests/detail/?requestId=${CUSTOMER_BID_VIEWING_AWARDED_REQUEST_ID}`);
    await expect(page.getByRole('heading', { name: 'Request not found or unavailable' })).toBeVisible();
    await expect(page.locator('[data-customer-bid-viewing]')).toHaveCount(0);

    await openDraftDetail(page, CUSTOMER_BID_VIEWING_PAST_CLOSE_REQUEST_ID);
    await page.getByRole('button', { name: 'View current bids' }).click();
    await expect(page.getByText('Current bids are unavailable right now.', { exact: true })).toBeVisible();
    await expect(page.locator('[data-customer-bid-card]')).toHaveCount(0);
    expect(policy.getRpcCount('customer_list_current_bids')).toBe(3);
  });

  await test.step('customer-bid-viewing-failure:signed-out', async () => {
    await signOutCustomer(page);
    await page.goto(`/app/customer/requests/detail/?requestId=${CUSTOMER_BID_VIEWING_REQUEST_ID}`);
    await expect(page.getByRole('heading', { name: 'Sign in required' })).toBeVisible();
    await expect(page.locator('[data-customer-bid-viewing]')).toHaveCount(0);
    expect(policy.getRpcCount('customer_list_current_bids')).toBe(3);
  });

  await test.step('customer-bid-viewing-failure:cross-customer', async () => {
    await signInCustomer(page, otherCustomer, { requireAnonymousStorage: true });
    await page.goto(`/app/customer/requests/detail/?requestId=${CUSTOMER_BID_VIEWING_REQUEST_ID}`);
    await expect(page.getByRole('heading', { name: 'Request not found or unavailable' })).toBeVisible();
    await expect(page.locator('[data-customer-bid-viewing]')).toHaveCount(0);
    expect(policy.getRpcCount('customer_list_current_bids')).toBe(3);
  });

  await test.step('customer-bid-viewing-failure:postcondition', async () => {
    await assertSyntheticCustomerBidViewingPostconditions(owner.email);
  });

  await test.step('customer-bid-viewing-failure:privacy', async () => {
    policy.assertClean();
    emissions.assertClean();
    await assertBrowserPrivacy(page, { markers, expectAuthSession: true });
  });

  await test.step('customer-bid-viewing-failure:sign-out', async () => {
    await signOutCustomer(page);
    await assertBrowserPrivacy(page, { markers, expectAuthSession: false });
  });
});
