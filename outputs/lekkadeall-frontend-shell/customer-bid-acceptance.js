import { isCustomerRequestId } from './customer-requests.js';

export const CUSTOMER_BID_ACCEPT_RPC = 'customer_accept_current_bid';
export const CUSTOMER_BID_RECONCILE_RPC = 'customer_reconcile_bid_acceptance';
export const CUSTOMER_BID_ACCEPT_UNAVAILABLE_MESSAGE = 'Bid acceptance is unavailable. Refresh the request and bids before trying again.';
export const CUSTOMER_BID_ACCEPT_SUCCESS_MESSAGE = 'Bid accepted. This request is now awarded.';
export const CUSTOMER_BID_ACCEPT_FIELDS = Object.freeze([
  'request_id', 'accepted_bid_id', 'request_status', 'bid_status', 'awarded_at', 'accepted_at',
]);
const SORTED_FIELDS = Object.freeze([...CUSTOMER_BID_ACCEPT_FIELDS].sort());
const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;

function isTimestamp(value) {
  return typeof value === 'string' && value.length > 0 && Number.isFinite(Date.parse(value));
}

export function createCustomerBidAcceptanceIntent(request, bid, randomUUID = () => globalThis.crypto?.randomUUID?.()) {
  if (!request || !bid || request.status !== 'open' || bid.status !== 'submitted'
      || !isCustomerRequestId(request.id) || !isCustomerRequestId(bid.bid_id)
      || !isTimestamp(request.updated_at) || !isTimestamp(bid.submitted_at)) return null;
  let key;
  try { key = randomUUID(); } catch { return null; }
  if (typeof key !== 'string' || !UUID_V4.test(key)) return null;
  return Object.freeze({
    requestId: request.id,
    bidId: bid.bid_id,
    requestUpdatedAt: request.updated_at,
    bidSubmittedAt: bid.submitted_at,
    idempotencyKey: key,
  });
}

export function parseCustomerBidAcceptance(value, intent) {
  if (!value || typeof value !== 'object' || Array.isArray(value) || !intent
      || Object.keys(value).length !== CUSTOMER_BID_ACCEPT_FIELDS.length
      || Object.keys(value).sort().some((field, index) => field !== SORTED_FIELDS[index])
      || value.request_id !== intent.requestId
      || value.accepted_bid_id !== intent.bidId
      || value.request_status !== 'awarded' || value.bid_status !== 'accepted'
      || !isTimestamp(value.awarded_at) || !isTimestamp(value.accepted_at)
      || Date.parse(value.awarded_at) !== Date.parse(value.accepted_at)) return null;
  return Object.freeze({
    request_id: value.request_id,
    accepted_bid_id: value.accepted_bid_id,
    request_status: value.request_status,
    bid_status: value.bid_status,
    awarded_at: value.awarded_at,
    accepted_at: value.accepted_at,
  });
}

function parseOneRow(data, intent) {
  return Array.isArray(data) && data.length === 1
    ? parseCustomerBidAcceptance(data[0], intent) : null;
}

export async function acceptCustomerCurrentBid(client, intent) {
  if (!client || !intent || !UUID_V4.test(intent.idempotencyKey ?? '')) return null;
  try {
    const { data, error } = await client.rpc(CUSTOMER_BID_ACCEPT_RPC, {
      p_request_id: intent.requestId,
      p_bid_id: intent.bidId,
      p_expected_request_updated_at: intent.requestUpdatedAt,
      p_expected_bid_submitted_at: intent.bidSubmittedAt,
      p_idempotency_key: intent.idempotencyKey,
    });
    return error ? null : parseOneRow(data, intent);
  } catch { return null; }
}

export async function reconcileCustomerBidAcceptance(client, intent) {
  if (!client || !intent || !UUID_V4.test(intent.idempotencyKey ?? '')) return null;
  try {
    const { data, error } = await client.rpc(CUSTOMER_BID_RECONCILE_RPC, {
      p_request_id: intent.requestId,
      p_idempotency_key: intent.idempotencyKey,
    });
    return error ? null : parseOneRow(data, intent);
  } catch { return null; }
}
