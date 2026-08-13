export const PROVIDER_DISCOVERY_RPC = 'provider_list_discoverable_requests';
export const PROVIDER_DISCOVERY_PAGE_SIZE = 20;
export const PROVIDER_DISCOVERY_UNAVAILABLE_MESSAGE = 'Request discovery is unavailable right now.';

export const PROVIDER_DISCOVERY_FIELDS = Object.freeze([
  'request_id',
  'category_id',
  'title',
  'description',
  'suburb',
  'city',
  'requested_start',
  'budget_minor',
  'closes_at',
  'published_at',
]);

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;

function isDateTime(value) {
  return typeof value === 'string' && value.length > 0 && Number.isFinite(Date.parse(value));
}

function safeDiscoveryRequest(value) {
  if (!value || typeof value !== 'object'
      || !UUID_PATTERN.test(String(value.request_id ?? ''))
      || !UUID_PATTERN.test(String(value.category_id ?? ''))
      || typeof value.title !== 'string'
      || typeof value.description !== 'string'
      || typeof value.suburb !== 'string'
      || typeof value.city !== 'string'
      || !isDateTime(value.requested_start)
      || !isDateTime(value.closes_at)
      || !isDateTime(value.published_at)
      || (value.budget_minor !== null && !Number.isSafeInteger(value.budget_minor))) {
    return null;
  }
  return Object.freeze({
    request_id: value.request_id,
    category_id: value.category_id,
    title: value.title,
    description: value.description,
    suburb: value.suburb,
    city: value.city,
    requested_start: value.requested_start,
    budget_minor: value.budget_minor,
    closes_at: value.closes_at,
    published_at: value.published_at,
  });
}

function safeCursor(cursor) {
  if (cursor === null || cursor === undefined) {
    return { publishedAt: null, requestId: null };
  }
  if (!isDateTime(cursor.publishedAt) || !UUID_PATTERN.test(String(cursor.requestId ?? ''))) {
    return null;
  }
  return { publishedAt: cursor.publishedAt, requestId: cursor.requestId };
}

export async function readProviderDiscoveryPage(
  client,
  { pageSize = PROVIDER_DISCOVERY_PAGE_SIZE, cursor = null } = {},
) {
  const safePageSize = Number(pageSize);
  const normalizedCursor = safeCursor(cursor);
  if (!client || !Number.isInteger(safePageSize) || safePageSize < 1 || safePageSize > 50
      || !normalizedCursor) {
    return { ok: false, data: [], cursor: null, hasMore: false, reason: 'discovery-unavailable' };
  }

  const { data, error } = await client.rpc(PROVIDER_DISCOVERY_RPC, {
    p_page_size: safePageSize,
    p_cursor_published_at: normalizedCursor.publishedAt,
    p_cursor_request_id: normalizedCursor.requestId,
  });
  if (error || !Array.isArray(data)) {
    return { ok: false, data: [], cursor: null, hasMore: false, reason: 'discovery-unavailable' };
  }

  const requests = data.map(safeDiscoveryRequest);
  if (requests.some((request) => request === null)) {
    return { ok: false, data: [], cursor: null, hasMore: false, reason: 'discovery-unavailable' };
  }
  const last = requests.at(-1);
  return {
    ok: true,
    data: requests,
    cursor: last ? { publishedAt: last.published_at, requestId: last.request_id } : null,
    hasMore: requests.length === safePageSize,
  };
}
