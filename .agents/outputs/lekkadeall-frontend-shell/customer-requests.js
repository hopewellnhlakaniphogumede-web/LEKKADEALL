export const CUSTOMER_REQUEST_PROJECTION = 'id,category_id,title,description,suburb,city,requested_start,budget_minor,status,created_at,updated_at';
export const CUSTOMER_REQUEST_STATUSES = Object.freeze(['draft', 'open', 'cancelled']);
export const CUSTOMER_REQUEST_DETAIL_ROUTE = '/app/customer/requests/detail';
export const CUSTOMER_REQUEST_EDIT_ROUTE = '/app/customer/requests/edit';
export const CUSTOMER_REQUEST_UNAVAILABLE_REASON = 'not-found-or-unavailable';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const STATUS_LABELS = Object.freeze({
  draft: 'Draft',
  open: 'Open',
  cancelled: 'Cancelled',
});

const SAST_FORMATTER = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'Africa/Johannesburg',
  day: '2-digit',
  month: 'short',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
});

export function isCustomerRequestId(value) {
  return typeof value === 'string' && UUID_PATTERN.test(value);
}

export function customerRequestDetailHref(requestId) {
  if (!isCustomerRequestId(requestId)) return null;
  return `${CUSTOMER_REQUEST_DETAIL_ROUTE}/?requestId=${encodeURIComponent(requestId)}`;
}

export function customerRequestEditHref(requestId) {
  if (!isCustomerRequestId(requestId)) return null;
  return `${CUSTOMER_REQUEST_EDIT_ROUTE}/?requestId=${encodeURIComponent(requestId)}`;
}

export function isAllowedCustomerRequestStatus(value) {
  return CUSTOMER_REQUEST_STATUSES.includes(value);
}

export function customerRequestStatusLabel(value) {
  return STATUS_LABELS[value] ?? 'Unavailable';
}

export function activeCategoryLabel(categories, categoryId) {
  if (!Array.isArray(categories)) return 'Category unavailable';
  const category = categories.find((item) => item?.id === categoryId);
  const label = typeof category?.name === 'string' ? category.name.trim() : '';
  return label || 'Category unavailable';
}

export function formatSastDateTime(value) {
  const parsed = new Date(value);
  if (!value || !Number.isFinite(parsed.getTime())) return 'Date unavailable';
  const parts = Object.fromEntries(
    SAST_FORMATTER.formatToParts(parsed)
      .filter(({ type }) => type !== 'literal')
      .map(({ type, value: partValue }) => [type, partValue]),
  );
  return `${parts.day} ${parts.month} ${parts.year}, ${parts.hour}:${parts.minute} SAST`;
}

export function formatZarBudgetMinor(value) {
  if (value === null || value === undefined) return 'Budget not specified';
  if (!Number.isSafeInteger(value) || value < 0) return 'Budget unavailable';
  const minor = BigInt(value);
  const whole = (minor / 100n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  const cents = (minor % 100n).toString().padStart(2, '0');
  return `ZAR ${whole}.${cents}`;
}
