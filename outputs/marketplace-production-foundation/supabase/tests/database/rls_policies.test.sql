begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, auth;

select plan(14);

\ir rls_test_seed.inc

-- Catch only the expected RLS error so unrelated schema errors fail loudly.
create function pg_temp.audit_insert_is_allowed()
returns boolean
language plpgsql
as $$
begin
  insert into public.audit_events (
    actor_id, action, object_type, object_id, reason
  ) values (
    auth.uid(), 'test.unauthorised_insert', 'booking',
    'TEST-ILLEGAL-AUDIT', 'This insert must be denied'
  );
  return true;
exception
  when insufficient_privilege then return false;
end;
$$;

create function pg_temp.identity_rows_are_readable()
returns boolean
language plpgsql
as $$
declare
  v_rows bigint;
begin
  select count(*) into v_rows from public.identity_verifications;
  return true;
exception
  when insufficient_privilege then return false;
end;
$$;

-- 1. A customer cannot view another customer's bookings.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

select is(
  (select count(*) from public.bookings
   where id = '00000000-0000-0000-0000-000000000401'),
  0::bigint,
  'customer B cannot view customer A booking'
);

reset role;

-- 5. A normal provider cannot change their own verification status.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

update public.provider_profiles
set verification_status = 'verified'
where user_id = '00000000-0000-0000-0000-000000000011';

reset role;

select is(
  (select verification_status::text from public.provider_profiles
   where user_id = '00000000-0000-0000-0000-000000000011'),
  'pending',
  'provider cannot self-verify'
);

-- Restore the fixture even if the assertion exposes a broken policy.
update public.provider_profiles
set verification_status = 'pending'
where user_id = '00000000-0000-0000-0000-000000000011';

-- 6a. A normal user cannot create an audit log.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.audit_insert_is_allowed(),
  false,
  'normal user cannot insert audit events'
);

reset role;

-- 6b. A normal user cannot edit an audit log.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

update public.audit_events
set action = 'test.tampered'
where object_id = 'TEST-AUDIT-EVENT';

reset role;

select is(
  (select action from public.audit_events
   where object_id = 'TEST-AUDIT-EVENT'),
  'test.seeded',
  'normal user cannot edit audit events'
);

-- 7a. A customer cannot promote themselves to admin.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

update public.profiles
set role = 'admin'
where id = '00000000-0000-0000-0000-000000000001';

reset role;

select is(
  (select role::text from public.profiles
   where id = '00000000-0000-0000-0000-000000000001'),
  'customer',
  'customer cannot change their own role to admin'
);

update public.profiles
set role = 'customer'
where id = '00000000-0000-0000-0000-000000000001';

-- 2. Provider B cannot view Provider A's private verification data.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

select is(
  pg_temp.identity_rows_are_readable(),
  false,
  'provider B cannot read raw private identity data'
);

reset role;

-- 3. Provider A cannot see Customer B's address before confirmation.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  (select count(*) from public.service_requests
   where id = '00000000-0000-0000-0000-000000000202'
     and precise_address_ciphertext is not null),
  0::bigint,
  'provider cannot see a precise address before confirmed selection'
);

reset role;

-- 4. Selected Provider A can see Customer A's address after confirmation.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  (select count(*) from public.service_requests
   where id = '00000000-0000-0000-0000-000000000201'
     and precise_address_ciphertext = 'enc:test-customer-a-confirmed-address'),
  1::bigint,
  'selected provider can see the precise address for a confirmed booking'
);

reset role;

-- 7b. A provider cannot perform the admin-only approval update.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

update public.provider_profiles
set review_status = 'approved'
where user_id = '00000000-0000-0000-0000-000000000011';

reset role;

select is(
  (select review_status from public.provider_profiles
   where user_id = '00000000-0000-0000-0000-000000000011'),
  'pending',
  'provider cannot approve their own provider application'
);

update public.provider_profiles
set review_status = 'pending'
where user_id = '00000000-0000-0000-0000-000000000011';

-- 7c. The admin user can perform the admin-only approval update.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';

update public.provider_profiles
set review_status = 'approved',
    reviewed_by = '00000000-0000-0000-0000-000000000099',
    reviewed_at = now()
where user_id = '00000000-0000-0000-0000-000000000011';

reset role;

select is(
  (select review_status from public.provider_profiles
   where user_id = '00000000-0000-0000-0000-000000000011'),
  'approved',
  'admin can approve a provider application'
);

update public.provider_profiles
set review_status = 'pending', reviewed_by = null, reviewed_at = null
where user_id = '00000000-0000-0000-0000-000000000011';
