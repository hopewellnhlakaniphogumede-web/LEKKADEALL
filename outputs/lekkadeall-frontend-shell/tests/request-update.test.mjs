import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  CUSTOMER_REQUEST_PROJECTION,
  customerRequestEditHref,
} from '../customer-requests.js';
import { REQUEST_PRIVACY_WARNING } from '../request-draft.js';
import {
  CUSTOMER_UPDATE_DRAFT_RPC,
  DRAFT_EDIT_AMBIGUOUS_MESSAGE,
  DRAFT_EDIT_SUCCESS_MESSAGE,
  DRAFT_EDIT_UNAVAILABLE_MESSAGE,
  customerDraftToEditValues,
  updateCustomerDraft,
} from '../request-update.js';
import { isProtectedRoute, resolveRouteAccess } from '../route-guards.js';
import { readOwnCustomerDraftForEdit } from '../safe-reads.js';
import { renderRoute } from '../shell.js';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const requestId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const categoryId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const allowedAccess = { kind: 'allowed', role: 'customer' };

function request(overrides = {}) {
  return {
    id: requestId,
    category_id: categoryId,
    title: 'Paint living room',
    description: 'Paint the living room walls and ceiling.',
    suburb: 'Woodstock',
    city: 'Cape Town',
    requested_start: '2026-07-20T07:30:00Z',
    budget_minor: 250050,
    status: 'draft',
    created_at: '2026-07-18T08:15:00Z',
    updated_at: '2026-07-19T10:45:00Z',
    ...overrides,
  };
}

function editView(overrides = {}) {
  const draft = request();
  return {
    access: allowedAccess,
    categoriesStatus: 'ready',
    categories: [{ id: categoryId, slug: 'painting', name: 'Painting' }],
    customerDraftEdit: {
      requestId,
      loadStatus: 'ready',
      request: draft,
      values: customerDraftToEditValues(draft),
      errors: {},
      message: '',
      submitting: false,
      confirmed: false,
      blocked: false,
      ...overrides,
    },
  };
}

function queryClient(response, records) {
  return {
    from(table) {
      const record = { table, projection: null, operations: [], maybeSingle: false };
      records.push(record);
      const builder = {
        select(projection) { record.projection = projection; return builder; },
        eq(...args) { record.operations.push(['eq', ...args]); return builder; },
        maybeSingle() { record.maybeSingle = true; return Promise.resolve(response); },
      };
      return builder;
    },
  };
}

test('fresh draft values are converted to the reviewed SAST and ZAR inputs', () => {
  assert.deepEqual(customerDraftToEditValues(request()), {
    category: categoryId,
    title: 'Paint living room',
    description: 'Paint the living room walls and ceiling.',
    suburb: 'Woodstock',
    city: 'Cape Town',
    requestedStart: '2026-07-20T09:30',
    budget: '2500.50',
  });
  assert.equal(customerDraftToEditValues(request({ budget_minor: null })).budget, '');
  assert.equal(customerDraftToEditValues(request({ status: 'open' })), null);
  assert.equal(customerDraftToEditValues(request({ id: 'not-a-uuid' })), null);
});

test('strict update RPC sends exactly the request ID and seven reviewed fields', async () => {
  const calls = [];
  const values = {
    categoryId,
    title: 'Paint two rooms',
    description: 'Paint two rooms and the ceilings in a neutral finish.',
    suburb: 'Woodstock',
    city: 'Cape Town',
    requestedStart: '2026-07-25T09:30:00+02:00',
    budgetMinor: 300050,
  };
  const client = { rpc: async (...args) => { calls.push(args); return { data: requestId, error: null }; } };
  assert.deepEqual(await updateCustomerDraft(client, requestId, values), { ok: true, requestId });
  assert.equal(CUSTOMER_UPDATE_DRAFT_RPC, 'customer_update_draft_request');
  assert.deepEqual(calls, [[CUSTOMER_UPDATE_DRAFT_RPC, {
    p_request_id: requestId,
    p_category_id: categoryId,
    p_title: values.title,
    p_description: values.description,
    p_suburb: values.suburb,
    p_city: values.city,
    p_requested_start: values.requestedStart,
    p_budget_minor: values.budgetMinor,
  }]]);
});

test('malformed IDs fail before RPC and server details remain private', async () => {
  let calls = 0;
  const invalid = await updateCustomerDraft({ rpc: async () => { calls += 1; } }, 'not-a-uuid', {});
  assert.deepEqual(invalid, { ok: false, kind: 'unavailable', message: DRAFT_EDIT_UNAVAILABLE_MESSAGE });
  assert.equal(calls, 0);

  const denied = await updateCustomerDraft({
    rpc: async () => ({ data: null, error: { code: '42501', message: 'private ownership detail' } }),
  }, requestId, {});
  assert.deepEqual(denied, { ok: false, kind: 'unavailable', message: DRAFT_EDIT_UNAVAILABLE_MESSAGE });

  for (const client of [
    { rpc: async () => ({ data: null, error: { code: '08006', message: 'network detail' } }) },
    { rpc: async () => ({ data: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', error: null }) },
    { rpc: async () => { throw new Error('transport detail'); } },
  ]) {
    assert.deepEqual(await updateCustomerDraft(client, requestId, {}), {
      ok: false,
      kind: 'ambiguous',
      message: DRAFT_EDIT_AMBIGUOUS_MESSAGE,
    });
  }
  assert.doesNotMatch(`${denied.message} ${DRAFT_EDIT_AMBIGUOUS_MESSAGE}`, /private ownership|network detail|transport detail|42501|08006/);
});

test('edit read validates UUID and is constrained to one RLS-visible draft', async () => {
  let fromCalls = 0;
  const malformed = await readOwnCustomerDraftForEdit({ from() { fromCalls += 1; } }, 'not-a-uuid');
  assert.equal(malformed.ok, false);
  assert.equal(fromCalls, 0);

  const records = [];
  const draft = request();
  assert.deepEqual(
    await readOwnCustomerDraftForEdit(queryClient({ data: draft, error: null }, records), requestId),
    { ok: true, data: draft },
  );
  assert.equal(records[0].table, 'service_requests');
  assert.equal(records[0].projection, CUSTOMER_REQUEST_PROJECTION);
  assert.deepEqual(records[0].operations, [['eq', 'id', requestId], ['eq', 'status', 'draft']]);
  assert.equal(records[0].maybeSingle, true);

  for (const response of [
    { data: null, error: null },
    { data: null, error: { code: '42501', message: 'denied' } },
    { data: request({ status: 'open' }), error: null },
  ]) {
    assert.equal((await readOwnCustomerDraftForEdit(queryClient(response, []), requestId)).ok, false);
  }
});

test('edit route is protected for active customers only', () => {
  const path = '/app/customer/requests/edit';
  const session = { user: { id: 'customer-1' } };
  assert.equal(isProtectedRoute(path), true);
  assert.deepEqual(resolveRouteAccess(path, null, null), { kind: 'signedOut' });
  assert.deepEqual(resolveRouteAccess(path, session, { role: 'customer', account_status: 'active' }), allowedAccess);
  assert.deepEqual(resolveRouteAccess(path, session, { role: 'provider', account_status: 'active' }), { kind: 'accessDenied' });
  assert.deepEqual(resolveRouteAccess(path, session, { role: 'customer', account_status: 'suspended' }), { kind: 'restricted', accountStatus: 'suspended' });
  assert.equal(customerRequestEditHref(requestId), `/app/customer/requests/edit/?requestId=${requestId}`);
  assert.equal(customerRequestEditHref('not-a-uuid'), null);
});

test('edit action appears only on fresh draft detail and never on list or non-draft detail', () => {
  const categories = [{ id: categoryId, name: 'Painting' }];
  const draftDetail = renderRoute('/app/customer/requests/detail', new URLSearchParams(), {
    access: allowedAccess,
    categories,
    customerRequestDetail: { ok: true, data: request() },
    customerDraftCancellation: { requestId, confirming: false, submitting: false, confirmed: false, blocked: false, message: '' },
  });
  assert.match(draftDetail, new RegExp(`/app/customer/requests/edit/\\?requestId=${requestId}`));
  assert.match(draftDetail, />Edit draft</);

  for (const status of ['open', 'cancelled']) {
    const detail = renderRoute('/app/customer/requests/detail', new URLSearchParams(), {
      access: allowedAccess,
      categories,
      customerRequestDetail: { ok: true, data: request({ status }) },
    });
    assert.doesNotMatch(detail, />Edit draft</);
  }

  const list = renderRoute('/app/customer/requests', new URLSearchParams(), {
    access: allowedAccess,
    categories,
    customerRequestList: { ok: true, data: [request()] },
  });
  assert.doesNotMatch(list, />Edit draft</);
});

test('edit form is prefilled, reuses privacy rules, and exposes only reviewed fields', () => {
  const page = renderRoute('/app/customer/requests/edit', new URLSearchParams(`requestId=${requestId}`), editView());
  assert.match(page, /data-draft-edit-form/);
  assert.match(page, /value="Paint living room"/);
  assert.match(page, /Paint the living room walls and ceiling\./);
  assert.match(page, /value="2026-07-20T09:30"/);
  assert.match(page, /value="2500\.50"/);
  assert.match(page, new RegExp(REQUEST_PRIVACY_WARNING.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.match(page, />Save draft changes</);
  for (const field of ['category', 'title', 'description', 'suburb', 'city', 'requested-start', 'budget']) {
    assert.match(page, new RegExp(`name="${field}"`));
  }
  assert.doesNotMatch(page, /name="(?:address|street|unit|room|phone|email|gps|latitude|longitude|card|cvv|payment_method)"/i);
  assert.doesNotMatch(page, />\s*Publish\s*</i);
  assert.match(page, /Publishing and the private exact-address step are not available/);
});

test('unavailable and confirmed states are generic and server-confirmed', () => {
  const unavailable = renderRoute('/app/customer/requests/edit', new URLSearchParams(), {
    access: allowedAccess,
    customerDraftEdit: { requestId, loadStatus: 'unavailable', request: null, blocked: true },
  });
  assert.match(unavailable, /Draft not found or unavailable/);
  assert.match(unavailable, new RegExp(DRAFT_EDIT_UNAVAILABLE_MESSAGE.replace('.', '\\.')));
  assert.doesNotMatch(unavailable, /data-draft-edit-form|ownership|RLS|status =/);

  const confirmed = renderRoute('/app/customer/requests/edit', new URLSearchParams(), editView({
    message: DRAFT_EDIT_SUCCESS_MESSAGE,
    confirmed: true,
  }));
  assert.match(confirmed, /Draft updated\./);
  assert.match(confirmed, /form-message is-success/);

  const blocked = renderRoute('/app/customer/requests/edit', new URLSearchParams(), editView({
    message: DRAFT_EDIT_AMBIGUOUS_MESSAGE,
    blocked: true,
  }));
  assert.match(blocked, /The update could not be confirmed/);
  assert.match(blocked, /Save draft changes<\/button>/);
  assert.equal((blocked.match(/disabled/g) ?? []).length >= 8, true);
});

test('app orchestration is single-flight and confirms success through a fresh draft-only RLS read', async () => {
  const source = await readFile(join(root, 'app.js'), 'utf8');
  assert.match(source, /draftEditInFlight/);
  assert.match(source, /if \(draftEditInFlight/);
  assert.match(source, /const result = await updateCustomerDraft\(state\.client, requestId, validation\.values\);[\s\S]*freshDraft = await readOwnCustomerDraftForEdit\(state\.client, requestId\);/);
  assert.match(source, /freshDraft\.data\?\.id === requestId && freshDraft\.data\?\.status === 'draft'/);
  assert.match(source, /state\.customerDraftEdit\.blocked = true/);
  assert.doesNotMatch(source, /setTimeout|setInterval|\bretry\b/i);
});

test('only five reviewed RPC modules exist and blocked browser capabilities remain absent', async () => {
  const moduleNames = (await readdir(root)).filter((name) => name.endsWith('.js') && !name.startsWith('runtime-config'));
  const entries = await Promise.all(moduleNames.map(async (name) => [name, await readFile(join(root, name), 'utf8')]));
  const rpcModules = entries.filter(([, source]) => source.includes('.rpc(')).map(([name]) => name).sort();
  assert.deepEqual(rpcModules, [
    'provider-application.js',
    'request-cancellation.js',
    'request-draft.js',
    'request-publication.js',
    'request-update.js',
  ]);

  const updateSource = entries.find(([name]) => name === 'request-update.js')[1];
  assert.equal((updateSource.match(/\.rpc\(/g) ?? []).length, 1);
  assert.match(updateSource, /\.rpc\(CUSTOMER_UPDATE_DRAFT_RPC, payload\)/);
  assert.doesNotMatch(updateSource, /p_customer_id|p_status|p_reason|p_metadata|p_precise_address|p_provider|p_booking/);

  const allSource = entries.map(([, source]) => source).join('\n');
  const forbidden = [
    '.insert(', '.update(', '.upsert(', '.delete(', ".select('*')", '.select("*")',
    'customer_cancel_request', 'customer_publish_request',
    'customer_upsert_service_request_address', 'customer_get_service_request_address',
    'reveal_confirmed_booking_address', 'localStorage', 'sessionStorage', 'indexedDB',
    'serviceWorker', 'navigator.geolocation', 'console.log', 'analytics', 'telemetry',
    'SUPABASE_SERVICE_ROLE_KEY', 'service_role',
  ];
  for (const token of forbidden) assert.equal(allSource.includes(token), false, `forbidden frontend token: ${token}`);
});
