import { assertLocalDockerConfiguration, runCaptured } from './local-environment.mjs';

export const ACTIVE_CATEGORY_ID = '90000000-0000-4000-8000-000000000001';
export const INACTIVE_CATEGORY_ID = '90000000-0000-4000-8000-000000000002';
export const ACTIVE_CATEGORY_NAME = 'Synthetic home maintenance';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const SYNTHETIC_EMAIL_PATTERN = /^[a-z0-9][a-z0-9+._-]{0,100}@lekkadeall\.invalid$/iu;
const DB_CONTAINER_NAME = 'supabase_db_lekkadeall-local';
const ROLES = new Set(['customer', 'provider']);
const ACCOUNT_STATUSES = new Set(['active', 'restricted', 'suspended', 'closed']);

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
      ('${INACTIVE_CATEGORY_ID}'::uuid, 'e2e-inactive-category', 'Synthetic inactive category', false, false)
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

export async function assertProvisionedCustomerProfile(emailValue) {
  const email = requireSyntheticEmail(emailValue);
  const output = await runSql(`
    select pg_catalog.concat_ws('|',
      u.id::text,
      pg_catalog.count(p.id)::text,
      pg_catalog.min(p.role::text),
      pg_catalog.min(p.account_status),
      pg_catalog.min(p.display_name),
      (select pg_catalog.count(*)::text from public.provider_profiles as pp where pp.user_id = u.id)
    )
    from auth.users as u
    left join public.profiles as p on p.id = u.id
    where pg_catalog.lower(u.email) = ${sqlLiteral(email)}
    group by u.id
    order by pg_catalog.max(u.created_at) desc
    limit 1;
  `);
  const [userId, profileCount, role, accountStatus, displayName, providerCount] = output.split('|');
  requireUuid(userId);
  if (profileCount !== '1'
      || role !== 'customer'
      || accountStatus !== 'active'
      || displayName !== 'New customer'
      || providerCount !== '0') {
    throw new Error('ticket-9b-profile-postcondition-failed');
  }
  return userId;
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

export { DB_CONTAINER_NAME, requireSyntheticEmail, requireUuid, runSql };
