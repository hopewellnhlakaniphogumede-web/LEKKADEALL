import { expect, test } from '@playwright/test';
import {
  PROVIDER_DISCOVERY_MATCHING_TITLE,
  assertSyntheticProviderBiddingPostconditions,
  prepareSyntheticProviderDiscovery,
} from './support/local-fixtures.mjs';
import {
  privacyMarkers,
  signInProvider,
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

test('eligible provider submits and withdraws one server-reconciled bid', async ({ page }) => {
  test.setTimeout(180_000);
  const provider = syntheticAccount('provider-bidding');
  const customer = syntheticAccount('bidding-customer');
  const markers = [...privacyMarkers(provider), customer.email, customer.password];
  const policy = attachNetworkPolicy(page, { appUrl, supabaseUrl, anonKey });
  const emissions = attachSensitiveEmissionAudit(page, markers);

  await test.step('provider-bidding-failure:fixture-setup', async () => {
    await prepareSyntheticProviderDiscovery(
      provider.email,
      provider.password,
      customer.email,
      customer.password,
    );
  });

  await test.step('provider-bidding-failure:browser-session', async () => {
    await signInProvider(page, provider);
    await assertBrowserPrivacy(page, { markers, expectAuthSession: true });
  });

  await test.step('provider-bidding-failure:discoverable-request', async () => {
    await expect(page.getByRole('heading', { name: PROVIDER_DISCOVERY_MATCHING_TITLE })).toBeVisible();
    await expect(page.locator('[data-provider-bid-form]')).toBeVisible();
    expect(policy.getRpcCount('provider_list_discoverable_requests')).toBe(1);
    expect(policy.getRpcCount('provider_read_own_bid')).toBe(1);
    expect(policy.getRpcCount('provider_submit_bid')).toBe(0);
    expect(policy.getRpcCount('provider_withdraw_bid')).toBe(0);
    expect(policy.getTableReadCount('service_requests')).toBe(0);
  });

  await test.step('provider-bidding-failure:confirmed-submit', async () => {
    const form = page.locator('[data-provider-bid-form]');
    await form.locator('input[name="bid-amount"]').fill('1000.50');
    await form.getByRole('button', { name: 'Review bid' }).click();
    await expect(page.getByRole('heading', { name: 'Submit this bid?' })).toBeVisible();
    expect(policy.getRpcCount('provider_submit_bid')).toBe(0);
    await page.getByRole('button', { name: 'Submit bid' }).click();
    await expect(page.getByText('Bid submitted.', { exact: true })).toBeVisible();
    await expect(page.getByText('submitted', { exact: true })).toBeVisible();
    expect(policy.getRpcCount('provider_submit_bid')).toBe(1);
    expect(policy.getRpcCount('provider_read_own_bid')).toBe(2);
  });

  await test.step('provider-bidding-failure:confirmed-withdrawal', async () => {
    await page.getByRole('button', { name: 'Withdraw bid' }).click();
    await expect(page.getByRole('heading', { name: 'Withdraw this bid?' })).toBeVisible();
    expect(policy.getRpcCount('provider_withdraw_bid')).toBe(0);
    await page.getByRole('button', { name: 'Withdraw bid' }).click();
    await expect(page.getByText('Bid withdrawn.', { exact: true })).toBeVisible();
    await expect(page.getByText('withdrawn', { exact: true })).toBeVisible();
    expect(policy.getRpcCount('provider_withdraw_bid')).toBe(1);
    expect(policy.getRpcCount('provider_read_own_bid')).toBe(3);
  });

  await test.step('provider-bidding-failure:terminal-controls', async () => {
    await expect(page.locator('[data-provider-bid-form]')).toHaveCount(0);
    await expect(page.locator('[data-provider-bid-confirm-form]')).toHaveCount(0);
    await expect(page.getByRole('button', { name: /submit bid|withdraw bid/iu })).toHaveCount(0);
    await expect(page.getByRole('button', { name: /accept|book|contact|message|pay|address/iu })).toHaveCount(0);
    policy.assertClean();
  });

  await test.step('provider-bidding-failure:postcondition', async () => {
    await assertSyntheticProviderBiddingPostconditions(provider.email);
  });

  await test.step('provider-bidding-failure:privacy', async () => {
    const markup = await page.locator('[data-provider-bid]').evaluate((element) => element.innerHTML);
    expect(markup).not.toMatch(/customer_id|customer_email|customer_phone|provider_id|precise_address|ciphertext|latitude|longitude|coordinates|booking_id|payment_id|ledger|payout|audit|moderation|customer_message|message_body|created_at|updated_at/iu);
    await assertBrowserPrivacy(page, { markers, expectAuthSession: true });
    policy.assertClean();
    emissions.assertClean();
  });

  await test.step('provider-bidding-failure:sign-out', async () => {
    await signOutCustomer(page);
    await assertBrowserPrivacy(page, { markers, expectAuthSession: false });
  });
});
