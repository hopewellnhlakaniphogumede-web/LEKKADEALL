import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  CUSTOMER_CURRENT_BID_FIELDS,
  CUSTOMER_CURRENT_BIDS_EMPTY_MESSAGE,
  CUSTOMER_CURRENT_BIDS_PAGE_SIZE,
  CUSTOMER_CURRENT_BIDS_RPC,
  CUSTOMER_CURRENT_BIDS_UNAVAILABLE_MESSAGE,
  parseCustomerCurrentBid,
  readCustomerCurrentBids,
} from '../customer-bid-viewing.js';
import { renderRoute } from '../shell.js';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const requestId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const firstBidId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const secondBidId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

function bid(overrides = {}) {
  return {
    bid_id: firstBidId,
    amount_minor: 100050,
    currency: 'ZAR',
    proposed_start: '2026-08-20T07:30:00Z',
    status: 'submitted',
    expires_at: '2026-08-18T07:30:00Z',
    submitted_at: '2026-08-15T07:30:00Z',
    ...overrides,
  };
}

function openRequest(status = 'open') {
  return {
    id: requestId,
    category_id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    title: 'Repair indoor fixture',
    description: 'Repair the reviewed indoor fixture using general details.',
    suburb: 'Woodstock',
    city: 'Cape Town',
    requested_start: '2026-08-20T07:30:00Z',
    budget_minor: 150000,
    status,
    created_at: '2026-08-14T07:30:00Z',
    updated_at: '2026-08-14T07:30:00Z',
  };
}

function detailView(status = 'open', bidView = {}) {
  return {
    access: { kind: 'allowed', role: 'customer' },
    accountStatus: 'active',
    categories: [],
    customerRequestDetail: { ok: true, data: openRequest(status) },
    customerBidViewing: {
      requestId,
      status: 'idle',
      items: [],
      cursor: null,
      hasMore: false,
      loadingMore: false,
      ...bidView,
    },
  };
}

test('customer bid viewer sends one exact RPC payload and returns only seven reviewed fields', async () => {
  const calls = [];
  const result = await readCustomerCurrentBids({
    rpc: async (...args) => {
      calls.push(args);
      return {
        data: [
          bid(),
          bid({
            bid_id: secondBidId,
            amount_minor: 120000,
            submitted_at: '2026-08-15T08:30:00Z',
          }),
        ],
        error: null,
      };
    },
  }, requestId);

  assert.equal(CUSTOMER_CURRENT_BIDS_RPC, 'customer_list_current_bids');
  assert.equal(CUSTOMER_CURRENT_BIDS_PAGE_SIZE, 20);
  assert.deepEqual(CUSTOMER_CURRENT_BID_FIELDS, [
    'bid_id', 'amount_minor', 'currency', 'proposed_start',
    'status', 'expires_at', 'submitted_at',
  ]);
  assert.deepEqual(calls, [[CUSTOMER_CURRENT_BIDS_RPC, {
    p_request_id: requestId,
    p_cursor_submitted_at: null,
    p_cursor_bid_id: null,
  }]]);
  assert.equal(result.ok, true);
  assert.deepEqual(result.data.map((item) => Object.keys(item)), [
    CUSTOMER_CURRENT_BID_FIELDS,
    CUSTOMER_CURRENT_BID_FIELDS,
  ]);
  assert.deepEqual(result.cursor, {
    submittedAt: '2026-08-15T08:30:00Z',
    bidId: secondBidId,
  });
  assert.equal(result.hasMore, false);
});

test('request and paired cursor validation fail before the network call', async () => {
  let calls = 0;
  const client = { rpc: async () => { calls += 1; } };
  for (const [id, cursor] of [
    ['not-a-uuid', null],
    [requestId, { submittedAt: '2026-08-15T08:30:00Z' }],
    [requestId, { bidId: secondBidId }],
    [requestId, { submittedAt: 'not-a-date', bidId: secondBidId }],
    [requestId, { submittedAt: '2026-08-15T08:30:00Z', bidId: 'not-a-uuid' }],
  ]) {
    assert.deepEqual(await readCustomerCurrentBids(client, id, { cursor }), {
      ok: false,
      data: [],
      cursor: null,
      hasMore: false,
      message: CUSTOMER_CURRENT_BIDS_UNAVAILABLE_MESSAGE,
    });
  }
  assert.equal(calls, 0);
});

test('denied, malformed, broad and unordered responses clear data without retrying', async () => {
  const responses = [
    { data: null, error: { code: '42501', message: 'private ownership detail' } },
    { data: [bid({ provider_id: secondBidId })], error: null },
    { data: [bid({ currency: 'USD' })], error: null },
    {
      data: [
        bid({ bid_id: secondBidId, submitted_at: '2026-08-15T08:30:00Z' }),
        bid({ submitted_at: '2026-08-15T07:30:00Z' }),
      ],
      error: null,
    },
  ];
  for (const response of responses) {
    let calls = 0;
    const result = await readCustomerCurrentBids({
      rpc: async () => { calls += 1; return response; },
    }, requestId);
    assert.deepEqual(result, {
      ok: false,
      data: [],
      cursor: null,
      hasMore: false,
      message: CUSTOMER_CURRENT_BIDS_UNAVAILABLE_MESSAGE,
    });
    assert.equal(calls, 1);
  }

  let thrownCalls = 0;
  const thrown = await readCustomerCurrentBids({
    rpc: async () => { thrownCalls += 1; throw new Error('transport detail'); },
  }, requestId);
  assert.equal(thrownCalls, 1);
  assert.equal(thrown.message, CUSTOMER_CURRENT_BIDS_UNAVAILABLE_MESSAGE);
  assert.doesNotMatch(thrown.message, /transport|ownership|42501|provider|request ID/i);
});

test('the deliberate control appears only for an active customer fresh open detail', () => {
  const open = renderRoute('/app/customer/requests/detail', new URLSearchParams(), detailView());
  assert.match(open, /data-customer-bid-view-action="view"/u);
  assert.match(open, />View current bids</u);
  assert.doesNotMatch(open, /data-customer-bid-card/u);

  for (const status of ['draft', 'cancelled']) {
    const page = renderRoute(
      '/app/customer/requests/detail',
      new URLSearchParams(),
      detailView(status),
    );
    assert.doesNotMatch(page, /data-customer-bid-viewing|data-customer-bid-view-action/u);
  }
  for (const access of [
    { kind: 'signedOut' },
    { kind: 'accessDenied' },
    { kind: 'restricted', accountStatus: 'restricted' },
    { kind: 'allowed', role: 'provider' },
  ]) {
    const page = renderRoute('/app/customer/requests/detail', new URLSearchParams(), {
      ...detailView(),
      access,
    });
    assert.doesNotMatch(page, /data-customer-bid-viewing|data-customer-bid-view-action/u);
  }
});

test('current bid cards render approved fields with ZAR and SAST formatting only', () => {
  const page = renderRoute('/app/customer/requests/detail', new URLSearchParams(), detailView('open', {
    status: 'ready',
    items: [bid()],
  }));
  const panel = page.slice(
    page.indexOf('<section class="panel customer-bid-viewing"'),
    page.indexOf('<section class="inline-warning request-boundary-note"'),
  );
  assert.equal((panel.match(/data-customer-bid-card/g) ?? []).length, 1);
  assert.match(panel, /ZAR 1 000\.50/u);
  assert.match(panel, /20 Aug 2026, 09:30 SAST/u);
  assert.match(panel, /18 Aug 2026, 09:30 SAST/u);
  assert.match(panel, /15 Aug 2026, 09:30 SAST/u);
  assert.match(panel, new RegExp(firstBidId));
  assert.match(panel, />submitted</u);
  assert.doesNotMatch(panel, /provider|business|email|phone|<dt>Message|perk|booking|payment|address/i);

  const empty = renderRoute('/app/customer/requests/detail', new URLSearchParams(), detailView('open', {
    status: 'empty',
  }));
  assert.match(empty, new RegExp(CUSTOMER_CURRENT_BIDS_EMPTY_MESSAGE.replace('.', '\\.')));
  assert.doesNotMatch(empty, /data-customer-bid-card/u);
});

test('app keeps viewing single-flight, deliberate, in-memory and stale-clearing', async () => {
  const source = await readFile(join(root, 'app.js'), 'utf8');
  const detailLoad = source.slice(
    source.indexOf("path === '/app/customer/requests/detail'"),
    source.indexOf("path === '/app/customer/requests/edit'"),
  );
  assert.match(source, /let customerBidViewInFlight = false;/u);
  assert.match(source, /if \(customerBidViewInFlight \|\| !isCustomerRequestId\(requestId\)/u);
  assert.equal((source.match(/await readCustomerCurrentBids\(state\.client, requestId, \{ cursor \}\)/gu) ?? []).length, 1);
  assert.doesNotMatch(detailLoad, /readCustomerCurrentBids/u);
  assert.match(source, /data-customer-bid-view-action[\s\S]*action === 'view'[\s\S]*loadCustomerBidView\(\)/u);
  assert.match(source, /if \(!result\.ok\) \{[\s\S]*resetCustomerBidViewing\(requestId, 'unavailable'\)/u);
  assert.match(source, /clearPersonalState\(\)[\s\S]*resetCustomerBidViewing\(\)/u);
});

test('new customer bid-view sources contain no alternate authority, mutation or persistence path', async () => {
  const moduleSource = await readFile(join(root, 'customer-bid-viewing.js'), 'utf8');
  const shellSource = await readFile(join(root, 'shell.js'), 'utf8');
  const panelSource = shellSource.slice(
    shellSource.indexOf('function customerBidViewingPanel'),
    shellSource.indexOf('function customerRequestDetailPage'),
  );
  assert.equal((moduleSource.match(/\.rpc\(/gu) ?? []).length, 1);
  assert.match(moduleSource, /client\.rpc\(CUSTOMER_CURRENT_BIDS_RPC, \{[\s\S]*p_request_id: requestId,[\s\S]*p_cursor_submitted_at: normalizedCursor\.submittedAt,[\s\S]*p_cursor_bid_id: normalizedCursor\.bidId/u);
  for (const source of [moduleSource, panelSource]) {
    for (const token of [
      '.from(', '.select(', '.insert(', '.update(', '.upsert(', '.delete(',
      'customer_accept_bid', 'provider_id', 'business_name', 'email', 'phone',
      'perks', 'address', 'booking', 'payment', 'payout', 'audit',
      'localStorage', 'sessionStorage', 'indexedDB', 'setTimeout', 'setInterval',
      'retry', 'poll', 'Accept bid', 'Choose provider', 'Select provider',
      'Book provider', 'Pay provider', 'Contact provider',
    ]) {
      assert.equal(source.includes(token), false, `prohibited customer bid-view token: ${token}`);
    }
  }
  assert.equal(parseCustomerCurrentBid(bid({ provider_id: secondBidId })), null);
});
