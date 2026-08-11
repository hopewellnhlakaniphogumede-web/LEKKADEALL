import {
  CUSTOMER_REQUEST_PROJECTION,
  CUSTOMER_REQUEST_STATUSES,
  CUSTOMER_REQUEST_UNAVAILABLE_REASON,
  isAllowedCustomerRequestStatus,
  isCustomerRequestId,
} from './customer-requests.js';

export const SAFE_PROJECTIONS = Object.freeze({
  serviceCategories: 'id,slug,name',
  routeProfile: 'id,role,account_status',
  settingsProfile: 'id,display_name,phone_e164,phone_verified_at,email_verified_at,suburb,city,avatar_path,role,account_status,created_at,updated_at',
  providerStatus: 'user_id,business_name,service_radius_km,verification_status,review_status',
  customerRequests: CUSTOMER_REQUEST_PROJECTION,
  customerBookings: 'id,public_reference,request_id,bid_id,service_amount_minor,platform_fee_minor,currency,scheduled_start,status,completion_confirmed_at,created_at,updated_at',
  customerPayments: 'id,booking_id,status,amount_minor,currency,release_status,release_paused,refunded_minor,checkout_expires_at,created_at,updated_at',
});

function safeResult(data, error) {
  return error
    ? { ok: false, data: null, reason: 'read-unavailable' }
    : { ok: true, data };
}

export async function readActiveServiceCategories(client) {
  const { data, error } = await client
    .from('service_categories')
    .select(SAFE_PROJECTIONS.serviceCategories)
    .eq('active', true)
    .order('name', { ascending: true })
    .limit(100);
  return safeResult(data ?? [], error);
}

export async function readOwnRouteProfile(client, userId) {
  const { data, error } = await client
    .from('profiles')
    .select(SAFE_PROJECTIONS.routeProfile)
    .eq('id', userId)
    .maybeSingle();
  return safeResult(data ?? null, error);
}

export async function readOwnSettingsProfile(client, userId) {
  const { data, error } = await client
    .from('profiles')
    .select(SAFE_PROJECTIONS.settingsProfile)
    .eq('id', userId)
    .maybeSingle();
  return safeResult(data ?? null, error);
}

export async function readOwnProviderStatus(client, userId) {
  const { data, error } = await client
    .from('provider_profiles')
    .select(SAFE_PROJECTIONS.providerStatus)
    .eq('user_id', userId)
    .maybeSingle();
  return safeResult(data ?? null, error);
}

export async function readOwnCustomerRequests(client) {
  const { data, error } = await client
    .from('service_requests')
    .select(SAFE_PROJECTIONS.customerRequests)
    .in('status', CUSTOMER_REQUEST_STATUSES)
    .order('created_at', { ascending: false })
    .limit(20);
  return safeResult(
    (data ?? []).filter((request) => isAllowedCustomerRequestStatus(request?.status)),
    error,
  );
}

export async function readOwnCustomerRequestDetail(client, requestId) {
  if (!isCustomerRequestId(requestId)) {
    return { ok: false, data: null, reason: CUSTOMER_REQUEST_UNAVAILABLE_REASON };
  }

  const { data, error } = await client
    .from('service_requests')
    .select(SAFE_PROJECTIONS.customerRequests)
    .eq('id', requestId)
    .in('status', CUSTOMER_REQUEST_STATUSES)
    .maybeSingle();

  if (error || !data || !isAllowedCustomerRequestStatus(data.status)) {
    return { ok: false, data: null, reason: CUSTOMER_REQUEST_UNAVAILABLE_REASON };
  }
  return { ok: true, data };
}

export async function readOwnCustomerDraftForEdit(client, requestId) {
  if (!isCustomerRequestId(requestId)) {
    return { ok: false, data: null, reason: CUSTOMER_REQUEST_UNAVAILABLE_REASON };
  }

  const { data, error } = await client
    .from('service_requests')
    .select(SAFE_PROJECTIONS.customerRequests)
    .eq('id', requestId)
    .eq('status', 'draft')
    .maybeSingle();

  if (error || !data || data.status !== 'draft') {
    return { ok: false, data: null, reason: CUSTOMER_REQUEST_UNAVAILABLE_REASON };
  }
  return { ok: true, data };
}

export async function readOwnCustomerBookings(client) {
  const { data, error } = await client
    .from('bookings')
    .select(SAFE_PROJECTIONS.customerBookings)
    .order('created_at', { ascending: false })
    .limit(20);
  return safeResult(data ?? [], error);
}

export async function readOwnCustomerPayments(client, bookingIds) {
  if (!Array.isArray(bookingIds) || bookingIds.length === 0) {
    return { ok: true, data: [] };
  }
  const { data, error } = await client
    .from('payments')
    .select(SAFE_PROJECTIONS.customerPayments)
    .in('booking_id', bookingIds.slice(0, 20))
    .order('created_at', { ascending: false })
    .limit(20);
  return safeResult(data ?? [], error);
}
