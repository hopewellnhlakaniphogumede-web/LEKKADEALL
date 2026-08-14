import { isCustomerRequestId } from './customer-requests.js';

export const CUSTOMER_CURRENT_BIDS_RPC = 'customer_list_current_bids';
export const CUSTOMER_CURRENT_BIDS_PAGE_SIZE = 20;
export const CUSTOMER_CURRENT_BIDS_UNAVAILABLE_MESSAGE = 'Current bids are unavailable right now.';
export const CUSTOMER_CURRENT_BIDS_EMPTY_MESSAGE = 'No current bids are available.';

export const CUSTOMER_CURRENT_BID_FIELDS = Object.freeze([
  'bid_id',
  'amount_minor',
  'currency',
  'proposed_start',
  'status',
  'expires_at',
  'submitted_at',
]);
const SORTED_CUSTOMER_CURRENT_BID_FIELDS = Object.freeze(
  [...CUSTOMER_CURRENT_BID_FIELDS].sort(),
);

function isDateTime(value) {
  return typeof value === 'string' && value.length > 0 && Number.isFinite(Date.parse(value));
}

function safeCursor(cursor) {
  if (cursor === null || cursor === undefined) {
    return { submittedAt: null, bidId: null };
  }
  if (!cursor || typeof cursor !== 'object'
      || !isDateTime(cursor.submittedAt)
      || !isCustomerRequestId(cursor.bidId)) return null;
  return { submittedAt: cursor.submittedAt, bidId: cursor.bidId };
}

export function parseCustomerCurrentBid(value) {
  if (!value || typeof value !== 'object'
      || Object.keys(value).sort().some(
        (field, index) => field !== SORTED_CUSTOMER_CURRENT_BID_FIELDS[index],
      )
      || Object.keys(value).length !== CUSTOMER_CURRENT_BID_FIELDS.length
      || !isCustomerRequestId(value.bid_id)
      || !Number.isSafeInteger(value.amount_minor)
      || value.amount_minor < 1
      || value.amount_minor > 100000000
      || value.currency !== 'ZAR'
      || !isDateTime(value.proposed_start)
      || value.status !== 'submitted'
      || !isDateTime(value.expires_at)
      || !isDateTime(value.submitted_at)) return null;

  return Object.freeze({
    bid_id: value.bid_id,
    amount_minor: value.amount_minor,
    currency: value.currency,
    proposed_start: value.proposed_start,
    status: value.status,
    expires_at: value.expires_at,
    submitted_at: value.submitted_at,
  });
}

function isChronologicalPage(bids) {
  return bids.every((bid, index) => {
    if (index === 0) return true;
    const previous = bids[index - 1];
    const previousTime = Date.parse(previous.submitted_at);
    const currentTime = Date.parse(bid.submitted_at);
    return currentTime > previousTime
      || (currentTime === previousTime && bid.bid_id > previous.bid_id);
  });
}

export async function readCustomerCurrentBids(client, requestId, { cursor = null } = {}) {
  const normalizedCursor = safeCursor(cursor);
  if (!client || !isCustomerRequestId(requestId) || !normalizedCursor) {
    return {
      ok: false,
      data: [],
      cursor: null,
      hasMore: false,
      message: CUSTOMER_CURRENT_BIDS_UNAVAILABLE_MESSAGE,
    };
  }

  try {
    const { data, error } = await client.rpc(CUSTOMER_CURRENT_BIDS_RPC, {
      p_request_id: requestId,
      p_cursor_submitted_at: normalizedCursor.submittedAt,
      p_cursor_bid_id: normalizedCursor.bidId,
    });
    if (error || !Array.isArray(data) || data.length > CUSTOMER_CURRENT_BIDS_PAGE_SIZE) {
      return {
        ok: false,
        data: [],
        cursor: null,
        hasMore: false,
        message: CUSTOMER_CURRENT_BIDS_UNAVAILABLE_MESSAGE,
      };
    }

    const bids = data.map(parseCustomerCurrentBid);
    if (bids.some((bid) => bid === null) || !isChronologicalPage(bids)) {
      return {
        ok: false,
        data: [],
        cursor: null,
        hasMore: false,
        message: CUSTOMER_CURRENT_BIDS_UNAVAILABLE_MESSAGE,
      };
    }
    const last = bids.at(-1);
    return {
      ok: true,
      data: bids,
      cursor: last ? { submittedAt: last.submitted_at, bidId: last.bid_id } : null,
      hasMore: bids.length === CUSTOMER_CURRENT_BIDS_PAGE_SIZE,
    };
  } catch {
    return {
      ok: false,
      data: [],
      cursor: null,
      hasMore: false,
      message: CUSTOMER_CURRENT_BIDS_UNAVAILABLE_MESSAGE,
    };
  }
}
