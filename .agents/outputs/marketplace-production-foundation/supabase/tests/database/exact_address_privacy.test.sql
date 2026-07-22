begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, auth;

select plan(49);

\ir rls_test_seed.inc

-- Provider A starts approved. Provider B starts unapproved so we can test
-- open-request summary denial before later approving Provider B for selected/
-- unselected reveal-path tests.
set local lekkadeall.allow_privileged_provider_profile_update = 'on';

update public.provider_profiles
set verification_status = 'verified',
    verification_reference = 'test-verification-provider-a-approved',
    bank_name_match = true,
    review_status = 'approved',
    reviewed_by = '00000000-0000-0000-0000-000000000099',
    reviewed_at = now()
where user_id = '00000000-0000-0000-0000-000000000011';

set local lekkadeall.allow_privileged_provider_profile_update = 'off';

create function pg_temp.provider_open_request_summary_count()
returns integer
language plpgsql
as $$
declare
  v_count integer;
begin
  select count(*)
    into v_count
  from public.list_provider_open_request_summaries(null, null, 50);

  return v_count;
exception
  when others then return -1;
end;
$$;

create function pg_temp.try_select_open_request_precise_address()
returns boolean
language plpgsql
as $$
declare
  v_precise_address text;
begin
  select precise_address_ciphertext
    into v_precise_address
  from public.service_requests
  where id = '00000000-0000-0000-0000-000000000202';

  return v_precise_address is not null;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_select_private_request_address()
returns boolean
language plpgsql
as $$
declare
  v_precise_address text;
begin
  select precise_address_ciphertext
    into v_precise_address
  from private.service_request_addresses
  where request_id = '00000000-0000-0000-0000-000000000202';

  return v_precise_address is not null;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_insert_private_request_address()
returns boolean
language plpgsql
as $$
begin
  insert into private.service_request_addresses (
    request_id,
    precise_address_ciphertext
  ) values (
    '00000000-0000-0000-0000-000000000203',
    'enc:direct-private-insert-must-fail'
  );

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_update_private_request_address()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update private.service_request_addresses
  set precise_address_ciphertext = 'enc:direct-private-update-must-fail'
  where request_id = '00000000-0000-0000-0000-000000000202';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_delete_private_request_address()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  delete from private.service_request_addresses
  where request_id = '00000000-0000-0000-0000-000000000202';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_reveal_booking_address(p_booking_id uuid)
returns text
language plpgsql
as $$
declare
  v_precise_address text;
begin
  select precise_address_ciphertext
    into v_precise_address
  from public.reveal_confirmed_booking_address(p_booking_id);

  return coalesce(v_precise_address, '<null>');
exception
  when others then return '<denied>';
end;
$$;

create function pg_temp.try_upsert_service_request_address(
  p_request_id uuid,
  p_precise_address_ciphertext text
)
returns boolean
language plpgsql
as $$
begin
  perform public.customer_upsert_service_request_address(
    p_request_id,
    p_precise_address_ciphertext
  );

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_customer_get_service_request_address(p_request_id uuid)
returns text
language plpgsql
as $$
declare
  v_precise_address text;
begin
  select precise_address_ciphertext
    into v_precise_address
  from public.customer_get_service_request_address(p_request_id);

  return coalesce(v_precise_address, '<null>');
exception
  when others then return '<denied>';
end;
$$;

create function pg_temp.try_admin_get_service_request_address(
  p_request_id uuid,
  p_reason text
)
returns text
language plpgsql
as $$
declare
  v_precise_address text;
begin
  select precise_address_ciphertext
    into v_precise_address
  from public.admin_get_service_request_address(p_request_id, p_reason);

  return coalesce(v_precise_address, '<null>');
exception
  when others then return '<denied>';
end;
$$;

create function pg_temp.try_direct_write_legacy_request_address()
returns boolean
language plpgsql
as $$
begin
  update public.service_requests
  set precise_address_ciphertext = 'enc:frontend-direct-write-must-fail'
  where id = '00000000-0000-0000-0000-000000000202';

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_update_provider_verification()
returns boolean
language plpgsql
as $$
begin
  update public.provider_profiles
  set verification_status = 'rejected'
  where user_id = auth.uid();

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_update_audit_event()
returns boolean
language plpgsql
as $$
begin
  update public.audit_events
  set action = 'test.ticket3_tampered'
  where object_id = 'TEST-AUDIT-EVENT';

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_insert_vendor_event()
returns boolean
language plpgsql
as $$
begin
  insert into public.vendor_events (
    provider_name,
    provider_event_id,
    event_type,
    payload_hash
  ) values (
    'mock',
    'evt-ticket-3-denied',
    'payment.updated',
    'sha256:ticket-3-denied'
  );

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_customer_update_service_category()
returns boolean
language plpgsql
as $$
begin
  update public.service_categories
  set active = false
  where id = '00000000-0000-0000-0000-000000000100';

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_insert_open_request_with_risky_description()
returns boolean
language plpgsql
as $$
begin
  insert into public.service_requests (
    id,
    customer_id,
    category_id,
    title,
    description,
    suburb,
    city,
    requested_start,
    budget_minor,
    status,
    closes_at
  ) values (
    '00000000-0000-0000-0000-000000000204',
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000100',
    'Risky public request',
    'Please come to 12 Church Street and call 082 123 4567 when outside.',
    'Baillie Park',
    'Potchefstroom',
    now() + interval '5 days',
    90000,
    'open',
    now() + interval '4 days'
  );

  return true;
exception
  when others then return false;
end;
$$;

-- 1-3. Exact addresses are isolated outside the public request row and tied to the customer owner.
select is(
  (
    select count(*)
    from private.service_request_addresses
    where request_id in (
      '00000000-0000-0000-0000-000000000201',
      '00000000-0000-0000-0000-000000000202'
    )
  ),
  2::bigint,
  'seeded exact addresses live in the private address table'
);

select is(
  (
    select count(*)
    from public.service_requests
    where precise_address_ciphertext is not null
  ),
  0::bigint,
  'public service_requests rows do not store exact address ciphertext'
);

select is(
  (
    select count(*)
    from private.service_request_addresses sra
    join public.service_requests sr on sr.id = sra.request_id
    where sra.customer_id <> sr.customer_id
  ),
  0::bigint,
  'private address records copy the owning customer_id from service_requests'
);

-- 4-11. Approved provider can read open summaries, but not precise address material.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.provider_open_request_summary_count(),
  1,
  'approved provider can view one open request summary'
);

select is(
  (
    select title
    from public.list_provider_open_request_summaries(null, null, 50)
    where request_id = '00000000-0000-0000-0000-000000000202'
  ),
  'Unconfirmed cleaning request',
  'approved provider can read safe open request summary fields'
);

select is(
  pg_temp.try_select_open_request_precise_address(),
  false,
  'approved provider cannot directly select precise address before confirmed booking'
);

select is(
  pg_temp.try_select_private_request_address(),
  false,
  'approved provider cannot directly select from private request address table'
);

select is(
  pg_temp.try_insert_private_request_address(),
  false,
  'approved provider cannot directly insert private request address rows'
);

select is(
  pg_temp.try_update_private_request_address(),
  false,
  'approved provider cannot directly update private request address rows'
);

select is(
  pg_temp.try_delete_private_request_address(),
  false,
  'approved provider cannot directly delete private request address rows'
);

select is(
  has_column_privilege(
    'authenticated',
    'public.service_requests',
    'precise_address_ciphertext',
    'SELECT'
  ),
  false,
  'authenticated role has no SELECT privilege on legacy precise address column'
);

reset role;

set local role service_role;

select is(
  pg_temp.try_select_private_request_address(),
  false,
  'service_role cannot directly select private request addresses and must use audited functions'
);

reset role;

-- 13-14. Unapproved providers cannot view open request summaries or reveal addresses.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

select is(
  pg_temp.provider_open_request_summary_count(),
  0,
  'unapproved provider cannot view open request summaries'
);

select is(
  pg_temp.try_reveal_booking_address('00000000-0000-0000-0000-000000000402'),
  '<denied>',
  'unapproved selected provider cannot reveal an address'
);

reset role;

-- Approve Provider B only for unselected/selected reveal-path negative tests.
set local lekkadeall.allow_privileged_provider_profile_update = 'on';

update public.provider_profiles
set verification_status = 'verified',
    verification_reference = 'test-verification-provider-b-approved',
    bank_name_match = true,
    review_status = 'approved',
    reviewed_by = '00000000-0000-0000-0000-000000000099',
    reviewed_at = now()
where user_id = '00000000-0000-0000-0000-000000000012';

set local lekkadeall.allow_privileged_provider_profile_update = 'off';

-- 15-17. Address reveal denies unselected, unconfirmed, and unrelated actors.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

select is(
  pg_temp.try_reveal_booking_address('00000000-0000-0000-0000-000000000401'),
  '<denied>',
  'approved but unselected provider cannot reveal confirmed booking address'
);

select is(
  pg_temp.try_reveal_booking_address('00000000-0000-0000-0000-000000000402'),
  '<denied>',
  'selected provider cannot reveal address while booking is still payment_pending'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

select is(
  pg_temp.try_reveal_booking_address('00000000-0000-0000-0000-000000000401'),
  '<denied>',
  'unrelated customer cannot reveal confirmed booking address'
);

reset role;

-- 18-21. Selected approved provider can reveal after confirmation and every reveal is audited.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_reveal_booking_address('00000000-0000-0000-0000-000000000401'),
  'enc:test-customer-a-confirmed-address',
  'selected provider can reveal exact address for scheduled confirmed booking'
);

reset role;

select is(
  (
    select count(*)
    from public.audit_events
    where action = 'booking.address_revealed'
      and object_type = 'booking'
      and object_id = '00000000-0000-0000-0000-000000000401'
  ),
  1::bigint,
  'first address reveal writes one audit event'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_reveal_booking_address('00000000-0000-0000-0000-000000000401'),
  'enc:test-customer-a-confirmed-address',
  'selected provider can reveal exact address again when still confirmed'
);

reset role;

select is(
  (
    select count(*)
    from public.audit_events
    where action = 'booking.address_revealed'
      and object_type = 'booking'
      and object_id = '00000000-0000-0000-0000-000000000401'
  ),
  2::bigint,
  'every address reveal writes a separate audit event'
);

-- 22-23. Suspended providers cannot view open request summaries or reveal addresses.
set local lekkadeall.allow_privileged_provider_profile_update = 'on';

update public.provider_profiles
set review_status = 'suspended',
    reviewed_by = '00000000-0000-0000-0000-000000000099',
    reviewed_at = now()
where user_id = '00000000-0000-0000-0000-000000000012';

set local lekkadeall.allow_privileged_provider_profile_update = 'off';

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

select is(
  pg_temp.provider_open_request_summary_count(),
  0,
  'suspended provider cannot view open request summaries'
);

select is(
  pg_temp.try_reveal_booking_address('00000000-0000-0000-0000-000000000402'),
  '<denied>',
  'suspended provider cannot reveal an address'
);

reset role;

-- 24-33. Customers can manage their own draft address only through controlled logic.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

select is(
  pg_temp.try_insert_private_request_address(),
  false,
  'customer cannot directly insert unsafe private address rows'
);

select is(
  pg_temp.try_upsert_service_request_address(
    '00000000-0000-0000-0000-000000000203',
    'enc:test-customer-b-draft-address'
  ),
  true,
  'customer can upsert own draft request address through controlled function'
);

select is(
  pg_temp.try_customer_get_service_request_address(
    '00000000-0000-0000-0000-000000000203'
  ),
  'enc:test-customer-b-draft-address',
  'customer can read own private draft request address through controlled function'
);

reset role;

select is(
  (
    select precise_address_ciphertext
    from private.service_request_addresses
    where request_id = '00000000-0000-0000-0000-000000000203'
      and customer_id = '00000000-0000-0000-0000-000000000002'
  ),
  'enc:test-customer-b-draft-address',
  'controlled address upsert updates the private address table with customer ownership'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

select is(
  pg_temp.try_upsert_service_request_address(
    '00000000-0000-0000-0000-000000000202',
    'enc:open-request-update-must-fail'
  ),
  false,
  'customer cannot update exact address after request publication'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_upsert_service_request_address(
    '00000000-0000-0000-0000-000000000201',
    'enc:confirmed-booking-address-update-must-fail'
  ),
  false,
  'customer cannot update exact address after provider selection or confirmed booking'
);

select is(
  pg_temp.try_upsert_service_request_address(
    '00000000-0000-0000-0000-000000000203',
    'enc:customer-a-must-not-update-customer-b-address'
  ),
  false,
  'customer cannot upsert another customer request address'
);

select is(
  pg_temp.try_customer_get_service_request_address(
    '00000000-0000-0000-0000-000000000203'
  ),
  '<denied>',
  'customer cannot read another customer exact address through controlled function'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

select is(
  pg_temp.try_direct_write_legacy_request_address(),
  false,
  'customer cannot directly write deprecated public precise address column'
);

reset role;

select is(
  (
    select count(*)
    from public.audit_events
    where action = 'customer.request_address_upserted'
      and object_type = 'service_request'
      and object_id = '00000000-0000-0000-0000-000000000203'
  ),
  1::bigint,
  'controlled customer address upsert writes an audit event'
);

-- 34-40. Public descriptions cannot contain likely exact-address material when published.
select is(
  public.service_request_description_has_exact_address_risk(
    'Please clean the kitchen and bathroom. The exact address will be shared after booking.'
  ),
  false,
  'safe public request description is not flagged'
);

select is(
  public.service_request_description_has_exact_address_risk(
    'Please come to 12 Church Street for the job.'
  ),
  true,
  'street number plus street name is flagged'
);

select is(
  public.service_request_description_has_exact_address_risk(
    'I am in Unit 4B at the complex.'
  ),
  true,
  'unit or room reference is flagged'
);

select is(
  public.service_request_description_has_exact_address_risk(
    'GPS is -26.714500, 27.097000.'
  ),
  true,
  'GPS coordinates are flagged'
);

select is(
  public.service_request_description_has_exact_address_risk(
    'Call 082 123 4567 when outside.'
  ),
  true,
  'phone number in public request description is flagged'
);

select is(
  public.service_request_description_has_exact_address_risk(
    'House 44 near the security gate.'
  ),
  true,
  'house, stand, or erf number is flagged'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

select is(
  pg_temp.try_insert_open_request_with_risky_description(),
  false,
  'publishing an open request with likely exact-address material is rejected'
);

reset role;

-- 41-44. Administrative/server address access is audited and ordinary users cannot use it.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';

select is(
  pg_temp.try_admin_get_service_request_address(
    '00000000-0000-0000-0000-000000000201',
    'Support review for test coverage'
  ),
  'enc:test-customer-a-confirmed-address',
  'admin can access exact address through audited admin function'
);

select is(
  pg_temp.try_admin_get_service_request_address(
    '00000000-0000-0000-0000-000000000201',
    '   '
  ),
  '<denied>',
  'admin exact-address access requires a non-empty reason'
);

reset role;

select is(
  (
    select count(*)
    from public.audit_events
    where action = 'admin.service_request_address_accessed'
      and object_type = 'service_request'
      and object_id = '00000000-0000-0000-0000-000000000201'
  ),
  1::bigint,
  'admin exact-address access writes an audit event'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_admin_get_service_request_address(
    '00000000-0000-0000-0000-000000000201',
    'Illegitimate customer access'
  ),
  '<denied>',
  'ordinary customer cannot use admin address access function'
);

reset role;

-- 45-49. Ticket 1 and Ticket 2 smoke protections remain intact.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_update_provider_verification(),
  false,
  'provider still cannot change own verification status'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_update_audit_event(),
  false,
  'frontend user still cannot edit audit events'
);

select is(
  pg_temp.try_insert_vendor_event(),
  false,
  'frontend user still cannot insert vendor events'
);

select is(
  pg_temp.try_customer_update_service_category(),
  false,
  'customer still cannot update service categories'
);

select ok(
  (
    select relrowsecurity
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'service_requests'
  ),
  'service_requests RLS remains enabled'
);

reset role;

select * from finish();

rollback;
