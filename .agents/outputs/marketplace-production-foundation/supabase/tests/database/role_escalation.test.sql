begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, auth;

select plan(37);

\ir rls_test_seed.inc

create function pg_temp.try_customer_safe_profile_update()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.profiles
  set display_name = 'Customer A Updated',
      phone_e164 = '+27820000001',
      suburb = 'Die Bult',
      city = 'Potchefstroom',
      avatar_path = 'avatars/customer-a.png'
  where id = '00000000-0000-0000-0000-000000000001';

  get diagnostics v_rows = row_count;
  return v_rows = 1;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_provider_safe_profile_update()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.provider_profiles
  set business_name = 'Provider A Updated Services',
      bio = 'Updated safe provider biography.',
      service_radius_km = 15
  where user_id = '00000000-0000-0000-0000-000000000011';

  get diagnostics v_rows = row_count;
  return v_rows = 1;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_customer_safe_update_plus_role_escalation()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.profiles
  set display_name = 'Customer A Escalated',
      role = 'provider'
  where id = '00000000-0000-0000-0000-000000000001';

  get diagnostics v_rows = row_count;
  return v_rows = 1;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_customer_make_self_provider()
returns boolean
language plpgsql
as $$
begin
  update public.profiles
  set role = 'provider'
  where id = '00000000-0000-0000-0000-000000000001';
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_provider_make_self_admin()
returns boolean
language plpgsql
as $$
begin
  update public.profiles
  set role = 'admin'
  where id = '00000000-0000-0000-0000-000000000011';
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_customer_change_account_status()
returns boolean
language plpgsql
as $$
begin
  update public.profiles
  set account_status = 'suspended'
  where id = '00000000-0000-0000-0000-000000000001';
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_provider_change_verification_status()
returns boolean
language plpgsql
as $$
begin
  update public.provider_profiles
  set verification_status = 'verified'
  where user_id = '00000000-0000-0000-0000-000000000011';
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_provider_change_identity_verification_status()
returns boolean
language plpgsql
as $$
begin
  update public.identity_verifications
  set status = 'verified'
  where user_id = '00000000-0000-0000-0000-000000000011';
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_provider_change_provider_status()
returns boolean
language plpgsql
as $$
begin
  update public.provider_profiles
  set review_status = 'approved',
      reviewed_by = '00000000-0000-0000-0000-000000000011',
      reviewed_at = now()
  where user_id = '00000000-0000-0000-0000-000000000011';
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_admin_set_user_role_as_normal_user()
returns boolean
language plpgsql
as $$
begin
  perform public.admin_set_user_role(
    '00000000-0000-0000-0000-000000000002',
    'provider'::public.user_role,
    'unauthorised role escalation test'
  );
  return true;
exception
  when insufficient_privilege then return false;
end;
$$;

create function pg_temp.try_admin_set_provider_review_status_as_normal_user()
returns boolean
language plpgsql
as $$
begin
  perform public.admin_set_provider_review_status(
    '00000000-0000-0000-0000-000000000011',
    'approved',
    'unauthorised provider approval test'
  );
  return true;
exception
  when insufficient_privilege then return false;
end;
$$;

-- Safe customer profile edits are still allowed, but privileged fields are not exposed.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_customer_safe_profile_update(),
  true,
  'customer can update safe profile fields'
);

reset role;

select is(
  (select display_name from public.profiles
   where id = '00000000-0000-0000-0000-000000000001'),
  'Customer A Updated',
  'safe customer profile update persists'
);

select is(
  (select concat_ws('|', phone_e164, suburb, city, avatar_path)
   from public.profiles
   where id = '00000000-0000-0000-0000-000000000001'),
  '+27820000001|Die Bult|Potchefstroom|avatars/customer-a.png',
  'safe customer phone/suburb/city/avatar update persists'
);

-- Safe-field edits cannot be combined with privileged role escalation.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_customer_safe_update_plus_role_escalation(),
  false,
  'safe profile update plus role escalation attempt is rejected'
);

reset role;

select is(
  (select role::text from public.profiles
   where id = '00000000-0000-0000-0000-000000000001'),
  'customer',
  'role remains unchanged after failed mixed safe/privileged update'
);

select is(
  (select display_name from public.profiles
   where id = '00000000-0000-0000-0000-000000000001'),
  'Customer A Updated',
  'safe display_name remains unchanged after failed mixed safe/privileged update'
);

-- Safe provider profile edits are still allowed, but verification/review fields are not exposed.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_provider_safe_profile_update(),
  true,
  'provider can update safe provider profile fields'
);

reset role;

select is(
  (select business_name from public.provider_profiles
   where user_id = '00000000-0000-0000-0000-000000000011'),
  'Provider A Updated Services',
  'safe provider profile update persists'
);

-- A customer cannot make themselves a provider.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_customer_make_self_provider(),
  false,
  'direct customer role escalation is rejected'
);

reset role;

select is(
  (select role::text from public.profiles
   where id = '00000000-0000-0000-0000-000000000001'),
  'customer',
  'customer cannot make themselves provider'
);

-- A provider cannot make themselves an admin.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_provider_make_self_admin(),
  false,
  'direct provider admin escalation is rejected'
);

reset role;

select is(
  (select role::text from public.profiles
   where id = '00000000-0000-0000-0000-000000000011'),
  'provider',
  'provider cannot make themselves admin'
);

-- A normal user cannot change account_status.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_customer_change_account_status(),
  false,
  'direct account_status change is rejected'
);

reset role;

select is(
  (select account_status from public.profiles
   where id = '00000000-0000-0000-0000-000000000001'),
  'active',
  'normal user cannot change account_status'
);

-- A normal provider cannot directly change verification_status.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_provider_change_verification_status(),
  false,
  'direct verification_status change is rejected'
);

reset role;

select is(
  (select verification_status::text from public.provider_profiles
   where user_id = '00000000-0000-0000-0000-000000000011'),
  'pending',
  'normal user cannot change provider_profiles.verification_status'
);

-- A normal provider cannot directly change identity_verifications.status either.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_provider_change_identity_verification_status(),
  false,
  'direct identity verification status change is rejected'
);

reset role;

select is(
  (select status::text from public.identity_verifications
   where user_id = '00000000-0000-0000-0000-000000000011'),
  'pending',
  'normal user cannot change identity_verifications.status'
);

-- review_status is the current schema's provider_status/activation field.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_provider_change_provider_status(),
  false,
  'direct provider_status/review_status change is rejected'
);

reset role;

select is(
  (select review_status from public.provider_profiles
   where user_id = '00000000-0000-0000-0000-000000000011'),
  'pending',
  'provider cannot approve themselves'
);

-- A normal customer cannot use the admin role-change function.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_admin_set_user_role_as_normal_user(),
  false,
  'normal user cannot call admin_set_user_role'
);

reset role;

select is(
  (select role::text from public.profiles
   where id = '00000000-0000-0000-0000-000000000002'),
  'customer',
  'unauthorised admin_set_user_role call leaves role unchanged'
);

-- A normal provider cannot use the admin provider-status function.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_admin_set_provider_review_status_as_normal_user(),
  false,
  'normal provider cannot call admin_set_provider_review_status'
);

reset role;

select is(
  (select review_status from public.provider_profiles
   where user_id = '00000000-0000-0000-0000-000000000011'),
  'pending',
  'unauthorised admin_set_provider_review_status call leaves provider status unchanged'
);

-- The authorised admin function can change a user role and writes an audit event.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';

select lives_ok(
  $$select public.admin_set_user_role(
      '00000000-0000-0000-0000-000000000002',
      'provider'::public.user_role,
      'Approved provider account during role-escalation hardening test'
    )$$,
  'admin_set_user_role works for authorised admin'
);

reset role;

select is(
  (select role::text from public.profiles
   where id = '00000000-0000-0000-0000-000000000002'),
  'provider',
  'authorised admin function can make a customer provider'
);

select is(
  (select count(*) from public.audit_events
   where actor_id = '00000000-0000-0000-0000-000000000099'
     and action = 'admin.user_role_changed'
     and object_id = '00000000-0000-0000-0000-000000000002'),
  1::bigint,
  'admin role change is audited'
);

-- The authorised admin function can change account_status and writes an audit event.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';

select lives_ok(
  $$select public.admin_set_account_status(
      '00000000-0000-0000-0000-000000000001',
      'restricted',
      'Restricted account during role-escalation hardening test'
    )$$,
  'admin_set_account_status works for authorised admin'
);

reset role;

select is(
  (select account_status from public.profiles
   where id = '00000000-0000-0000-0000-000000000001'),
  'restricted',
  'authorised admin function can change account_status'
);

select is(
  (select count(*) from public.audit_events
   where actor_id = '00000000-0000-0000-0000-000000000099'
     and action = 'admin.account_status_changed'
     and object_id = '00000000-0000-0000-0000-000000000001'),
  1::bigint,
  'admin account_status change is audited'
);

-- The authorised admin functions can update provider verification/review status and audit both changes.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';

select lives_ok(
  $$select public.admin_set_provider_verification_status(
      '00000000-0000-0000-0000-000000000011',
      'verified'::public.verification_status,
      'test-verification-provider-a-approved',
      true,
      'Identity verification approved during role-escalation hardening test'
    )$$,
  'admin_set_provider_verification_status works for authorised admin'
);

select lives_ok(
  $$select public.admin_set_provider_review_status(
      '00000000-0000-0000-0000-000000000011',
      'approved',
      'Provider application approved during role-escalation hardening test'
    )$$,
  'admin_set_provider_review_status works for authorised admin'
);

reset role;

select is(
  (select verification_status::text from public.provider_profiles
   where user_id = '00000000-0000-0000-0000-000000000011'),
  'verified',
  'authorised admin function can change verification_status'
);

select is(
  (select review_status from public.provider_profiles
   where user_id = '00000000-0000-0000-0000-000000000011'),
  'approved',
  'authorised admin function can change provider_status/review_status'
);

select is(
  (select reviewed_by from public.provider_profiles
   where user_id = '00000000-0000-0000-0000-000000000011'),
  '00000000-0000-0000-0000-000000000099'::uuid,
  'authorised provider status change records reviewed_by'
);

select ok(
  (select reviewed_at is not null from public.provider_profiles
   where user_id = '00000000-0000-0000-0000-000000000011'),
  'authorised provider status change records reviewed_at'
);

select is(
  (select count(*) from public.audit_events
   where actor_id = '00000000-0000-0000-0000-000000000099'
     and action in (
       'admin.provider_verification_status_changed',
       'admin.provider_review_status_changed'
     )
     and object_id = '00000000-0000-0000-0000-000000000011'),
  2::bigint,
  'provider verification/review status changes are audited'
);

select * from finish();

rollback;
