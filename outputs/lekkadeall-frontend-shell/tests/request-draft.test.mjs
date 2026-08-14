import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  CUSTOMER_CREATE_DRAFT_RPC,
  REQUEST_PRIVACY_WARNING,
  containsRequestPrivacyRisk,
  createCustomerDraftRequest,
  parseZarToMinorUnits,
  sastDateTimeToIso,
  validateCustomerDraft,
} from '../request-draft.js';
import { renderRoute } from '../shell.js';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const categoryId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const requestId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const activeCategories = [{ id: categoryId, slug: 'painting', name: 'Painting' }];

test('privacy warning is exact and public-risk detection covers prohibited details', () => {
  assert.equal(REQUEST_PRIVACY_WARNING, 'This title and description may later be shown to service providers. Do not include your exact address, street or house number, complex, unit or room number, GPS location, phone number, email address, access code, or private contact details. Enter suburb and city only.');
  const risky = [
    'Meet at 14 Long Street', 'Unit 7 needs paint', 'House 42', '-26.2041, 28.0473',
    'Call 082 123 4567', 'Email me@example.test', 'https://example.test',
    'WhatsApp me', 'Message @privatehandle', 'Gate code 9911',
  ];
  for (const value of risky) assert.equal(containsRequestPrivacyRisk(value), true, value);
  assert.equal(containsRequestPrivacyRisk('Paint the living room walls and ceiling.'), false);
  assert.equal(containsRequestPrivacyRisk('General area is Cape Town CBD.'), false);
});

test('ZAR budget uses string and integer conversion only', () => {
  assert.deepEqual(parseZarToMinorUnits(''), { ok: true, value: null });
  assert.deepEqual(parseZarToMinorUnits('0'), { ok: true, value: 0 });
  assert.deepEqual(parseZarToMinorUnits('0.01'), { ok: true, value: 1 });
  assert.deepEqual(parseZarToMinorUnits('12.3'), { ok: true, value: 1230 });
  assert.deepEqual(parseZarToMinorUnits('1500.50'), { ok: true, value: 150050 });
  assert.equal(parseZarToMinorUnits('-1').ok, false);
  assert.equal(parseZarToMinorUnits('1,500.00').ok, false);
  assert.equal(parseZarToMinorUnits('1e3').ok, false);
  assert.equal(parseZarToMinorUnits('R100').ok, false);
  assert.equal(parseZarToMinorUnits('1.234').ok, false);
  assert.equal(parseZarToMinorUnits('21474836.48').ok, false);
  assert.deepEqual(parseZarToMinorUnits('21474836.47'), { ok: true, value: 2147483647 });
});

test('requested start is validated and converted with explicit SAST offset', () => {
  const now = Date.parse('2026-07-15T10:00:00+02:00');
  assert.deepEqual(sastDateTimeToIso('2026-07-15T10:16', now), { ok: true, value: '2026-07-15T10:16:00+02:00' });
  assert.equal(sastDateTimeToIso('2026-07-15T10:14', now).ok, false);
  assert.equal(sastDateTimeToIso('2026-02-30T12:00', now).ok, false);
  assert.equal(sastDateTimeToIso('2026-07-15 12:00', now).ok, false);
});

function validValues(overrides = {}) {
  return {
    category: categoryId,
    title: 'Paint living room',
    description: 'Paint the living room walls and ceiling in a neutral colour.',
    suburb: 'Woodstock',
    city: 'Cape Town',
    requestedStart: '2026-07-20T09:30',
    budget: '2500.50',
    ...overrides,
  };
}

test('draft validation mirrors field boundaries and active-category allowlist', () => {
  const now = Date.parse('2026-07-15T10:00:00+02:00');
  const valid = validateCustomerDraft(validValues(), activeCategories, { nowMs: now });
  assert.equal(valid.ok, true);
  assert.deepEqual(valid.values, {
    categoryId,
    title: 'Paint living room',
    description: 'Paint the living room walls and ceiling in a neutral colour.',
    suburb: 'Woodstock', city: 'Cape Town',
    requestedStart: '2026-07-20T09:30:00+02:00', budgetMinor: 250050,
  });

  assert.equal(validateCustomerDraft(validValues({ title: 'abc' }), activeCategories, { nowMs: now }).ok, true);
  assert.equal(validateCustomerDraft(validValues({ title: 'a'.repeat(120) }), activeCategories, { nowMs: now }).ok, true);
  assert.equal(validateCustomerDraft(validValues({ description: 'abcdefghij' }), activeCategories, { nowMs: now }).ok, true);

  assert.equal(validateCustomerDraft(validValues({ category: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc' }), activeCategories, { nowMs: now }).errors.category.length > 0, true);
  assert.equal(validateCustomerDraft(validValues({ title: 'ab' }), activeCategories, { nowMs: now }).errors.title.length > 0, true);
  assert.equal(validateCustomerDraft(validValues({ title: 'a'.repeat(121) }), activeCategories, { nowMs: now }).errors.title.length > 0, true);
  assert.equal(validateCustomerDraft(validValues({ description: 'too short' }), activeCategories, { nowMs: now }).errors.description.length > 0, true);
  assert.equal(validateCustomerDraft(validValues({ description: 'a'.repeat(3001) }), activeCategories, { nowMs: now }).errors.description.length > 0, true);
  assert.equal(validateCustomerDraft(validValues({ suburb: 'Unit 4' }), activeCategories, { nowMs: now }).errors.suburb.length > 0, true);
  assert.equal(validateCustomerDraft(validValues({ city: 'Cape Town\nStreet' }), activeCategories, { nowMs: now }).errors.city.length > 0, true);
});

test('trusted mutation calls only the reviewed RPC with null ciphertext', async () => {
  const calls = [];
  const client = { rpc: async (...args) => { calls.push(args); return { data: requestId, error: null }; } };
  const result = await createCustomerDraftRequest(client, {
    categoryId, title: 'Paint living room', description: 'Paint living room walls safely.',
    suburb: 'Woodstock', city: 'Cape Town', requestedStart: '2026-07-20T09:30:00+02:00', budgetMinor: 250050,
  });
  assert.deepEqual(result, { ok: true, requestId });
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], CUSTOMER_CREATE_DRAFT_RPC);
  assert.deepEqual(calls[0][1], {
    p_category_id: categoryId,
    p_title: 'Paint living room',
    p_description: 'Paint living room walls safely.',
    p_suburb: 'Woodstock',
    p_city: 'Cape Town',
    p_requested_start: '2026-07-20T09:30:00+02:00',
    p_budget_minor: 250050,
    p_precise_address_ciphertext: null,
  });
});

test('Ticket 9A-5 server validation failures stay generic and are not retried', async () => {
  let calls = 0;
  const client = { rpc: async () => { calls += 1; return { data: null, error: { code: '22023', message: 'Public title contains private or unsupported information' } }; } };
  const result = await createCustomerDraftRequest(client, {
    categoryId, title: 'Safe title', description: 'Safe description text', suburb: 'Woodstock', city: 'Cape Town',
    requestedStart: '2026-07-20T09:30:00+02:00', budgetMinor: null,
  });
  assert.equal(calls, 1);
  assert.equal(result.ok, false);
  assert.equal(result.message, 'The draft could not be confirmed. Refresh your drafts before trying again.');
  assert.doesNotMatch(result.message, /Public title|private or unsupported|22023/);
});

test('customer request page is customer-only, draft-only, and contains no sensitive fields', () => {
  const signedOut = renderRoute('/app/customer/requests/new');
  assert.match(signedOut, /data-state="signedOut"/);
  const page = renderRoute('/app/customer/requests/new', new URLSearchParams(), {
    access: { kind: 'allowed', role: 'customer' }, categoriesStatus: 'ready', categories: activeCategories,
    requestDraft: { values: {}, errors: {}, message: '', submitting: false, requestId: null },
  });
  assert.match(page, /data-draft-request-form/);
  assert.match(page, new RegExp(REQUEST_PRIVACY_WARNING.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  for (const field of ['category', 'title', 'description', 'suburb', 'city', 'requested-start', 'budget']) {
    assert.match(page, new RegExp(`name="${field}"`));
  }
  assert.doesNotMatch(page, /name="(?:address|street|unit|room|phone|email|gps|latitude|longitude|card|cvv|payment_method)"/i);
  assert.doesNotMatch(page, />\s*Publish\s*</i);
  assert.match(page, /Publishing and the private exact-address step are not available/);
});

test('draft confirmation appears only with a returned request ID', () => {
  const pending = renderRoute('/app/customer/requests/new', new URLSearchParams(), {
    access: { kind: 'allowed', role: 'customer' }, categoriesStatus: 'ready', categories: activeCategories,
    requestDraft: { values: {}, errors: {}, message: '', submitting: true, requestId: null },
  });
  assert.doesNotMatch(pending, /Your request draft is saved/);
  const created = renderRoute('/app/customer/requests/new', new URLSearchParams(), {
    access: { kind: 'allowed', role: 'customer' }, categoriesStatus: 'ready', categories: activeCategories,
    requestDraft: { values: {}, errors: {}, message: '', submitting: false, requestId },
  });
  assert.match(created, /Your request draft is saved/);
  assert.match(created, new RegExp(`/app/customer/requests/detail/\\?requestId=${requestId}`));
  assert.match(created, />View draft</);
  assert.match(created, />View all requests</);
  assert.match(created, /It remains a private draft/);
});

test('only reviewed request mutation modules contain RPC boundaries and blocked capabilities are absent', async () => {
  const moduleNames = (await readdir(root)).filter((name) => name.endsWith('.js') && !name.startsWith('runtime-config'));
  const entries = await Promise.all(moduleNames.map(async (name) => [name, await readFile(join(root, name), 'utf8')]));
  const requestSource = entries.find(([name]) => name === 'request-draft.js')[1];
  const cancellationSource = entries.find(([name]) => name === 'request-cancellation.js')[1];
  const publicationSource = entries.find(([name]) => name === 'request-publication.js')[1];
  const updateSource = entries.find(([name]) => name === 'request-update.js')[1];
  const otherSource = entries.filter(([name]) => ![
    'customer-bid-viewing.js', 'provider-application.js', 'provider-bidding.js', 'provider-discovery.js', 'request-draft.js', 'request-cancellation.js',
    'request-publication.js', 'request-update.js',
  ].includes(name)).map(([, source]) => source).join('\n');
  assert.equal((requestSource.match(/\.rpc\(/g) ?? []).length, 1);
  assert.match(requestSource, /\.rpc\(CUSTOMER_CREATE_DRAFT_RPC, payload\)/);
  assert.equal((cancellationSource.match(/\.rpc\(/g) ?? []).length, 1);
  assert.match(cancellationSource, /\.rpc\(CUSTOMER_CANCEL_DRAFT_RPC, \{/);
  assert.equal((publicationSource.match(/\.rpc\(/g) ?? []).length, 1);
  assert.match(publicationSource, /\.rpc\('customer_publish_draft_request', \{/);
  assert.equal((updateSource.match(/\.rpc\(/g) ?? []).length, 1);
  assert.match(updateSource, /\.rpc\(CUSTOMER_UPDATE_DRAFT_RPC, payload\)/);
  assert.doesNotMatch(otherSource, /\.rpc\(/);
  const allSource = entries.map(([, source]) => source).join('\n');
  const forbidden = [
    '.insert(', '.update(', '.upsert(', '.delete(', ".select('*')", '.select("*")',
    'customer_cancel_request', 'customer_publish_request', 'customer_upsert_service_request_address',
    'customer_get_service_request_address', 'reveal_confirmed_booking_address',
    'localStorage', 'sessionStorage', 'geolocation', 'service_role', 'SUPABASE_SERVICE_ROLE_KEY',
  ];
  for (const token of forbidden) assert.equal(allSource.includes(token), false, `forbidden frontend token: ${token}`);
});

test('single-flight guard exists and ambiguous failures have no retry path', async () => {
  const source = await readFile(join(root, 'app.js'), 'utf8');
  assert.match(source, /draftSubmissionInFlight/);
  assert.match(source, /if \(draftSubmissionInFlight/);
  assert.doesNotMatch(source, /retry|setTimeout|setInterval/i);
});
