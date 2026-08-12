create extension if not exists pgtap with schema extensions;

-- Commit only the genuine two-session revocation fixture before pgTAP starts.
begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000010401', 'ticket10c-admin@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000010402', 'ticket10c-provider@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000010403', 'ticket10c-customer@lekkadeall.test');

set local lekkadeall.allow_privileged_profile_update = 'on';
update public.profiles
set role = 'admin'::public.user_role
where id = '00000000-0000-0000-0000-000000010401';
update public.profiles
set role = 'provider'::public.user_role
where id = '00000000-0000-0000-0000-000000010402';
set local lekkadeall.allow_privileged_profile_update = 'off';

insert into public.service_categories (id, slug, name, active) values (
  '00000000-0000-0000-0000-000000010490',
  'ticket10c-concurrent',
  'Ticket 10C Concurrent',
  true
);

insert into public.provider_profiles (
  user_id, business_name, service_radius_km, verification_status, review_status
) values (
  '00000000-0000-0000-0000-000000010402',
  'Ticket 10C Concurrent Services',
  20,
  'not_started',
  'pending'
);

insert into public.provider_services (
  provider_id, category_id, description, base_price_minor, active
) values (
  '00000000-0000-0000-0000-000000010402',
  '00000000-0000-0000-0000-000000010490',
  null,
  null,
  false
);

insert into public.consents (
  user_id, purpose, policy_version, granted, source, withdrawn_at
) values (
  '00000000-0000-0000-0000-000000010402',
  'provider_application_terms',
  'provider-application-v1',
  true,
  'customer_provider_application_rpc',
  null
);

insert into public.audit_events (
  actor_id, action, object_type, object_id, reason, metadata
) values (
  '00000000-0000-0000-0000-000000010402',
  'customer.provider_application_submitted',
  'provider_profile',
  '00000000-0000-0000-0000-000000010402',
  'Customer submitted closed-pilot provider application',
  '{}'::pg_catalog.jsonb
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010401';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000010401","role":"authenticated","aal":"aal2"}';
select public.admin_transition_provider_marketplace_review(
  '00000000-0000-0000-0000-000000010402',
  'approve_manual_pilot',
  'pending',
  '00000000-0000-0000-0000-000000010481'
);
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010402';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000010402","role":"authenticated","aal":"aal1"}';
update public.provider_services
set active = true
where provider_id = '00000000-0000-0000-0000-000000010402'
  and category_id = '00000000-0000-0000-0000-000000010490';
reset role;

set local lekkadeall.allow_marketplace_state_transition = 'on';
insert into public.service_requests (
  id, customer_id, category_id, title, description, suburb, city,
  requested_start, budget_minor, status, closes_at, published_at
) values (
  '00000000-0000-0000-0000-000000010491',
  '00000000-0000-0000-0000-000000010403',
  '00000000-0000-0000-0000-000000010490',
  'Concurrent discovery request',
  'Safe public request for the discovery and revocation serialization test.',
  'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 15000,
  'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '1 hour'
);
set local lekkadeall.allow_marketplace_state_transition = 'off';

do $$
declare
  v_password pg_catalog.text := pg_catalog.replace(
    pg_catalog.gen_random_uuid()::pg_catalog.text,
    '-',
    ''
  );
begin
  execute pg_catalog.format(
    'create role ticket10c_concurrency_login login password %L',
    v_password
  );
  perform pg_catalog.set_config(
    'lekkadeall.ticket10c_concurrency_password',
    v_password,
    false
  );
end;
$$;

grant authenticated to ticket10c_concurrency_login;

commit;

begin;

create extension if not exists dblink with schema extensions;
set local search_path = public, extensions, auth;

select plan(60);

select is(
  extensions.dblink_connect(
    'ticket10c_discovery',
    pg_catalog.format(
      'hostaddr=%s port=%s dbname=%L user=%L password=%L',
      pg_catalog.inet_server_addr(),
      pg_catalog.current_setting('port'),
      pg_catalog.current_database(),
      'ticket10c_concurrency_login',
      pg_catalog.current_setting('lekkadeall.ticket10c_concurrency_password')
    )
  ),
  'OK',
  'independent discovery session connects'
);

select is(
  extensions.dblink_connect(
    'ticket10c_review',
    pg_catalog.format(
      'hostaddr=%s port=%s dbname=%L user=%L password=%L',
      pg_catalog.inet_server_addr(),
      pg_catalog.current_setting('port'),
      pg_catalog.current_database(),
      'ticket10c_concurrency_login',
      pg_catalog.current_setting('lekkadeall.ticket10c_concurrency_password')
    )
  ),
  'OK',
  'independent revocation session connects'
);

do $$
begin
  perform pg_catalog.set_config('lekkadeall.ticket10c_concurrency_password', '', false);
  perform extensions.dblink_exec('ticket10c_discovery', 'set role authenticated');
  perform extensions.dblink_exec('ticket10c_review', 'set role authenticated');
  perform extensions.dblink_exec(
    'ticket10c_discovery',
    'set request.jwt.claim.sub = ''00000000-0000-0000-0000-000000010402'''
  );
  perform extensions.dblink_exec(
    'ticket10c_discovery',
    'set request.jwt.claims = ''{"sub":"00000000-0000-0000-0000-000000010402","role":"authenticated","aal":"aal1"}'''
  );
  perform extensions.dblink_exec(
    'ticket10c_review',
    'set request.jwt.claim.sub = ''00000000-0000-0000-0000-000000010401'''
  );
  perform extensions.dblink_exec(
    'ticket10c_review',
    'set request.jwt.claims = ''{"sub":"00000000-0000-0000-0000-000000010401","role":"authenticated","aal":"aal2"}'''
  );
  perform extensions.dblink_exec('ticket10c_discovery', 'begin');
  perform extensions.dblink_exec('ticket10c_review', 'begin');
end;
$$;

select is(
  (
    select result.request_count
    from extensions.dblink(
      'ticket10c_discovery',
      'select pg_catalog.count(*) from public.provider_list_discoverable_requests()'
    ) as result(request_count pg_catalog.int8)
  ),
  1::pg_catalog.int8,
  'authorized discovery completes before a conflicting revocation'
);

select is(
  extensions.dblink_send_query(
    'ticket10c_review',
    $query$
      select public.admin_transition_provider_marketplace_review(
        '00000000-0000-0000-0000-000000010402',
        'suspend',
        'approved',
        '00000000-0000-0000-0000-000000010482'
      )
    $query$
  ),
  1,
  'suspension starts while discovery retains shared authority locks'
);

select is(
  extensions.dblink_is_busy('ticket10c_review'),
  1,
  'suspension waits for the authorized discovery transaction'
);

select is(
  extensions.dblink_exec('ticket10c_discovery', 'commit'),
  'COMMIT',
  'authorized discovery transaction releases its authority locks'
);

create temporary table ticket10c_revocation_result (
  review_status pg_catalog.text
) on commit drop;

insert into ticket10c_revocation_result (review_status)
select result.review_status
from extensions.dblink_get_result('ticket10c_review', false)
  as result(review_status pg_catalog.text);

select is(
  (select review_status from ticket10c_revocation_result),
  'suspended',
  'waiting suspension completes after the prior discovery releases its locks'
);

select is(
  extensions.dblink_error_message('ticket10c_review'),
  'OK',
  'suspension session reports no hidden database detail'
);

select is(
  extensions.dblink_exec('ticket10c_review', 'commit'),
  'COMMIT',
  'suspension transaction commits before fresh discovery'
);

select throws_ok(
  $$select result.request_id
    from extensions.dblink(
      'ticket10c_discovery',
      'select request_id from public.provider_list_discoverable_requests()'
    ) as result(request_id pg_catalog.uuid)$$,
  '42501',
  'Provider request discovery is unavailable',
  'fresh discovery after committed suspension fails closed'
);

select is(extensions.dblink_disconnect('ticket10c_discovery'), 'OK', 'discovery session disconnects');
select is(extensions.dblink_disconnect('ticket10c_review'), 'OK', 'revocation session disconnects');

-- Transactional fixtures for contract, matching, state and pagination tests.
\ir rls_test_seed.inc

set local lekkadeall.allow_privileged_provider_profile_update = 'on';
update public.provider_profiles
set verification_status = 'not_started',
    review_status = 'approved',
    reviewed_by = '00000000-0000-0000-0000-000000000099',
    reviewed_at = pg_catalog.now()
where user_id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_provider_profile_update = 'off';

insert into public.provider_services (
  provider_id, category_id, description, base_price_minor, active
) values (
  '00000000-0000-0000-0000-000000000011',
  '00000000-0000-0000-0000-000000000100',
  'Active discovery service',
  50000,
  true
);

set local lekkadeall.allow_marketplace_state_transition = 'on';

update public.service_requests
set published_at = pg_catalog.now() - interval '2 hours'
where id = '00000000-0000-0000-0000-000000000202';

insert into public.service_categories (id, slug, name, active) values
  ('00000000-0000-0000-0000-000000010500', 'ticket10c-other', 'Ticket 10C Other', true),
  ('00000000-0000-0000-0000-000000010501', 'ticket10c-inactive', 'Ticket 10C Inactive', false);

-- Another provider's active service must never widen this caller's category set.
insert into public.provider_services (
  provider_id, category_id, description, base_price_minor, active
) values (
  '00000000-0000-0000-0000-000000000012',
  '00000000-0000-0000-0000-000000010500',
  'Other provider active service',
  60000,
  true
);

insert into public.service_requests (
  id, customer_id, category_id, title, description, suburb, city,
  requested_start, budget_minor, status, closes_at, published_at,
  awarded_at, cancelled_at
) values
  ('00000000-0000-0000-0000-000000010510', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000100', 'Second matching request', 'Safe matching request for keyset pagination coverage.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 11000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '1 hour', null, null),
  ('00000000-0000-0000-0000-000000010511', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000100', 'Tie matching request', 'Safe matching request with a deterministic publication tie.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 12000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '1 hour', null, null),
  ('00000000-0000-0000-0000-000000010512', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000010500', 'Unmatched request', 'Safe request in a category without an active owned service.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 13000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '1 hour', null, null),
  ('00000000-0000-0000-0000-000000010513', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000010501', 'Inactive category request', 'Safe request whose category is no longer active.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 14000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '1 hour', null, null),
  ('00000000-0000-0000-0000-000000010514', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000100', 'Null publication request', 'Safe but internally inconsistent null-publication request.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 15000, 'open', pg_catalog.now() + interval '2 days', null, null, null),
  ('00000000-0000-0000-0000-000000010515', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000100', 'Future publication request', 'Safe but internally inconsistent future-publication request.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 16000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() + interval '1 hour', null, null),
  ('00000000-0000-0000-0000-000000010516', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000100', 'Past close request', 'Safe request whose discovery close time has passed.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 17000, 'open', pg_catalog.now() - interval '1 hour', pg_catalog.now() - interval '2 hours', null, null),
  ('00000000-0000-0000-0000-000000010517', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000100', 'Past start request', 'Safe request whose requested start is no longer usable.', 'Die Bult', 'Potchefstroom', pg_catalog.now() - interval '1 hour', 18000, 'open', pg_catalog.now() + interval '1 hour', pg_catalog.now() - interval '2 hours', null, null),
  ('00000000-0000-0000-0000-000000010518', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000100', 'Invalid close order request', 'Safe request whose close time follows the requested start.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '1 day', 19000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '2 hours', null, null),
  ('00000000-0000-0000-0000-000000010519', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000100', 'Cancelled request', 'Safe request already cancelled by its customer.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 20000, 'cancelled', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '2 hours', null, pg_catalog.now()),
  ('00000000-0000-0000-0000-000000010520', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000100', 'Awarded request', 'Safe request already awarded to a selected provider.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 21000, 'awarded', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '2 hours', pg_catalog.now(), null),
  ('00000000-0000-0000-0000-000000010521', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000100', 'Expired request', 'Safe request whose authoritative state is expired.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 22000, 'expired', pg_catalog.now() - interval '1 hour', pg_catalog.now() - interval '2 hours', null, null),
  ('00000000-0000-0000-0000-000000010522', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000100', 'Null close request', 'Safe but internally inconsistent null-close request.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 23000, 'open', null, pg_catalog.now() - interval '2 hours', null, null),
  ('00000000-0000-0000-0000-000000010523', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000100', 'Open awarded timestamp request', 'Safe but inconsistent open request with an award timestamp.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 24000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '2 hours', pg_catalog.now(), null),
  ('00000000-0000-0000-0000-000000010524', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000100', 'Open cancelled timestamp request', 'Safe but inconsistent open request with a cancellation timestamp.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 25000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '2 hours', null, pg_catalog.now());

alter table public.service_requests disable trigger prevent_service_request_precise_address_write;
insert into public.service_requests (
  id, customer_id, category_id, title, description, suburb, city,
  requested_start, budget_minor, status, closes_at, published_at,
  precise_address_ciphertext
) values (
  '00000000-0000-0000-0000-000000010525',
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000100',
  'Deprecated address residue request',
  'Safe public text with prohibited deprecated address-column residue.',
  'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 26000,
  'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '2 hours',
  'synthetic-residue'
);
alter table public.service_requests enable trigger prevent_service_request_precise_address_write;

alter table public.service_requests disable trigger enforce_service_request_public_fields;
alter table public.service_requests
  disable trigger prevent_public_request_description_exact_address_material;
insert into public.service_requests (
  id, customer_id, category_id, title, description, suburb, city,
  requested_start, budget_minor, status, closes_at, published_at
) values (
  '00000000-0000-0000-0000-000000010526',
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000100',
  'Unsafe public request',
  'Call 082 000 0000 to arrange this otherwise unsafe public request.',
  'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 27000,
  'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '2 hours'
);
alter table public.service_requests
  enable trigger prevent_public_request_description_exact_address_material;
alter table public.service_requests enable trigger enforce_service_request_public_fields;

set local lekkadeall.allow_marketplace_state_transition = 'off';

-- Metadata, grants and removal of alternate provider discovery authorities.
select has_function(
  'public',
  'provider_list_discoverable_requests',
  array['integer', 'timestamp with time zone', 'uuid'],
  'one intended provider discovery signature exists'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname in (
        'provider_list_discoverable_requests',
        'list_provider_open_request_summaries'
      )
  ),
  1::pg_catalog.int8,
  'no legacy or alternate provider discovery overload remains'
);

select is(
  (
    select procedure.prosecdef
    from pg_catalog.pg_proc as procedure
    where procedure.oid = 'public.provider_list_discoverable_requests(integer,timestamptz,uuid)'::pg_catalog.regprocedure
  ),
  true,
  'provider discovery is SECURITY DEFINER'
);

select is(
  (
    select procedure.provolatile
    from pg_catalog.pg_proc as procedure
    where procedure.oid = 'public.provider_list_discoverable_requests(integer,timestamptz,uuid)'::pg_catalog.regprocedure
  ),
  'v'::pg_catalog.char,
  'provider discovery is volatile for current locking authorization'
);

select is(
  (
    select procedure.proconfig
    from pg_catalog.pg_proc as procedure
    where procedure.oid = 'public.provider_list_discoverable_requests(integer,timestamptz,uuid)'::pg_catalog.regprocedure
  ),
  array['search_path=pg_catalog']::pg_catalog.text[],
  'provider discovery uses only the fixed pg_catalog search path'
);

select is(has_function_privilege('public', 'public.provider_list_discoverable_requests(integer,timestamptz,uuid)', 'EXECUTE'), false, 'PUBLIC cannot execute provider discovery');
select is(has_function_privilege('anon', 'public.provider_list_discoverable_requests(integer,timestamptz,uuid)', 'EXECUTE'), false, 'anon cannot execute provider discovery');
select is(has_function_privilege('authenticated', 'public.provider_list_discoverable_requests(integer,timestamptz,uuid)', 'EXECUTE'), true, 'authenticated can execute provider discovery');
select is(has_function_privilege('service_role', 'public.provider_list_discoverable_requests(integer,timestamptz,uuid)', 'EXECUTE'), false, 'service_role has no provider discovery execution grant');

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies as policy
    where policy.schemaname = 'public'
      and policy.tablename = 'service_requests'
      and policy.policyname = 'approved providers see open requests'
  ),
  0::pg_catalog.int8,
  'provider-wide raw service_requests discovery policy is removed'
);

select is(
  (
    select pg_catalog.count(*)
    from pg_catalog.pg_policies as policy
    where policy.schemaname = 'public'
      and policy.tablename = 'service_requests'
      and policy.policyname = 'customer owns requests'
  ),
  1::pg_catalog.int8,
  'customer own-request RLS policy remains'
);

select is(
  (
    select relation.relrowsecurity
    from pg_catalog.pg_class as relation
    where relation.oid = 'public.service_requests'::pg_catalog.regclass
  ),
  true,
  'service_requests RLS remains enabled'
);

select is(
  pg_catalog.regexp_replace(
    pg_catalog.pg_get_functiondef(
      'public.provider_list_discoverable_requests(integer,timestamptz,uuid)'::pg_catalog.regprocedure
    ),
    '[[:space:]]+',
    ' ',
    'g'
  ) ~* 'perform private\.require_provider_marketplace_eligibility\(v_actor_id\)',
  true,
  'provider discovery reuses the authoritative Ticket 10B locking requirement'
);

select is(
  pg_catalog.pg_get_functiondef(
    'public.provider_list_discoverable_requests(integer,timestamptz,uuid)'::pg_catalog.regprocedure
  ) ~* 'select[[:space:]]+\*',
  false,
  'provider discovery contains no SELECT star'
);

select is(
  pg_catalog.pg_get_functiondef(
    'public.provider_list_discoverable_requests(integer,timestamptz,uuid)'::pg_catalog.regprocedure
  ) ~* '(private\.service_request_addresses|public\.profiles|public\.bids|public\.bookings|public\.payments|public\.audit_events)',
  false,
  'result construction reads no private address, customer profile, bid, booking, payment or audit relation'
);

select is(
  pg_catalog.pg_get_functiondef(
    'public.provider_list_discoverable_requests(integer,timestamptz,uuid)'::pg_catalog.regprocedure
  ) ~* 'private\.service_request_public_field_violation',
  true,
  'discovery rechecks authoritative public-field privacy validity'
);

-- Freeze the exact ten returned column names using information_schema routine metadata.
select is(
  (
    select pg_catalog.array_agg(parameter.parameter_name order by parameter.ordinal_position)
    from information_schema.parameters as parameter
    where parameter.specific_schema = 'public'
      and parameter.specific_name = (
        select routine.specific_name
        from information_schema.routines as routine
        where routine.routine_schema = 'public'
          and routine.routine_name = 'provider_list_discoverable_requests'
      )
      and parameter.parameter_mode = 'OUT'
  ),
  array[
    'request_id', 'category_id', 'title', 'description', 'suburb', 'city',
    'requested_start', 'budget_minor', 'closes_at', 'published_at'
  ]::pg_catalog.text[],
  'provider discovery returns exactly the ten allowlisted columns'
);

-- Raw reads and authorization failures fail closed.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000011","role":"authenticated","aal":"aal1"}';

select is((select pg_catalog.count(*) from public.service_requests), 0::pg_catalog.int8, 'eligible provider has no raw service_requests bypass');

select is(
  (select pg_catalog.count(*) from public.provider_list_discoverable_requests()),
  3::pg_catalog.int8,
  'eligible provider sees only three valid active-service requests'
);

select is(
  (select title from public.provider_list_discoverable_requests() where request_id = '00000000-0000-0000-0000-000000000202'),
  'Unconfirmed cleaning request',
  'positive discovery returns the canonical safe request title'
);

select is(
  (select pg_catalog.count(*) from public.provider_list_discoverable_requests() where request_id in (
    '00000000-0000-0000-0000-000000010512',
    '00000000-0000-0000-0000-000000010513',
    '00000000-0000-0000-0000-000000010514',
    '00000000-0000-0000-0000-000000010515',
    '00000000-0000-0000-0000-000000010516',
    '00000000-0000-0000-0000-000000010517',
    '00000000-0000-0000-0000-000000010518',
    '00000000-0000-0000-0000-000000010519',
    '00000000-0000-0000-0000-000000010520',
    '00000000-0000-0000-0000-000000010521',
    '00000000-0000-0000-0000-000000010522',
    '00000000-0000-0000-0000-000000010523',
    '00000000-0000-0000-0000-000000010524',
    '00000000-0000-0000-0000-000000010525',
    '00000000-0000-0000-0000-000000010526'
  )),
  0::pg_catalog.int8,
  'unmatched, inactive-category and invalid-state requests are all excluded'
);

select throws_ok($$select * from public.provider_list_discoverable_requests(0)$$, '22023', 'Provider request discovery is unavailable', 'zero page size fails closed');
select throws_ok($$select * from public.provider_list_discoverable_requests(51)$$, '22023', 'Provider request discovery is unavailable', 'oversized page fails closed');
select throws_ok($$select * from public.provider_list_discoverable_requests(null)$$, '22023', 'Provider request discovery is unavailable', 'null page size fails closed');
select throws_ok($$select * from public.provider_list_discoverable_requests(20, pg_catalog.now(), null)$$, '22023', 'Provider request discovery is unavailable', 'partial timestamp cursor fails closed');
select throws_ok($$select * from public.provider_list_discoverable_requests(20, null, '00000000-0000-0000-0000-000000010510')$$, '22023', 'Provider request discovery is unavailable', 'partial request cursor fails closed');

select results_eq(
  $$select request_id from public.provider_list_discoverable_requests(2)$$,
  $$values
    ('00000000-0000-0000-0000-000000010511'::pg_catalog.uuid),
    ('00000000-0000-0000-0000-000000010510'::pg_catalog.uuid)$$,
  'first keyset page uses publication time and descending request-ID tie-breaker'
);

select results_eq(
  $$select request_id from public.provider_list_discoverable_requests(
      2,
      (select published_at from public.service_requests where id = '00000000-0000-0000-0000-000000010510'),
      '00000000-0000-0000-0000-000000010510'
    )$$,
  $$values ('00000000-0000-0000-0000-000000000202'::pg_catalog.uuid)$$,
  'next keyset page is stable and non-overlapping'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
select is((select pg_catalog.count(*) from public.service_requests where id = '00000000-0000-0000-0000-000000000201'), 1::pg_catalog.int8, 'customer owner raw read remains available');
select is((select pg_catalog.count(*) from public.service_requests where id = '00000000-0000-0000-0000-000000000202'), 0::pg_catalog.int8, 'cross-customer raw request stays RLS-hidden');
select throws_ok($$select * from public.provider_list_discoverable_requests()$$, '42501', 'Provider request discovery is unavailable', 'customer cannot use provider discovery');
reset role;

set local role anon;
select throws_ok($$select * from public.provider_list_discoverable_requests()$$, '42501', 'permission denied for function provider_list_discoverable_requests', 'signed-out caller cannot execute provider discovery');
reset role;

-- No active matching service and inactive proposal states return no rows.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
update public.provider_services set active = false where provider_id = '00000000-0000-0000-0000-000000000011';
select is((select pg_catalog.count(*) from public.provider_list_discoverable_requests()), 0::pg_catalog.int8, 'inactive provider service proposal yields no discovery rows');
reset role;

update public.provider_services set active = true where provider_id = '00000000-0000-0000-0000-000000000011';

-- Each protected authority state independently fails closed with one category.
set local lekkadeall.allow_privileged_provider_profile_update = 'on';
update public.provider_profiles set review_status = 'pending' where user_id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_provider_profile_update = 'off';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select * from public.provider_list_discoverable_requests()$$, '42501', 'Provider request discovery is unavailable', 'pending provider review denies discovery');
reset role;

set local lekkadeall.allow_privileged_provider_profile_update = 'on';
update public.provider_profiles set review_status = 'rejected' where user_id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_provider_profile_update = 'off';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select * from public.provider_list_discoverable_requests()$$, '42501', 'Provider request discovery is unavailable', 'rejected provider review denies discovery');
reset role;

set local lekkadeall.allow_privileged_provider_profile_update = 'on';
update public.provider_profiles set review_status = 'suspended' where user_id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_provider_profile_update = 'off';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select * from public.provider_list_discoverable_requests()$$, '42501', 'Provider request discovery is unavailable', 'suspended provider review denies discovery');
reset role;

set local lekkadeall.allow_privileged_provider_profile_update = 'on';
update public.provider_profiles set review_status = 'expired' where user_id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_provider_profile_update = 'off';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select * from public.provider_list_discoverable_requests()$$, '42501', 'Provider request discovery is unavailable', 'expired provider review denies discovery');
reset role;

set local lekkadeall.allow_privileged_provider_profile_update = 'on';
update public.provider_profiles set review_status = 'approved' where user_id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_provider_profile_update = 'off';
set local lekkadeall.allow_privileged_profile_update = 'on';
update public.profiles set account_status = 'restricted' where id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_profile_update = 'off';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select * from public.provider_list_discoverable_requests()$$, '42501', 'Provider request discovery is unavailable', 'restricted account denies discovery');
reset role;

set local lekkadeall.allow_privileged_profile_update = 'on';
update public.profiles set account_status = 'suspended' where id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_profile_update = 'off';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select * from public.provider_list_discoverable_requests()$$, '42501', 'Provider request discovery is unavailable', 'suspended account denies discovery');
reset role;

set local lekkadeall.allow_privileged_profile_update = 'on';
update public.profiles set account_status = 'closed' where id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_profile_update = 'off';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select * from public.provider_list_discoverable_requests()$$, '42501', 'Provider request discovery is unavailable', 'closed account denies discovery');
reset role;

set local lekkadeall.allow_privileged_profile_update = 'on';
update public.profiles set account_status = 'active' where id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_profile_update = 'off';
set local lekkadeall.allow_privileged_provider_profile_update = 'on';
update public.provider_profiles set verification_status = 'rejected' where user_id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_provider_profile_update = 'off';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select * from public.provider_list_discoverable_requests()$$, '42501', 'Provider request discovery is unavailable', 'rejected verification denies discovery');
reset role;

set local lekkadeall.allow_privileged_provider_profile_update = 'on';
update public.provider_profiles set verification_status = 'expired' where user_id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_provider_profile_update = 'off';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select * from public.provider_list_discoverable_requests()$$, '42501', 'Provider request discovery is unavailable', 'expired verification denies discovery');
reset role;

set local lekkadeall.allow_privileged_provider_profile_update = 'on';
update public.provider_profiles set verification_status = 'not_started' where user_id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_provider_profile_update = 'off';
update private.provider_marketplace_eligibility set status = 'pending', basis = null, expires_at = null where provider_id = '00000000-0000-0000-0000-000000000011';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select * from public.provider_list_discoverable_requests()$$, '42501', 'Provider request discovery is unavailable', 'pending eligibility denies discovery');
reset role;

update private.provider_marketplace_eligibility set status = 'rejected' where provider_id = '00000000-0000-0000-0000-000000000011';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select * from public.provider_list_discoverable_requests()$$, '42501', 'Provider request discovery is unavailable', 'rejected eligibility denies discovery');
reset role;

update private.provider_marketplace_eligibility set status = 'approved', basis = 'manual_pilot', expires_at = pg_catalog.now() + interval '1 day', current_decision_id = null, reviewer_id = null, reason_code = null where provider_id = '00000000-0000-0000-0000-000000000011';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select * from public.provider_list_discoverable_requests()$$, '42501', 'Provider request discovery is unavailable', 'incomplete current eligibility decision denies discovery');
reset role;

update private.provider_marketplace_eligibility set current_decision_id = '00000000-0000-0000-0000-000000000611', reviewer_id = '00000000-0000-0000-0000-000000000099', reason_code = 'manual_pilot_approved', expires_at = pg_catalog.now() - interval '1 second' where provider_id = '00000000-0000-0000-0000-000000000011';
update private.provider_marketplace_eligibility set expires_at = pg_catalog.now() - interval '1 second' where provider_id = '00000000-0000-0000-0000-000000000011';

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select * from public.provider_list_discoverable_requests()$$, '42501', 'Provider request discovery is unavailable', 'fresh expired eligibility denies discovery');
reset role;

select is(has_column_privilege('authenticated', 'public.service_requests', 'precise_address_ciphertext', 'SELECT'), false, 'exact-address column remains denied');
select is(has_table_privilege('authenticated', 'private.service_request_addresses', 'SELECT'), false, 'private exact-address table remains denied');

select * from finish();

rollback;

-- Remove committed concurrency-only fixtures and login.
begin;
alter table public.audit_events disable trigger audit_events_append_only;
delete from public.audit_events
where actor_id in (
  '00000000-0000-0000-0000-000000010401',
  '00000000-0000-0000-0000-000000010402'
)
or metadata ->> 'provider_id' = '00000000-0000-0000-0000-000000010402';
alter table public.audit_events enable trigger audit_events_append_only;

set local lekkadeall.allow_marketplace_state_transition = 'on';
delete from public.service_requests where id = '00000000-0000-0000-0000-000000010491';
set local lekkadeall.allow_marketplace_state_transition = 'off';

alter table private.provider_eligibility_decisions disable trigger provider_eligibility_decisions_append_only;
alter table public.consents disable trigger protect_provider_application_terms;
delete from private.provider_marketplace_eligibility where provider_id = '00000000-0000-0000-0000-000000010402';
delete from private.provider_eligibility_decisions where provider_id = '00000000-0000-0000-0000-000000010402';
delete from auth.users where id in (
  '00000000-0000-0000-0000-000000010401',
  '00000000-0000-0000-0000-000000010402',
  '00000000-0000-0000-0000-000000010403'
);
alter table public.consents enable trigger protect_provider_application_terms;
alter table private.provider_eligibility_decisions enable trigger provider_eligibility_decisions_append_only;
delete from public.service_categories where id = '00000000-0000-0000-0000-000000010490';
commit;

drop role ticket10c_concurrency_login;
