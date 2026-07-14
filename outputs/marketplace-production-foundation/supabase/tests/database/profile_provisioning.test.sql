begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, auth;

select plan(44);

create function pg_temp.try_frontend_insert_profile()
returns boolean
language plpgsql
as $$
begin
  insert into public.profiles (
    id, role, display_name, city, account_status
  ) values (
    '00000000-0000-0000-0000-000000009999',
    'admin',
    'Injected admin',
    'Potchefstroom',
    'active'
  );
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_frontend_delete_own_profile()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  delete from public.profiles
  where id = '00000000-0000-0000-0000-000000009902';
  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_frontend_change_role()
returns boolean
language plpgsql
as $$
begin
  update public.profiles
  set role = 'admin'
  where id = '00000000-0000-0000-0000-000000009902';
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_frontend_change_account_status()
returns boolean
language plpgsql
as $$
begin
  update public.profiles
  set account_status = 'suspended'
  where id = '00000000-0000-0000-0000-000000009902';
  return true;
exception
  when others then return false;
end;
$$;

-- 1-12. Object security and Ticket 2 permissions.
select ok(
  exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'auth'
      and c.relname = 'users'
      and t.tgname = 'provision_auth_user_profile_after_insert'
      and not t.tgisinternal
  ),
  'auth.users has the profile provisioning trigger'
);

select ok(
  (
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = 'provision_auth_user_profile'
      and p.pronargs = 0
  ),
  'profile provisioning trigger function is SECURITY DEFINER'
);

select ok(
  (
    select coalesce(p.proconfig, '{}'::text[]) @> array['search_path=pg_catalog']
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = 'provision_auth_user_profile'
      and p.pronargs = 0
  ),
  'profile provisioning trigger function has a safe search_path'
);

select ok(
  (
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = 'ensure_auth_user_profile'
      and p.pronargs = 2
  ),
  'idempotent profile helper is SECURITY DEFINER'
);

select ok(
  (
    select coalesce(p.proconfig, '{}'::text[]) @> array['search_path=pg_catalog']
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = 'ensure_auth_user_profile'
      and p.pronargs = 2
  ),
  'idempotent profile helper has a safe search_path'
);

select is(
  (
    select has_function_privilege('anon', p.oid, 'EXECUTE')
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = 'provision_auth_user_profile'
      and p.pronargs = 0
  ),
  false,
  'anon cannot execute the trigger function'
);

select is(
  (
    select has_function_privilege('authenticated', p.oid, 'EXECUTE')
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = 'provision_auth_user_profile'
      and p.pronargs = 0
  ),
  false,
  'authenticated cannot execute the trigger function'
);

select is(
  (
    select has_function_privilege('anon', p.oid, 'EXECUTE')
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = 'ensure_auth_user_profile'
      and p.pronargs = 2
  ),
  false,
  'anon cannot execute the idempotent helper'
);

select is(
  (
    select has_function_privilege('authenticated', p.oid, 'EXECUTE')
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = 'ensure_auth_user_profile'
      and p.pronargs = 2
  ),
  false,
  'authenticated cannot execute the idempotent helper'
);

select is(
  (select relrowsecurity from pg_class where oid = 'public.profiles'::regclass),
  true,
  'profiles RLS remains enabled'
);

select is(
  has_table_privilege('authenticated', 'public.profiles', 'INSERT'),
  false,
  'authenticated still has no direct profile INSERT privilege'
);

select is(
  has_table_privilege('authenticated', 'public.profiles', 'DELETE'),
  false,
  'authenticated still has no direct profile DELETE privilege'
);

-- Hostile registration metadata must have no effect on the application profile.
insert into auth.users (
  id,
  email,
  raw_user_meta_data,
  raw_app_meta_data
) values (
  '00000000-0000-0000-0000-000000009901',
  'hostile-registration@lekkadeall.test',
  '{
    "display_name": "Injected administrator",
    "role": "admin",
    "account_status": "active",
    "provider": true,
    "verification_status": "verified",
    "review_status": "approved",
    "identity_status": "verified",
    "payment_status": "paid",
    "exact_address": "must not be copied"
  }'::jsonb,
  '{
    "role": "service_role",
    "roles": ["admin", "support"],
    "provider_approved": true
  }'::jsonb
);

insert into auth.users (id, email) values (
  '00000000-0000-0000-0000-000000009902',
  'normal-customer@lekkadeall.test'
);

-- 13-22. Fixed defaults, metadata rejection, and privacy-safe audit event.
select is(
  (select count(*) from public.profiles where id = '00000000-0000-0000-0000-000000009901'),
  1::bigint,
  'normal Auth insertion creates exactly one matching profile'
);

select is(
  (select role from public.profiles where id = '00000000-0000-0000-0000-000000009901'),
  'customer'::public.user_role,
  'hostile metadata cannot change the fixed customer role'
);

select is(
  (select account_status from public.profiles where id = '00000000-0000-0000-0000-000000009901'),
  'active',
  'hostile metadata cannot change the fixed active account status'
);

select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-000000009901'),
  'New customer',
  'hostile metadata cannot change the neutral display name'
);

select ok(
  (
    select phone_e164 is null
      and phone_verified_at is null
      and email_verified_at is null
      and suburb is null
      and city = 'Potchefstroom'
      and avatar_path is null
    from public.profiles
    where id = '00000000-0000-0000-0000-000000009901'
  ),
  'optional personal and verification fields use approved null/default values'
);

select is(
  (select count(*) from public.provider_profiles where user_id = '00000000-0000-0000-0000-000000009901'),
  0::bigint,
  'registration does not create provider_profiles'
);

select is(
  (
    select count(*)
    from public.profiles
    where id in (
      '00000000-0000-0000-0000-000000009901',
      '00000000-0000-0000-0000-000000009902'
    )
      and role in ('admin', 'support')
  ),
  0::bigint,
  'normal registration cannot create admin or support profiles'
);

select is(
  (
    select count(*)
    from public.audit_events
    where action = 'system.profile_provisioned'
      and object_type = 'profile'
      and object_id = '00000000-0000-0000-0000-000000009901'
  ),
  1::bigint,
  'first-time trigger provisioning writes one audit event'
);

select is(
  (
    select metadata
    from public.audit_events
    where action = 'system.profile_provisioned'
      and object_id = '00000000-0000-0000-0000-000000009901'
  ),
  '{"source":"auth_trigger","version":1}'::jsonb,
  'provisioning audit metadata contains only fixed source and version values'
);

select ok(
  (
    select actor_id is null
      and reason = 'auth user registration'
      and not (metadata ?| array[
        'email', 'phone', 'token', 'raw_user_meta_data',
        'raw_app_meta_data', 'registration_payload'
      ])
    from public.audit_events
    where action = 'system.profile_provisioned'
      and object_id = '00000000-0000-0000-0000-000000009901'
  ),
  'provisioning audit event is system-owned and contains no registration data'
);

-- 23-26. Replaying the private helper is idempotent and never overwrites.
select is(
  private.ensure_auth_user_profile(
    '00000000-0000-0000-0000-000000009901',
    'auth_trigger'
  ),
  false,
  'replaying provisioning reports that no profile was created'
);

select is(
  (select count(*) from public.profiles where id = '00000000-0000-0000-0000-000000009901'),
  1::bigint,
  'replaying provisioning leaves exactly one profile'
);

set local lekkadeall.allow_privileged_profile_update = 'on';

update public.profiles
set role = 'support',
    display_name = 'Existing protected profile',
    city = 'Johannesburg',
    account_status = 'suspended'
where id = '00000000-0000-0000-0000-000000009901';

set local lekkadeall.allow_privileged_profile_update = 'off';

select is(
  private.ensure_auth_user_profile(
    '00000000-0000-0000-0000-000000009901',
    'migration_backfill'
  ),
  false,
  'backfill replay does not recreate an existing profile'
);

select ok(
  (
    select role = 'support'::public.user_role
      and display_name = 'Existing protected profile'
      and city = 'Johannesburg'
      and account_status = 'suspended'
    from public.profiles
    where id = '00000000-0000-0000-0000-000000009901'
  ),
  'idempotent conflict handling does not overwrite any existing profile fields'
);

-- 27-34. Browser denials, own-read behavior, and Ticket 1 protections.
-- Create a valid Auth identity without a profile so the INSERT denial cannot be
-- satisfied merely by a foreign-key or duplicate-key failure.
alter table auth.users disable trigger provision_auth_user_profile_after_insert;

insert into auth.users (id, email) values (
  '00000000-0000-0000-0000-000000009999',
  'direct-insert-denial@lekkadeall.test'
);

alter table auth.users enable trigger provision_auth_user_profile_after_insert;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009902';

select is(
  pg_temp.try_frontend_insert_profile(),
  false,
  'authenticated browser user cannot insert a profile directly'
);

select is(
  pg_temp.try_frontend_delete_own_profile(),
  false,
  'authenticated browser user cannot delete their own profile'
);

select is(
  (select count(*) from public.profiles where id = '00000000-0000-0000-0000-000000009902'),
  1::bigint,
  'authenticated user can read their own provisioned profile'
);

select is(
  (select count(*) from public.profiles where id = '00000000-0000-0000-0000-000000009901'),
  0::bigint,
  'authenticated user cannot read another provisioned profile'
);

select is(
  pg_temp.try_frontend_change_role(),
  false,
  'Ticket 1 still blocks a frontend role change'
);

select is(
  pg_temp.try_frontend_change_account_status(),
  false,
  'Ticket 1 still blocks a frontend account-status change'
);

reset role;

delete from auth.users
where id = '00000000-0000-0000-0000-000000009999';

select ok(
  (
    select role = 'customer'::public.user_role
      and account_status = 'active'
    from public.profiles
    where id = '00000000-0000-0000-0000-000000009902'
  ),
  'failed browser escalation attempts leave the profile customer and active'
);

select is(
  (
    select count(*)
    from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and cmd in ('INSERT', 'DELETE', 'ALL')
  ),
  0::bigint,
  'Ticket 9B adds no frontend profile insert/delete policy'
);

-- 35-41. Simulate a pre-migration Auth user and exercise safe backfill.
alter table auth.users disable trigger provision_auth_user_profile_after_insert;

insert into auth.users (
  id,
  email,
  raw_user_meta_data,
  raw_app_meta_data
) values (
  '00000000-0000-0000-0000-000000009903',
  'backfill-user@lekkadeall.test',
  '{"role":"admin","display_name":"Backfill injection"}'::jsonb,
  '{"role":"service_role"}'::jsonb
);

alter table auth.users enable trigger provision_auth_user_profile_after_insert;

select is(
  (select count(*) from public.profiles where id = '00000000-0000-0000-0000-000000009903'),
  0::bigint,
  'pre-existing Auth user starts without a profile in the backfill simulation'
);

select is(
  private.ensure_auth_user_profile(
    '00000000-0000-0000-0000-000000009903',
    'migration_backfill'
  ),
  true,
  'backfill creates the missing profile'
);

select ok(
  (
    select role = 'customer'::public.user_role
      and account_status = 'active'
      and display_name = 'New customer'
      and phone_e164 is null
      and suburb is null
      and city = 'Potchefstroom'
    from public.profiles
    where id = '00000000-0000-0000-0000-000000009903'
  ),
  'backfill uses the same fixed safe defaults and ignores metadata'
);

select is(
  private.ensure_auth_user_profile(
    '00000000-0000-0000-0000-000000009903',
    'migration_backfill'
  ),
  false,
  'repeated backfill is idempotent'
);

select is(
  (select count(*) from public.profiles where id = '00000000-0000-0000-0000-000000009903'),
  1::bigint,
  'repeated backfill leaves exactly one profile'
);

select is(
  (
    select count(*)
    from public.audit_events
    where action = 'system.profile_provisioned'
      and object_id = '00000000-0000-0000-0000-000000009903'
      and metadata = '{"source":"migration_backfill","version":1}'::jsonb
  ),
  1::bigint,
  'backfill writes one minimal source-labelled audit event'
);

select is(
  (select count(*) from public.provider_profiles where user_id = '00000000-0000-0000-0000-000000009903'),
  0::bigint,
  'backfill does not create provider_profiles'
);

-- 42-44. Ticket 1 and Ticket 2 regression smoke checks.
select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.profiles'::regclass
      and tgname = 'protect_profile_privileged_fields'
      and not tgisinternal
  ),
  'Ticket 1 privileged profile trigger remains installed'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'profile owner reads self'
      and cmd = 'SELECT'
  ),
  'Ticket 2 own-profile read policy remains installed'
);

select is(
  (
    select count(*)
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r'
      and c.relrowsecurity = false
  ),
  0::bigint,
  'Ticket 2 RLS remains enabled on every public table'
);

select * from finish();

rollback;
