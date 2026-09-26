import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  CUSTOMER_BID_ACCEPT_FIELDS,
  CUSTOMER_BID_ACCEPT_RPC,
  CUSTOMER_BID_RECONCILE_RPC,
  CUSTOMER_BID_ACCEPT_UNAVAILABLE_MESSAGE,
  acceptCustomerCurrentBid,
  createCustomerBidAcceptanceIntent,
  parseCustomerBidAcceptance,
  reconcileCustomerBidAcceptance,
} from '../customer-bid-acceptance.js';
import { renderRoute } from '../shell.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const requestId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const bidId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const key = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const request = {
  id: requestId, status: 'open', updated_at: '2026-08-14T07:30:00Z',
  category_id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', title: 'Safe repair',
  description: 'Reviewed public repair.', suburb: 'Woodstock', city: 'Cape Town',
  requested_start: '2026-08-20T07:30:00Z', budget_minor: 150000,
  created_at: '2026-08-14T07:30:00Z',
};
const bid = {
  bid_id: bidId, status: 'submitted', submitted_at: '2026-08-15T07:30:00Z',
  amount_minor: 100050, currency: 'ZAR', proposed_start: '2026-08-20T07:30:00Z',
  expires_at: '2026-08-18T07:30:00Z',
};
const canonical = {
  request_id: requestId, accepted_bid_id: bidId, request_status: 'awarded',
  bid_status: 'accepted', awarded_at: '2026-08-16T07:30:00Z',
  accepted_at: '2026-08-16T07:30:00+00:00',
};
const intent = createCustomerBidAcceptanceIntent(request, bid, () => key);

function view({ access = { kind: 'allowed', role: 'customer' }, sessionReady = true, status = 'open',
  accountStatus = 'active', bidStatus = 'ready', bids = [bid], acceptance = {} } = {}) {
  return {
    access, sessionReady, accountStatus, categories: [],
    customerRequestDetail: { ok: true, data: { ...request, status } },
    customerBidViewing: {
      requestId, status: bidStatus, items: bids, hasMore: false, loadingMore: false,
    },
    customerBidAcceptance: {
      requestId, selectedBid: null, confirming: false, submitting: false,
      blocked: false, confirmed: false, message: '', ...acceptance,
    },
  };
}

function page(options) {
  return renderRoute('/app/customer/requests/detail', new URLSearchParams(), view(options));
}

test('one native UUID binds exact request and bid versions; malformed intent fails before network', () => {
  assert.deepEqual(intent, {
    requestId, bidId, requestUpdatedAt: request.updated_at,
    bidSubmittedAt: bid.submitted_at, idempotencyKey: key,
  });
  assert.equal(createCustomerBidAcceptanceIntent(request, bid, () => 'invalid'), null);
  assert.equal(createCustomerBidAcceptanceIntent(request, bid, () => { throw Error('private'); }), null);
  assert.equal(createCustomerBidAcceptanceIntent({ ...request, status: 'draft' }, bid, () => key), null);
  assert.equal(createCustomerBidAcceptanceIntent(request, { ...bid, status: 'withdrawn' }, () => key), null);
  assert.equal(createCustomerBidAcceptanceIntent({ ...request, updated_at: 'invalid' }, bid, () => key), null);
  assert.equal(createCustomerBidAcceptanceIntent(request, { ...bid, bid_id: 'invalid' }, () => key), null);
});

test('acceptance calls one exact RPC and canonical six-field result; reconciliation uses same key', async () => {
  const calls = [];
  const client = { rpc: async (...args) => { calls.push(args); return { data: [canonical], error: null }; } };
  assert.deepEqual(await acceptCustomerCurrentBid(client, intent), canonical);
  assert.deepEqual(await reconcileCustomerBidAcceptance(client, intent), canonical);
  assert.deepEqual(calls, [
    [CUSTOMER_BID_ACCEPT_RPC, {
      p_request_id: requestId, p_bid_id: bidId,
      p_expected_request_updated_at: request.updated_at,
      p_expected_bid_submitted_at: bid.submitted_at,
      p_idempotency_key: key,
    }],
    [CUSTOMER_BID_RECONCILE_RPC, { p_request_id: requestId, p_idempotency_key: key }],
  ]);
  assert.deepEqual(CUSTOMER_BID_ACCEPT_FIELDS, [
    'request_id', 'accepted_bid_id', 'request_status', 'bid_status', 'awarded_at', 'accepted_at',
  ]);
});

test('malformed, mismatched, broad or denied results never become success', async () => {
  for (const value of [
    null, [], [canonical, canonical],
    [{ ...canonical, provider_id: bidId }],
    [{ ...canonical, accepted_bid_id: requestId }],
    [{ ...canonical, request_status: 'open' }],
    [{ ...canonical, bid_status: 'submitted' }],
    [{ ...canonical, accepted_at: '2026-08-16T07:31:00Z' }],
    [{ ...canonical, awarded_at: 'invalid' }],
  ]) {
    const client = { rpc: async () => ({ data: value, error: null }) };
    assert.equal(await acceptCustomerCurrentBid(client, intent), null);
    assert.equal(await reconcileCustomerBidAcceptance(client, intent), null);
  }
  assert.equal(parseCustomerBidAcceptance({ ...canonical, private_receipt: key }, intent), null);
  let calls = 0;
  const client = { rpc: async () => { calls += 1; throw Error('private SQL detail'); } };
  assert.equal(await acceptCustomerCurrentBid(client, intent), null);
  assert.equal(calls, 1);
  assert.equal(await reconcileCustomerBidAcceptance(client, intent), null);
  assert.equal(calls, 2);
  assert.doesNotMatch(CUSTOMER_BID_ACCEPT_UNAVAILABLE_MESSAGE, /SQL|provider|receipt|token|key/iu);
});

test('accept controls require a loaded submitted bid on owned active open detail', () => {
  assert.equal((page().match(/data-customer-bid-accept-action="open"/gu) ?? []).length, 1);
  for (const options of [
    { status: 'draft' }, { status: 'cancelled' }, { status: 'awarded' },
    { accountStatus: 'restricted' },
    { access: { kind: 'signedOut' } },
    { sessionReady: false },
    { access: { kind: 'allowed', role: 'provider' } },
    { bidStatus: 'idle' }, { bidStatus: 'loading' }, { bidStatus: 'unavailable' },
    { bidStatus: 'empty', bids: [] },
  ]) assert.doesNotMatch(page(options), /data-customer-bid-accept-action="open"/u);
});

test('confirmation is explicit; canonical success removes actions and blocked outcome requires refresh', () => {
  const confirmation = page({ acceptance: { selectedBid: bid, confirming: true } });
  assert.match(confirmation, /role="alertdialog"/u);
  assert.match(confirmation, /Confirm acceptance/u);
  assert.match(confirmation, /data-customer-bid-accept-action="cancel"/u);
  assert.doesNotMatch(confirmation, /data-customer-bid-accept-action="open"/u);

  const success = page({ acceptance: { selectedBid: bid, confirmed: true } });
  assert.match(success, /Bid accepted\. This request is now awarded\./u);
  assert.match(success, /No booking, payment, contact details or exact address have been created or revealed yet\./u);
  assert.doesNotMatch(success, /data-customer-bid-accept-action="open"|data-customer-bid-accept-form/u);

  const blocked = page({ acceptance: { blocked: true } });
  assert.match(blocked, /data-customer-bid-accept-action="refresh"/u);
  assert.doesNotMatch(blocked, /data-customer-bid-accept-action="open"|Bid accepted\. This request is now awarded\./u);
});

test('app preserves single-flight, no retry, no direct DML and no persistent key', async () => {
  const app = await readFile(join(root, 'app.js'), 'utf8');
  const module = await readFile(join(root, 'customer-bid-acceptance.js'), 'utf8');
  const network = await readFile(join(root, 'tests/e2e/support/network-policy.mjs'), 'utf8');
  assert.match(app, /let customerBidAcceptanceInFlight = false;/u);
  assert.match(app, /if \(customerBidAcceptanceInFlight \|\| !state\.customerBidAcceptance\.confirming/u);
  assert.match(app, /if \(!canonical\) canonical = await reconcileCustomerBidAcceptance\(state\.client, intent\);/u);
  assert.equal((app.match(/await acceptCustomerCurrentBid\(state\.client, intent\)/gu) ?? []).length, 1);
  assert.equal((app.match(/await reconcileCustomerBidAcceptance\(state\.client, intent\)/gu) ?? []).length, 1);
  assert.match(app, /resetCustomerBidViewing\(requestId\)/u);
  assert.match(network, /'customer_accept_current_bid'[,\s\S]*'customer_reconcile_bid_acceptance'/u);
  for (const source of [app, module]) {
    for (const forbidden of [
      '.from(\'bids\')', '.from(\'bookings\')', '.from(\'payments\')',
      '.insert(', '.update(', '.upsert(', '.delete(', 'localStorage', 'sessionStorage',
      'indexedDB', 'setTimeout', 'setInterval', 'service_role',
    ]) assert.equal(source.includes(forbidden), false, forbidden);
  }
  assert.equal((module.match(/client\.rpc\(/gu) ?? []).length, 2);
});
