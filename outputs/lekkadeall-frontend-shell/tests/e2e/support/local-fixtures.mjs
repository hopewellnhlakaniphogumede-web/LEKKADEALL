import {
  assertLocalDockerConfiguration,
  assertLoopbackUrl,
  runCaptured,
} from './local-environment.mjs';

export const ACTIVE_CATEGORY_ID = '90000000-0000-4000-8000-000000000001';
export const INACTIVE_CATEGORY_ID = '90000000-0000-4000-8000-000000000002';
export const NONMATCHING_CATEGORY_ID = '90000000-0000-4000-8000-000000000003';
export const ACTIVE_CATEGORY_NAME = 'Synthetic home maintenance';
export const PROVIDER_DISCOVERY_MATCHING_TITLE = 'Repair synthetic indoor fixture';
export const PROVIDER_DISCOVERY_NONMATCHING_TITLE = 'Service synthetic outdoor fixture';
export const PROVIDER_DISCOVERY_MATCHING_REQUEST_ID = '90000000-0000-4000-8000-000000000221';
export const CUSTOMER_BID_VIEWING_REQUEST_ID = '90000000-0000-4000-8000-000000000223';
export const CUSTOMER_BID_VIEWING_DRAFT_REQUEST_ID = '90000000-0000-4000-8000-000000000224';
export const CUSTOMER_BID_VIEWING_CANCELLED_REQUEST_ID = '90000000-0000-4000-8000-000000000225';
export const CUSTOMER_BID_VIEWING_AWARDED_REQUEST_ID = '90000000-0000-4000-8000-000000000226';
export const CUSTOMER_BID_VIEWING_PAST_CLOSE_REQUEST_ID = '90000000-0000-4000-8000-000000000227';
export const CUSTOMER_BID_VIEWING_TITLE = 'Review synthetic current bids';
const PROVIDER_DISCOVERY_ADMIN_ID = '90000000-0000-4000-8000-000000000201';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const SYNTHETIC_EMAIL_PATTERN = /^[a-z0-9][a-z0-9+._-]{0,100}@lekkadeall\.invalid$/iu;
const SYNTHETIC_PASSWORD_PATTERN = /^E2e-[A-Za-z0-9_-]{24}!9$/u;
const DB_CONTAINER_NAME = 'supabase_db_lekkadeall-local';
const ROLES = new Set(['customer', 'provider']);
const ACCOUNT_STATUSES = new Set(['active', 'restricted', 'suspended', 'closed']);
const FIXTURE_STATES = new Set(['absent', 'auth-only', 'ready', 'invalid']);

function safeDockerEnvironment() {
  const safe = {};
  for (const name of [
    'APPDATA', 'HOME', 'LOCALAPPDATA', 'PATH', 'PATHEXT',
    'SystemRoot', 'TEMP', 'TMP', 'USERPROFILE', 'WINDIR',
  ]) {
    if (process.env[name] !== undefined) safe[name] = process.env[name];
  }
  return safe;
}

function requireUuid(value) {
  if (!UUID_PATTERN.test(String(value ?? ''))) throw new Error('fixture-uuid-invalid');
  return String(value);
}

function requireSyntheticEmail(value) {
  const email = String(value ?? '').toLowerCase();
  if (!SYNTHETIC_EMAIL_PATTERN.test(email)) throw new Error('fixture-email-must-be-synthetic');
  return email;
}

function requireSyntheticPassword(value) {
  const password = String(value ?? '');
  if (!SYNTHETIC_PASSWORD_PATTERN.test(password)) {
    throw new Error('fixture-password-must-be-synthetic');
  }
  return password;
}

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

async function assertDatabaseContainer() {
  assertLocalDockerConfiguration();
  const result = await runCaptured('docker', [
    'ps',
    '--filter', `name=^/${DB_CONTAINER_NAME}$`,
    '--format', '{{.Names}}',
  ], { env: safeDockerEnvironment() });
  const names = result.stdout.split(/\r?\n/u).map((value) => value.trim()).filter(Boolean);
  if (names.length !== 1 || names[0] !== DB_CONTAINER_NAME) {
    throw new Error('local-supabase-database-container-unavailable');
  }
}

async function runSql(sql) {
  await assertDatabaseContainer();
  const result = await runCaptured('docker', [
    'exec', '-i', DB_CONTAINER_NAME,
    'psql', '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres',
  ], { input: sql, env: safeDockerEnvironment() });
  return result.stdout.trim();
}

export async function seedBaseFixtures() {
  await runSql(`
    insert into public.service_categories (id, slug, name, active, requires_manual_review)
    values
      ('${ACTIVE_CATEGORY_ID}'::uuid, 'e2e-synthetic-home-maintenance', '${ACTIVE_CATEGORY_NAME}', true, false),
      ('${INACTIVE_CATEGORY_ID}'::uuid, 'e2e-inactive-category', 'Synthetic inactive category', false, false),
      ('${NONMATCHING_CATEGORY_ID}'::uuid, 'e2e-synthetic-outdoor-maintenance', 'Synthetic outdoor maintenance', true, false)
    on conflict (id) do update
      set slug = excluded.slug,
          name = excluded.name,
          active = excluded.active,
          requires_manual_review = excluded.requires_manual_review;
  `);
}

export async function findSyntheticUserId(emailValue) {
  const email = requireSyntheticEmail(emailValue);
  const output = await runSql(`
    select u.id::text
    from auth.users as u
    where pg_catalog.lower(u.email) = ${sqlLiteral(email)}
    order by u.created_at desc
    limit 1;
  `);
  return requireUuid(output);
}

export async function readSyntheticAccountFixtureState(emailValue) {
  const email = requireSyntheticEmail(emailValue);
  const output = await runSql(`
    with fixture_counts as (
      select
        (select pg_catalog.count(*)
         from auth.users as u
         where pg_catalog.lower(u.email) = ${sqlLiteral(email)}) as auth_count,
        (select pg_catalog.count(*)
         from auth.users as u
         join public.profiles as p on p.id = u.id
         where pg_catalog.lower(u.email) = ${sqlLiteral(email)}) as profile_count,
        (select pg_catalog.count(*)
         from auth.users as u
         join public.profiles as p on p.id = u.id
         where pg_catalog.lower(u.email) = ${sqlLiteral(email)}
           and p.role = 'customer'::public.user_role
           and p.account_status = 'active'
           and p.display_name = 'New customer') as ready_profile_count,
        (select pg_catalog.count(*)
         from auth.users as u
         join public.provider_profiles as pp on pp.user_id = u.id
         where pg_catalog.lower(u.email) = ${sqlLiteral(email)}) as provider_profile_count
    )
    select case
      when auth_count = 0 and profile_count = 0 and provider_profile_count = 0 then 'absent'
      when auth_count = 1 and profile_count = 0 and provider_profile_count = 0 then 'auth-only'
      when auth_count = 1
       and profile_count = 1
       and ready_profile_count = 1
       and provider_profile_count = 0 then 'ready'
      else 'invalid'
    end
    from fixture_counts;
  `);
  if (!FIXTURE_STATES.has(output)) throw new Error('fixture-state-classification-invalid');
  return output;
}

export async function assertProvisionedCustomerProfile(emailValue) {
  const state = await readSyntheticAccountFixtureState(emailValue);
  if (state !== 'ready') throw new Error(`ticket-9b-profile-state-${state}`);
}

export async function waitForProvisionedCustomerProfile(
  emailValue,
  { timeoutMs = 30_000, intervalMs = 250 } = {},
) {
  const email = requireSyntheticEmail(emailValue);
  const deadline = Date.now() + timeoutMs;
  do {
    try {
      await assertProvisionedCustomerProfile(email);
      return;
    } catch (error) {
      if (!['ticket-9b-profile-state-absent', 'ticket-9b-profile-state-auth-only']
        .includes(error?.message)) throw error;
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  } while (Date.now() < deadline);
  throw new Error('ticket-9b-profile-readiness-timeout');
}

export async function assertSyntheticAccountAbsent(emailValue) {
  const state = await readSyntheticAccountFixtureState(emailValue);
  if (state !== 'absent') throw new Error('synthetic-ui-signup-identity-not-absent');
}

export async function reconcileAmbiguousUiSignup(
  emailValue,
  {
    discoveryTimeoutMs = 5_000,
    readinessTimeoutMs = 60_000,
    intervalMs = 100,
  } = {},
) {
  const email = requireSyntheticEmail(emailValue);
  const deadline = Date.now() + discoveryTimeoutMs;
  do {
    const state = await readSyntheticAccountFixtureState(email);
    if (state === 'invalid') throw new Error('synthetic-ui-signup-reconciliation-invalid');
    if (state === 'auth-only' || state === 'ready') {
      await waitForProvisionedCustomerProfile(email, {
        timeoutMs: readinessTimeoutMs,
        intervalMs: 250,
      });
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  } while (Date.now() < deadline);
  throw new Error('synthetic-ui-signup-reconciliation-absent');
}

async function reconcileAmbiguousSyntheticAuthCreation(
  email,
  { timeoutMs = 5_000, intervalMs = 100 } = {},
) {
  const deadline = Date.now() + timeoutMs;
  do {
    const state = await readSyntheticAccountFixtureState(email);
    if (state === 'auth-only' || state === 'ready') return;
    if (state === 'invalid') throw new Error('synthetic-auth-fixture-ambiguous-invalid');
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  } while (Date.now() < deadline);
  throw new Error('synthetic-auth-fixture-ambiguous-absent');
}

export async function createSyntheticLocalAuthUser(emailValue, passwordValue) {
  const email = requireSyntheticEmail(emailValue);
  const password = requireSyntheticPassword(passwordValue);
  const apiUrl = assertLoopbackUrl(process.env.E2E_SUPABASE_URL, 'fixture-auth');
  const adminKey = String(process.env.E2E_LOCAL_FIXTURE_ADMIN_KEY ?? '');
  if (adminKey.length < 40) throw new Error('local-fixture-admin-key-unavailable');
  let response;
  try {
    response = await fetch(new URL('/auth/v1/admin/users', apiUrl), {
      method: 'POST',
      redirect: 'manual',
      headers: {
        apikey: adminKey,
        authorization: `Bearer ${adminKey}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        email,
        password,
        email_confirm: true,
        app_metadata: {},
        user_metadata: {},
      }),
    });
  } catch {
    await reconcileAmbiguousSyntheticAuthCreation(email);
    return;
  }
  const status = response.status;
  await response.body?.cancel();
  if (status === 429) throw new Error('synthetic-auth-fixture-http-429');
  if ([409, 422].includes(status)) throw new Error('synthetic-auth-fixture-http-conflict');
  if (status < 200 || status >= 300) throw new Error('synthetic-auth-fixture-http-failure');
}

export async function prepareSyntheticCustomerAccount(emailValue, passwordValue) {
  const email = requireSyntheticEmail(emailValue);
  await createSyntheticLocalAuthUser(email, passwordValue);
  await waitForProvisionedCustomerProfile(email);
}

export async function prepareSyntheticProviderDiscovery(
  providerEmailValue,
  providerPasswordValue,
  customerEmailValue,
  customerPasswordValue,
) {
  const providerEmail = requireSyntheticEmail(providerEmailValue);
  const customerEmail = requireSyntheticEmail(customerEmailValue);
  await prepareSyntheticCustomerAccount(providerEmail, providerPasswordValue);
  await prepareSyntheticCustomerAccount(customerEmail, customerPasswordValue);
  const providerId = await findSyntheticUserId(providerEmail);
  const customerId = await findSyntheticUserId(customerEmail);
  await runSql(`
    begin;

    insert into auth.users (id, email)
    values ('${PROVIDER_DISCOVERY_ADMIN_ID}'::uuid, 'ticket10c-e2e-admin@lekkadeall.invalid')
    on conflict (id) do nothing;

    set local lekkadeall.allow_privileged_profile_update = 'on';
    update public.profiles
    set role = 'admin'::public.user_role
    where id = '${PROVIDER_DISCOVERY_ADMIN_ID}'::uuid;
    update public.profiles
    set role = 'provider'::public.user_role
    where id = '${providerId}'::uuid;
    set local lekkadeall.allow_privileged_profile_update = 'off';

    insert into public.provider_profiles (
      user_id, business_name, service_radius_km, verification_status, review_status
    ) values (
      '${providerId}'::uuid,
      'Synthetic discovery services',
      20,
      'not_started'::public.verification_status,
      'pending'
    );

    insert into public.provider_services (
      provider_id, category_id, description, base_price_minor, active
    ) values
      ('${providerId}'::uuid, '${ACTIVE_CATEGORY_ID}'::uuid, null, null, false),
      ('${providerId}'::uuid, '${NONMATCHING_CATEGORY_ID}'::uuid, null, null, false);

    insert into public.consents (
      user_id, purpose, policy_version, granted, source, withdrawn_at
    ) values (
      '${providerId}'::uuid,
      'provider_application_terms',
      'provider-application-v1',
      true,
      'customer_provider_application_rpc',
      null
    );

    insert into public.audit_events (
      actor_id, action, object_type, object_id, reason, metadata
    ) values (
      '${providerId}'::uuid,
      'customer.provider_application_submitted',
      'provider_profile',
      '${providerId}'::uuid,
      'Customer submitted closed-pilot provider application',
      '{}'::pg_catalog.jsonb
    );

    set local role authenticated;
    set local request.jwt.claim.sub = '${PROVIDER_DISCOVERY_ADMIN_ID}';
    set local request.jwt.claims = '{"sub":"${PROVIDER_DISCOVERY_ADMIN_ID}","role":"authenticated","aal":"aal2"}';
    select public.admin_transition_provider_marketplace_review(
      '${providerId}'::uuid,
      'approve_manual_pilot',
      'pending',
      '90000000-0000-4000-8000-000000000211'::uuid
    );
    reset role;

    set local role authenticated;
    set local request.jwt.claim.sub = '${providerId}';
    set local request.jwt.claims = '{"sub":"${providerId}","role":"authenticated","aal":"aal1"}';
    update public.provider_services
    set active = true
    where provider_id = '${providerId}'::uuid
      and category_id = '${ACTIVE_CATEGORY_ID}'::uuid;
    reset role;

    set local lekkadeall.allow_marketplace_state_transition = 'on';
    insert into public.service_requests (
      id, customer_id, category_id, title, description, suburb, city,
      requested_start, budget_minor, status, closes_at, published_at
    ) values
      (
        '${PROVIDER_DISCOVERY_MATCHING_REQUEST_ID}'::uuid,
        '${customerId}'::uuid,
        '${ACTIVE_CATEGORY_ID}'::uuid,
        '${PROVIDER_DISCOVERY_MATCHING_TITLE}',
        'Repair the reviewed synthetic indoor fixture using general service details only.',
        'Woodstock',
        'Cape Town',
        pg_catalog.now() + interval '5 days',
        125000,
        'open'::public.request_status,
        pg_catalog.now() + interval '2 days',
        pg_catalog.now() - interval '1 hour'
      ),
      (
        '90000000-0000-4000-8000-000000000222'::uuid,
        '${customerId}'::uuid,
        '${NONMATCHING_CATEGORY_ID}'::uuid,
        '${PROVIDER_DISCOVERY_NONMATCHING_TITLE}',
        'Service the reviewed synthetic outdoor fixture using general service details only.',
        'Woodstock',
        'Cape Town',
        pg_catalog.now() + interval '6 days',
        95000,
        'open'::public.request_status,
        pg_catalog.now() + interval '2 days',
        pg_catalog.now() - interval '2 hours'
      );
    set local lekkadeall.allow_marketplace_state_transition = 'off';

    commit;
  `);
}

async function submitSyntheticProviderBid(providerEmailValue, requestIdValue, amountMinorValue) {
  const providerEmail = requireSyntheticEmail(providerEmailValue);
  const requestId = requireUuid(requestIdValue);
  const amountMinor = Number(amountMinorValue);
  if (!Number.isSafeInteger(amountMinor) || amountMinor < 1 || amountMinor > 100000000) {
    throw new Error('synthetic-bid-amount-invalid');
  }
  const providerId = await findSyntheticUserId(providerEmail);
  const bidId = await runSql(`
    begin;
    set local role authenticated;
    set local request.jwt.claim.sub = '${providerId}';
    set local request.jwt.claims = '{"sub":"${providerId}","role":"authenticated","aal":"aal1"}';
    select public.provider_submit_bid('${requestId}'::uuid, ${amountMinor}::integer)::text;
    reset role;
    commit;
  `);
  return requireUuid(bidId);
}

async function withdrawSyntheticProviderBid(providerEmailValue, bidIdValue) {
  const providerEmail = requireSyntheticEmail(providerEmailValue);
  const bidId = requireUuid(bidIdValue);
  const providerId = await findSyntheticUserId(providerEmail);
  const status = await runSql(`
    begin;
    set local role authenticated;
    set local request.jwt.claim.sub = '${providerId}';
    set local request.jwt.claims = '{"sub":"${providerId}","role":"authenticated","aal":"aal1"}';
    select public.provider_withdraw_bid('${bidId}'::uuid)::text;
    reset role;
    commit;
  `);
  if (status !== 'withdrawn') throw new Error('synthetic-bid-withdrawal-unconfirmed');
}

export async function prepareSyntheticCustomerBidViewing({
  owner,
  otherCustomer,
  providers,
}) {
  if (!owner || !otherCustomer || !Array.isArray(providers) || providers.length !== 6) {
    throw new Error('customer-bid-viewing-fixture-input-invalid');
  }
  const accounts = [owner, otherCustomer, ...providers];
  for (const account of accounts) {
    await prepareSyntheticCustomerAccount(account.email, account.password);
  }
  const emails = accounts.map((account) => requireSyntheticEmail(account.email));
  if (new Set(emails).size !== accounts.length) {
    throw new Error('customer-bid-viewing-fixture-actors-not-distinct');
  }

  const ownerId = await findSyntheticUserId(owner.email);
  const providerIds = [];
  for (const provider of providers) providerIds.push(await findSyntheticUserId(provider.email));
  const providerProfileValues = providerIds.map((providerId, index) => `
      ('${providerId}'::uuid, 'Synthetic bid viewing service ${index + 1}', 20,
       'not_started'::public.verification_status, 'pending')`).join(',');
  const providerServiceValues = providerIds.map((providerId) => `
      ('${providerId}'::uuid, '${ACTIVE_CATEGORY_ID}'::uuid, null, null, false)`).join(',');
  const providerConsentValues = providerIds.map((providerId) => `
      ('${providerId}'::uuid, 'provider_application_terms', 'provider-application-v1',
       true, 'customer_provider_application_rpc', null)`).join(',');
  const providerAuditValues = providerIds.map((providerId) => `
      ('${providerId}'::uuid, 'customer.provider_application_submitted',
       'provider_profile', '${providerId}'::uuid,
       'Customer submitted closed-pilot provider application', '{}'::pg_catalog.jsonb)`).join(',');
  const approvalSql = providerIds.map((providerId, index) => `
    select public.admin_transition_provider_marketplace_review(
      '${providerId}'::uuid,
      'approve_manual_pilot',
      'pending',
      '90000000-0000-4000-8000-${String(231 + index).padStart(12, '0')}'::uuid
    );`).join('');

  await runSql(`
    begin;

    insert into auth.users (id, email)
    values ('${PROVIDER_DISCOVERY_ADMIN_ID}'::uuid, 'ticket10e-e2e-admin@lekkadeall.invalid')
    on conflict (id) do nothing;

    set local lekkadeall.allow_privileged_profile_update = 'on';
    update public.profiles
    set role = 'admin'::public.user_role
    where id = '${PROVIDER_DISCOVERY_ADMIN_ID}'::uuid;
    update public.profiles
    set role = 'provider'::public.user_role
    where id = any(array[${providerIds.map((id) => `'${id}'::uuid`).join(',')}]);
    set local lekkadeall.allow_privileged_profile_update = 'off';

    insert into public.provider_profiles (
      user_id, business_name, service_radius_km, verification_status, review_status
    ) values ${providerProfileValues};

    insert into public.provider_services (
      provider_id, category_id, description, base_price_minor, active
    ) values ${providerServiceValues};

    insert into public.consents (
      user_id, purpose, policy_version, granted, source, withdrawn_at
    ) values ${providerConsentValues};

    insert into public.audit_events (
      actor_id, action, object_type, object_id, reason, metadata
    ) values ${providerAuditValues};

    set local role authenticated;
    set local request.jwt.claim.sub = '${PROVIDER_DISCOVERY_ADMIN_ID}';
    set local request.jwt.claims = '{"sub":"${PROVIDER_DISCOVERY_ADMIN_ID}","role":"authenticated","aal":"aal2"}';
    ${approvalSql}
    reset role;

    update public.provider_services
    set active = true
    where provider_id = any(array[${providerIds.map((id) => `'${id}'::uuid`).join(',')}])
      and category_id = '${ACTIVE_CATEGORY_ID}'::uuid;

    set local lekkadeall.allow_marketplace_state_transition = 'on';
    insert into public.service_requests (
      id, customer_id, category_id, title, description, suburb, city,
      requested_start, budget_minor, status, closes_at, published_at,
      awarded_at, cancelled_at
    ) values
      (
        '${CUSTOMER_BID_VIEWING_REQUEST_ID}'::uuid,
        '${ownerId}'::uuid,
        '${ACTIVE_CATEGORY_ID}'::uuid,
        '${CUSTOMER_BID_VIEWING_TITLE}',
        'Review submitted synthetic service bids using public request details only.',
        'Woodstock',
        'Cape Town',
        pg_catalog.now() + interval '5 days',
        150000,
        'open'::public.request_status,
        pg_catalog.now() + interval '2 days',
        pg_catalog.now() - interval '1 hour',
        null,
        null
      ),
      (
        '${CUSTOMER_BID_VIEWING_DRAFT_REQUEST_ID}'::uuid,
        '${ownerId}'::uuid,
        '${ACTIVE_CATEGORY_ID}'::uuid,
        'Synthetic draft bid boundary',
        'A draft request must not expose the current bid viewer.',
        'Woodstock',
        'Cape Town',
        pg_catalog.now() + interval '5 days',
        150000,
        'draft'::public.request_status,
        null,
        null,
        null,
        null
      ),
      (
        '${CUSTOMER_BID_VIEWING_CANCELLED_REQUEST_ID}'::uuid,
        '${ownerId}'::uuid,
        '${ACTIVE_CATEGORY_ID}'::uuid,
        'Synthetic cancelled bid boundary',
        'A cancelled request must not expose the current bid viewer.',
        'Woodstock',
        'Cape Town',
        pg_catalog.now() + interval '5 days',
        150000,
        'cancelled'::public.request_status,
        null,
        null,
        null,
        pg_catalog.now() - interval '30 minutes'
      ),
      (
        '${CUSTOMER_BID_VIEWING_AWARDED_REQUEST_ID}'::uuid,
        '${ownerId}'::uuid,
        '${ACTIVE_CATEGORY_ID}'::uuid,
        'Synthetic awarded bid boundary',
        'An awarded request must not expose the current bid viewer.',
        'Woodstock',
        'Cape Town',
        pg_catalog.now() + interval '5 days',
        150000,
        'awarded'::public.request_status,
        pg_catalog.now() + interval '2 days',
        pg_catalog.now() - interval '2 hours',
        pg_catalog.now() - interval '30 minutes',
        null
      ),
      (
        '${CUSTOMER_BID_VIEWING_PAST_CLOSE_REQUEST_ID}'::uuid,
        '${ownerId}'::uuid,
        '${ACTIVE_CATEGORY_ID}'::uuid,
        'Synthetic past close bid boundary',
        'A past-close request must return only the generic viewer boundary.',
        'Woodstock',
        'Cape Town',
        pg_catalog.now() + interval '5 days',
        150000,
        'open'::public.request_status,
        pg_catalog.now() - interval '1 hour',
        pg_catalog.now() - interval '2 days',
        null,
        null
      );

    insert into public.bids (
      id, request_id, provider_id, amount_minor, currency, proposed_start,
      message, perks, status, expires_at, declined_at, created_at, updated_at
    ) values
      (
        '90000000-0000-4000-8000-000000000245'::uuid,
        '${CUSTOMER_BID_VIEWING_REQUEST_ID}'::uuid,
        '${providerIds[4]}'::uuid,
        140000,
        'ZAR',
        (select request.requested_start from public.service_requests as request
         where request.id = '${CUSTOMER_BID_VIEWING_REQUEST_ID}'::uuid),
        null,
        '{}'::text[],
        'expired'::public.bid_status,
        pg_catalog.now() - interval '1 hour',
        null,
        pg_catalog.now() - interval '2 hours',
        pg_catalog.now() - interval '2 hours'
      ),
      (
        '90000000-0000-4000-8000-000000000246'::uuid,
        '${CUSTOMER_BID_VIEWING_REQUEST_ID}'::uuid,
        '${providerIds[5]}'::uuid,
        150000,
        'ZAR',
        (select request.requested_start from public.service_requests as request
         where request.id = '${CUSTOMER_BID_VIEWING_REQUEST_ID}'::uuid),
        null,
        '{}'::text[],
        'declined'::public.bid_status,
        pg_catalog.now() + interval '2 days',
        pg_catalog.now() - interval '1 hour',
        pg_catalog.now() - interval '2 hours',
        pg_catalog.now() - interval '1 hour'
      );
    set local lekkadeall.allow_marketplace_state_transition = 'off';
    commit;
  `);

  await submitSyntheticProviderBid(providers[0].email, CUSTOMER_BID_VIEWING_REQUEST_ID, 100050);
  await submitSyntheticProviderBid(providers[1].email, CUSTOMER_BID_VIEWING_REQUEST_ID, 110000);
  const withdrawnBidId = await submitSyntheticProviderBid(
    providers[2].email,
    CUSTOMER_BID_VIEWING_REQUEST_ID,
    120000,
  );
  await withdrawSyntheticProviderBid(providers[2].email, withdrawnBidId);
  await submitSyntheticProviderBid(providers[3].email, CUSTOMER_BID_VIEWING_REQUEST_ID, 130000);
}

export async function revokeSyntheticCustomerBidViewingService(providerEmailValue) {
  const providerEmail = requireSyntheticEmail(providerEmailValue);
  const providerId = await findSyntheticUserId(providerEmail);
  await runSql(`
    update public.provider_services as service
    set active = false
    where service.provider_id = '${providerId}'::uuid
      and service.category_id = '${ACTIVE_CATEGORY_ID}'::uuid;
    do $e2e$
    begin
      if exists (
        select 1 from public.provider_services as service
        where service.provider_id = '${providerId}'::uuid
          and service.category_id = '${ACTIVE_CATEGORY_ID}'::uuid
          and service.active
      ) then
        raise exception 'customer bid viewing service revocation failed';
      end if;
    end;
    $e2e$;
  `);
}

export async function assertSyntheticCustomerBidViewingPostconditions(ownerEmailValue) {
  const ownerEmail = requireSyntheticEmail(ownerEmailValue);
  const ownerId = await findSyntheticUserId(ownerEmail);
  await runSql(`
    do $e2e$
    begin
      if not exists (
        select 1 from public.service_requests as request
        where request.id = '${CUSTOMER_BID_VIEWING_REQUEST_ID}'::uuid
          and request.customer_id = '${ownerId}'::uuid
          and request.status = 'open'::public.request_status
          and request.awarded_at is null
          and request.cancelled_at is null
          and request.precise_address_ciphertext is null
      )
      or (select pg_catalog.count(*) from public.bids as bid
          where bid.request_id = '${CUSTOMER_BID_VIEWING_REQUEST_ID}'::uuid) <> 6
      or (select pg_catalog.count(*) from public.bids as bid
          where bid.request_id = '${CUSTOMER_BID_VIEWING_REQUEST_ID}'::uuid
            and bid.status = 'submitted'::public.bid_status) <> 3
      or (select pg_catalog.count(*) from public.bids as bid
          where bid.request_id = '${CUSTOMER_BID_VIEWING_REQUEST_ID}'::uuid
            and bid.status = 'withdrawn'::public.bid_status) <> 1
      or (select pg_catalog.count(*) from public.bids as bid
          where bid.request_id = '${CUSTOMER_BID_VIEWING_REQUEST_ID}'::uuid
            and bid.status = 'expired'::public.bid_status) <> 1
      or (select pg_catalog.count(*) from public.bids as bid
          where bid.request_id = '${CUSTOMER_BID_VIEWING_REQUEST_ID}'::uuid
            and bid.status = 'declined'::public.bid_status) <> 1
      or (select pg_catalog.count(*) from public.audit_events as audit
          join public.bids as bid on bid.id::text = audit.object_id
          where bid.request_id = '${CUSTOMER_BID_VIEWING_REQUEST_ID}'::uuid
            and audit.object_type = 'bid') <> 5
      or exists (
        select 1 from private.service_request_addresses as address
        where address.request_id = '${CUSTOMER_BID_VIEWING_REQUEST_ID}'::uuid
      )
      or exists (
        select 1 from public.bookings as booking
        where booking.request_id = '${CUSTOMER_BID_VIEWING_REQUEST_ID}'::uuid
      )
      or exists (
        select 1 from public.payments as payment
        join public.bookings as booking on booking.id = payment.booking_id
        where booking.request_id = '${CUSTOMER_BID_VIEWING_REQUEST_ID}'::uuid
      ) then
        raise exception 'customer bid viewing postcondition failed';
      end if;
    end;
    $e2e$;
  `);
}

export async function suspendSyntheticProviderDiscovery(providerEmailValue) {
  const providerEmail = requireSyntheticEmail(providerEmailValue);
  const providerId = await findSyntheticUserId(providerEmail);
  await runSql(`
    begin;
    set local role authenticated;
    set local request.jwt.claim.sub = '${PROVIDER_DISCOVERY_ADMIN_ID}';
    set local request.jwt.claims = '{"sub":"${PROVIDER_DISCOVERY_ADMIN_ID}","role":"authenticated","aal":"aal2"}';
    select public.admin_transition_provider_marketplace_review(
      '${providerId}'::uuid,
      'suspend',
      'approved',
      '90000000-0000-4000-8000-000000000212'::uuid
    );
    reset role;
    commit;
  `);
}

export async function assertSyntheticProviderBiddingPostconditions(providerEmailValue) {
  const providerEmail = requireSyntheticEmail(providerEmailValue);
  const providerId = await findSyntheticUserId(providerEmail);
  await runSql(`
    do $e2e$
    declare
      v_bid_id uuid;
    begin
      select bid.id into v_bid_id
      from public.bids as bid
      where bid.provider_id = '${providerId}'::uuid
        and bid.request_id = '${PROVIDER_DISCOVERY_MATCHING_REQUEST_ID}'::uuid
        and bid.amount_minor = 100050
        and bid.currency = 'ZAR'
        and bid.status = 'withdrawn'::public.bid_status
        and bid.message is null
        and pg_catalog.cardinality(bid.perks) = 0
        and bid.proposed_start = (
          select request.requested_start from public.service_requests as request
          where request.id = '${PROVIDER_DISCOVERY_MATCHING_REQUEST_ID}'::uuid
        )
        and bid.expires_at = (
          select request.closes_at from public.service_requests as request
          where request.id = '${PROVIDER_DISCOVERY_MATCHING_REQUEST_ID}'::uuid
        );

      if v_bid_id is null
         or (select pg_catalog.count(*) from public.bids as bid
             where bid.provider_id = '${providerId}'::uuid
               and bid.request_id = '${PROVIDER_DISCOVERY_MATCHING_REQUEST_ID}'::uuid) <> 1
         or (select pg_catalog.count(*) from public.audit_events as audit
             where audit.actor_id = '${providerId}'::uuid
               and audit.object_type = 'bid'
               and audit.object_id = v_bid_id::text
               and audit.action = 'provider.bid_submitted') <> 1
         or (select pg_catalog.count(*) from public.audit_events as audit
             where audit.actor_id = '${providerId}'::uuid
               and audit.object_type = 'bid'
               and audit.object_id = v_bid_id::text
               and audit.action = 'provider.bid_withdrawn') <> 1
         or exists (select 1 from public.bookings as booking where booking.bid_id = v_bid_id)
         or exists (
           select 1 from private.service_request_addresses as address
           where address.request_id = '${PROVIDER_DISCOVERY_MATCHING_REQUEST_ID}'::uuid
         ) then
        raise exception 'provider bidding postcondition failed';
      end if;
    end;
    $e2e$;
  `);
}

export async function assertSyntheticRequestOwner(emailValue, requestIdValue) {
  const email = requireSyntheticEmail(emailValue);
  const requestId = requireUuid(requestIdValue);
  await runSql(`
    do $e2e$
    declare
      v_user_id uuid;
    begin
      select u.id into v_user_id
      from auth.users as u
      where pg_catalog.lower(u.email) = ${sqlLiteral(email)}
      order by u.created_at desc
      limit 1;
      if v_user_id is null
         or not exists (
           select 1
           from public.service_requests as sr
           where sr.id = '${requestId}'::uuid
             and sr.customer_id = v_user_id
             and sr.status = 'draft'::public.request_status
         ) then
        raise exception 'synthetic request ownership invariant failed';
      end if;
    end;
    $e2e$;
  `);
}

export async function assertDistinctSyntheticUsers(firstEmailValue, secondEmailValue) {
  const firstEmail = requireSyntheticEmail(firstEmailValue);
  const secondEmail = requireSyntheticEmail(secondEmailValue);
  if (firstEmail === secondEmail) throw new Error('synthetic users must be distinct');
  await runSql(`
    do $e2e$
    declare
      v_first_user_id uuid;
      v_second_user_id uuid;
    begin
      select u.id into v_first_user_id
      from auth.users as u
      where pg_catalog.lower(u.email) = ${sqlLiteral(firstEmail)}
      order by u.created_at desc
      limit 1;
      select u.id into v_second_user_id
      from auth.users as u
      where pg_catalog.lower(u.email) = ${sqlLiteral(secondEmail)}
      order by u.created_at desc
      limit 1;
      if v_first_user_id is null
         or v_second_user_id is null
         or v_first_user_id = v_second_user_id then
        raise exception 'synthetic Auth users are not distinct';
      end if;
    end;
    $e2e$;
  `);
}

export async function setSyntheticProfileState(emailValue, { role = 'customer', accountStatus = 'active' } = {}) {
  const email = requireSyntheticEmail(emailValue);
  if (!ROLES.has(role) || !ACCOUNT_STATUSES.has(accountStatus)) {
    throw new Error('fixture-profile-state-invalid');
  }
  await runSql(`
    do $e2e$
    declare
      v_user_id uuid;
    begin
      select u.id into v_user_id
      from auth.users as u
      where pg_catalog.lower(u.email) = ${sqlLiteral(email)}
      order by u.created_at desc
      limit 1;
      if v_user_id is null then
        raise exception 'synthetic user unavailable';
      end if;
      perform pg_catalog.set_config('lekkadeall.allow_privileged_profile_update', 'on', true);
      update public.profiles as p
      set role = ${sqlLiteral(role)}::public.user_role,
          account_status = ${sqlLiteral(accountStatus)},
          updated_at = pg_catalog.clock_timestamp()
      where p.id = v_user_id;
      if not found then
        raise exception 'synthetic profile unavailable';
      end if;
      if not exists (
        select 1
        from public.profiles as p
        where p.id = v_user_id
          and p.role = ${sqlLiteral(role)}::public.user_role
          and p.account_status = ${sqlLiteral(accountStatus)}
      ) then
        raise exception 'synthetic profile state mismatch';
      end if;
      perform pg_catalog.set_config('lekkadeall.allow_privileged_profile_update', 'off', true);
    exception
      when others then
        perform pg_catalog.set_config('lekkadeall.allow_privileged_profile_update', 'off', true);
        raise;
    end;
    $e2e$;
  `);
}

export async function assertSyntheticProfileState(
  emailValue,
  { role = 'customer', accountStatus = 'active' } = {},
) {
  const email = requireSyntheticEmail(emailValue);
  if (!ROLES.has(role) || !ACCOUNT_STATUSES.has(accountStatus)) {
    throw new Error('fixture-profile-state-invalid');
  }
  await runSql(`
    do $e2e$
    declare
      v_user_id uuid;
    begin
      select u.id into v_user_id
      from auth.users as u
      where pg_catalog.lower(u.email) = ${sqlLiteral(email)}
      order by u.created_at desc
      limit 1;
      if v_user_id is null
         or not exists (
           select 1
           from public.profiles as p
           where p.id = v_user_id
             and p.role = ${sqlLiteral(role)}::public.user_role
             and p.account_status = ${sqlLiteral(accountStatus)}
         ) then
        raise exception 'synthetic profile post-route mismatch';
      end if;
    end;
    $e2e$;
  `);
}

export async function assertSyntheticProviderFixtureIsIsolated(emailValue) {
  const email = requireSyntheticEmail(emailValue);
  await runSql(`
    do $e2e$
    declare
      v_user_id uuid;
    begin
      select u.id into v_user_id
      from auth.users as u
      where pg_catalog.lower(u.email) = ${sqlLiteral(email)};
      if v_user_id is null
         or (
           select pg_catalog.count(*)
           from auth.users as u
           where pg_catalog.lower(u.email) = ${sqlLiteral(email)}
         ) <> 1
         or (
           select pg_catalog.count(*)
           from public.profiles as p
           where p.id = v_user_id
             and p.role = 'provider'::public.user_role
             and p.account_status = 'active'
         ) <> 1
         or exists (select 1 from public.provider_profiles as pp where pp.user_id = v_user_id)
         or exists (select 1 from public.provider_services as ps where ps.provider_id = v_user_id)
         or exists (select 1 from public.service_requests as sr where sr.customer_id = v_user_id)
         or exists (select 1 from private.service_request_addresses as sra where sra.customer_id = v_user_id)
         or exists (select 1 from public.bids as b where b.provider_id = v_user_id)
         or exists (
           select 1
           from public.bookings as b
           where v_user_id in (b.customer_id, b.provider_id)
         )
         or exists (
           select 1
           from public.payments as p
           join public.bookings as b on b.id = p.booking_id
           where v_user_id in (b.customer_id, b.provider_id)
         )
         or exists (
           select 1
           from public.identity_verifications as iv
           where iv.user_id = v_user_id
         ) then
        raise exception 'synthetic provider fixture isolation failed';
      end if;
    end;
    $e2e$;
  `);
}

export async function removeSyntheticProfile(emailValue) {
  const email = requireSyntheticEmail(emailValue);
  await runSql(`
    do $e2e$
    declare
      v_user_id uuid;
      v_deleted integer;
    begin
      select u.id into v_user_id
      from auth.users as u
      where pg_catalog.lower(u.email) = ${sqlLiteral(email)}
      order by u.created_at desc
      limit 1;
      if v_user_id is null then
        raise exception 'synthetic user unavailable';
      end if;

      delete from public.profiles as p
      where p.id = v_user_id;
      get diagnostics v_deleted = row_count;
      if v_deleted <> 1 then
        raise exception 'synthetic profile removal mismatch';
      end if;
      if not exists (select 1 from auth.users as u where u.id = v_user_id)
         or exists (select 1 from public.profiles as p where p.id = v_user_id) then
        raise exception 'synthetic missing-profile invariant failed';
      end if;
    end;
    $e2e$;
  `);
}

export async function assertSyntheticProfileAbsent(emailValue) {
  const email = requireSyntheticEmail(emailValue);
  await runSql(`
    do $e2e$
    declare
      v_user_id uuid;
    begin
      select u.id into v_user_id
      from auth.users as u
      where pg_catalog.lower(u.email) = ${sqlLiteral(email)}
      order by u.created_at desc
      limit 1;
      if v_user_id is null
         or not exists (select 1 from auth.users as u where u.id = v_user_id)
         or exists (select 1 from public.profiles as p where p.id = v_user_id) then
        raise exception 'synthetic missing-profile post-route mismatch';
      end if;
    end;
    $e2e$;
  `);
}

export async function assertCustomerLifecyclePostconditions(emailValue, requestIdValue) {
  const email = requireSyntheticEmail(emailValue);
  const requestId = requireUuid(requestIdValue);
  await runSql(`
    do $e2e$
    declare
      v_user_id uuid;
    begin
      select u.id into v_user_id
      from auth.users as u
      where pg_catalog.lower(u.email) = ${sqlLiteral(email)}
      order by u.created_at desc
      limit 1;

      if v_user_id is null then
        raise exception 'lifecycle actor unavailable';
      end if;

      if not exists (
        select 1 from public.profiles as p
        where p.id = v_user_id
          and p.role = 'customer'::public.user_role
          and p.account_status = 'active'
      ) then
        raise exception 'lifecycle profile invariant failed';
      end if;

      if not exists (
        select 1 from public.service_requests as sr
        where sr.id = '${requestId}'::uuid
          and sr.customer_id = v_user_id
          and sr.status = 'cancelled'::public.request_status
          and sr.closes_at is null
          and sr.published_at is null
          and sr.awarded_at is null
          and sr.cancelled_at is not null
          and sr.precise_address_ciphertext is null
      ) then
        raise exception 'lifecycle request invariant failed';
      end if;

      if exists (select 1 from public.provider_profiles as pp where pp.user_id = v_user_id)
         or exists (select 1 from private.service_request_addresses as sra where sra.request_id = '${requestId}'::uuid)
         or exists (select 1 from public.bids as b where b.request_id = '${requestId}'::uuid)
         or exists (select 1 from public.bookings as b where b.request_id = '${requestId}'::uuid) then
        raise exception 'blocked lifecycle row was created';
      end if;

      if (select pg_catalog.count(*) from public.audit_events as ae
          where ae.object_type = 'service_request'
            and ae.object_id = '${requestId}'
            and ae.action = 'customer.service_request_draft_created') <> 1
         or (select pg_catalog.count(*) from public.audit_events as ae
             where ae.object_type = 'service_request'
               and ae.object_id = '${requestId}'
               and ae.action = 'customer.service_request_draft_updated') <> 1
         or (select pg_catalog.count(*) from public.audit_events as ae
             where ae.object_type = 'service_request'
               and ae.object_id = '${requestId}'
               and ae.action = 'customer.service_request_draft_cancelled') <> 1 then
        raise exception 'lifecycle audit count failed';
      end if;

      if exists (
        select 1
        from public.audit_events as ae
        where ae.object_type = 'service_request'
          and ae.object_id = '${requestId}'
          and (
            (ae.action = 'customer.service_request_draft_created'
             and ae.metadata - array['request_id', 'category_id']::text[] <> '{}'::jsonb)
            or (ae.action = 'customer.service_request_draft_updated'
                and ae.metadata - array['request_id', 'changed_fields']::text[] <> '{}'::jsonb)
            or (ae.action = 'customer.service_request_draft_cancelled'
                and ae.metadata - array['request_id', 'previous_status', 'new_status']::text[] <> '{}'::jsonb)
          )
      ) then
        raise exception 'lifecycle audit metadata failed';
      end if;
    end;
    $e2e$;
  `);
}

export async function assertCustomerPublicationPostconditions(emailValue, requestIdValue) {
  const email = requireSyntheticEmail(emailValue);
  const requestId = requireUuid(requestIdValue);
  await runSql(`
    do $e2e$
    declare
      v_user_id uuid;
    begin
      select u.id into v_user_id
      from auth.users as u
      where pg_catalog.lower(u.email) = ${sqlLiteral(email)}
      order by u.created_at desc
      limit 1;

      if v_user_id is null
         or not exists (
           select 1 from public.profiles as p
           where p.id = v_user_id
             and p.role = 'customer'::public.user_role
             and p.account_status = 'active'
         ) then
        raise exception 'publication actor invariant failed';
      end if;

      if not exists (
        select 1 from public.service_requests as sr
        where sr.id = '${requestId}'::uuid
          and sr.customer_id = v_user_id
          and sr.status = 'open'::public.request_status
          and sr.published_at is not null
          and sr.closes_at > sr.published_at
          and sr.closes_at < sr.requested_start
          and sr.awarded_at is null
          and sr.cancelled_at is null
          and sr.precise_address_ciphertext is null
      ) then
        raise exception 'publication request invariant failed';
      end if;

      if exists (select 1 from private.service_request_addresses as sra where sra.request_id = '${requestId}'::uuid)
         or exists (select 1 from public.bids as b where b.request_id = '${requestId}'::uuid)
         or exists (select 1 from public.bookings as b where b.request_id = '${requestId}'::uuid) then
        raise exception 'publication boundary row was created';
      end if;

      if (select pg_catalog.count(*) from public.audit_events as ae
          where ae.object_type = 'service_request'
            and ae.object_id = '${requestId}'
            and ae.action = 'customer.service_request_draft_created') <> 1
         or (select pg_catalog.count(*) from public.audit_events as ae
             where ae.object_type = 'service_request'
               and ae.object_id = '${requestId}'
               and ae.action = 'customer.service_request_draft_published') <> 1 then
        raise exception 'publication audit count failed';
      end if;

      if not exists (
        select 1 from public.audit_events as ae
        where ae.object_type = 'service_request'
          and ae.object_id = '${requestId}'
          and ae.action = 'customer.service_request_draft_published'
          and ae.reason = 'Customer published own draft service request'
          and ae.metadata = pg_catalog.jsonb_build_object(
            'request_id', '${requestId}'::uuid,
            'previous_status', 'draft',
            'new_status', 'open'
          )
      ) then
        raise exception 'publication audit invariant failed';
      end if;
    end;
    $e2e$;
  `);
}

export { DB_CONTAINER_NAME, requireSyntheticEmail, requireUuid, runSql };
