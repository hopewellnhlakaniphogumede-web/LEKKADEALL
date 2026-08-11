import { assertLoopbackUrl } from './local-environment.mjs';

export const ALLOWED_MARKETPLACE_RPCS = Object.freeze([
  'customer_submit_provider_application',
  'customer_create_draft_request',
  'customer_update_draft_request',
  'customer_cancel_draft_request',
  'customer_publish_draft_request',
]);

const ALLOWED_READ_TABLES = new Set([
  'profiles',
  'provider_profiles',
  'service_categories',
  'service_requests',
  'bookings',
  'payments',
]);
const AUTHORITY_KEYS = new Set([
  'role',
  'account_status',
  'provider_status',
  'verification_status',
  'review_status',
  'identity_status',
  'payment_status',
  'admin',
  'support',
  'address',
  'precise_address_ciphertext',
]);
const EXPECTED_RPC_KEYS = Object.freeze({
  customer_submit_provider_application: [
    'p_business_name', 'p_category_ids', 'p_service_radius_km', 'p_terms_version',
  ],
  customer_create_draft_request: [
    'p_budget_minor', 'p_category_id', 'p_city', 'p_description',
    'p_precise_address_ciphertext', 'p_requested_start', 'p_suburb', 'p_title',
  ],
  customer_update_draft_request: [
    'p_budget_minor', 'p_category_id', 'p_city', 'p_description',
    'p_request_id', 'p_requested_start', 'p_suburb', 'p_title',
  ],
  customer_cancel_draft_request: ['p_request_id'],
  customer_publish_draft_request: ['p_request_id'],
});

function decodeJwtRole(value) {
  try {
    const token = String(value ?? '').replace(/^Bearer\s+/iu, '');
    const payload = token.split('.')[1];
    if (!payload) return null;
    return JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')).role ?? null;
  } catch {
    return null;
  }
}

function hasAuthorityKey(value) {
  if (!value || typeof value !== 'object') return false;
  for (const [key, nested] of Object.entries(value)) {
    if (AUTHORITY_KEYS.has(key.toLowerCase()) || hasAuthorityKey(nested)) return true;
  }
  return false;
}

function sortedKeys(value) {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? Object.keys(value).sort()
    : [];
}

function sameKeys(actual, expected) {
  return actual.length === expected.length && actual.every((key, index) => key === expected[index]);
}

export function attachNetworkPolicy(page, { appUrl, supabaseUrl, anonKey }) {
  const app = assertLoopbackUrl(appUrl, 'frontend');
  const supabase = assertLoopbackUrl(supabaseUrl, 'supabase');
  if (!anonKey || anonKey.length < 40) throw new Error('network-policy-anon-key-invalid');

  const violations = new Set();
  const rpcCounts = new Map();
  const tableReadCounts = new Map();
  let signupCount = 0;

  function violate(code) {
    violations.add(code);
  }

  page.on('request', (request) => {
    try {
      const url = new URL(request.url());
      if (['http:', 'https:'].includes(url.protocol)
          && !['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname)) {
        violate('non-loopback-request');
        return;
      }
      if (url.origin !== supabase.origin) return;

      const headers = request.headers();
      if (headers.apikey !== anonKey) violate('non-anon-api-key');
      if (decodeJwtRole(headers.authorization) === 'service_role') violate('service-role-authorization');

      if (url.pathname === '/auth/v1/signup') {
        signupCount += 1;
        const body = request.postDataJSON();
        if (hasAuthorityKey(body?.data) || hasAuthorityKey(body?.app_metadata)) {
          violate('registration-authority-metadata');
        }
        return;
      }

      if (!url.pathname.startsWith('/rest/v1/')) return;
      const restPath = url.pathname.slice('/rest/v1/'.length);
      if (restPath.startsWith('rpc/')) {
        const functionName = decodeURIComponent(restPath.slice('rpc/'.length));
        if (!ALLOWED_MARKETPLACE_RPCS.includes(functionName)) {
          violate('rpc-not-allowlisted');
          return;
        }
        if (request.method() !== 'POST') violate('rpc-method-invalid');
        const count = rpcCounts.get(functionName) ?? 0;
        rpcCounts.set(functionName, count + 1);
        const body = request.postDataJSON();
        if (!sameKeys(sortedKeys(body), EXPECTED_RPC_KEYS[functionName])) {
          violate('rpc-payload-shape-invalid');
        }
        if (functionName === 'customer_create_draft_request'
            && body?.p_precise_address_ciphertext !== null) {
          violate('draft-address-boundary-invalid');
        }
        return;
      }

      const table = decodeURIComponent(restPath.split('/')[0]);
      if (!ALLOWED_READ_TABLES.has(table)) violate('blocked-table-read');
      if (!['GET', 'HEAD'].includes(request.method())) violate('direct-application-table-dml');
      else tableReadCounts.set(table, (tableReadCounts.get(table) ?? 0) + 1);
      const projection = url.searchParams.get('select');
      if (!projection || projection.includes('*')) violate('broad-column-select');
    } catch {
      violate('network-inspection-failed');
    }
  });

  page.on('requestfailed', (request) => {
    try {
      const url = new URL(request.url());
      if (url.origin === app.origin && request.resourceType() === 'document') {
        violate('frontend-document-request-failed');
      }
    } catch {
      violate('network-failure-inspection-failed');
    }
  });

  return Object.freeze({
    getRpcCount(functionName) {
      return rpcCounts.get(functionName) ?? 0;
    },
    getSignupCount() {
      return signupCount;
    },
    getTableReadCount(table) {
      return tableReadCounts.get(table) ?? 0;
    },
    assertClean() {
      if (violations.size) throw new Error('browser-network-policy-violation');
    },
  });
}
