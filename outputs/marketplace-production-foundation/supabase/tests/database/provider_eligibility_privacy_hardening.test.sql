create extension if not exists pgtap with schema extensions;

-- Commit only the two-session fixture before the pgTAP transaction starts.
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000010301', 'ticket10b-concurrent-admin@lekkadeall.test', '{}'::jsonb),
  ('00000000-0000-0000-0000-000000010302', 'ticket10b-concurrent-provider@lekkadeall.test', '{}'::jsonb);

set local lekkadeall.allow_privileged_profile_update = 'on';

update public.profiles
set role = 'admin'::public.user_role,
    display_name = 'Ticket 10B Concurrent Admin'
where id = '00000000-0000-0000-0000-000000010301';

update public.profiles
set role = 'provider'::public.user_role,
    display_name = 'Ticket 10B Concurrent Provider'
where id = '00000000-0000-0000-0000-000000010302';

set local lekkadeall.allow_privileged_profile_update = 'off';

insert into public.service_categories (id, slug, name, active) values (
  '00000000-0000-0000-0000-000000010390',
  'ticket10b-concurrent',
  'Ticket 10B Concurrent',
  true
);

insert into public.provider_profiles (
  user_id, business_name, service_radius_km, verification_status, review_status
) values (
  '00000000-0000-0000-0000-000000010302',
  'Ticket 10B Concurrent Services',
  20,
  'not_started',
  'pending'
);

insert into public.provider_services (
  provider_id, category_id, description, base_price_minor, active
) values (
  '00000000-0000-0000-0000-000000010302',
  '00000000-0000-0000-0000-000000010390',
  null,
  null,
  false
);

insert into public.consents (
  user_id, purpose, policy_version, granted, source, withdrawn_at
) values (
  '00000000-0000-0000-0000-000000010302',
  'provider_application_terms',
  'provider-application-v1',
  true,
  'customer_provider_application_rpc',
  null
);

insert into public.audit_events (
  actor_id, action, object_type, object_id, reason, metadata
) values (
  '00000000-0000-0000-0000-000000010302',
  'customer.provider_application_submitted',
  'provider_profile',
  '00000000-0000-0000-0000-000000010302',
  'Customer submitted closed-pilot provider application',
  '{}'::jsonb
);

do $$
declare
  v_password text := pg_catalog.replace(pg_catalog.gen_random_uuid()::pg_catalog.text, '-', '');
begin
  execute pg_catalog.format(
    'create role ticket10b_concurrency_login login password %L',
    v_password
  );
  perform pg_catalog.set_config(
    'lekkadeall.ticket10b_concurrency_password',
    v_password,
    false
  );
end;
$$;

grant authenticated to ticket10b_concurrency_login;

commit;

begin;

create extension if not exists dblink with schema extensions;
set local search_path = public, extensions, auth;

select plan(76);

select is(
  extensions.dblink_connect(
    'ticket10b_a',
    pg_catalog.format(
      'hostaddr=%s port=%s dbname=%L user=%L password=%L',
      pg_catalog.inet_server_addr(),
      pg_catalog.current_setting('port'),
      pg_catalog.current_database(),
      'ticket10b_concurrency_login',
      pg_catalog.current_setting('lekkadeall.ticket10b_concurrency_password')
    )
  ),
  'OK',
  'first independent eligibility-review session connects'
);

select is(
  extensions.dblink_connect(
    'ticket10b_b',
    pg_catalog.format(
      'hostaddr=%s port=%s dbname=%L user=%L password=%L',
      pg_catalog.inet_server_addr(),
      pg_catalog.current_setting('port'),
      pg_catalog.current_database(),
      'ticket10b_concurrency_login',
      pg_catalog.current_setting('lekkadeall.ticket10b_concurrency_password')
    )
  ),
  'OK',
  'second independent eligibility-review session connects'
);

create temporary table ticket10b_concurrency_results (
  connection_name text primary key,
  result_status text,
  error_message text
) on commit drop;

insert into ticket10b_concurrency_results (connection_name) values ('a'), ('b');

do $$
begin
  perform pg_catalog.set_config('lekkadeall.ticket10b_concurrency_password', '', false);
  perform extensions.dblink_exec('ticket10b_a', 'set role authenticated');
  perform extensions.dblink_exec('ticket10b_b', 'set role authenticated');
  perform extensions.dblink_exec(
    'ticket10b_a',
    'set request.jwt.claim.sub = ''00000000-0000-0000-0000-000000010301'''
  );
  perform extensions.dblink_exec(
    'ticket10b_b',
    'set request.jwt.claim.sub = ''00000000-0000-0000-0000-000000010301'''
  );
  perform extensions.dblink_exec(
    'ticket10b_a',
    'set request.jwt.claims = ''{"sub":"00000000-0000-0000-0000-000000010301","role":"authenticated","aal":"aal2"}'''
  );
  perform extensions.dblink_exec(
    'ticket10b_b',
    'set request.jwt.claims = ''{"sub":"00000000-0000-0000-0000-000000010301","role":"authenticated","aal":"aal2"}'''
  );
  perform extensions.dblink_exec('ticket10b_a', 'begin');
end;
$$;

select is(
  extensions.dblink_send_query(
    'ticket10b_a',
    $query$
      select public.admin_transition_provider_marketplace_review(
        '00000000-0000-0000-0000-000000010302',
        'approve_manual_pilot',
        'pending',
        '00000000-0000-0000-0000-000000010381'
      )
    $query$
  ),
  1,
  'first review decision starts asynchronously'
);

update ticket10b_concurrency_results as result
set result_status = remote.result_status
from extensions.dblink_get_result('ticket10b_a', false) as remote(result_status text)
where result.connection_name = 'a';

select is(
  extensions.dblink_send_query(
    'ticket10b_b',
    $query$
      select public.admin_transition_provider_marketplace_review(
        '00000000-0000-0000-0000-000000010302',
        'reject',
        'pending',
        '00000000-0000-0000-0000-000000010382'
      )
    $query$
  ),
  1,
  'conflicting review decision starts while the first transaction is open'
);

do $$
begin
  perform extensions.dblink_exec('ticket10b_a', 'commit');
end;
$$;

update ticket10b_concurrency_results as result
set result_status = remote.result_status
from extensions.dblink_get_result('ticket10b_b', false) as remote(result_status text)
where result.connection_name = 'b';

update ticket10b_concurrency_results
set error_message = extensions.dblink_error_message('ticket10b_b')
where connection_name = 'b';

select is(
  (select result_status from ticket10b_concurrency_results where connection_name = 'a'),
  'approved',
  'one concurrent decision succeeds'
);

select is(
  (
    select count(*)
    from ticket10b_concurrency_results
    where connection_name = 'b'
      and error_message is not null
      and error_message <> 'OK'
  ),
  1::bigint,
  'conflicting concurrent decision fails closed'
);

select is(
  (
    select pg_catalog.split_part(error_message, E'\n', 1)
    from ticket10b_concurrency_results
    where connection_name = 'b'
  ),
  'ERROR:  Provider marketplace review is unavailable',
  'concurrent stale decision returns the fixed privacy-safe error'
);

select is(
  extensions.dblink_disconnect('ticket10b_a'),
  'OK',
  'first eligibility-review session disconnects'
);

select is(
  extensions.dblink_disconnect('ticket10b_b'),
  'OK',
  'second eligibility-review session disconnects'
);

select is(
  (
    select count(*)
    from private.provider_eligibility_decisions
    where provider_id = '00000000-0000-0000-0000-000000010302'
  ),
  1::bigint,
  'concurrent decisions create exactly one decision row'
);

select is(
  (
    select count(*)
    from public.audit_events
    where action = 'admin.provider_marketplace_approved'
      and metadata ->> 'provider_id' = '00000000-0000-0000-0000-000000010302'
  ),
  1::bigint,
  'concurrent decisions create exactly one audit event'
);

-- Transactional fixtures for authority, transition, privacy and capability tests.
\ir rls_test_seed.inc

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000010311', 'ticket10b-provider-a@lekkadeall.test', '{}'),
  ('00000000-0000-0000-0000-000000010312', 'ticket10b-provider-b@lekkadeall.test', '{}'),
  ('00000000-0000-0000-0000-000000010313', 'ticket10b-restricted@lekkadeall.test', '{}'),
  ('00000000-0000-0000-0000-000000010314', 'ticket10b-missing-app@lekkadeall.test', '{}'),
  ('00000000-0000-0000-0000-000000010315', 'ticket10b-inactive-admin@lekkadeall.test', '{}');

set local lekkadeall.allow_privileged_profile_update = 'on';

update public.profiles
set role = case
      when id = '00000000-0000-0000-0000-000000010315' then 'admin'::public.user_role
      else 'provider'::public.user_role
    end,
    account_status = case
      when id in (
        '00000000-0000-0000-0000-000000010313',
        '00000000-0000-0000-0000-000000010315'
      ) then 'restricted'
      else 'active'
    end
where id in (
  '00000000-0000-0000-0000-000000010311',
  '00000000-0000-0000-0000-000000010312',
  '00000000-0000-0000-0000-000000010313',
  '00000000-0000-0000-0000-000000010314',
  '00000000-0000-0000-0000-000000010315'
);

set local lekkadeall.allow_privileged_profile_update = 'off';

insert into public.provider_profiles (
  user_id, business_name, service_radius_km, verification_status, review_status
) values
  ('00000000-0000-0000-0000-000000010311', 'Ticket 10B Provider A', 20, 'not_started', 'pending'),
  ('00000000-0000-0000-0000-000000010312', 'Ticket 10B Provider B', 20, 'manual_review', 'pending'),
  ('00000000-0000-0000-0000-000000010313', 'Ticket 10B Restricted', 20, 'not_started', 'pending'),
  ('00000000-0000-0000-0000-000000010314', 'Ticket 10B Missing App', 20, 'not_started', 'pending');

insert into public.provider_services (
  provider_id, category_id, description, base_price_minor, active
) values
  ('00000000-0000-0000-0000-000000010311', '00000000-0000-0000-0000-000000000100', null, null, false),
  ('00000000-0000-0000-0000-000000010312', '00000000-0000-0000-0000-000000000100', null, null, false),
  ('00000000-0000-0000-0000-000000010313', '00000000-0000-0000-0000-000000000100', null, null, false);

insert into public.consents (
  user_id, purpose, policy_version, granted, source, withdrawn_at
)
select
  actor_id,
  'provider_application_terms',
  'provider-application-v1',
  true,
  'customer_provider_application_rpc',
  null
from (values
  ('00000000-0000-0000-0000-000000010311'::uuid),
  ('00000000-0000-0000-0000-000000010312'::uuid),
  ('00000000-0000-0000-0000-000000010313'::uuid)
) as applicant(actor_id);

insert into public.audit_events (
  actor_id, action, object_type, object_id, reason, metadata
)
select
  actor_id,
  'customer.provider_application_submitted',
  'provider_profile',
  actor_id::text,
  'Customer submitted closed-pilot provider application',
  '{}'::jsonb
from (values
  ('00000000-0000-0000-0000-000000010311'::uuid),
  ('00000000-0000-0000-0000-000000010312'::uuid),
  ('00000000-0000-0000-0000-000000010313'::uuid)
) as applicant(actor_id);

select has_function(
  'public',
  'admin_transition_provider_marketplace_review',
  array['uuid', 'text', 'text', 'uuid'],
  'one narrow marketplace-review transition RPC exists'
);

select function_returns(
  'public',
  'admin_transition_provider_marketplace_review',
  array['uuid', 'text', 'text', 'uuid'],
  'text',
  'marketplace-review RPC returns only a coarse status'
);

select ok(
  (
    select p.prosecdef
    from pg_catalog.pg_proc as p
    join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'admin_transition_provider_marketplace_review'
  ),
  'marketplace-review RPC is SECURITY DEFINER'
);

select is(
  (
    select pg_catalog.array_to_string(p.proconfig, ',')
    from pg_catalog.pg_proc as p
    join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'admin_transition_provider_marketplace_review'
  ),
  'search_path=pg_catalog',
  'marketplace-review RPC fixes search_path to pg_catalog'
);

select ok(
  pg_catalog.strpos(
    pg_catalog.lower(
      pg_catalog.pg_get_functiondef(
        'public.admin_transition_provider_marketplace_review(uuid,text,text,uuid)'::regprocedure
      )
    ),
    'select *'
  ) = 0,
  'marketplace-review RPC contains no SELECT star'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.admin_transition_provider_marketplace_review(uuid,text,text,uuid)',
    'EXECUTE'
  ),
  'authenticated may execute the actor-derived review RPC'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.admin_transition_provider_marketplace_review(uuid,text,text,uuid)',
    'EXECUTE'
  ),
  'anon cannot execute the review RPC'
);

select ok(
  not has_function_privilege(
    'service_role',
    'public.admin_transition_provider_marketplace_review(uuid,text,text,uuid)',
    'EXECUTE'
  ),
  'service role cannot execute the review RPC'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.admin_set_provider_review_status(uuid,text,text)',
    'EXECUTE'
  ),
  'legacy provider-review RPC is revoked from authenticated'
);

select ok(
  not has_function_privilege(
    'service_role',
    'public.admin_set_provider_verification_status(uuid,public.verification_status,text,boolean,text)',
    'EXECUTE'
  ),
  'legacy provider-verification RPC is revoked from service role'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.identity_verifications',
    'SELECT'
  ),
  'authenticated cannot read raw identity-verification rows'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'private.provider_marketplace_eligibility',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'private.provider_eligibility_decisions',
    'SELECT'
  ),
  'browser role cannot read eligibility state or decision internals'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'private.provider_marketplace_eligibility',
    'INSERT'
  )
  and not has_table_privilege(
    'authenticated',
    'private.provider_marketplace_eligibility',
    'UPDATE'
  )
  and not has_table_privilege(
    'authenticated',
    'private.provider_marketplace_eligibility',
    'DELETE'
  )
  and not has_table_privilege(
    'authenticated',
    'private.provider_eligibility_decisions',
    'INSERT'
  )
  and not has_table_privilege(
    'authenticated',
    'private.provider_eligibility_decisions',
    'UPDATE'
  )
  and not has_table_privilege(
    'authenticated',
    'private.provider_eligibility_decisions',
    'DELETE'
  ),
  'browser role cannot mutate eligibility state or decisions'
);

select ok(
  not has_column_privilege(
    'authenticated',
    'public.provider_profiles',
    'verification_reference',
    'SELECT'
  )
  and not has_column_privilege(
    'authenticated',
    'public.provider_profiles',
    'bank_name_match',
    'SELECT'
  )
  and not has_column_privilege(
    'authenticated',
    'public.provider_profiles',
    'reviewed_by',
    'SELECT'
  ),
  'verification and reviewer details remain outside browser reads'
);

select is(
  (
    select status
    from private.provider_marketplace_eligibility
    where provider_id = '00000000-0000-0000-0000-000000010311'
  ),
  'pending',
  'new provider application begins pending'
);

select is(
  public.is_approved_provider('00000000-0000-0000-0000-000000010311'),
  false,
  'pending application is not marketplace eligible'
);

-- Signed-out, AAL1, ordinary, inactive-admin and service-role paths fail closed.
set local role authenticated;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '{"role":"authenticated","aal":"aal2"}';

select throws_ok(
  $$select public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000010311',
    'approve_manual_pilot',
    'pending',
    '00000000-0000-0000-0000-000000010351'
  )$$,
  '42501',
  'Provider marketplace review is unavailable',
  'signed-out review is rejected'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000099","role":"authenticated","aal":"aal1","user_metadata":{"role":"admin"}}';

select throws_ok(
  $$select public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000010311',
    'approve_manual_pilot',
    'pending',
    '00000000-0000-0000-0000-000000010352'
  )$$,
  '42501',
  'Provider marketplace review is unavailable',
  'AAL1 admin session is rejected'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2","user_metadata":{"role":"admin"}}';

select throws_ok(
  $$select public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000010311',
    'approve_manual_pilot',
    'pending',
    '00000000-0000-0000-0000-000000010353'
  )$$,
  '42501',
  'Provider marketplace review is unavailable',
  'forged metadata cannot make a customer an admin reviewer'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010315';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000010315","role":"authenticated","aal":"aal2"}';

select throws_ok(
  $$select public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000010311',
    'approve_manual_pilot',
    'pending',
    '00000000-0000-0000-0000-000000010354'
  )$$,
  '42501',
  'Provider marketplace review is unavailable',
  'inactive admin reviewer is rejected'
);

reset role;

set local role service_role;

select throws_ok(
  $$select public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000010311',
    'approve_manual_pilot',
    'pending',
    '00000000-0000-0000-0000-000000010355'
  )$$,
  '42501',
  'permission denied for function admin_transition_provider_marketplace_review',
  'service role has no reviewer execution path'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000099","role":"authenticated","aal":"aal2"}';

select throws_ok(
  $$select public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000010314',
    'approve_manual_pilot',
    'pending',
    '00000000-0000-0000-0000-000000010356'
  )$$,
  '42501',
  'Provider marketplace review is unavailable',
  'provider without application evidence is rejected'
);

select throws_ok(
  $$select public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000000001',
    'approve_manual_pilot',
    'pending',
    '00000000-0000-0000-0000-000000010350'
  )$$,
  '42501',
  'Provider marketplace review is unavailable',
  'wrong-role target is rejected'
);

select throws_ok(
  $$select public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000019999',
    'approve_manual_pilot',
    'pending',
    '00000000-0000-0000-0000-000000010349'
  )$$,
  '42501',
  'Provider marketplace review is unavailable',
  'missing provider profile is rejected'
);

select throws_ok(
  $$select public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000000099',
    'approve_manual_pilot',
    'pending',
    '00000000-0000-0000-0000-000000010357'
  )$$,
  '42501',
  'Provider marketplace review is unavailable',
  'reviewer cannot approve themselves'
);

select throws_ok(
  $$select public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000010311',
    'approve_verified_identity',
    'pending',
    '00000000-0000-0000-0000-000000010358'
  )$$,
  '42501',
  'Provider marketplace review is unavailable',
  'verified-identity basis fails closed without authoritative evidence'
);

select throws_ok(
  $$select public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000010313',
    'approve_manual_pilot',
    'pending',
    '00000000-0000-0000-0000-000000010359'
  )$$,
  '42501',
  'Provider marketplace review is unavailable',
  'restricted provider cannot receive manual-pilot eligibility'
);

select is(
  public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000010311',
    'approve_manual_pilot',
    'pending',
    '00000000-0000-0000-0000-000000010360'
  ),
  'approved',
  'AAL2 active admin approves a valid pending provider'
);

reset role;

select is(
  (
    select status || '|' || basis || '|' || policy_version
    from private.provider_marketplace_eligibility
    where provider_id = '00000000-0000-0000-0000-000000010311'
  ),
  'approved|manual_pilot|provider-eligibility-v1',
  'manual-pilot decision is explicit and policy-versioned'
);

select ok(
  (
    select expires_at > now() + interval '29 days'
       and expires_at <= now() + interval '31 days'
    from private.provider_marketplace_eligibility
    where provider_id = '00000000-0000-0000-0000-000000010311'
  ),
  'manual-pilot expiry is short and server-owned'
);

select is(
  (
    select verification_status::text
    from public.provider_profiles
    where user_id = '00000000-0000-0000-0000-000000010311'
  ),
  'not_started',
  'manual-pilot approval does not claim identity verification'
);

select is(
  (
    select review_status
    from public.provider_profiles
    where user_id = '00000000-0000-0000-0000-000000010311'
  ),
  'approved',
  'coarse provider review state mirrors the protected decision'
);

select is(
  public.is_approved_provider('00000000-0000-0000-0000-000000010311'),
  true,
  'manual-pilot provider satisfies the strengthened eligibility predicate'
);

select is(
  (
    select count(*)
    from private.provider_eligibility_decisions
    where provider_id = '00000000-0000-0000-0000-000000010311'
  ),
  1::bigint,
  'approval creates exactly one decision row'
);

select is(
  (
    select count(*)
    from public.audit_events
    where actor_id = '00000000-0000-0000-0000-000000000099'
      and action = 'admin.provider_marketplace_approved'
      and metadata ->> 'provider_id' = '00000000-0000-0000-0000-000000010311'
  ),
  1::bigint,
  'approval creates exactly one fixed audit event'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000099","role":"authenticated","aal":"aal2"}';

select is(
  public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000010311',
    'approve_manual_pilot',
    'pending',
    '00000000-0000-0000-0000-000000010360'
  ),
  'approved',
  'exact replay returns the prior result'
);

reset role;

select is(
  (
    select count(*)
    from private.provider_eligibility_decisions
    where provider_id = '00000000-0000-0000-0000-000000010311'
  ),
  1::bigint,
  'exact replay creates no duplicate decision'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000099","role":"authenticated","aal":"aal2"}';

select throws_ok(
  $$select public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000010311',
    'suspend',
    'approved',
    '00000000-0000-0000-0000-000000010360'
  )$$,
  '23505',
  'Provider marketplace review is unavailable',
  'divergent idempotency-key reuse fails closed'
);

select throws_ok(
  $$select public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000010311',
    'reject',
    'pending',
    '00000000-0000-0000-0000-000000010361'
  )$$,
  '40001',
  'Provider marketplace review is unavailable',
  'stale expected state fails closed'
);

reset role;

-- An eligible provider may activate the approved category and read open work.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010311';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000010311","role":"authenticated","aal":"aal1"}';

select lives_ok(
  $$update public.provider_services
    set active = true,
        description = 'Approved test service'
    where provider_id = '00000000-0000-0000-0000-000000010311'$$,
  'eligible provider can activate an owned service'
);

select ok(
  (
    select count(*)
    from public.service_requests
    where status = 'open'
  ) > 0,
  'eligible provider can discover open requests'
);

reset role;
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '';

-- Build deterministic historical capability rows as the database owner. The
-- runtime functions still perform fresh actor-derived eligibility checks.
set local lekkadeall.allow_marketplace_state_transition = 'on';

insert into public.service_requests (
  id, customer_id, category_id, title, description, suburb, city,
  requested_start, budget_minor, status, closes_at
) values
  (
    '00000000-0000-0000-0000-000000010371',
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000100',
    'Ticket 10B bid acceptance',
    'Safe request for Ticket 10B bid acceptance revocation.',
    'Die Bult', 'Potchefstroom', now() + interval '4 days', 10000,
    'open', now() + interval '2 days'
  ),
  (
    '00000000-0000-0000-0000-000000010372',
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000100',
    'Ticket 10B booking progression',
    'Safe request for Ticket 10B booking revocation.',
    'Die Bult', 'Potchefstroom', now() + interval '4 days', 12000,
    'awarded', now() + interval '2 days'
  ),
  (
    '00000000-0000-0000-0000-000000010373',
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000100',
    'Ticket 10B payout eligibility',
    'Safe request for Ticket 10B payout revocation.',
    'Die Bult', 'Potchefstroom', now() + interval '4 days', 14000,
    'awarded', now() + interval '2 days'
  );

insert into public.bids (
  id, request_id, provider_id, amount_minor, proposed_start, status, expires_at
) values
  (
    '00000000-0000-0000-0000-000000010374',
    '00000000-0000-0000-0000-000000010371',
    '00000000-0000-0000-0000-000000010311',
    10000, now() + interval '4 days', 'submitted', now() + interval '2 days'
  ),
  (
    '00000000-0000-0000-0000-000000010375',
    '00000000-0000-0000-0000-000000010372',
    '00000000-0000-0000-0000-000000010311',
    12000, now() + interval '4 days', 'accepted', now() + interval '2 days'
  ),
  (
    '00000000-0000-0000-0000-000000010376',
    '00000000-0000-0000-0000-000000010373',
    '00000000-0000-0000-0000-000000010311',
    14000, now() + interval '4 days', 'accepted', now() + interval '2 days'
  );

insert into public.bookings (
  id, public_reference, request_id, bid_id, customer_id, provider_id,
  service_amount_minor, platform_fee_minor, scheduled_start, status,
  completion_confirmed_at
) values
  (
    '00000000-0000-0000-0000-000000010377', 'TICKET-10B-PROGRESSION',
    '00000000-0000-0000-0000-000000010372',
    '00000000-0000-0000-0000-000000010375',
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000010311',
    12000, 0, now() + interval '4 days', 'scheduled', null
  ),
  (
    '00000000-0000-0000-0000-000000010378', 'TICKET-10B-PAYOUT',
    '00000000-0000-0000-0000-000000010373',
    '00000000-0000-0000-0000-000000010376',
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000010311',
    14000, 0, now() + interval '4 days', 'completed', now()
  );

insert into private.service_request_addresses (
  request_id, precise_address_ciphertext
) values (
  '00000000-0000-0000-0000-000000010372',
  'enc:ticket10b-private-fixture'
);

set local lekkadeall.allow_marketplace_state_transition = 'off';

set local lekkadeall.allow_trusted_payment_update = 'on';

insert into public.payments (
  id, booking_id, provider_name, status, amount_minor, payment_method,
  release_paused, funded_at, paid_at, refunded_minor, release_status
) values (
  '00000000-0000-0000-0000-000000010379',
  '00000000-0000-0000-0000-000000010378',
  'mock', 'paid', 14000, 'sandbox_online', false, now(), now(), 0, 'pending'
);

set local lekkadeall.allow_trusted_payment_update = 'off';

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000099","role":"authenticated","aal":"aal2"}';

select is(
  public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000010311',
    'suspend',
    'approved',
    '00000000-0000-0000-0000-000000010362'
  ),
  'suspended',
  'active approval can be suspended'
);

reset role;

create function pg_temp.update_suspended_provider_service()
returns pg_catalog.int8
language plpgsql
as $$
declare
  v_rows pg_catalog.int8;
begin
  update public.provider_services
  set description = 'Suspended mutation attempt'
  where provider_id = '00000000-0000-0000-0000-000000010311';

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

select is(
  public.is_approved_provider('00000000-0000-0000-0000-000000010311'),
  false,
  'suspension immediately removes effective eligibility'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010311';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000010311","role":"authenticated","aal":"aal1"}';

select is(
  (
    select count(*)
    from public.service_requests
    where status = 'open'
  ),
  0::bigint,
  'suspended provider immediately loses open-request discovery'
);

select throws_ok(
  $$select public.provider_submit_bid(
    '00000000-0000-0000-0000-000000010371',
    9000,
    now() + interval '4 days',
    null,
    '{}'::text[],
    now() + interval '1 day'
  )$$,
  '42501',
  'Only active approved providers may submit bids',
  'suspended provider cannot submit a new bid'
);

select is(
  pg_temp.update_suspended_provider_service(),
  0::pg_catalog.int8,
  'suspended provider cannot manage services'
);

select throws_ok(
  $$select public.reveal_confirmed_booking_address(
    '00000000-0000-0000-0000-000000010377'
  )$$,
  '42501',
  'Provider marketplace capability is unavailable',
  'suspended provider cannot reveal an exact address'
);

select throws_ok(
  $$select public.booking_mark_in_progress(
    '00000000-0000-0000-0000-000000010377'
  )$$,
  '42501',
  'Provider marketplace capability is unavailable',
  'suspended provider cannot progress a booking'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal1"}';

select throws_ok(
  $$select public.customer_accept_bid(
    '00000000-0000-0000-0000-000000010374'
  )$$,
  '42501',
  'Bid provider is no longer active and approved',
  'suspended provider bid cannot be accepted'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010311';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000010311","role":"authenticated","aal":"aal1"}';

select lives_ok(
  $$select public.provider_withdraw_bid(
    '00000000-0000-0000-0000-000000010374',
    'Risk-reducing withdrawal while suspended'
  )$$,
  'suspended provider may withdraw an owned submitted bid'
);

reset role;

select ok(
  'provider_not_eligible' = any(
    private.payout_release_blockers(
      '00000000-0000-0000-0000-000000010379',
      false
    )
  ),
  'payout release recomputes and blocks current ineligibility'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000099","role":"authenticated","aal":"aal2"}';

select is(
  public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000010311',
    'reinstate_manual_pilot',
    'suspended',
    '00000000-0000-0000-0000-000000010363'
  ),
  'approved',
  'suspended provider requires an explicit new reinstate decision'
);

select is(
  public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000010311',
    'expire',
    'approved',
    '00000000-0000-0000-0000-000000010364'
  ),
  'expired',
  'approved provider can be explicitly expired'
);

reset role;

select is(
  public.is_approved_provider('00000000-0000-0000-0000-000000010311'),
  false,
  'expired provider is not marketplace eligible'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000099","role":"authenticated","aal":"aal2"}';

select is(
  public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000010311',
    'renew_manual_pilot',
    'expired',
    '00000000-0000-0000-0000-000000010365'
  ),
  'approved',
  'expired approval requires a fresh renewal decision'
);

select is(
  public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000010312',
    'reject',
    'pending',
    '00000000-0000-0000-0000-000000010366'
  ),
  'rejected',
  'pending provider can be rejected'
);

select throws_ok(
  $$select public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000010312',
    'approve_manual_pilot',
    'rejected',
    '00000000-0000-0000-0000-000000010367'
  )$$,
  '42501',
  'Provider marketplace review is unavailable',
  'rejected provider cannot shortcut directly to approved'
);

select is(
  public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000010312',
    'reopen',
    'rejected',
    '00000000-0000-0000-0000-000000010368'
  ),
  'pending',
  'rejected provider requires explicit reopen to pending'
);

reset role;

-- Audit failure must roll back the state, decision and coarse review mirror.
create function pg_temp.reject_ticket10b_audit()
returns trigger
language plpgsql
as $$
begin
  if new.action = 'admin.provider_marketplace_approved'
     and new.metadata ->> 'provider_id' = '00000000-0000-0000-0000-000000010312' then
    raise exception 'forced-ticket10b-audit-failure';
  end if;
  return new;
end;
$$;

create trigger reject_ticket10b_audit
before insert on public.audit_events
for each row execute function pg_temp.reject_ticket10b_audit();

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000099","role":"authenticated","aal":"aal2"}';

select throws_ok(
  $$select public.admin_transition_provider_marketplace_review(
    '00000000-0000-0000-0000-000000010312',
    'approve_manual_pilot',
    'pending',
    '00000000-0000-0000-0000-000000010369'
  )$$,
  'P0001',
  'forced-ticket10b-audit-failure',
  'audit failure aborts marketplace approval'
);

reset role;
drop trigger reject_ticket10b_audit on public.audit_events;

select is(
  (
    select status
    from private.provider_marketplace_eligibility
    where provider_id = '00000000-0000-0000-0000-000000010312'
  ),
  'pending',
  'audit failure rolls back current eligibility state'
);

select is(
  (
    select review_status
    from public.provider_profiles
    where user_id = '00000000-0000-0000-0000-000000010312'
  ),
  'pending',
  'audit failure rolls back coarse review state'
);

select is(
  (
    select count(*)
    from private.provider_eligibility_decisions
    where provider_id = '00000000-0000-0000-0000-000000010312'
      and action = 'approve_manual_pilot'
  ),
  0::bigint,
  'audit failure rolls back the decision ledger insert'
);

select is(
  pg_catalog.current_setting(
    'lekkadeall.allow_privileged_provider_profile_update',
    true
  ),
  'off',
  'privileged provider-profile flag is disabled after failure'
);

create function pg_temp.try_mutate_eligibility_decision()
returns boolean
language plpgsql
as $$
begin
  update private.provider_eligibility_decisions
  set reason_code = 'tampered'
  where provider_id = '00000000-0000-0000-0000-000000010311';
  return true;
exception
  when others then return false;
end;
$$;

select is(
  pg_temp.try_mutate_eligibility_decision(),
  false,
  'eligibility decision ledger is append-only'
);

select ok(
  not exists (
    select 1
    from public.audit_events
    where action like 'admin.provider_marketplace_%'
      and (
        metadata ? 'verification_reference'
        or metadata ? 'bank_name_match'
        or metadata ? 'evidence'
        or metadata ? 'failure_codes'
        or metadata ? 'reviewer_id'
      )
  ),
  'eligibility audit metadata contains no restricted identity or reviewer detail'
);

select * from finish();

rollback;

-- Remove the committed two-session fixture and ephemeral login.
begin;
alter table public.audit_events disable trigger audit_events_append_only;
delete from public.audit_events
where actor_id in (
  '00000000-0000-0000-0000-000000010301',
  '00000000-0000-0000-0000-000000010302'
)
or metadata ->> 'provider_id' = '00000000-0000-0000-0000-000000010302';
alter table public.audit_events enable trigger audit_events_append_only;

alter table private.provider_eligibility_decisions
  disable trigger provider_eligibility_decisions_append_only;
alter table public.consents disable trigger protect_provider_application_terms;
delete from private.provider_marketplace_eligibility
where provider_id = '00000000-0000-0000-0000-000000010302';
delete from private.provider_eligibility_decisions
where provider_id = '00000000-0000-0000-0000-000000010302';
set local lekkadeall.allow_privileged_provider_profile_update = 'on';
update public.provider_profiles
set reviewed_by = null,
    reviewed_at = null
where user_id = '00000000-0000-0000-0000-000000010302';
set local lekkadeall.allow_privileged_provider_profile_update = 'off';
delete from auth.users
where id in (
  '00000000-0000-0000-0000-000000010301',
  '00000000-0000-0000-0000-000000010302'
);
alter table public.consents enable trigger protect_provider_application_terms;
alter table private.provider_eligibility_decisions
  enable trigger provider_eligibility_decisions_append_only;
delete from public.service_categories
where id = '00000000-0000-0000-0000-000000010390';
commit;

do $$
begin
  perform pg_catalog.set_config(
    'lekkadeall.ticket10b_concurrency_password',
    '',
    false
  );
end;
$$;

drop role ticket10b_concurrency_login;
