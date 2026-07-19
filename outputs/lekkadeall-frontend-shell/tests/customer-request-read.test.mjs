import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  CUSTOMER_REQUEST_PROJECTION,
  CUSTOMER_REQUEST_STATUSES,
  CUSTOMER_REQUEST_UNAVAILABLE_REASON,
  activeCategoryLabel,
  customerRequestDetailHref,
  formatSastDateTime,
  formatZarBudgetMinor,
  isCustomerRequestId,
} from '../customer-requests.js';
import {
  readOwnCustomerRequestDetail,
  readOwnCustomerRequests,
} from '../safe-reads.js';
import { isProtectedRoute, resolveRouteAccess } from '../route-guards.js';
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

function queryClient(response, records) {
  return {
    from(table) {
      const record = { table, projection: null, operations: [], maybeSingle: false };
      records.push(record);
      const builder = {
        select(projection) { record.projection = projection; return builder; },
        eq(...args) { record.operations.push(['eq', ...args]); return builder; },
        in(...args) { record.operations.push(['in', ...args]); return builder; },
        order(...args) { record.operations.push(['order', ...args]); return builder; },
        limit(...args) { record.operations.push(['limit', ...args]); return builder; },
        maybeSingle() { record.maybeSingle = true; return Promise.resolve(response); },
        then(resolve) { return Promise.resolve(response).then(resolve); },
      };
      return builder;
    },
  };
}

test('request contract uses only the approved projection, statuses and display formats', () => {
  assert.equal(
    CUSTOMER_REQUEST_PROJECTION,
    'id,category_id,title,description,suburb,city,requested_start,budget_minor,status,created_at,updated_at',
  );
  assert.deepEqual(CUSTOMER_REQUEST_STATUSES, ['draft', 'open', 'cancelled']);
  assert.doesNotMatch(
    CUSTOMER_REQUEST_PROJECTION,
    /customer_id|closes_at|published_at|cancelled_at|precise_address|payment|booking|bid|provider|audit/,
  );
  assert.equal(formatSastDateTime('2026-07-20T07:30:00Z'), '20 Jul 2026, 09:30 SAST');
  assert.equal(formatSastDateTime('invalid'), 'Date unavailable');
  assert.equal(formatZarBudgetMinor(250050), 'ZAR 2 500.50');
  assert.equal(formatZarBudgetMinor(0), 'ZAR 0.00');
  assert.equal(formatZarBudgetMinor(null), 'Budget not specified');
  assert.equal(formatZarBudgetMinor(-1), 'Budget unavailable');
  assert.equal(activeCategoryLabel([{ id: categoryId, name: 'Painting' }], categoryId), 'Painting');
  assert.equal(activeCategoryLabel([], categoryId), 'Category unavailable');
});

test('request list read is RLS-scoped, newest-first, status-filtered and bounded to 20', async () => {
  const records = [];
  const result = await readOwnCustomerRequests(queryClient({
    data: [request(), request({ id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', status: 'completed' })],
    error: null,
  }, records));

  assert.deepEqual(result, { ok: true, data: [request()] });
  assert.equal(records.length, 1);
  assert.equal(records[0].table, 'service_requests');
  assert.equal(records[0].projection, CUSTOMER_REQUEST_PROJECTION);
  assert.deepEqual(records[0].operations, [
    ['in', 'status', CUSTOMER_REQUEST_STATUSES],
    ['order', 'created_at', { ascending: false }],
    ['limit', 20],
  ]);
});

test('detail validates the UUID before querying and builds an opaque-ID-only URL', async () => {
  let fromCalls = 0;
  const client = { from() { fromCalls += 1; throw new Error('must not query'); } };
  const malformed = await readOwnCustomerRequestDetail(client, 'not-a-uuid');
  assert.deepEqual(malformed, {
    ok: false,
    data: null,
    reason: CUSTOMER_REQUEST_UNAVAILABLE_REASON,
  });
  assert.equal(fromCalls, 0);
  assert.equal(isCustomerRequestId(requestId), true);
  assert.equal(isCustomerRequestId('not-a-uuid'), false);
  assert.equal(
    customerRequestDetailHref(requestId),
    `/app/customer/requests/detail/?requestId=${requestId}`,
  );
  assert.equal(customerRequestDetailHref('not-a-uuid'), null);
});

test('detail uses the exact projection, status allowlist and maybeSingle semantics', async () => {
  const records = [];
  const expected = request({ status: 'open' });
  const result = await readOwnCustomerRequestDetail(
    queryClient({ data: expected, error: null }, records),
    requestId,
  );
  assert.deepEqual(result, { ok: true, data: expected });
  assert.equal(records[0].table, 'service_requests');
  assert.equal(records[0].projection, CUSTOMER_REQUEST_PROJECTION);
  assert.deepEqual(records[0].operations, [
    ['eq', 'id', requestId],
    ['in', 'status', CUSTOMER_REQUEST_STATUSES],
  ]);
  assert.equal(records[0].maybeSingle, true);
});

test('missing, RLS-hidden, query-error and unsupported-status details collapse to one state', async () => {
  const generic = { ok: false, data: null, reason: CUSTOMER_REQUEST_UNAVAILABLE_REASON };
  for (const response of [
    { data: null, error: null },
    { data: null, error: { code: '42501', message: 'denied' } },
    { data: request({ status: 'completed' }), error: null },
  ]) {
    assert.deepEqual(await readOwnCustomerRequestDetail(queryClient(response, []), requestId), generic);
  }

  const rendered = renderRoute('/app/customer/requests/detail', new URLSearchParams(), {
    access: allowedAccess,
    customerRequestDetail: generic,
  });
  assert.match(rendered, /data-state="notFound"/);
  assert.match(rendered, /Request not found or unavailable/);
  assert.doesNotMatch(rendered, /denied|cross-customer|RLS-hidden|completed/);
});

test('request list and detail routes require an active customer profile', () => {
  const session = { user: { id: 'customer-1' } };
  for (const path of ['/app/customer/requests', '/app/customer/requests/detail']) {
    assert.equal(isProtectedRoute(path), true);
    assert.deepEqual(resolveRouteAccess(path, null, null), { kind: 'signedOut' });
    assert.deepEqual(
      resolveRouteAccess(path, session, { role: 'customer', account_status: 'active' }),
      allowedAccess,
    );
    assert.deepEqual(
      resolveRouteAccess(path, session, { role: 'provider', account_status: 'active' }),
      { kind: 'accessDenied' },
    );
    assert.deepEqual(
      resolveRouteAccess(path, session, { role: 'customer', account_status: 'suspended' }),
      { kind: 'restricted', accountStatus: 'suspended' },
    );
  }
});

test('list and detail render database values as escaped text with safe fallbacks', () => {
  const hostile = request({
    title: '<img src=x onerror=alert(1)>',
    description: '<script>alert(1)</script>',
    suburb: '<b>Woodstock</b>',
    city: 'Cape Town & surrounds',
    category_id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  });
  const list = renderRoute('/app/customer/requests', new URLSearchParams(), {
    access: allowedAccess,
    categories: [{ id: categoryId, name: '<em>Painting</em>' }],
    customerRequestList: { ok: true, data: [hostile] },
  });
  assert.match(list, /&lt;img src=x onerror=alert\(1\)&gt;/);
  assert.doesNotMatch(list, /<img src=x/);
  assert.match(list, /Category unavailable/);
  assert.match(list, /20 Jul 2026, 09:30 SAST/);
  assert.match(list, /ZAR 2 500\.50/);
  assert.match(list, new RegExp(`/app/customer/requests/detail/\\?requestId=${requestId}`));

  const detail = renderRoute('/app/customer/requests/detail', new URLSearchParams(), {
    access: allowedAccess,
    categories: [],
    customerRequestDetail: { ok: true, data: hostile },
  });
  assert.match(detail, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
  assert.doesNotMatch(detail, /<script>alert/);
  assert.match(detail, /&lt;b&gt;Woodstock&lt;\/b&gt;/);
  assert.match(detail, /Cape Town &amp; surrounds/);
  assert.match(detail, /Category unavailable/);
  assert.doesNotMatch(detail, />\s*(?:Publish|Edit|Pay)\s*</i);
});

test('frontend source adds no writes, blocked RPCs, broad selects or request persistence', async () => {
  const moduleNames = (await readdir(root))
    .filter((name) => name.endsWith('.js') && !name.startsWith('runtime-config'));
  const source = (await Promise.all(
    moduleNames.map((name) => readFile(join(root, name), 'utf8')),
  )).join('\n');
  const forbidden = [
    '.insert(', '.update(', '.upsert(', '.delete(', ".select('*')", '.select("*")',
    'customer_cancel_request', 'customer_publish_request',
    'customer_upsert_service_request_address', 'customer_get_service_request_address',
    'reveal_confirmed_booking_address', 'localStorage', 'sessionStorage', 'indexedDB',
    'serviceWorker', 'navigator.geolocation', 'console.log', 'analytics', 'telemetry',
    'SUPABASE_SERVICE_ROLE_KEY', 'service_role',
  ];
  for (const token of forbidden) {
    assert.equal(source.includes(token), false, `forbidden frontend token: ${token}`);
  }
});
