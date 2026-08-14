export const PROVIDER_SUBMIT_BID_RPC = 'provider_submit_bid';
export const PROVIDER_WITHDRAW_BID_RPC = 'provider_withdraw_bid';
export const PROVIDER_READ_OWN_BID_RPC = 'provider_read_own_bid';
export const PROVIDER_BID_CONFIRM_TITLE = 'Submit this bid?';
export const PROVIDER_BID_CONFIRM_TEXT = 'Your amount will be submitted only after you confirm this action.';
export const PROVIDER_BID_WITHDRAW_CONFIRM_TITLE = 'Withdraw this bid?';
export const PROVIDER_BID_WITHDRAW_CONFIRM_TEXT = 'A withdrawn bid cannot be submitted again for this request.';
export const PROVIDER_BID_SUBMITTED_MESSAGE = 'Bid submitted.';
export const PROVIDER_BID_WITHDRAWN_MESSAGE = 'Bid withdrawn.';
export const PROVIDER_BID_UNAVAILABLE_MESSAGE = 'This bid action is unavailable.';
export const PROVIDER_BID_AMBIGUOUS_MESSAGE = 'The bid result could not be confirmed. Refresh requests before another action.';

export const PROVIDER_OWN_BID_FIELDS = Object.freeze([
  'bid_id',
  'request_id',
  'amount_minor',
  'currency',
  'proposed_start',
  'status',
  'expires_at',
]);

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const BID_STATUSES = new Set(['submitted', 'withdrawn', 'accepted', 'declined', 'expired']);

function isUuid(value) {
  return UUID_PATTERN.test(String(value ?? ''));
}

function isDateTime(value) {
  return typeof value === 'string' && value.length > 0 && Number.isFinite(Date.parse(value));
}

function safeOwnBid(value) {
  if (!value || typeof value !== 'object'
      || !isUuid(value.bid_id)
      || !isUuid(value.request_id)
      || !Number.isSafeInteger(value.amount_minor)
      || value.amount_minor < 1
      || value.amount_minor > 100000000
      || value.currency !== 'ZAR'
      || !isDateTime(value.proposed_start)
      || !BID_STATUSES.has(value.status)
      || !isDateTime(value.expires_at)) return null;

  return Object.freeze({
    bid_id: value.bid_id,
    request_id: value.request_id,
    amount_minor: value.amount_minor,
    currency: value.currency,
    proposed_start: value.proposed_start,
    status: value.status,
    expires_at: value.expires_at,
  });
}

export function parseProviderBidAmount(value) {
  const normalized = String(value ?? '').trim();
  if (!/^(?:0|[1-9][0-9]{0,6})(?:\.[0-9]{1,2})?$/u.test(normalized)) return null;
  const [whole, fraction = ''] = normalized.split('.');
  const amountMinor = (Number(whole) * 100) + Number(fraction.padEnd(2, '0'));
  return Number.isSafeInteger(amountMinor) && amountMinor >= 1 && amountMinor <= 100000000
    ? amountMinor
    : null;
}

export async function readOwnProviderBid(client, requestId) {
  if (!client || !isUuid(requestId)) {
    return { ok: false, data: null, message: PROVIDER_BID_UNAVAILABLE_MESSAGE };
  }
  try {
    const { data, error } = await client.rpc(PROVIDER_READ_OWN_BID_RPC, {
      p_request_id: requestId,
    });
    if (error || !Array.isArray(data) || data.length > 1) {
      return { ok: false, data: null, message: PROVIDER_BID_UNAVAILABLE_MESSAGE };
    }
    if (data.length === 0) return { ok: true, data: null };
    const bid = safeOwnBid(data[0]);
    return bid && bid.request_id === requestId
      ? { ok: true, data: bid }
      : { ok: false, data: null, message: PROVIDER_BID_UNAVAILABLE_MESSAGE };
  } catch {
    return { ok: false, data: null, message: PROVIDER_BID_UNAVAILABLE_MESSAGE };
  }
}

export async function submitProviderBid(client, requestId, amountMinor) {
  if (!client || !isUuid(requestId) || !Number.isSafeInteger(amountMinor)
      || amountMinor < 1 || amountMinor > 100000000) {
    return { ok: false, kind: 'unavailable', message: PROVIDER_BID_UNAVAILABLE_MESSAGE };
  }
  try {
    const { data, error } = await client.rpc(PROVIDER_SUBMIT_BID_RPC, {
      p_request_id: requestId,
      p_amount_minor: amountMinor,
    });
    if (error) {
      const kind = ['22023', '42501'].includes(error.code) ? 'unavailable' : 'ambiguous';
      return {
        ok: false,
        kind,
        message: kind === 'ambiguous'
          ? PROVIDER_BID_AMBIGUOUS_MESSAGE
          : PROVIDER_BID_UNAVAILABLE_MESSAGE,
      };
    }
    return isUuid(data)
      ? { ok: true, bidId: data }
      : { ok: false, kind: 'ambiguous', message: PROVIDER_BID_AMBIGUOUS_MESSAGE };
  } catch {
    return { ok: false, kind: 'ambiguous', message: PROVIDER_BID_AMBIGUOUS_MESSAGE };
  }
}

export async function withdrawProviderBid(client, bidId) {
  if (!client || !isUuid(bidId)) {
    return { ok: false, kind: 'unavailable', message: PROVIDER_BID_UNAVAILABLE_MESSAGE };
  }
  try {
    const { data, error } = await client.rpc(PROVIDER_WITHDRAW_BID_RPC, {
      p_bid_id: bidId,
    });
    if (error) {
      const kind = error.code === '42501' ? 'unavailable' : 'ambiguous';
      return {
        ok: false,
        kind,
        message: kind === 'ambiguous'
          ? PROVIDER_BID_AMBIGUOUS_MESSAGE
          : PROVIDER_BID_UNAVAILABLE_MESSAGE,
      };
    }
    return data === 'withdrawn'
      ? { ok: true, status: 'withdrawn' }
      : { ok: false, kind: 'ambiguous', message: PROVIDER_BID_AMBIGUOUS_MESSAGE };
  } catch {
    return { ok: false, kind: 'ambiguous', message: PROVIDER_BID_AMBIGUOUS_MESSAGE };
  }
}
