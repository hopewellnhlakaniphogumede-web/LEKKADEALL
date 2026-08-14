import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { extractAuthCode, registerWithPassword } from '../auth-session.js';
import { readPublicConfig } from '../public-config.js';
import { createPublicSupabaseClient } from '../supabase-public-client.js';
import {
  SAFE_PROJECTIONS,
  readActiveServiceCategories,
  readOwnCustomerBookings,
  readOwnCustomerPayments,
  readOwnCustomerRequestDetail,
  readOwnCustomerRequests,
  readOwnProviderStatus,
  readOwnRouteProfile,
  readOwnSettingsProfile,
} from '../safe-reads.js';
import { resolveRouteAccess } from '../route-guards.js';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');

test('public config rejects placeholders and accepts only documented browser values', () => {
  assert.equal(readPublicConfig({
    appEnv: 'development', appUrl: 'http://localhost:4173',
    supabaseUrl: 'https://YOUR_PROJECT_REF.supabase.co', supabaseAnonKey: 'YOUR_SUPABASE_ANON_KEY',
  }).ok, false);
  const result = readPublicConfig({
    appEnv: 'development', appUrl: 'http://localhost:4173',
    supabaseUrl: 'https://project-ref.supabase.co', supabaseAnonKey: 'public-anon-value',
  });
  assert.equal(result.ok, true);
  assert.deepEqual(Object.keys(result.config).sort(), ['appEnv', 'appUrl', 'supabaseAnonKey', 'supabaseUrl']);

  const localTest = readPublicConfig({
    appEnv: 'test', appUrl: 'http://127.0.0.1:4173',
    supabaseUrl: 'http://127.0.0.1:54321', supabaseAnonKey: 'local-public-anon-value',
  });
  assert.equal(localTest.ok, true);
  assert.equal(readPublicConfig({
    appEnv: 'test', appUrl: 'https://remote.example.test',
    supabaseUrl: 'http://127.0.0.1:54321', supabaseAnonKey: 'local-public-anon-value',
  }).ok, false);
  assert.equal(readPublicConfig({
    appEnv: 'test', appUrl: 'http://127.0.0.1:4173',
    supabaseUrl: 'https://project-ref.supabase.co', supabaseAnonKey: 'public-anon-value',
  }).ok, false);
  assert.equal(readPublicConfig({
    appEnv: 'production', appUrl: 'https://marketplace.example.test',
    supabaseUrl: 'http://127.0.0.1:54321', supabaseAnonKey: 'local-public-anon-value',
  }).ok, false);
});

test('browser client receives only public URL, anon key and safe options', () => {
  const calls = [];
  const client = createPublicSupabaseClient(
    { supabaseUrl: 'https://project-ref.supabase.co', supabaseAnonKey: 'anon-value' },
    (...args) => { calls.push(args); return { boundary: 'public' }; },
  );
  assert.deepEqual(client, { boundary: 'public' });
  assert.deepEqual(calls[0], [
    'https://project-ref.supabase.co', 'anon-value',
    { db: { schema: 'public' }, auth: { flowType: 'pkce', autoRefreshToken: true, persistSession: true, detectSessionInUrl: false } },
  ]);
});

test('registration sends no metadata and callback ignores role and status input', async () => {
  let payload;
  const client = { auth: { signUp: async (value) => { payload = value; return { data: { session: null }, error: null }; } } };
  const result = await registerWithPassword(client, 'customer@example.test', 'a-long-password', 'http://localhost:4173');
  assert.equal(result.ok, true);
  assert.deepEqual(payload, {
    email: 'customer@example.test', password: 'a-long-password',
    options: { emailRedirectTo: 'http://localhost:4173/auth/callback' },
  });
  assert.equal(extractAuthCode('http://localhost/auth/callback?code=valid&role=admin&account_status=active'), 'valid');
});

test('route guards use session plus protected profile role and status', () => {
  const session = { user: { id: 'user-1' } };
  assert.deepEqual(resolveRouteAccess('/app/customer', null, null), { kind: 'signedOut' });
  assert.deepEqual(resolveRouteAccess('/app/customer', session, null), { kind: 'missingProfile' });
  assert.deepEqual(resolveRouteAccess('/app/customer', session, { role: 'customer', account_status: 'active' }), { kind: 'allowed', role: 'customer' });
  assert.deepEqual(resolveRouteAccess('/app/customer/requests/new', session, { role: 'customer', account_status: 'active' }), { kind: 'allowed', role: 'customer' });
  assert.deepEqual(resolveRouteAccess('/app/customer/requests', session, { role: 'customer', account_status: 'active' }), { kind: 'allowed', role: 'customer' });
  assert.deepEqual(resolveRouteAccess('/app/customer/requests/detail', session, { role: 'customer', account_status: 'active' }), { kind: 'allowed', role: 'customer' });
  assert.deepEqual(resolveRouteAccess('/app/customer/requests/new', session, { role: 'provider', account_status: 'active' }), { kind: 'accessDenied' });
  assert.deepEqual(resolveRouteAccess('/app/customer/requests', session, { role: 'provider', account_status: 'active' }), { kind: 'accessDenied' });
  assert.deepEqual(resolveRouteAccess('/app/customer/requests/detail', session, { role: 'provider', account_status: 'active' }), { kind: 'accessDenied' });
  assert.deepEqual(resolveRouteAccess('/app/provider', session, { role: 'customer', account_status: 'active' }), { kind: 'accessDenied' });
  assert.deepEqual(resolveRouteAccess('/app/provider', session, { role: 'provider', account_status: 'suspended' }), { kind: 'restricted', accountStatus: 'suspended' });
  assert.deepEqual(resolveRouteAccess('/app/settings', session, { role: 'admin', account_status: 'active' }), { kind: 'accessDenied' });
  assert.deepEqual(resolveRouteAccess('/app/settings', session, { role: 'unexpected', account_status: 'active' }), { kind: 'accessDenied' });
});

function recordingClient(records) {
  return {
    from(table) {
      const record = { table, projection: null, operations: [] };
      records.push(record);
      const builder = {
        select(projection) { record.projection = projection; return builder; },
        eq(...args) { record.operations.push(['eq', ...args]); return builder; },
        in(...args) { record.operations.push(['in', ...args]); return builder; },
        order(...args) { record.operations.push(['order', ...args]); return builder; },
        limit(...args) { record.operations.push(['limit', ...args]); return builder; },
        maybeSingle() { return Promise.resolve({ data: null, error: null }); },
        then(resolve) { return Promise.resolve({ data: [], error: null }).then(resolve); },
      };
      return builder;
    },
  };
}

test('all reads use a fixed table allowlist and explicit projections', async () => {
  const records = [];
  const client = recordingClient(records);
  await readActiveServiceCategories(client);
  await readOwnRouteProfile(client, 'user-1');
  await readOwnSettingsProfile(client, 'user-1');
  await readOwnProviderStatus(client, 'user-1');
  await readOwnCustomerRequests(client);
  await readOwnCustomerRequestDetail(client, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  await readOwnCustomerBookings(client);
  await readOwnCustomerPayments(client, ['booking-1']);
  assert.deepEqual(records.map(({ table }) => table), [
    'service_categories', 'profiles', 'profiles', 'provider_profiles',
    'service_requests', 'service_requests', 'bookings', 'payments',
  ]);
  for (const record of records) {
    assert.ok(record.projection && !record.projection.includes('*'), `${record.table} must use an explicit projection`);
  }
  assert.equal(records[0].operations.some((operation) => operation[0] === 'eq' && operation[1] === 'active' && operation[2] === true), true);
  assert.equal(SAFE_PROJECTIONS.customerRequests, 'id,category_id,title,description,suburb,city,requested_start,budget_minor,status,created_at,updated_at');
  assert.doesNotMatch(SAFE_PROJECTIONS.customerRequests, /customer_id|closes_at|published_at|cancelled_at|precise_address/);
  assert.equal(Object.values(SAFE_PROJECTIONS).some((projection) => projection.includes('precise_address') || projection.includes('provider_reference')), false);
});

test('non-mutation browser modules contain no application DML, RPC, broad select or blocked source', async () => {
  const mutationModules = new Set([
    'provider-application.js', 'provider-bidding.js', 'provider-discovery.js', 'request-draft.js', 'request-cancellation.js',
    'request-publication.js', 'request-update.js',
  ]);
  const moduleNames = (await readdir(root)).filter((name) => name.endsWith('.js') && !name.startsWith('runtime-config') && !mutationModules.has(name));
  const source = (await Promise.all(moduleNames.map((name) => readFile(join(root, name), 'utf8')))).join('\n');
  const forbidden = [
    '.insert(', '.update(', '.upsert(', '.delete(', '.rpc(', ".select('*')", '.select("*")',
    "from('addresses')", "from('identity_verifications')", "from('payment_events')",
    "from('refund_requests')", "from('disputes')", "from('reviews')", "from('support_cases')",
    'service_role', 'SUPABASE_SERVICE_ROLE_KEY', 'webhook_secret', 'provider_secret', 'identity_secret',
  ];
  for (const token of forbidden) assert.equal(source.includes(token), false, `forbidden browser token: ${token}`);
});

test('environment example contains placeholders only and local config is ignored', async () => {
  const [environment, ignore] = await Promise.all([
    readFile(join(root, '.env.example'), 'utf8'),
    readFile(join(root, '..', '..', '.gitignore'), 'utf8'),
  ]);
  assert.match(environment, /PUBLIC_SUPABASE_URL=https:\/\/YOUR_PROJECT_REF\.supabase\.co/);
  assert.match(environment, /PUBLIC_SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY/);
  assert.doesNotMatch(environment, /service[_-]?role|secret/i);
  assert.match(ignore, /runtime-config\.local\.js/);
});
