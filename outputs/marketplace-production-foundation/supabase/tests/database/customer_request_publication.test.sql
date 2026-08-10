create extension if not exists pgtap with schema extensions;

-- The concurrency fixture must be committed before the two independent
-- dblink sessions start. It is removed after the transactional pgTAP body.
begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000011099', 'ticket9a11-concurrent@lekkadeall.test');

insert into public.service_categories (id, slug, name, active) values
  ('00000000-0000-0000-0000-000000011090', 'ticket9a11-concurrent', 'Ticket 9A-11 Concurrent', true);

set local lekkadeall.allow_marketplace_state_transition = 'on';

insert into public.service_requests (
  id, customer_id, category_id, title, description, suburb, city,
  requested_start, budget_minor, status, closes_at,
  published_at, awarded_at, cancelled_at, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000011199',
  '00000000-0000-0000-0000-000000011099',
  '00000000-0000-0000-0000-000000011090',
  'Concurrent publication draft',
  'Safe address-independent request for concurrent publication testing.',
  'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '8 days', 99000,
  'draft', null, null, null, null,
  pg_catalog.now() - interval '2 hours', pg_catalog.now() - interval '2 hours'
);

-- dblink rejects passwordless connections from the local Supabase postgres
-- role because that role is intentionally not a superuser. Generate a
-- disposable credential inside this disposable database instead of placing a
-- credential in source or workflow output. Both race sessions are constrained
-- to the current server address, current port, and current database.
do $$
declare
  v_password text := pg_catalog.replace(pg_catalog.gen_random_uuid()::pg_catalog.text, '-', '');
begin
  execute pg_catalog.format(
    'create role ticket9a11_concurrency_login login password %L',
    v_password
  );
  perform pg_catalog.set_config(
    'lekkadeall.ticket9a11_concurrency_password',
    v_password,
    false
  );
end;
$$;

grant authenticated to ticket9a11_concurrency_login;

commit;

begin;

create extension if not exists dblink with schema extensions;

set local search_path = public, extensions, auth;

select plan(75);

-- Run the two-session race before this transaction takes fixture DDL locks.
-- The first session keeps its successful transition uncommitted while the
-- second starts, so the request row lock serializes both guarded transitions.
create temporary table ticket9a11_concurrency_results (
  connection_name text primary key,
  result_status text,
  error_message text
) on commit drop;

insert into ticket9a11_concurrency_results (connection_name) values ('a'), ('b');

select is(
  extensions.dblink_connect(
    'ticket9a11_a',
    pg_catalog.format(
      'hostaddr=%s port=%s dbname=%L user=%L password=%L',
      pg_catalog.inet_server_addr(),
      pg_catalog.current_setting('port'),
      pg_catalog.current_database(),
      'ticket9a11_concurrency_login',
      pg_catalog.current_setting('lekkadeall.ticket9a11_concurrency_password')
    )
  ),
  'OK',
  'first independent concurrency session connects'
);
select is(
  extensions.dblink_connect(
    'ticket9a11_b',
    pg_catalog.format(
      'hostaddr=%s port=%s dbname=%L user=%L password=%L',
      pg_catalog.inet_server_addr(),
      pg_catalog.current_setting('port'),
      pg_catalog.current_database(),
      'ticket9a11_concurrency_login',
      pg_catalog.current_setting('lekkadeall.ticket9a11_concurrency_password')
    )
  ),
  'OK',
  'second independent concurrency session connects'
);

do $$
begin
  perform pg_catalog.set_config(
    'lekkadeall.ticket9a11_concurrency_password',
    '',
    false
  );
end;
$$;

do $$
begin
  perform extensions.dblink_exec('ticket9a11_a', 'set role authenticated');
  perform extensions.dblink_exec('ticket9a11_b', 'set role authenticated');
  perform extensions.dblink_exec(
    'ticket9a11_a',
    'set request.jwt.claim.sub = ''00000000-0000-0000-0000-000000011099'''
  );
  perform extensions.dblink_exec(
    'ticket9a11_b',
    'set request.jwt.claim.sub = ''00000000-0000-0000-0000-000000011099'''
  );
  perform extensions.dblink_exec('ticket9a11_a', 'begin');
end;
$$;

select is(
  extensions.dblink_send_query(
    'ticket9a11_a',
    $query$
      select public.customer_publish_draft_request(
        '00000000-0000-0000-0000-000000011199'::pg_catalog.uuid
      )::pg_catalog.text
    $query$
  ),
  1,
  'first publication race query starts asynchronously'
);

update ticket9a11_concurrency_results as result
set result_status = remote.result_status
from extensions.dblink_get_result('ticket9a11_a', false) as remote(result_status text)
where result.connection_name = 'a';

update ticket9a11_concurrency_results
set error_message = extensions.dblink_error_message('ticket9a11_a')
where connection_name = 'a';

select is(
  extensions.dblink_send_query(
    'ticket9a11_b',
    $query$
      select public.customer_publish_draft_request(
        '00000000-0000-0000-0000-000000011199'::pg_catalog.uuid
      )::pg_catalog.text
    $query$
  ),
  1,
  'second publication race query starts asynchronously'
);

do $$
begin
  perform extensions.dblink_exec('ticket9a11_a', 'commit');
end;
$$;

update ticket9a11_concurrency_results as result
set result_status = remote.result_status
from extensions.dblink_get_result('ticket9a11_b', false) as remote(result_status text)
where result.connection_name = 'b';

update ticket9a11_concurrency_results
set error_message = extensions.dblink_error_message('ticket9a11_b')
where connection_name = 'b';

select is(
  (select count(*) from ticket9a11_concurrency_results where result_status = 'open'),
  1::bigint,
  'concurrent publication permits exactly one successful transition'
);
select is(
  (select count(*) from ticket9a11_concurrency_results
   where error_message is not null and error_message <> 'OK'),
  1::bigint,
  'concurrent duplicate receives exactly one failure'
);
select is(
  (select status::text from public.service_requests
   where id = '00000000-0000-0000-0000-000000011199'),
  'open',
  'concurrent publication leaves one authoritative open state'
);
select is(
  (select count(*) from public.audit_events
   where action = 'customer.service_request_draft_published'
     and object_id = '00000000-0000-0000-0000-000000011199'),
  1::bigint,
  'concurrent publication appends exactly one audit event'
);
select is(
  (select count(*) from private.service_request_addresses
   where request_id = '00000000-0000-0000-0000-000000011199'),
  0::bigint,
  'concurrent publication neither requires nor creates an address row'
);
select is(extensions.dblink_disconnect('ticket9a11_a'), 'OK',
  'first concurrency session disconnects');
select is(extensions.dblink_disconnect('ticket9a11_b'), 'OK',
  'second concurrency session disconnects');

select ok(
  (select relrowsecurity from pg_catalog.pg_class as c
   join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'service_requests'),
  'service_requests RLS remains enabled'
);

\ir rls_test_seed.inc

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000011001', 'ticket9a11-active@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000011002', 'ticket9a11-other@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000011003', 'ticket9a11-restricted@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000011004', 'ticket9a11-suspended@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000011005', 'ticket9a11-closed@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000011006', 'ticket9a11-support@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000011007', 'ticket9a11-missing@lekkadeall.test');

set local lekkadeall.allow_privileged_profile_update = 'on';

update public.profiles as p
set display_name = v.display_name,
    account_status = v.account_status,
    updated_at = pg_catalog.now()
from (values
  ('00000000-0000-0000-0000-000000011001'::uuid, 'Active Customer', 'active'),
  ('00000000-0000-0000-0000-000000011002'::uuid, 'Other Customer', 'active'),
  ('00000000-0000-0000-0000-000000011003'::uuid, 'Restricted Customer', 'restricted'),
  ('00000000-0000-0000-0000-000000011004'::uuid, 'Suspended Customer', 'suspended'),
  ('00000000-0000-0000-0000-000000011005'::uuid, 'Closed Customer', 'closed'),
  ('00000000-0000-0000-0000-000000011006'::uuid, 'Support User', 'active')
) as v(id, display_name, account_status)
where p.id = v.id;

update public.profiles
set role = 'support'::public.user_role,
    updated_at = pg_catalog.now()
where id = '00000000-0000-0000-0000-000000011006';

set local lekkadeall.allow_privileged_profile_update = 'off';

delete from public.profiles
where id = '00000000-0000-0000-0000-000000011007';

insert into public.service_categories (id, slug, name, active) values
  ('00000000-0000-0000-0000-000000011080', 'ticket9a11-active', 'Ticket 9A-11 Active', true),
  ('00000000-0000-0000-0000-000000011081', 'ticket9a11-inactive', 'Ticket 9A-11 Inactive', false);

set local lekkadeall.allow_marketplace_state_transition = 'on';
alter table public.service_requests disable trigger enforce_service_request_public_fields;
alter table public.service_requests disable trigger prevent_service_request_precise_address_write;

insert into public.service_requests (
  id, customer_id, category_id, title, description, suburb, city,
  precise_address_ciphertext, requested_start, budget_minor, status, closes_at,
  published_at, awarded_at, cancelled_at, created_at, updated_at
) values
  (
    '00000000-0000-0000-0000-000000011101', '00000000-0000-0000-0000-000000011001',
    '00000000-0000-0000-0000-000000011080', 'Address independent success draft',
    'Safe service request fixture for publication without an exact address.',
    'Die Bult', 'Potchefstroom', null, pg_catalog.now() + interval '8 days', 81000,
    'draft', null, null, null, null, pg_catalog.now() - interval '2 hours', pg_catalog.now() - interval '2 hours'
  ),
  (
    '00000000-0000-0000-0000-000000011102', '00000000-0000-0000-0000-000000011002',
    '00000000-0000-0000-0000-000000011080', 'Other customer draft',
    'Safe publication fixture belonging to another active customer.',
    'Miederpark', 'Potchefstroom', null, pg_catalog.now() + interval '8 days', 82000,
    'draft', null, null, null, null, pg_catalog.now() - interval '2 hours', pg_catalog.now() - interval '2 hours'
  ),
  (
    '00000000-0000-0000-0000-000000011103', '00000000-0000-0000-0000-000000011001',
    '00000000-0000-0000-0000-000000011080', 'Open publication fixture',
    'Safe open request fixture for repeated publication rejection.',
    'Die Bult', 'Potchefstroom', null, pg_catalog.now() + interval '8 days', 83000,
    'open', pg_catalog.now() + interval '2 days', pg_catalog.now(), null, null,
    pg_catalog.now() - interval '2 hours', pg_catalog.now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000011104', '00000000-0000-0000-0000-000000011001',
    '00000000-0000-0000-0000-000000011080', 'Awarded publication fixture',
    'Safe awarded request fixture for publication rejection.',
    'Die Bult', 'Potchefstroom', null, pg_catalog.now() + interval '8 days', 84000,
    'awarded', pg_catalog.now() + interval '2 days', pg_catalog.now(), pg_catalog.now(), null,
    pg_catalog.now() - interval '2 hours', pg_catalog.now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000011105', '00000000-0000-0000-0000-000000011001',
    '00000000-0000-0000-0000-000000011080', 'Cancelled publication fixture',
    'Safe cancelled request fixture for publication rejection.',
    'Die Bult', 'Potchefstroom', null, pg_catalog.now() + interval '8 days', 85000,
    'cancelled', null, null, null, pg_catalog.now(),
    pg_catalog.now() - interval '2 hours', pg_catalog.now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000011106', '00000000-0000-0000-0000-000000011001',
    '00000000-0000-0000-0000-000000011080', 'Expired publication fixture',
    'Safe expired request fixture for publication rejection.',
    'Die Bult', 'Potchefstroom', null, pg_catalog.now() + interval '8 days', 86000,
    'expired', pg_catalog.now() - interval '1 hour', pg_catalog.now() - interval '3 days', null, null,
    pg_catalog.now() - interval '4 days', pg_catalog.now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000011107', '00000000-0000-0000-0000-000000011001',
    '00000000-0000-0000-0000-000000011080', 'Inconsistent close draft',
    'Safe draft fixture with an inconsistent close timestamp.',
    'Die Bult', 'Potchefstroom', null, pg_catalog.now() + interval '8 days', 87000,
    'draft', pg_catalog.now() + interval '2 days', null, null, null,
    pg_catalog.now() - interval '2 hours', pg_catalog.now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000011108', '00000000-0000-0000-0000-000000011001',
    '00000000-0000-0000-0000-000000011080', 'Inconsistent published draft',
    'Safe draft fixture with an inconsistent publication timestamp.',
    'Die Bult', 'Potchefstroom', null, pg_catalog.now() + interval '8 days', 88000,
    'draft', null, pg_catalog.now(), null, null,
    pg_catalog.now() - interval '2 hours', pg_catalog.now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000011109', '00000000-0000-0000-0000-000000011001',
    '00000000-0000-0000-0000-000000011080', 'Inconsistent awarded draft',
    'Safe draft fixture with an inconsistent award timestamp.',
    'Die Bult', 'Potchefstroom', null, pg_catalog.now() + interval '8 days', 89000,
    'draft', null, null, pg_catalog.now(), null,
    pg_catalog.now() - interval '2 hours', pg_catalog.now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000011110', '00000000-0000-0000-0000-000000011001',
    '00000000-0000-0000-0000-000000011080', 'Inconsistent cancelled draft',
    'Safe draft fixture with an inconsistent cancellation timestamp.',
    'Die Bult', 'Potchefstroom', null, pg_catalog.now() + interval '8 days', 90000,
    'draft', null, null, null, pg_catalog.now(),
    pg_catalog.now() - interval '2 hours', pg_catalog.now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000011111', '00000000-0000-0000-0000-000000011001',
    '00000000-0000-0000-0000-000000011080', 'Bid contaminated draft',
    'Safe draft fixture with an inconsistent provider bid.',
    'Die Bult', 'Potchefstroom', null, pg_catalog.now() + interval '8 days', 91000,
    'draft', null, null, null, null,
    pg_catalog.now() - interval '2 hours', pg_catalog.now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000011112', '00000000-0000-0000-0000-000000011001',
    '00000000-0000-0000-0000-000000011080', 'Booking contaminated draft',
    'Safe draft fixture with an inconsistent booking.',
    'Die Bult', 'Potchefstroom', null, pg_catalog.now() + interval '8 days', 92000,
    'draft', null, null, null, null,
    pg_catalog.now() - interval '2 hours', pg_catalog.now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000011113', '00000000-0000-0000-0000-000000011001',
    '00000000-0000-0000-0000-000000011081', 'Inactive category draft',
    'Safe draft fixture with an inactive service category.',
    'Die Bult', 'Potchefstroom', null, pg_catalog.now() + interval '8 days', 93000,
    'draft', null, null, null, null,
    pg_catalog.now() - interval '2 hours', pg_catalog.now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000011114', '00000000-0000-0000-0000-000000011001',
    '00000000-0000-0000-0000-000000011080', 'Past requested start draft',
    'Safe draft fixture with a stale requested start.',
    'Die Bult', 'Potchefstroom', null, pg_catalog.now() - interval '1 hour', 94000,
    'draft', null, null, null, null,
    pg_catalog.now() - interval '2 hours', pg_catalog.now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000011115', '00000000-0000-0000-0000-000000011001',
    '00000000-0000-0000-0000-000000011080', 'Too close requested start draft',
    'Safe draft fixture without enough publication lead time.',
    'Die Bult', 'Potchefstroom', null, pg_catalog.now() + interval '30 minutes', 95000,
    'draft', null, null, null, null,
    pg_catalog.now() - interval '2 hours', pg_catalog.now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000011116', '00000000-0000-0000-0000-000000011001',
    '00000000-0000-0000-0000-000000011080', 'Repair at 14 Long Street',
    'Legacy unsafe public-field fixture for publication validation.',
    'Die Bult', 'Potchefstroom', null, pg_catalog.now() + interval '8 days', 96000,
    'draft', null, null, null, null,
    pg_catalog.now() - interval '2 hours', pg_catalog.now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000011117', '00000000-0000-0000-0000-000000011001',
    '00000000-0000-0000-0000-000000011080', 'Deprecated address residue draft',
    'Safe draft fixture with forbidden deprecated address residue.',
    'Die Bult', 'Potchefstroom', 'legacy-address-residue', pg_catalog.now() + interval '8 days', 97000,
    'draft', null, null, null, null,
    pg_catalog.now() - interval '2 hours', pg_catalog.now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000011118', '00000000-0000-0000-0000-000000011001',
    '00000000-0000-0000-0000-000000011080', 'Audit rollback draft',
    'Safe draft fixture for atomic publication audit rollback.',
    'Die Bult', 'Potchefstroom', null, pg_catalog.now() + interval '8 days', 98000,
    'draft', null, null, null, null,
    pg_catalog.now() - interval '2 hours', pg_catalog.now() - interval '1 hour'
  );

alter table public.service_requests enable trigger prevent_service_request_precise_address_write;
alter table public.service_requests enable trigger enforce_service_request_public_fields;
set local lekkadeall.allow_marketplace_state_transition = 'off';

set local lekkadeall.allow_marketplace_state_transition = 'on';

insert into public.bids (
  id, request_id, provider_id, amount_minor, currency, proposed_start,
  message, status, expires_at, accepted_at
) values
  (
    '00000000-0000-0000-0000-000000011211',
    '00000000-0000-0000-0000-000000011111',
    '00000000-0000-0000-0000-000000000011',
    70000, 'ZAR', pg_catalog.now() + interval '8 days',
    'Inconsistent submitted bid fixture.', 'submitted', pg_catalog.now() + interval '2 days', null
  ),
  (
    '00000000-0000-0000-0000-000000011212',
    '00000000-0000-0000-0000-000000011112',
    '00000000-0000-0000-0000-000000000011',
    71000, 'ZAR', pg_catalog.now() + interval '8 days',
    'Inconsistent accepted bid fixture.', 'accepted', pg_catalog.now() + interval '2 days', pg_catalog.now()
  );

insert into public.bookings (
  id, public_reference, request_id, bid_id, customer_id, provider_id,
  service_amount_minor, platform_fee_minor, currency, scheduled_start, status
) values (
  '00000000-0000-0000-0000-000000011301', 'TICKET-NINE-A-ELEVEN-BOOKING',
  '00000000-0000-0000-0000-000000011112', '00000000-0000-0000-0000-000000011212',
  '00000000-0000-0000-0000-000000011001', '00000000-0000-0000-0000-000000000011',
  71000, 3550, 'ZAR', pg_catalog.now() + interval '8 days', 'scheduled'
);

set local lekkadeall.allow_marketplace_state_transition = 'off';

create function pg_temp.publish_draft_error(p_request_id uuid)
returns text
language plpgsql
as $$
begin
  perform public.customer_publish_draft_request(p_request_id);
  return '<no error>';
exception
  when others then return sqlstate || ':' || sqlerrm;
end;
$$;

create function pg_temp.try_direct_publish(p_request_id uuid)
returns boolean
language plpgsql
as $$
begin
  update public.service_requests
  set status = 'open',
      published_at = pg_catalog.now(),
      closes_at = pg_catalog.now() + interval '1 day'
  where id = p_request_id;
  return true;
exception
  when others then return false;
end;
$$;

-- Function contract, authority, static boundary, and restrictive grants.
select has_function(
  'public', 'customer_publish_draft_request', array['uuid'],
  'hardened customer publication function exists'
);

select function_returns(
  'public', 'customer_publish_draft_request', array['uuid'], 'request_status',
  'publication returns only request_status'
);

select is(
  (select p.provolatile from pg_catalog.pg_proc as p
   join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'customer_publish_draft_request'),
  'v'::"char",
  'publication function is volatile'
);

select ok(
  (select p.prosecdef from pg_catalog.pg_proc as p
   join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'customer_publish_draft_request'),
  'publication function is security definer'
);

select is(
  (select p.proconfig from pg_catalog.pg_proc as p
   join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'customer_publish_draft_request'),
  array['search_path=pg_catalog']::text[],
  'publication function has fixed pg_catalog search path'
);

select is(
  pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'public.customer_publish_draft_request(uuid)'::regprocedure
  )), 'select *'),
  0,
  'publication boundary contains no SELECT star'
);

select is(
  pg_catalog.strpos(pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'public.customer_publish_draft_request(uuid)'::regprocedure
  )), 'private.service_request_addresses'),
  0,
  'publication boundary does not read the private address table'
);

select alike(
  pg_catalog.pg_get_functiondef('public.customer_publish_draft_request(uuid)'::regprocedure),
  '%private.assert_service_request_public_fields(%',
  'publication calls the authoritative public-field validator'
);

select ok(
  pg_catalog.pg_get_functiondef(
    'public.customer_publish_draft_request(uuid)'::regprocedure
  ) like '%pg_catalog.set_config(%true%'
  and pg_catalog.pg_get_functiondef(
    'public.customer_publish_draft_request(uuid)'::regprocedure
  ) like '%''off''%private.append_audit_event(%',
  'publication uses a transaction-local guard and disables it before audit'
);

select is(has_function_privilege('public', 'public.customer_publish_draft_request(uuid)', 'EXECUTE'), false,
  'PUBLIC cannot execute hardened publication');
select is(has_function_privilege('anon', 'public.customer_publish_draft_request(uuid)', 'EXECUTE'), false,
  'anon cannot execute hardened publication');
select is(has_function_privilege('authenticated', 'public.customer_publish_draft_request(uuid)', 'EXECUTE'), true,
  'authenticated can execute hardened publication');
select is(has_function_privilege('service_role', 'public.customer_publish_draft_request(uuid)', 'EXECUTE'), false,
  'service_role is not granted hardened browser publication');
select is(has_function_privilege('public', 'public.customer_publish_request(uuid,timestamptz)', 'EXECUTE'), false,
  'PUBLIC cannot execute legacy publication');
select is(has_function_privilege('anon', 'public.customer_publish_request(uuid,timestamptz)', 'EXECUTE'), false,
  'anon cannot execute legacy publication');
select is(has_function_privilege('authenticated', 'public.customer_publish_request(uuid,timestamptz)', 'EXECUTE'), false,
  'authenticated cannot execute legacy publication');
select is(has_table_privilege('authenticated', 'public.service_requests', 'INSERT'), false,
  'authenticated still cannot insert service requests directly');
select is(has_table_privilege('authenticated', 'public.service_requests', 'UPDATE'), false,
  'authenticated still cannot update service requests directly');
select is(has_table_privilege('authenticated', 'public.service_requests', 'DELETE'), false,
  'authenticated still cannot delete service requests directly');

-- Authentication, profile authority, ownership, and indistinguishable IDs.
reset role;
set local request.jwt.claim.sub = '';
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011101'),
  '42501:Authentication is required to publish a draft', 'signed-out publication is rejected');
select is(pg_temp.publish_draft_error(null),
  '22023:Draft request ID is required', 'null request ID is rejected before authentication');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000011007';
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011101'),
  '42501:Draft publication is unavailable', 'missing-profile actor is rejected');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000011003';
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011101'),
  '42501:Draft publication is unavailable', 'restricted customer is rejected');
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000011004';
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011101'),
  '42501:Draft publication is unavailable', 'suspended customer is rejected');
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000011005';
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011101'),
  '42501:Draft publication is unavailable', 'closed customer is rejected');
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000011006';
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011101'),
  '42501:Draft publication is unavailable', 'wrong-role actor is rejected');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000011001';
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011102'),
  '42501:Draft is not available for publication', 'cross-customer request is rejected');
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011999'),
  '42501:Draft is not available for publication', 'unknown request uses the same safe error');

-- State, consistency, category, timing, validator, bid, and booking failures.
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011103'),
  '42501:Draft is not available for publication', 'already-open request is rejected');
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011104'),
  '42501:Draft is not available for publication', 'awarded request is rejected');
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011105'),
  '42501:Draft is not available for publication', 'cancelled request is rejected');
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011106'),
  '42501:Draft is not available for publication', 'expired request is rejected');
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011107'),
  '42501:Draft is not available for publication', 'draft with close timestamp is rejected');
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011108'),
  '42501:Draft is not available for publication', 'draft with publication timestamp is rejected');
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011109'),
  '42501:Draft is not available for publication', 'draft with award timestamp is rejected');
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011110'),
  '42501:Draft is not available for publication', 'draft with cancellation timestamp is rejected');
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011111'),
  '42501:Draft is not available for publication', 'draft with a bid is rejected');
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011112'),
  '42501:Draft is not available for publication', 'draft with a booking is rejected');
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011113'),
  '22023:Draft publication is unavailable', 'draft with inactive category is rejected');
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011114'),
  '22023:Draft publication is unavailable', 'draft with past requested start is rejected');
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011115'),
  '22023:Draft publication is unavailable', 'draft without closing-time runway is rejected');
select alike(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011116'),
  '22023:%', 'unsafe public fields are rejected by the authoritative validator');
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011117'),
  '42501:Draft is not available for publication', 'deprecated public address residue is rejected');

select is(
  coalesce(pg_catalog.current_setting('lekkadeall.allow_marketplace_state_transition', true), 'off'),
  'off',
  'transition guard remains disabled after all pre-update failures'
);

-- Active-owner address-independent publication and authoritative postconditions.
reset role;

select is(
  (select count(*) from private.service_request_addresses
   where request_id = '00000000-0000-0000-0000-000000011101'),
  0::bigint,
  'successful publication fixture has no private address row'
);

set local role authenticated;

select is(
  public.customer_publish_draft_request('00000000-0000-0000-0000-000000011101')::text,
  'open',
  'active owner publishes an address-independent draft'
);

reset role;

select is(
  (select status::text from public.service_requests
   where id = '00000000-0000-0000-0000-000000011101'),
  'open',
  'publication sets the authoritative request status to open'
);
select ok(
  (select published_at is not null and closes_at is not null
          and closes_at > published_at and closes_at < requested_start
   from public.service_requests
   where id = '00000000-0000-0000-0000-000000011101'),
  'publication sets valid server-controlled timestamps'
);
select ok(
  (select closes_at <= published_at + interval '3 days'
   from public.service_requests
   where id = '00000000-0000-0000-0000-000000011101'),
  'publication preserves the established maximum three-day close window'
);
select ok(
  (select category_id = '00000000-0000-0000-0000-000000011080'
          and title = 'Address independent success draft'
          and description = 'Safe service request fixture for publication without an exact address.'
          and suburb = 'Die Bult'
          and city = 'Potchefstroom'
          and budget_minor = 81000
          and awarded_at is null
          and cancelled_at is null
          and precise_address_ciphertext is null
   from public.service_requests
   where id = '00000000-0000-0000-0000-000000011101'),
  'publication changes only reviewed workflow fields'
);
select is(
  (select count(*) from private.service_request_addresses
   where request_id = '00000000-0000-0000-0000-000000011101'),
  0::bigint,
  'publication creates no private address row'
);
select is(
  (select count(*) from public.audit_events
   where action = 'customer.service_request_draft_published'
     and object_id = '00000000-0000-0000-0000-000000011101'),
  1::bigint,
  'successful publication appends exactly one audit event'
);
select ok(
  exists (
    select 1 from public.audit_events
    where action = 'customer.service_request_draft_published'
      and object_type = 'service_request'
      and object_id = '00000000-0000-0000-0000-000000011101'
      and actor_id = '00000000-0000-0000-0000-000000011001'
      and reason = 'Customer published own draft service request'
      and metadata = pg_catalog.jsonb_build_object(
        'request_id', '00000000-0000-0000-0000-000000011101'::uuid,
        'previous_status', 'draft',
        'new_status', 'open'
      )
  ),
  'publication audit contains only fixed allowlisted metadata'
);
select ok(
  (select pg_catalog.lower(reason || metadata::text) !~
      '(address independent success|exact address|die bult|potchefstroom|ticket9a11-active@|token|password|ciphertext)'
   from public.audit_events
   where action = 'customer.service_request_draft_published'
     and object_id = '00000000-0000-0000-0000-000000011101'),
  'publication audit contains no request, address, credential, or Auth values'
);
select is(
  coalesce(pg_catalog.current_setting('lekkadeall.allow_marketplace_state_transition', true), 'off'),
  'off',
  'transition guard is disabled after successful publication'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000011001';
select is(pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011101'),
  '42501:Draft is not available for publication', 'repeated publication is rejected');
reset role;
select is(
  (select count(*) from public.audit_events
   where action = 'customer.service_request_draft_published'
     and object_id = '00000000-0000-0000-0000-000000011101'),
  1::bigint,
  'repeated publication creates no duplicate audit event'
);
select is(
  coalesce(pg_catalog.current_setting('lekkadeall.allow_marketplace_state_transition', true), 'off'),
  'off',
  'transition guard is disabled after repeated publication rejection'
);

-- Browser direct DML remains denied.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000011001';
select is(pg_temp.try_direct_publish('00000000-0000-0000-0000-000000011118'), false,
  'authenticated customer cannot publish by direct table update');
reset role;

-- Audit insertion failure rolls back the request transition atomically.
create function pg_temp.fail_ticket9a11_audit()
returns trigger
language plpgsql
as $$
begin
  if new.action = 'customer.service_request_draft_published'
     and new.object_id = '00000000-0000-0000-0000-000000011118' then
    raise exception 'Synthetic publication audit failure';
  end if;
  return new;
end;
$$;

create trigger fail_ticket9a11_audit_insert
before insert on public.audit_events
for each row execute function pg_temp.fail_ticket9a11_audit();

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000011001';
select isnt(
  pg_temp.publish_draft_error('00000000-0000-0000-0000-000000011118'),
  '<no error>',
  'audit failure prevents publication success'
);
reset role;

drop trigger fail_ticket9a11_audit_insert on public.audit_events;

select is(
  (select status::text from public.service_requests
   where id = '00000000-0000-0000-0000-000000011118'),
  'draft',
  'audit failure rolls back the request transition'
);
select is(
  (select count(*) from public.audit_events
   where action = 'customer.service_request_draft_published'
     and object_id = '00000000-0000-0000-0000-000000011118'),
  0::bigint,
  'audit failure leaves no partial publication event'
);
select is(
  coalesce(pg_catalog.current_setting('lekkadeall.allow_marketplace_state_transition', true), 'off'),
  'off',
  'transition guard is disabled after audit failure'
);

select * from finish();

rollback;

-- Remove the committed concurrency-only fixture without weakening production
-- triggers or retaining synthetic rows.
begin;

set local lekkadeall.allow_marketplace_state_transition = 'on';
delete from public.service_requests
where id = '00000000-0000-0000-0000-000000011199';

alter table public.audit_events disable trigger audit_events_append_only;
delete from public.audit_events
where object_id in (
  '00000000-0000-0000-0000-000000011099',
  '00000000-0000-0000-0000-000000011199'
);
alter table public.audit_events enable trigger audit_events_append_only;

delete from auth.users
where id = '00000000-0000-0000-0000-000000011099';
delete from public.service_categories
where id = '00000000-0000-0000-0000-000000011090';

commit;

drop role ticket9a11_concurrency_login;
