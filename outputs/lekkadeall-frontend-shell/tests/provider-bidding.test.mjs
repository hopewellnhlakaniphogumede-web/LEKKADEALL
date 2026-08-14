import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  PROVIDER_BID_AMBIGUOUS_MESSAGE,
  PROVIDER_BID_SUBMITTED_MESSAGE,
  PROVIDER_BID_UNAVAILABLE_MESSAGE,
  PROVIDER_BID_WITHDRAWN_MESSAGE,
  PROVIDER_OWN_BID_FIELDS,
  PROVIDER_READ_OWN_BID_RPC,
  PROVIDER_SUBMIT_BID_RPC,
  PROVIDER_WITHDRAW_BID_RPC,
  parseProviderBidAmount,
  readOwnProviderBid,
  submitProviderBid,
  withdrawProviderBid,
} from '../provider-bidding.js';
import { renderRoute } from '../shell.js';

const here = dirname(fileURLToPath(import.meta.url));
const frontendRoot = resolve(here, '..');
const requestId = '11111111-1111-4111-8111-111111111111';
const bidId = '33333333-3333-4333-8333-333333333333';
const categoryId = '22222222-2222-4222-8222-222222222222';
const request = Object.freeze({
  request_id: requestId,
  category_id: categoryId,
  title: 'Repair a safe synthetic fixture',
  description: 'Repair the reviewed synthetic fixture without private information.',
  suburb: 'Woodstock',
  city: 'Cape Town',
  requested_start: '2030-01-05T10:00:00.000Z',
  budget_minor: 125000,
  closes_at: '2030-01-03T10:00:00.000Z',
  published_at: '2030-01-01T10:00:00.000Z',
});
const bid = Object.freeze({
  bid_id: bidId,
  request_id: requestId,
  amount_minor: 100050,
  currency: 'ZAR',
  proposed_start: request.requested_start,
  status: 'submitted',
  expires_at: request.closes_at,
});

function providerView(entry = { ok: true, data: null }, action = null, access = { kind: 'allowed', role: 'provider' }) {
  return {
    sessionReady: true,
    access,
    providerStatus: { ok: true, data: { business_name: 'Synthetic services' } },
    providerApplication: {},
    providerDiscovery: {
      status: 'ready', items: [request], cursor: null, hasMore: false, loadingMore: false,
    },
    providerBidding: { entries: { [requestId]: entry }, action },
  };
}

function rpcClient(responses) {
  const calls = [];
  return {
    calls,
    client: {
      async rpc(name, payload) {
        calls.push({ name, payload });
        const response = responses[name];
        return typeof response === 'function' ? response() : response;
      },
    },
  };
}

test('bid amount validation produces bounded integer minor units only', () => {
  assert.equal(parseProviderBidAmount('1000.50'), 100050);
  assert.equal(parseProviderBidAmount('0.01'), 1);
  assert.equal(parseProviderBidAmount('1000000.00'), 100000000);
  for (const value of ['', '0', '-1', '1.001', '1000000.01', 'NaN', '1e3']) {
    assert.equal(parseProviderBidAmount(value), null);
  }
});

test('submit and withdrawal send exactly one hardened RPC with only reviewed input', async () => {
  const mock = rpcClient({
    [PROVIDER_SUBMIT_BID_RPC]: { data: bidId, error: null },
    [PROVIDER_WITHDRAW_BID_RPC]: { data: 'withdrawn', error: null },
  });
  assert.deepEqual(await submitProviderBid(mock.client, requestId, 100050), { ok: true, bidId });
  assert.deepEqual(await withdrawProviderBid(mock.client, bidId), { ok: true, status: 'withdrawn' });
  assert.deepEqual(mock.calls, [
    { name: 'provider_submit_bid', payload: { p_request_id: requestId, p_amount_minor: 100050 } },
    { name: 'provider_withdraw_bid', payload: { p_bid_id: bidId } },
  ]);
});

test('own-bid reconciliation accepts only zero or one canonical seven-field row', async () => {
  const clean = rpcClient({ [PROVIDER_READ_OWN_BID_RPC]: { data: [{ ...bid, hidden: 'discarded' }], error: null } });
  const result = await readOwnProviderBid(clean.client, requestId);
  assert.equal(result.ok, true);
  assert.deepEqual(Object.keys(result.data), PROVIDER_OWN_BID_FIELDS);
  assert.deepEqual(result.data, bid);
  assert.deepEqual(clean.calls, [{ name: 'provider_read_own_bid', payload: { p_request_id: requestId } }]);

  const empty = rpcClient({ [PROVIDER_READ_OWN_BID_RPC]: { data: [], error: null } });
  assert.deepEqual(await readOwnProviderBid(empty.client, requestId), { ok: true, data: null });
  for (const data of [[bid, bid], [{ ...bid, request_id: categoryId }], [{ ...bid, currency: 'USD' }]]) {
    const malformed = rpcClient({ [PROVIDER_READ_OWN_BID_RPC]: { data, error: null } });
    assert.equal((await readOwnProviderBid(malformed.client, requestId)).ok, false);
  }
});

test('RPC and transport failures are generic, fail closed and are never retried', async () => {
  for (const operation of [
    () => submitProviderBid({ rpc: async () => ({ data: null, error: { code: '42501', message: 'internal detail' } }) }, requestId, 100050),
    () => submitProviderBid({ rpc: async () => { throw new Error('transport detail'); } }, requestId, 100050),
    () => withdrawProviderBid({ rpc: async () => ({ data: null, error: { code: '40001', message: 'constraint detail' } }) }, bidId),
  ]) {
    const result = await operation();
    assert.equal(result.ok, false);
    assert.match(result.message, /unavailable|could not be confirmed/u);
    assert.doesNotMatch(result.message, /internal|transport|constraint|42501|40001/iu);
  }
  assert.equal((await submitProviderBid(null, requestId, 100050)).message, PROVIDER_BID_UNAVAILABLE_MESSAGE);
  assert.equal(PROVIDER_BID_AMBIGUOUS_MESSAGE.includes('Refresh requests'), true);
});

test('eligible discovery card requires review and explicit fixed confirmation before submit', () => {
  const ready = renderRoute('/app/provider', new URLSearchParams(), providerView());
  assert.match(ready, /data-provider-bid-form/);
  assert.match(ready, /name="bid-amount"/);
  assert.match(ready, />Review bid</);
  assert.doesNotMatch(ready, /data-provider-bid-confirm-form/);

  const confirmation = renderRoute('/app/provider', new URLSearchParams(), providerView(
    { ok: true, data: null },
    { requestId, kind: 'submit', amountMinor: 100050, confirming: true, submitting: false },
  ));
  assert.match(confirmation, /Submit this bid\?/);
  assert.match(confirmation, /data-provider-bid-confirm-form/);
  assert.match(confirmation, />Submit bid</);
  assert.doesNotMatch(confirmation, /data-provider-bid-confirm-form[\s\S]*<(?:input|textarea|select)/iu);
});

test('canonical submitted and withdrawn states come from fresh reconciliation and expose no adjacent controls', () => {
  const submitted = renderRoute('/app/provider', new URLSearchParams(), providerView(
    { ok: true, data: bid },
    { requestId, kind: 'submit', confirmed: true, message: PROVIDER_BID_SUBMITTED_MESSAGE },
  ));
  assert.match(submitted, /Bid submitted\./);
  assert.match(submitted, />submitted</);
  assert.match(submitted, />Withdraw bid</);
  const bidBoundary = submitted.match(/<section class="panel" data-provider-bid>[\s\S]*?<\/section>/u)?.[0] ?? '';
  assert.doesNotMatch(bidBoundary, /accept bid|book|contact|payment|address/iu);
  assert.doesNotMatch(bidBoundary, />\s*(?:Send message|Message customer)\s*</iu);

  const withdrawn = renderRoute('/app/provider', new URLSearchParams(), providerView(
    { ok: true, data: { ...bid, status: 'withdrawn' } },
    { requestId, kind: 'withdraw', confirmed: true, message: PROVIDER_BID_WITHDRAWN_MESSAGE },
  ));
  assert.match(withdrawn, /Bid withdrawn\./);
  assert.match(withdrawn, />withdrawn</);
  assert.doesNotMatch(withdrawn, /data-provider-bid-form|data-provider-bid-action="withdraw"/u);
});

test('ambiguous state and ineligible routes render no bid mutation control', () => {
  const blocked = renderRoute('/app/provider', new URLSearchParams(), providerView(
    { ok: true, data: null },
    { requestId, kind: 'submit', blocked: true, message: PROVIDER_BID_AMBIGUOUS_MESSAGE },
  ));
  assert.match(blocked, /Refresh required/);
  assert.doesNotMatch(blocked, /data-provider-bid-form|data-provider-bid-confirm-form|data-provider-bid-action="withdraw"/u);
  for (const access of [{ kind: 'signedOut' }, { kind: 'accessDenied' }, { kind: 'restricted' }]) {
    const page = renderRoute('/app/provider', new URLSearchParams(), providerView({ ok: true, data: null }, null, access));
    assert.doesNotMatch(page, /data-provider-bid/u);
  }
});

test('app uses one dedicated mutation flight and fresh reconciliation after each successful mutation', async () => {
  const source = await readFile(join(frontendRoot, 'app.js'), 'utf8');
  assert.match(source, /let providerBidMutationInFlight = false;/u);
  assert.match(source, /if \(providerBidMutationInFlight[\s\S]*return;/u);
  assert.equal((source.match(/await submitProviderBid\(state\.client, requestId, action\.amountMinor\)/gu) ?? []).length, 1);
  assert.equal((source.match(/await withdrawProviderBid\(state\.client, action\.bidId\)/gu) ?? []).length, 1);
  assert.match(source, /const result = validSubmit[\s\S]*const freshBid = await readOwnProviderBid\(state\.client, requestId\)/u);
  assert.match(source, /canonicalBid\?\.bid_id === result\.bidId[\s\S]*canonicalBid\.status === 'submitted'/u);
  assert.match(source, /canonicalBid\?\.bid_id === action\.bidId[\s\S]*canonicalBid\.status === 'withdrawn'/u);
  assert.doesNotMatch(source, /setTimeout|setInterval|maxRetries|\bretry\b/iu);
});

test('provider bidding adds no direct table DML, private read, storage or raw error surface', async () => {
  const moduleNames = (await readdir(frontendRoot)).filter((name) => name.endsWith('.js') && !name.startsWith('runtime-config'));
  const productionSource = (await Promise.all(moduleNames.map((name) => readFile(join(frontendRoot, name), 'utf8')))).join('\n');
  const biddingSource = await readFile(join(frontendRoot, 'provider-bidding.js'), 'utf8');
  assert.equal((biddingSource.match(/\.rpc\(/gu) ?? []).length, 3);
  assert.doesNotMatch(biddingSource, /\.from\(|\.select\(|customer_id|provider_id|role|eligibility|category_id|service_request_addresses|precise_address|ciphertext|booking|payment|audit/iu);
  for (const token of [
    '.insert(', '.update(', '.upsert(', '.delete(', ".select('*')", '.select("*")',
    'service_request_addresses', 'reveal_confirmed_booking_address', 'SUPABASE_SERVICE_ROLE_KEY',
    'service_role', 'localStorage', 'sessionStorage', 'indexedDB', 'console.log', 'analytics', 'telemetry',
  ]) assert.equal(productionSource.includes(token), false, `forbidden frontend token: ${token}`);
});
