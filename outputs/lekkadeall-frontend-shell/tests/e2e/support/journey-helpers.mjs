import { createHash, randomBytes } from 'node:crypto';
import { expect, test } from '@playwright/test';
import {
  ACTIVE_CATEGORY_ID,
  assertSyntheticAccountAbsent,
  reconcileAmbiguousUiSignup,
  waitForProvisionedCustomerProfile,
} from './local-fixtures.mjs';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const E2E_RUN_ID_PATTERN = /^r(?:[0-9]{1,20}|local[0-9]{1,10})-a[0-9]{1,6}-[0-9a-f]{8}$/u;
const AUTH_STORAGE_KEY_PATTERN = /^sb-[a-z0-9-]+-auth-token$/iu;
const EMAIL_LOCAL_PART_MAX_LENGTH = 64;

function testIdentityComponent() {
  const title = String(test.info().title ?? '');
  if (!title) throw new Error('synthetic-test-identity-invalid');
  return createHash('sha256').update(title).digest('hex').slice(0, 6);
}

export function syntheticAccount(label) {
  const runId = String(process.env.E2E_RUN_ID ?? '');
  const actor = String(label ?? '').toLowerCase();
  if (!E2E_RUN_ID_PATTERN.test(runId) || !/^[a-z0-9][a-z0-9-]{0,23}$/u.test(actor)) {
    throw new Error('synthetic-account-identity-invalid');
  }
  const testComponent = testIdentityComponent();
  const actorComponent = createHash('sha256').update(actor).digest('hex').slice(0, 6);
  const actorSuffix = createHash('sha256')
    .update(`${runId}:${testComponent}:${actor}`)
    .digest('hex')
    .slice(0, 10);
  const localPart = `${runId}.${testComponent}.${actorComponent}.${actorSuffix}`;
  if (localPart.length > EMAIL_LOCAL_PART_MAX_LENGTH) {
    throw new Error('synthetic-account-identity-too-long');
  }
  return Object.freeze({
    email: `${localPart}@lekkadeall.invalid`,
    password: `E2e-${randomBytes(18).toString('base64url')}!9`,
  });
}

async function authStorageEntryCount(page) {
  return page.evaluate((patternSource) => {
    const pattern = new RegExp(patternSource, 'iu');
    let count = 0;
    for (let index = 0; index < localStorage.length; index += 1) {
      if (pattern.test(localStorage.key(index) ?? '')) count += 1;
    }
    return count;
  }, AUTH_STORAGE_KEY_PATTERN.source);
}

async function failRegistration(category) {
  await test.step(`registration-failure:${category}`, async () => {
    throw new Error('privacy-safe-registration-failure');
  });
}

async function reconcileSingleUiSignup(page, account, signupRequestCount) {
  if (signupRequestCount === 0) {
    await failRegistration('signup-network-failure');
    return;
  }
  if (signupRequestCount !== 1) {
    await failRegistration('signup-duplicate-request');
    return;
  }
  try {
    await reconcileAmbiguousUiSignup(account.email);
  } catch (error) {
    if (error?.message === 'synthetic-ui-signup-reconciliation-absent') {
      await failRegistration('signup-unexpected-collision');
    } else if (error?.message === 'synthetic-ui-signup-reconciliation-invalid') {
      await failRegistration('signup-reconciliation-invalid');
    } else {
      await failRegistration('profile-readiness-timeout');
    }
    return;
  }
  const storageCount = await authStorageEntryCount(page);
  if (storageCount === 0) {
    try {
      await signInCustomer(page, account);
    } catch {
      await failRegistration('signup-reconciliation-session-failure');
    }
  } else if (storageCount !== 1) {
    await failRegistration('signup-reconciliation-session-failure');
  }
}

export async function registerCustomer(page, account) {
  await test.step('registration-phase:identity-precondition', async () => {
    try {
      await assertSyntheticAccountAbsent(account.email);
    } catch {
      await failRegistration('signup-unexpected-collision');
    }
  });
  await page.goto('/auth/register');
  const form = page.locator('form[data-auth-form="register"]');
  await form.locator('input[name="email"]').fill(account.email);
  await form.locator('input[name="password"]').fill(account.password);

  await test.step('registration-phase:signup-request', async () => {
    let response;
    let signupRequestCount = 0;
    const countSignupRequest = (request) => {
      try {
        const url = new URL(request.url());
        if (url.pathname === '/auth/v1/signup' && request.method() === 'POST') {
          signupRequestCount += 1;
        }
      } catch {
        // A malformed request cannot be the exact loopback signup boundary.
      }
    };
    page.on('request', countSignupRequest);
    try {
      const signupResponse = page.waitForResponse((candidate) => {
        const url = new URL(candidate.url());
        return url.pathname === '/auth/v1/signup'
          && candidate.request().method() === 'POST';
      });
      await form.getByRole('button', { name: 'Create account' }).click();
      response = await signupResponse;
    } catch {
      await reconcileSingleUiSignup(page, account, signupRequestCount);
      return;
    } finally {
      page.off('request', countSignupRequest);
    }
    if (signupRequestCount !== 1) {
      await failRegistration('signup-duplicate-request');
      return;
    }
    if (response.status() === 429) {
      await failRegistration('signup-http-429');
    } else if (response.status() === 409) {
      await failRegistration('signup-http-409');
    } else if (response.status() === 422) {
      await failRegistration('signup-http-422');
    } else if (!response.ok()) {
      await failRegistration('signup-http-other');
    }
  });

  await test.step('registration-phase:auth-session', async () => {
    try {
      await expect.poll(
        () => authStorageEntryCount(page),
        { timeout: 30_000, message: 'local Auth session readiness failed' },
      ).toBe(1);
    } catch {
      await failRegistration('signup-session-missing');
    }
  });

  await test.step('registration-phase:profile-ready', async () => {
    try {
      await waitForProvisionedCustomerProfile(account.email);
    } catch {
      await failRegistration('profile-readiness-timeout');
    }
  });

  await test.step('registration-phase:dashboard', async () => {
    await expect(page).toHaveURL(/\/app\/customer\/?$/u);
    await expect(page.getByRole('heading', { name: 'Your safe account view.' })).toBeVisible();
  });
}

export async function signOutCustomer(page) {
  await page.getByRole('button', { name: 'Sign out' }).first().click();
  await expect(page).toHaveURL(/\/auth\/sign-in\/?$/u);
  await expect(page.getByRole('heading', { name: 'Sign in to your workspace.' })).toBeVisible();
}

export async function signInCustomer(page, account) {
  await page.goto('/auth/sign-in');
  const form = page.locator('form[data-auth-form="sign-in"]');
  await form.locator('input[name="email"]').fill(account.email);
  await form.locator('input[name="password"]').fill(account.password);
  let response;
  try {
    const signInResponse = page.waitForResponse((candidate) => {
      const url = new URL(candidate.url());
      return url.pathname === '/auth/v1/token'
        && url.searchParams.get('grant_type') === 'password'
        && candidate.request().method() === 'POST';
    }, { timeout: 30_000 });
    await form.getByRole('button', { name: 'Sign in' }).click();
    response = await signInResponse;
  } catch {
    throw new Error('fixture-sign-in-network-failure');
  }
  if (response.status() === 429) throw new Error('fixture-sign-in-http-429');
  if (!response.ok()) throw new Error('fixture-sign-in-http-failure');
  try {
    await expect.poll(
      () => authStorageEntryCount(page),
      { timeout: 30_000, message: 'local Auth session readiness failed' },
    ).toBe(1);
  } catch {
    throw new Error('fixture-sign-in-session-missing');
  }
  await expect(page).toHaveURL(/\/app\/customer\/?$/u, { timeout: 30_000 });
  await expect(page.getByRole('heading', { name: 'Your safe account view.' })).toBeVisible({ timeout: 30_000 });
}

export function futureSastInput(days = 3, minuteOffset = 0) {
  const target = new Date(Date.now() + (days * 24 * 60 * 60 * 1000) + (minuteOffset * 60 * 1000));
  return new Date(target.getTime() + (2 * 60 * 60 * 1000)).toISOString().slice(0, 16);
}

export async function fillDraftForm(page, values) {
  const form = page.locator('form.request-form');
  await form.locator('select[name="category"]').selectOption(values.categoryId ?? ACTIVE_CATEGORY_ID);
  await form.locator('input[name="title"]').fill(values.title);
  await form.locator('textarea[name="description"]').fill(values.description);
  await form.locator('input[name="suburb"]').fill(values.suburb);
  await form.locator('input[name="city"]').fill(values.city);
  await form.locator('input[name="requested-start"]').fill(values.requestedStart);
  await form.locator('input[name="budget"]').fill(values.budget);
  return form;
}

export async function createDraftThroughUi(page, values) {
  await page.goto('/app/customer/requests/new/');
  await expect(page.getByRole('heading', { name: 'Create a private draft.' })).toBeVisible();
  const form = await fillDraftForm(page, values);
  await form.getByRole('button', { name: 'Create private draft' }).click();
  await expect(page.getByRole('heading', { name: 'Your request draft is saved.' })).toBeVisible();
  const href = await page.getByRole('link', { name: 'View draft' }).getAttribute('href');
  const requestId = new URL(href, 'http://127.0.0.1').searchParams.get('requestId');
  if (!UUID_PATTERN.test(requestId ?? '')) throw new Error('draft-created-without-valid-request-id');
  return requestId;
}

export async function openDraftDetail(page, requestId) {
  if (!UUID_PATTERN.test(requestId)) throw new Error('request-id-invalid');
  await page.goto(`/app/customer/requests/detail/?requestId=${requestId}`);
  await expect(page.locator('.request-detail-card')).toBeVisible();
}

export function mainDraftValues() {
  return Object.freeze({
    categoryId: ACTIVE_CATEGORY_ID,
    title: 'Prepare lounge walls',
    description: 'Prepare and paint the lounge walls using a neutral finish.',
    suburb: 'Woodstock',
    city: 'Cape Town',
    requestedStart: futureSastInput(3),
    budget: '2450.50',
  });
}

export function editedDraftValues() {
  return Object.freeze({
    categoryId: ACTIVE_CATEGORY_ID,
    title: 'Prepare lounge and study walls',
    description: 'Prepare and paint the lounge and study walls using a neutral finish.',
    suburb: 'Woodstock',
    city: 'Cape Town',
    requestedStart: futureSastInput(4, 30),
    budget: '3100.00',
  });
}

export function privacyMarkers(account, ...drafts) {
  return [
    account.email,
    account.password,
    ...drafts.flatMap((draft) => [
      draft.title,
      draft.description,
      draft.suburb,
      draft.city,
      draft.requestedStart,
      draft.budget,
    ]),
  ];
}

export { AUTH_STORAGE_KEY_PATTERN, E2E_RUN_ID_PATTERN, UUID_PATTERN };
