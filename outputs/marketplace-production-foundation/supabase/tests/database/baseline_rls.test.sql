begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, auth;

select plan(47);

\ir rls_test_seed.inc

insert into public.vendor_events (
  id, provider_name, provider_event_id, event_type, related_reference, payload_hash
) values (
  '00000000-0000-0000-0000-000000000801',
  'mock', 'evt-ticket-2-seed', 'payment.updated', 'test-payment-confirmed-booking',
  'sha256:test-vendor-event'
);

insert into public.service_categories (id, slug, name, active) values
  ('00000000-0000-0000-0000-000000000101', 'test-inactive', 'Inactive Test Category', false),
  ('00000000-0000-0000-0000-000000000102', 'test-gardening', 'Test Gardening', true);

-- Prepare one approved provider and one unapproved provider for provider_services policy tests.
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

create function pg_temp.visible_vendor_event_count()
returns integer
language plpgsql
as $$
declare
  v_count integer;
begin
  select count(*) into v_count from public.vendor_events;
  return v_count;
exception
  when others then return -1;
end;
$$;

create function pg_temp.visible_payment_count()
returns integer
language plpgsql
as $$
declare
  v_count integer;
begin
  select count(*) into v_count from public.payments;
  return v_count;
exception
  when others then return -1;
end;
$$;

create function pg_temp.visible_provider_service_count()
returns integer
language plpgsql
as $$
declare
  v_count integer;
begin
  select count(*) into v_count from public.provider_services;
  return v_count;
exception
  when others then return -1;
end;
$$;

create function pg_temp.try_insert_vendor_event()
returns boolean
language plpgsql
as $$
begin
  insert into public.vendor_events (
    provider_name, provider_event_id, event_type, payload_hash
  ) values (
    'mock', 'evt-frontend-write', 'test.frontend', 'sha256:frontend'
  );
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_update_vendor_event()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.vendor_events
  set processed_at = now()
  where id = '00000000-0000-0000-0000-000000000801';
  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_delete_vendor_event()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  delete from public.vendor_events
  where id = '00000000-0000-0000-0000-000000000801';
  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_customer_update_service_category()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.service_categories
  set name = 'Customer Edited Category'
  where id = '00000000-0000-0000-0000-000000000100';
  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_insert_service_category()
returns boolean
language plpgsql
as $$
begin
  insert into public.service_categories (slug, name, active) values (
    'frontend-insert-' || replace(gen_random_uuid()::text, '-', ''),
    'Frontend Inserted Category',
    true
  );
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_delete_service_category()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  delete from public.service_categories
  where id = '00000000-0000-0000-0000-000000000100';
  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_provider_update_service_category()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.service_categories
  set name = 'Provider Edited Category'
  where id = '00000000-0000-0000-0000-000000000100';
  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_provider_insert_own_service()
returns boolean
language plpgsql
as $$
begin
  insert into public.provider_services (
    provider_id, category_id, description, base_price_minor, active
  ) values (
    '00000000-0000-0000-0000-000000000011',
    '00000000-0000-0000-0000-000000000100',
    'Approved provider owned service.',
    50000,
    true
  );
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_provider_update_own_service()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.provider_services
  set description = 'Approved provider updated owned service.'
  where provider_id = '00000000-0000-0000-0000-000000000011'
    and category_id = '00000000-0000-0000-0000-000000000100';
  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_provider_insert_other_provider_service()
returns boolean
language plpgsql
as $$
begin
  insert into public.provider_services (
    provider_id, category_id, description, base_price_minor, active
  ) values (
    '00000000-0000-0000-0000-000000000012',
    '00000000-0000-0000-0000-000000000102',
    'Illegitimate service for another provider.',
    60000,
    true
  );
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_provider_update_other_provider_service()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.provider_services
  set description = 'Provider B should not update Provider A service.'
  where provider_id = '00000000-0000-0000-0000-000000000011'
    and category_id = '00000000-0000-0000-0000-000000000100';
  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_customer_insert_provider_service()
returns boolean
language plpgsql
as $$
begin
  insert into public.provider_services (
    provider_id, category_id, description, base_price_minor, active
  ) values (
    '00000000-0000-0000-0000-000000000011',
    '00000000-0000-0000-0000-000000000102',
    'Customer should not create provider service.',
    50000,
    true
  );
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_customer_update_provider_service()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.provider_services
  set description = 'Customer should not update provider service.'
  where provider_id = '00000000-0000-0000-0000-000000000011'
    and category_id = '00000000-0000-0000-0000-000000000100';
  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_customer_delete_provider_service()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  delete from public.provider_services
  where provider_id = '00000000-0000-0000-0000-000000000011'
    and category_id = '00000000-0000-0000-0000-000000000100';
  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_unapproved_provider_insert_active_service()
returns boolean
language plpgsql
as $$
begin
  insert into public.provider_services (
    provider_id, category_id, description, base_price_minor, active
  ) values (
    '00000000-0000-0000-0000-000000000012',
    '00000000-0000-0000-0000-000000000100',
    'Pending provider should not create an active service.',
    65000,
    true
  );
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_suspended_provider_insert_active_service()
returns boolean
language plpgsql
as $$
begin
  insert into public.provider_services (
    provider_id, category_id, description, base_price_minor, active
  ) values (
    '00000000-0000-0000-0000-000000000012',
    '00000000-0000-0000-0000-000000000102',
    'Suspended provider should not create an active service.',
    70000,
    true
  );
  return true;
exception
  when others then return false;
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

create function pg_temp.try_update_audit_event()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.audit_events
  set reason = 'tampered by frontend'
  where object_id = 'TEST-AUDIT-EVENT';
  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_insert_identity_verification()
returns boolean
language plpgsql
as $$
begin
  insert into public.identity_verifications (
    user_id, provider_name, provider_reference, status,
    consent_version, consent_recorded_at
  ) values (
    '00000000-0000-0000-0000-000000000011',
    'mock', 'frontend-created-identity-verification', 'verified',
    'test-v1', now()
  );
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_update_identity_verification()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.identity_verifications
  set status = 'verified'
  where id = '00000000-0000-0000-0000-000000000601';
  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_read_identity_verifications()
returns boolean
language plpgsql
as $$
declare
  v_rows bigint;
begin
  select count(*)
    into v_rows
  from public.identity_verifications;
  return true;
exception
  when insufficient_privilege then return false;
  when others then raise;
end;
$$;

create function pg_temp.try_server_record_vendor_event()
returns boolean
language plpgsql
as $$
declare
  v_event_id uuid;
begin
  v_event_id := private.record_vendor_event(
    'mock',
    'evt-ticket-2-server',
    'payment.updated',
    'test-payment-confirmed-booking',
    'sha256:test-server-vendor-event'
  );

  return v_event_id is not null;
exception
  when others then return false;
end;
$$;

-- 1. RLS is enabled on every public table.
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
  'RLS is enabled on every public table'
);

-- 2-4. Anonymous users cannot access protected tables.
set local role anon;
set local request.jwt.claim.sub = '';

select ok(
  pg_temp.visible_payment_count() <= 0,
  'anonymous users cannot access protected payments'
);

select ok(
  pg_temp.visible_vendor_event_count() <= 0,
  'anonymous users cannot read vendor_events'
);

select is(
  pg_temp.try_insert_vendor_event(),
  false,
  'anonymous users cannot write vendor_events'
);

reset role;

-- 5-8. Frontend authenticated users cannot read/write vendor_events.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select ok(
  pg_temp.visible_vendor_event_count() <= 0,
  'authenticated frontend users cannot read vendor_events'
);

select is(
  pg_temp.try_insert_vendor_event(),
  false,
  'authenticated frontend users cannot insert vendor_events'
);

select is(
  pg_temp.try_update_vendor_event(),
  false,
  'authenticated frontend users cannot update vendor_events'
);

select is(
  pg_temp.try_delete_vendor_event(),
  false,
  'authenticated frontend users cannot delete vendor_events'
);

reset role;

-- 9-13. Providers also cannot read/write vendor_events; service role has the safe writer.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select ok(
  pg_temp.visible_vendor_event_count() <= 0,
  'authenticated providers cannot read vendor_events'
);

select is(
  pg_temp.try_insert_vendor_event(),
  false,
  'authenticated providers cannot insert vendor_events'
);

select is(
  pg_temp.try_update_vendor_event(),
  false,
  'authenticated providers cannot update vendor_events'
);

select is(
  pg_temp.try_delete_vendor_event(),
  false,
  'authenticated providers cannot delete vendor_events'
);

reset role;

set local role service_role;

select is(
  pg_temp.try_server_record_vendor_event(),
  true,
  'service role can record vendor_events through the safe server function'
);

reset role;

-- 14-19. Service categories are safe read-only for frontend users.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_insert_service_category(),
  false,
  'customers cannot insert service_categories'
);

select is(
  pg_temp.try_customer_update_service_category(),
  false,
  'customers cannot edit service_categories'
);

select is(
  pg_temp.try_delete_service_category(),
  false,
  'customers cannot delete service_categories'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_insert_service_category(),
  false,
  'providers cannot insert service_categories'
);

select is(
  pg_temp.try_provider_update_service_category(),
  false,
  'providers cannot edit service_categories'
);

select is(
  pg_temp.try_delete_service_category(),
  false,
  'providers cannot delete service_categories'
);

reset role;

-- 20-21. Active categories are readable; inactive categories are hidden.
set local role anon;
set local request.jwt.claim.sub = '';

select is(
  (
    select count(*)
    from public.service_categories
    where id = '00000000-0000-0000-0000-000000000100'
  ),
  1::bigint,
  'anonymous users can read active service categories'
);

select is(
  (
    select count(*)
    from public.service_categories
    where id = '00000000-0000-0000-0000-000000000101'
  ),
  0::bigint,
  'anonymous users cannot read inactive service categories'
);

reset role;

-- 22-25. Authenticated users cannot access unrelated private rows or requests.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

select is(
  (
    select count(*)
    from public.bookings
    where id = '00000000-0000-0000-0000-000000000401'
  ),
  0::bigint,
  'customer cannot access another customer booking'
);

select is(
  (
    select count(*)
    from public.payments
    where id = '00000000-0000-0000-0000-000000000501'
  ),
  0::bigint,
  'customer cannot access another customer payment'
);

select is(
  (
    select count(*)
    from public.service_requests
    where id = '00000000-0000-0000-0000-000000000201'
  ),
  0::bigint,
  'customer cannot view another customer request'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  (
    select count(*)
    from public.service_requests
    where id = '00000000-0000-0000-0000-000000000201'
  ),
  1::bigint,
  'customer can view their own request'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

select is(
  pg_temp.try_read_identity_verifications(),
  false,
  'provider cannot read raw identity-verification rows'
);

reset role;

-- 26-32. Approved providers can view open requests but not precise address fields.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  (
    select count(*)
    from public.service_requests
    where id = '00000000-0000-0000-0000-000000000202'
  ),
  1::bigint,
  'approved provider can view eligible open requests'
);

select is(
  (
    select title
    from public.service_requests
    where id = '00000000-0000-0000-0000-000000000202'
  ),
  'Unconfirmed cleaning request',
  'approved provider can read safe open request fields'
);

select is(
  pg_temp.try_select_open_request_precise_address(),
  false,
  'approved provider cannot select precise address before confirmed booking'
);

select is(
  has_column_privilege(
    'authenticated',
    'public.service_requests',
    'precise_address_ciphertext',
    'SELECT'
  ),
  false,
  'authenticated role has no SELECT privilege on precise_address_ciphertext'
);

select is(
  (
    select count(*)
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'service_requests'
      and c.column_name ~* '(precise|address|latitude|longitude|gps|geocode)'
      and has_column_privilege(
        'authenticated',
        'public.service_requests',
        c.column_name,
        'SELECT'
      )
  ),
  0::bigint,
  'frontend roles cannot select exact-address material from service_requests'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

select is(
  (
    select count(*)
    from public.service_requests
    where id = '00000000-0000-0000-0000-000000000202'
  ),
  0::bigint,
  'unapproved provider cannot view open requests'
);

reset role;

-- 33-39. Approved providers can manage only their own provider_services; customers cannot manage them.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_provider_insert_own_service(),
  true,
  'approved provider can create own provider_service'
);

select is(
  pg_temp.try_provider_update_own_service(),
  true,
  'approved provider can update own provider_service'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_customer_insert_provider_service(),
  false,
  'customers cannot create provider_services'
);

select is(
  pg_temp.try_customer_update_provider_service(),
  false,
  'customers cannot update provider_services'
);

select is(
  pg_temp.try_customer_delete_provider_service(),
  false,
  'customers cannot delete provider_services'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_provider_insert_other_provider_service(),
  false,
  'approved provider cannot create provider_service for another provider'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

select is(
  pg_temp.try_provider_update_other_provider_service(),
  false,
  'provider cannot update another provider provider_service'
);

reset role;

-- 40-42. Unapproved or suspended providers cannot create active provider_services or view open requests.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

select is(
  pg_temp.try_unapproved_provider_insert_active_service(),
  false,
  'unapproved provider cannot create active provider_service'
);

reset role;

set local lekkadeall.allow_privileged_provider_profile_update = 'on';

update public.provider_profiles
set verification_status = 'verified',
    review_status = 'suspended',
    reviewed_by = '00000000-0000-0000-0000-000000000099',
    reviewed_at = now()
where user_id = '00000000-0000-0000-0000-000000000012';

set local lekkadeall.allow_privileged_provider_profile_update = 'off';

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

select is(
  pg_temp.try_suspended_provider_insert_active_service(),
  false,
  'suspended provider cannot create active provider_service'
);

select is(
  (
    select count(*)
    from public.service_requests
    where id = '00000000-0000-0000-0000-000000000202'
  ),
  0::bigint,
  'suspended provider cannot view open requests'
);

reset role;

-- 43-44. Provider services are visible only after provider approval and authentication.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  (
    select count(*)
    from public.provider_services
    where provider_id = '00000000-0000-0000-0000-000000000011'
      and category_id = '00000000-0000-0000-0000-000000000100'
  ),
  1::bigint,
  'authenticated users can read active services for approved providers'
);

reset role;

set local role anon;
set local request.jwt.claim.sub = '';

select is(
  pg_temp.visible_provider_service_count(),
  -1,
  'anonymous users cannot read protected provider_services'
);

reset role;

-- 45. Audit events remain non-editable by frontend users.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_update_audit_event(),
  false,
  'frontend users cannot edit audit_events'
);

reset role;

-- 46-47. Identity verification rows remain server/admin controlled for writes.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_insert_identity_verification(),
  false,
  'frontend users cannot insert identity_verifications'
);

select is(
  pg_temp.try_update_identity_verification(),
  false,
  'frontend users cannot update identity_verifications'
);

reset role;

select * from finish();

rollback;
