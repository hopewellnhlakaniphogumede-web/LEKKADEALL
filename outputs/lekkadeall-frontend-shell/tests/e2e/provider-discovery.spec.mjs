import { expect, test } from '@playwright/test';
import {
  PROVIDER_DISCOVERY_MATCHING_TITLE,
  PROVIDER_DISCOVERY_NONMATCHING_TITLE,
  prepareSyntheticProviderDiscovery,
  suspendSyntheticProviderDiscovery,
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

test('eligible provider discovers one safe matching request and loses it after revocation', async ({ page }) => {
  test.setTimeout(180_000);
  const provider = syntheticAccount('provider-discovery');
  const customer = syntheticAccount('discovery-customer');
  const markers = [...privacyMarkers(provider), customer.email, customer.password];
  const policy = attachNetworkPolicy(page, { appUrl, supabaseUrl, anonKey });
  const emissions = attachSensitiveEmissionAudit(page, markers);

  await test.step('provider-discovery-failure:fixture-setup', async () => {
    await prepareSyntheticProviderDiscovery(
      provider.email,
      provider.password,
      customer.email,
      customer.password,
    );
  });

  await test.step('provider-discovery-failure:browser-session', async () => {
    await signInProvider(page, provider);
    await assertBrowserPrivacy(page, { markers, expectAuthSession: true });
  });

  await test.step('provider-discovery-failure:initial-discovery', async () => {
    await expect(page.getByRole('heading', { name: PROVIDER_DISCOVERY_MATCHING_TITLE })).toBeVisible();
    await expect(page.getByRole('heading', { name: PROVIDER_DISCOVERY_NONMATCHING_TITLE })).toHaveCount(0);
    expect(policy.getRpcCount('provider_list_discoverable_requests')).toBe(1);
    expect(policy.getTableReadCount('service_requests')).toBe(0);
  });

  await test.step('provider-discovery-failure:privacy', async () => {
    const discoveryMarkup = await page.locator('[data-provider-discovery]').evaluate((element) => element.innerHTML);
    expect(discoveryMarkup).not.toMatch(/customer_id|customer_email|customer_phone|profile_id|auth_id|precise_address|ciphertext|latitude|longitude|coordinates|bid_id|booking_id|payment_id|ledger|payout|audit|moderation|created_at|updated_at/iu);
    await expect(page.getByRole('button', { name: /bid|book|message|contact|pay|payout|address/iu })).toHaveCount(0);
    await assertBrowserPrivacy(page, { markers, expectAuthSession: true });
    policy.assertClean();
    emissions.assertClean();
  });

  await test.step('provider-discovery-failure:revocation', async () => {
    await suspendSyntheticProviderDiscovery(provider.email);
  });

  await test.step('provider-discovery-failure:fresh-discovery', async () => {
    await page.getByRole('button', { name: 'Refresh requests' }).click();
    await expect(page.getByRole('heading', { name: 'Request discovery unavailable' })).toBeVisible();
    await expect(page.getByRole('heading', { name: PROVIDER_DISCOVERY_MATCHING_TITLE })).toHaveCount(0);
    await expect(page.getByText('Request discovery is unavailable right now.')).toBeVisible();
    expect(policy.getRpcCount('provider_list_discoverable_requests')).toBe(2);
    expect(policy.getTableReadCount('service_requests')).toBe(0);
    policy.assertClean();
    emissions.assertClean();
  });

  await test.step('provider-discovery-failure:sign-out', async () => {
    await signOutCustomer(page);
    await assertBrowserPrivacy(page, { markers, expectAuthSession: false });
  });
});
