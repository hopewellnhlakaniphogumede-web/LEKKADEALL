import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  CUSTOMER_PROVIDER_APPLICATION_RPC,
  PROVIDER_APPLICATION_AMBIGUOUS_MESSAGE,
  PROVIDER_APPLICATION_CONFIRM_TEXT,
  PROVIDER_APPLICATION_CONFIRM_TITLE,
  PROVIDER_APPLICATION_SUCCESS_MESSAGE,
  PROVIDER_APPLICATION_TERMS_VERSION,
  PROVIDER_APPLICATION_UNAVAILABLE_MESSAGE,
  isConfirmedPendingProviderApplication,
  isEligibleCustomerProviderApplication,
  submitCustomerProviderApplication,
  validateProviderApplication,
} from '../provider-application.js';
import { SAFE_PROJECTIONS } from '../safe-reads.js';
import { renderRoute } from '../shell.js';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const actorId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const categoryId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const categories = [{ id: categoryId, slug: 'painting', name: 'Painting' }];

function applicationValues(overrides = {}) {
  return {
    businessName: 'Owner Services',
    serviceRadiusKm: '25',
    categoryIds: [categoryId],
    acceptedTerms: true,
    ...overrides,
  };
}

function customerView(application = {}, overrides = {}) {
  return {
    sessionReady: true,
    access: { kind: 'allowed', role: 'customer' },
    accountStatus: 'active',
    categoriesStatus: 'ready',
    categories,
    customer: {
      requests: { ok: true, data: [] },
      bookings: { ok: true, data: [] },
      payments: { ok: true, data: [] },
    },
    providerStatus: { ok: true, data: null },
    providerApplication: {
      loadStatus: 'eligible',
      values: {},
      errors: {},
      confirming: false,
      submitting: false,
      confirmed: false,
      blocked: false,
      message: '',
      validatedValues: null,
      ...application,
    },
    ...overrides,
  };
}

test('application validation accepts only minimal canonical fields and active categories', () => {
  const valid = validateProviderApplication(applicationValues(), categories);
  assert.equal(valid.ok, true);
  assert.deepEqual(valid.values, {
    businessName: 'Owner Services',
    serviceRadiusKm: 25,
    categoryIds: [categoryId],
    termsVersion: PROVIDER_APPLICATION_TERMS_VERSION,
  });
  assert.equal(PROVIDER_APPLICATION_TERMS_VERSION, 'provider-application-v1');

  assert.equal(validateProviderApplication(applicationValues({ businessName: 'ab' }), categories).ok, false);
  assert.equal(validateProviderApplication(applicationValues({ businessName: 'Call 082 123 4567' }), categories).ok, false);
  assert.equal(validateProviderApplication(applicationValues({ serviceRadiusKm: '0' }), categories).ok, false);
  assert.equal(validateProviderApplication(applicationValues({ serviceRadiusKm: '25.5' }), categories).ok, false);
  assert.equal(validateProviderApplication(applicationValues({ categoryIds: [] }), categories).ok, false);
  assert.equal(validateProviderApplication(applicationValues({
    categoryIds: ['cccccccc-cccc-4ccc-8ccc-cccccccccccc'],
  }), categories).ok, false);
  assert.equal(validateProviderApplication(applicationValues({ acceptedTerms: false }), categories).ok, false);
});

test('one deliberate application submit sends exactly one allowlisted RPC payload', async () => {
  const calls = [];
  const validated = validateProviderApplication(applicationValues(), categories).values;
  const result = await submitCustomerProviderApplication({
    rpc: async (...args) => {
      calls.push(args);
      return { data: 'pending', error: null };
    },
  }, validated);
  assert.deepEqual(result, { ok: true, status: 'pending' });
  assert.equal(CUSTOMER_PROVIDER_APPLICATION_RPC, 'customer_submit_provider_application');
  assert.deepEqual(calls, [[CUSTOMER_PROVIDER_APPLICATION_RPC, {
    p_business_name: 'Owner Services',
    p_service_radius_km: 25,
    p_category_ids: [categoryId],
    p_terms_version: 'provider-application-v1',
  }]]);
});

test('server, transport and non-canonical outcomes are generic and never retried', async () => {
  const validated = validateProviderApplication(applicationValues(), categories).values;
  const unavailable = await submitCustomerProviderApplication({
    rpc: async () => ({ data: null, error: { code: '42501', message: 'private account detail' } }),
  }, validated);
  assert.deepEqual(unavailable, {
    ok: false,
    kind: 'unavailable',
    message: PROVIDER_APPLICATION_UNAVAILABLE_MESSAGE,
  });

  for (const response of [
    async () => ({ data: null, error: { code: '08006', message: 'network detail' } }),
    async () => ({ data: 'approved', error: null }),
    async () => { throw new Error('transport detail'); },
  ]) {
    let calls = 0;
    const result = await submitCustomerProviderApplication({
      rpc: async () => {
        calls += 1;
        return response();
      },
    }, validated);
    assert.deepEqual(result, {
      ok: false,
      kind: 'ambiguous',
      message: PROVIDER_APPLICATION_AMBIGUOUS_MESSAGE,
    });
    assert.equal(calls, 1);
  }
  assert.doesNotMatch(
    `${unavailable.message} ${PROVIDER_APPLICATION_AMBIGUOUS_MESSAGE}`,
    /private account|network detail|transport detail|42501|08006|approved/i,
  );
});

test('fresh server verification requires the same actor and pending unverified status', () => {
  const profile = { ok: true, data: { id: actorId, role: 'provider', account_status: 'active' } };
  const provider = {
    ok: true,
    data: {
      user_id: actorId,
      business_name: 'Owner Services',
      service_radius_km: 25,
      verification_status: 'not_started',
      review_status: 'pending',
    },
  };
  assert.equal(isConfirmedPendingProviderApplication(actorId, profile, provider), true);
  assert.equal(isConfirmedPendingProviderApplication('cccccccc-cccc-4ccc-8ccc-cccccccccccc', profile, provider), false);
  assert.equal(isConfirmedPendingProviderApplication(actorId, profile, {
    ...provider, data: { ...provider.data, review_status: 'approved' },
  }), false);
  assert.equal(isConfirmedPendingProviderApplication(actorId, profile, {
    ...provider, data: { ...provider.data, verification_status: 'verified' },
  }), false);
});

test('fresh protected state allows only an active pristine customer to apply', () => {
  const profile = { id: actorId, role: 'customer', account_status: 'active' };
  const provider = { ok: true, data: null };
  const requests = { ok: true, data: [] };
  const bookings = { ok: true, data: [] };
  assert.equal(isEligibleCustomerProviderApplication(
    profile, provider, requests, bookings, categories,
  ), true);
  assert.equal(isEligibleCustomerProviderApplication(
    { ...profile, role: 'provider' }, provider, requests, bookings, categories,
  ), false);
  assert.equal(isEligibleCustomerProviderApplication(
    { ...profile, account_status: 'restricted' }, provider, requests, bookings, categories,
  ), false);
  assert.equal(isEligibleCustomerProviderApplication(
    profile, { ok: true, data: { user_id: actorId } }, requests, bookings, categories,
  ), false);
  assert.equal(isEligibleCustomerProviderApplication(
    profile, provider, { ok: true, data: [{ id: 'request' }] }, bookings, categories,
  ), false);
  assert.equal(isEligibleCustomerProviderApplication(
    profile, provider, requests, { ok: true, data: [{ id: 'booking' }] }, categories,
  ), false);
  assert.equal(isEligibleCustomerProviderApplication(
    profile, provider, requests, bookings, [],
  ), false);
});

test('eligible fresh customer sees only the minimal application form', () => {
  const page = renderRoute('/app/customer', new URLSearchParams(), customerView());
  assert.match(page, /data-provider-application-form/);
  assert.match(page, />Apply to provide services</);
  for (const field of ['business-name', 'service-radius-km', 'category', 'accept-terms']) {
    assert.match(page, new RegExp(`name="${field}"`));
  }
  assert.match(page, /provider-application-v1/);
  assert.doesNotMatch(page, /name="(?:bio|phone|email|contact|address|street|identity|document|selfie|bank|card|payment|verification|review|active|role)"/i);
  assert.doesNotMatch(page, /verification_reference|bank_name_match|reviewed_by|reviewed_at|audit/i);
});

test('signed-out, wrong-role, restricted and ineligible views render no application form', () => {
  for (const view of [
    customerView({}, { access: { kind: 'signedOut' }, accountStatus: null }),
    customerView({}, { access: { kind: 'allowed', role: 'provider' } }),
    customerView({}, { access: { kind: 'restricted', accountStatus: 'suspended' }, accountStatus: 'suspended' }),
    customerView({ loadStatus: 'ineligible' }),
    customerView({ loadStatus: 'unavailable' }),
  ]) {
    const page = renderRoute('/app/customer', new URLSearchParams(), view);
    assert.doesNotMatch(page, /data-provider-application-form|data-provider-application-confirm-form/);
  }
});

test('explicit confirmation contains no mutable application fields or optimistic approval', () => {
  const page = renderRoute('/app/customer', new URLSearchParams(), customerView({
    confirming: true,
    values: applicationValues(),
  }));
  assert.match(page, new RegExp(PROVIDER_APPLICATION_CONFIRM_TITLE.replace('?', '\\?')));
  assert.match(page, new RegExp(PROVIDER_APPLICATION_CONFIRM_TEXT.replace('.', '\\.')));
  assert.match(page, /data-provider-application-confirm-form/);
  assert.match(page, />Submit provider application</);
  assert.doesNotMatch(page, /data-provider-application-form/);
  assert.doesNotMatch(page, /<(?:input|textarea|select)[^>]*name=/i);
  assert.doesNotMatch(page, /approved|verified provider|application approved/i);
});

test('pending provider status remains read-only and exposes no approved-provider capability', () => {
  const page = renderRoute('/app/provider', new URLSearchParams(), {
    sessionReady: true,
    access: { kind: 'allowed', role: 'provider' },
    providerStatus: {
      ok: true,
      data: {
        user_id: actorId,
        business_name: 'Owner Services',
        service_radius_km: 25,
        verification_status: 'not_started',
        review_status: 'pending',
      },
    },
    providerApplication: {
      confirmed: true,
      message: PROVIDER_APPLICATION_SUCCESS_MESSAGE,
    },
  });
  assert.match(page, /pending/);
  assert.match(page, /not_started/);
  assert.match(page, /pending and unverified/);
  assert.doesNotMatch(page, /<(?:button|a)[^>]*>(?:[^<]*(?:open requests|bid|activate service|booking|payout|payment|address reveal))/i);
  assert.doesNotMatch(page, /verification_reference|bank_name_match|reviewed_by|reviewed_at|audit/i);
});

test('application orchestration is single-flight and server-confirmed through fresh reads', async () => {
  const source = await readFile(join(root, 'app.js'), 'utf8');
  assert.match(source, /let providerApplicationInFlight = false;/);
  assert.match(source, /if \(providerApplicationInFlight \|\| !providerApplicationIsEligible\(\)/);
  assert.equal((source.match(/await submitCustomerProviderApplication\(/g) ?? []).length, 1);
  assert.match(source, /submitCustomerProviderApplication\([\s\S]*readOwnRouteProfile\(state\.client, actorId\)[\s\S]*readOwnProviderStatus\(state\.client, actorId\)/);
  assert.match(source, /isConfirmedPendingProviderApplication\(actorId, freshProfile, freshProviderStatus\)/);
  assert.match(source, /window\.history\.replaceState\(\{\}, '', '\/app\/provider'\)/);
  assert.doesNotMatch(source, /routeProfile[^\n]*role\s*=\s*['"]provider|providerStatus[^\n]*review_status\s*=|setTimeout|setInterval|\bretry\b/i);
});

test('frontend boundary has one new RPC, narrow reads, no DML and no private fields', async () => {
  const moduleNames = (await readdir(root))
    .filter((name) => name.endsWith('.js') && !name.startsWith('runtime-config'));
  const entries = await Promise.all(moduleNames.map(async (name) => [name, await readFile(join(root, name), 'utf8')]));
  const rpcModules = entries.filter(([, source]) => source.includes('.rpc(')).map(([name]) => name).sort();
  assert.deepEqual(rpcModules, [
    'provider-application.js',
    'request-cancellation.js',
    'request-draft.js',
    'request-publication.js',
    'request-update.js',
  ]);

  const applicationSource = entries.find(([name]) => name === 'provider-application.js')[1];
  assert.equal((applicationSource.match(/\.rpc\(/g) ?? []).length, 1);
  assert.match(applicationSource, /client\.rpc\(CUSTOMER_PROVIDER_APPLICATION_RPC, payload\)/);
  assert.deepEqual(SAFE_PROJECTIONS.providerStatus, 'user_id,business_name,service_radius_km,verification_status,review_status');
  assert.doesNotMatch(SAFE_PROJECTIONS.providerStatus, /bio|verification_reference|bank_name_match|reviewed_by|reviewed_at|created_at|updated_at/);

  const allSource = entries.map(([, source]) => source).join('\n');
  for (const token of [
    '.insert(', '.update(', '.upsert(', '.delete(', ".select('*')", '.select("*")',
    'service_request_addresses', 'identity_verifications', 'payment_events',
    'SUPABASE_SERVICE_ROLE_KEY', 'service_role', 'console.log', 'analytics', 'telemetry',
  ]) {
    assert.equal(allSource.includes(token), false, `forbidden frontend token: ${token}`);
  }
});
