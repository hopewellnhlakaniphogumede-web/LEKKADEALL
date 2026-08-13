create extension if not exists pgtap with schema extensions;

-- Commit only the concurrency fixture before starting two genuine sessions.
begin;

insert into auth.users (id, email, raw_user_meta_data) values (
  '00000000-0000-0000-0000-000000010211',
  'ticket10a-concurrent@lekkadeall.test',
  '{}'::jsonb
);

insert into public.service_categories (id, slug, name, active) values (
  '00000000-0000-0000-0000-000000010293',
  'ticket10a-concurrent',
  'Ticket 10A Concurrent',
  true
);

do $$
declare
  v_password text := pg_catalog.replace(pg_catalog.gen_random_uuid()::pg_catalog.text, '-', '');
begin
  execute pg_catalog.format(
    'create role ticket10a_concurrency_login login password %L',
    v_password
  );
  perform pg_catalog.set_config(
    'lekkadeall.ticket10a_concurrency_password',
    v_password,
    false
  );
end;
$$;

grant authenticated to ticket10a_concurrency_login;

commit;

begin;

create extension if not exists dblink with schema extensions;
set local search_path = public, extensions, auth;

select plan(85);

create temporary table ticket10a_concurrency_results (
  connection_name text primary key,
  result_status text,
  error_message text
) on commit drop;

insert into ticket10a_concurrency_results (connection_name) values ('a'), ('b');

select is(
  extensions.dblink_connect(
    'ticket10a_a',
    pg_catalog.format(
      'hostaddr=%s port=%s dbname=%L user=%L password=%L',
      pg_catalog.inet_server_addr(),
      pg_catalog.current_setting('port'),
      pg_catalog.current_database(),
      'ticket10a_concurrency_login',
      pg_catalog.current_setting('lekkadeall.ticket10a_concurrency_password')
    )
  ),
  'OK',
  'first independent provider-application session connects'
);

select is(
  extensions.dblink_connect(
    'ticket10a_b',
    pg_catalog.format(
      'hostaddr=%s port=%s dbname=%L user=%L password=%L',
      pg_catalog.inet_server_addr(),
      pg_catalog.current_setting('port'),
      pg_catalog.current_database(),
      'ticket10a_concurrency_login',
      pg_catalog.current_setting('lekkadeall.ticket10a_concurrency_password')
    )
  ),
  'OK',
  'second independent provider-application session connects'
);

do $$
begin
  perform pg_catalog.set_config(
    'lekkadeall.ticket10a_concurrency_password',
    '',
    false
  );
  perform extensions.dblink_exec('ticket10a_a', 'set role authenticated');
  perform extensions.dblink_exec('ticket10a_b', 'set role authenticated');
  perform extensions.dblink_exec(
    'ticket10a_a',
    'set request.jwt.claim.sub = ''00000000-0000-0000-0000-000000010211'''
  );
  perform extensions.dblink_exec(
    'ticket10a_b',
    'set request.jwt.claim.sub = ''00000000-0000-0000-0000-000000010211'''
  );
  perform extensions.dblink_exec('ticket10a_a', 'begin');
end;
$$;

select is(
  extensions.dblink_send_query(
    'ticket10a_a',
    $query$
      select public.customer_submit_provider_application(
        'Concurrent Services',
        20,
        array['00000000-0000-0000-0000-000000010293'::pg_catalog.uuid],
        'provider-application-v1'
      )
    $query$
  ),
  1,
  'first provider application starts asynchronously'
);

update ticket10a_concurrency_results as result
set result_status = remote.result_status
from extensions.dblink_get_result('ticket10a_a', false) as remote(result_status text)
where result.connection_name = 'a';

update ticket10a_concurrency_results
set error_message = extensions.dblink_error_message('ticket10a_a')
where connection_name = 'a';

select is(
  extensions.dblink_send_query(
    'ticket10a_b',
    $query$
      select public.customer_submit_provider_application(
        'Concurrent Services',
        20,
        array['00000000-0000-0000-0000-000000010293'::pg_catalog.uuid],
        'provider-application-v1'
      )
    $query$
  ),
  1,
  'second provider application starts while the first role transition is uncommitted'
);

do $$
begin
  perform extensions.dblink_exec('ticket10a_a', 'commit');
end;
$$;

update ticket10a_concurrency_results as result
set result_status = remote.result_status
from extensions.dblink_get_result('ticket10a_b', false) as remote(result_status text)
where result.connection_name = 'b';

update ticket10a_concurrency_results
set error_message = extensions.dblink_error_message('ticket10a_b')
where connection_name = 'b';

select is(
  (select result_status from ticket10a_concurrency_results where connection_name = 'a'),
  'pending',
  'first concurrent application returns pending'
);

select is(
  (select result_status from ticket10a_concurrency_results where connection_name = 'b'),
  'pending',
  'second concurrent application is an idempotent pending replay'
);

select is(
  extensions.dblink_disconnect('ticket10a_a'),
  'OK',
  'first provider-application session disconnects'
);

select is(
  extensions.dblink_disconnect('ticket10a_b'),
  'OK',
  'second provider-application session disconnects'
);

select is(
  (select role::text from public.profiles where id = '00000000-0000-0000-0000-000000010211'),
  'provider',
  'concurrent applications perform exactly one role transition'
);

select is(
  (select count(*) from public.provider_profiles where user_id = '00000000-0000-0000-0000-000000010211'),
  1::bigint,
  'concurrent applications create exactly one provider profile'
);

select is(
  (select count(*) from public.provider_services where provider_id = '00000000-0000-0000-0000-000000010211' and active = false),
  1::bigint,
  'concurrent applications create exactly one inactive category proposal'
);

select is(
  (select count(*) from public.consents where user_id = '00000000-0000-0000-0000-000000010211' and purpose = 'provider_application_terms'),
  1::bigint,
  'concurrent applications create exactly one terms record'
);

select is(
  (select count(*) from public.audit_events where actor_id = '00000000-0000-0000-0000-000000010211' and action = 'customer.provider_application_submitted'),
  1::bigint,
  'concurrent applications create exactly one audit event'
);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000010201', 'ticket10a-owner@lekkadeall.test', '{}'::jsonb),
  ('00000000-0000-0000-0000-000000010202', 'ticket10a-restricted@lekkadeall.test', '{}'::jsonb),
  ('00000000-0000-0000-0000-000000010203', 'ticket10a-suspended@lekkadeall.test', '{}'::jsonb),
  ('00000000-0000-0000-0000-000000010204', 'ticket10a-closed@lekkadeall.test', '{}'::jsonb),
  ('00000000-0000-0000-0000-000000010205', 'ticket10a-wrong-role@lekkadeall.test', '{}'::jsonb),
  ('00000000-0000-0000-0000-000000010206', 'ticket10a-history@lekkadeall.test', '{}'::jsonb),
  (
    '00000000-0000-0000-0000-000000010207',
    'ticket10a-hostile-metadata@lekkadeall.test',
    '{"role":"admin","provider":true,"review_status":"approved"}'::jsonb
  ),
  ('00000000-0000-0000-0000-000000010208', 'ticket10a-invalid@lekkadeall.test', '{}'::jsonb),
  ('00000000-0000-0000-0000-000000010209', 'ticket10a-rollback@lekkadeall.test', '{}'::jsonb),
  ('00000000-0000-0000-0000-000000010210', 'ticket10a-missing-profile@lekkadeall.test', '{}'::jsonb);

insert into public.service_categories (id, slug, name, active) values
  ('00000000-0000-0000-0000-000000010290', 'ticket10a-cleaning', 'Ticket 10A Cleaning', true),
  ('00000000-0000-0000-0000-000000010291', 'ticket10a-repairs', 'Ticket 10A Repairs', true),
  ('00000000-0000-0000-0000-000000010292', 'ticket10a-inactive', 'Ticket 10A Inactive', false);

set local lekkadeall.allow_privileged_profile_update = 'on';

update public.profiles
set account_status = 'restricted'
where id = '00000000-0000-0000-0000-000000010202';

update public.profiles
set account_status = 'suspended'
where id = '00000000-0000-0000-0000-000000010203';

update public.profiles
set account_status = 'closed'
where id = '00000000-0000-0000-0000-000000010204';

update public.profiles
set role = 'support'::public.user_role
where id = '00000000-0000-0000-0000-000000010205';

set local lekkadeall.allow_privileged_profile_update = 'off';

set local lekkadeall.allow_marketplace_state_transition = 'on';

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
  closes_at,
  published_at,
  awarded_at,
  cancelled_at
) values (
  '00000000-0000-0000-0000-000000010299',
  '00000000-0000-0000-0000-000000010206',
  '00000000-0000-0000-0000-000000010290',
  'Existing marketplace request',
  'This fixture proves that customer marketplace history blocks role conversion.',
  'Die Bult',
  'Potchefstroom',
  pg_catalog.now() + interval '7 days',
  60000,
  'open'::public.request_status,
  pg_catalog.now() + interval '3 days',
  pg_catalog.now(),
  null,
  null
);

set local lekkadeall.allow_marketplace_state_transition = 'off';

delete from public.profiles
where id = '00000000-0000-0000-0000-000000010210';

create function pg_temp.try_activate_provider_service(p_actor_id uuid)
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);

  update public.provider_services
  set active = true
  where provider_id = p_actor_id;

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_self_approve(p_actor_id uuid)
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);

  update public.provider_profiles
  set review_status = 'approved'
  where user_id = p_actor_id;

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_delete_provider_terms(p_actor_id uuid)
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  delete from public.consents
  where user_id = p_actor_id
    and purpose = 'provider_application_terms';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_duplicate_provider_terms(p_actor_id uuid)
returns boolean
language plpgsql
as $$
begin
  insert into public.consents (
    user_id, purpose, policy_version, granted, source, recorded_at, withdrawn_at
  ) values (
    p_actor_id,
    'provider_application_terms',
    'provider-application-v1',
    true,
    'customer_provider_application_rpc',
    pg_catalog.now(),
    null
  );

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.fail_ticket10a_audit()
returns trigger
language plpgsql
as $$
begin
  if new.action = 'customer.provider_application_submitted'
     and new.actor_id = '00000000-0000-0000-0000-000000010209'::uuid then
    raise exception 'Synthetic Ticket 10A audit failure';
  end if;

  return new;
end;
$$;

-- Function contract, fixed authority, narrow source, and restrictive grants.
select has_function(
  'public',
  'customer_submit_provider_application',
  array['text', 'numeric', 'uuid[]', 'text'],
  'trusted provider application function exists'
);

select function_returns(
  'public',
  'customer_submit_provider_application',
  array['text', 'numeric', 'uuid[]', 'text'],
  'text',
  'provider application returns only the fixed pending category'
);

select is(
  (
    select p.provolatile
    from pg_catalog.pg_proc as p
    join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'customer_submit_provider_application'
  ),
  'v'::"char",
  'provider application is volatile'
);

select is(
  (
    select p.prosecdef
    from pg_catalog.pg_proc as p
    join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'customer_submit_provider_application'
  ),
  true,
  'provider application is security definer'
);

select is(
  (
    select p.proconfig
    from pg_catalog.pg_proc as p
    join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'customer_submit_provider_application'
  ),
  array['search_path=pg_catalog']::text[],
  'provider application fixes search_path to pg_catalog'
);

select is(
  pg_catalog.strpos(
    pg_catalog.lower(pg_catalog.pg_get_functiondef(
      'public.customer_submit_provider_application(text,numeric,uuid[],text)'::regprocedure
    )),
    'select *'
  ),
  0,
  'provider application contains no SELECT star'
);

select is(
  pg_catalog.strpos(
    pg_catalog.lower(pg_catalog.pg_get_functiondef(
      'public.customer_submit_provider_application(text,numeric,uuid[],text)'::regprocedure
    )),
    'service_request_addresses'
  ),
  0,
  'provider application never reads the private exact-address boundary'
);

select ok(
  pg_catalog.strpos(
    pg_catalog.lower(pg_catalog.pg_get_functiondef(
      'public.customer_submit_provider_application(text,numeric,uuid[],text)'::regprocedure
    )),
    'private.service_request_public_field_violation'
  ) > 0,
  'provider application reuses the authoritative privacy-safe public-field validator'
);

select is(
  has_function_privilege(
    'public',
    'public.customer_submit_provider_application(text,numeric,uuid[],text)',
    'EXECUTE'
  ),
  false,
  'PUBLIC cannot execute provider application'
);

select is(
  has_function_privilege(
    'anon',
    'public.customer_submit_provider_application(text,numeric,uuid[],text)',
    'EXECUTE'
  ),
  false,
  'anon cannot execute provider application'
);

select is(
  has_function_privilege(
    'authenticated',
    'public.customer_submit_provider_application(text,numeric,uuid[],text)',
    'EXECUTE'
  ),
  true,
  'authenticated can execute provider application'
);

select is(
  has_function_privilege(
    'service_role',
    'public.customer_submit_provider_application(text,numeric,uuid[],text)',
    'EXECUTE'
  ),
  false,
  'service_role is not granted the actor-derived browser boundary'
);

select is(
  has_column_privilege('authenticated', 'public.provider_profiles', 'business_name', 'UPDATE')
  or has_column_privilege('authenticated', 'public.provider_profiles', 'bio', 'UPDATE')
  or has_column_privilege('authenticated', 'public.provider_profiles', 'service_radius_km', 'UPDATE'),
  false,
  'authenticated cannot directly edit provider application fields'
);

select is(
  has_table_privilege('authenticated', 'public.provider_profiles', 'SELECT'),
  false,
  'authenticated has no broad provider_profiles SELECT grant'
);

select is(
  has_column_privilege('authenticated', 'public.provider_profiles', 'business_name', 'SELECT'),
  true,
  'authenticated retains the reviewed narrow provider-profile projection'
);

select is(
  has_column_privilege('authenticated', 'public.provider_profiles', 'verification_reference', 'SELECT')
  or has_column_privilege('authenticated', 'public.provider_profiles', 'bank_name_match', 'SELECT')
  or has_column_privilege('authenticated', 'public.provider_profiles', 'reviewed_by', 'SELECT')
  or has_column_privilege('authenticated', 'public.provider_profiles', 'reviewed_at', 'SELECT'),
  false,
  'browser roles cannot select provider verification or review internals'
);

select is(
  has_table_privilege('authenticated', 'public.consents', 'INSERT'),
  false,
  'authenticated cannot forge provider terms records'
);

select is(
  has_table_privilege('authenticated', 'public.consents', 'UPDATE'),
  false,
  'authenticated cannot rewrite provider terms records'
);

select is(
  has_table_privilege('authenticated', 'public.consents', 'DELETE'),
  false,
  'authenticated cannot delete provider terms records'
);

select is(
  (
    select i.indisunique
    from pg_catalog.pg_index as i
    join pg_catalog.pg_class as c on c.oid = i.indexrelid
    join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'provider_application_terms_one_per_user_uidx'
  ),
  true,
  'provider terms have a replay-uniqueness index'
);

select is(
  (
    select t.tgenabled
    from pg_catalog.pg_trigger as t
    where t.tgrelid = 'public.consents'::regclass
      and t.tgname = 'protect_provider_application_terms'
      and not t.tgisinternal
  ),
  'O'::"char",
  'provider terms immutability trigger is enabled'
);

-- Authentication, input, actor-state, and marketplace-history failures.
set local role authenticated;
set local request.jwt.claim.sub = '';

select throws_ok(
  $$select public.customer_submit_provider_application(
    'Safe Services', 20,
    array['00000000-0000-0000-0000-000000010290'::uuid],
    'provider-application-v1'
  )$$,
  '42501',
  'Authentication is required to submit a provider application',
  'signed-out caller is rejected'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010208';

select throws_ok(
  $$select public.customer_submit_provider_application(
    ' ', 20,
    array['00000000-0000-0000-0000-000000010290'::uuid],
    'provider-application-v1'
  )$$,
  '22023',
  'Provider application is invalid',
  'blank business name is rejected'
);

select throws_ok(
  $$select public.customer_submit_provider_application(
    'Safe Services', 0,
    array['00000000-0000-0000-0000-000000010290'::uuid],
    'provider-application-v1'
  )$$,
  '22023',
  'Provider application is invalid',
  'invalid service radius is rejected'
);

select throws_ok(
  $$select public.customer_submit_provider_application(
    'Safe Services', 20,
    array['00000000-0000-0000-0000-000000010290'::uuid],
    'unsupported-version'
  )$$,
  '22023',
  'Provider application is invalid',
  'unsupported terms version is rejected'
);

select throws_ok(
  $$select public.customer_submit_provider_application(
    'Safe Services', 20,
    array[]::uuid[],
    'provider-application-v1'
  )$$,
  '22023',
  'Provider application is invalid',
  'empty category selection is rejected'
);

select throws_ok(
  $$select public.customer_submit_provider_application(
    'Safe Services', 20,
    array[
      '00000000-0000-0000-0000-000000010290'::uuid,
      '00000000-0000-0000-0000-000000010290'::uuid
    ],
    'provider-application-v1'
  )$$,
  '22023',
  'Provider application is invalid',
  'duplicate category selection is rejected'
);

select throws_ok(
  $$select public.customer_submit_provider_application(
    'Safe Services', 20,
    array['00000000-0000-0000-0000-000000010292'::uuid],
    'provider-application-v1'
  )$$,
  '22023',
  'Provider application is invalid',
  'inactive category selection is rejected'
);

select throws_ok(
  $$select public.customer_submit_provider_application(
    'See https://example.test',
    20,
    array['00000000-0000-0000-0000-000000010290'::uuid],
    'provider-application-v1'
  )$$,
  '22023',
  'Provider application is invalid',
  'unsafe eventual-public provider content is rejected by the authoritative validator'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010202';
select throws_ok(
  $$select public.customer_submit_provider_application(
    'Restricted Services', 20,
    array['00000000-0000-0000-0000-000000010290'::uuid],
    'provider-application-v1'
  )$$,
  '42501',
  'Provider application is unavailable',
  'restricted customer is rejected'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010203';
select throws_ok(
  $$select public.customer_submit_provider_application(
    'Suspended Services', 20,
    array['00000000-0000-0000-0000-000000010290'::uuid],
    'provider-application-v1'
  )$$,
  '42501',
  'Provider application is unavailable',
  'suspended customer is rejected'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010204';
select throws_ok(
  $$select public.customer_submit_provider_application(
    'Closed Services', 20,
    array['00000000-0000-0000-0000-000000010290'::uuid],
    'provider-application-v1'
  )$$,
  '42501',
  'Provider application is unavailable',
  'closed customer is rejected'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010205';
select throws_ok(
  $$select public.customer_submit_provider_application(
    'Wrong Role Services', 20,
    array['00000000-0000-0000-0000-000000010290'::uuid],
    'provider-application-v1'
  )$$,
  '42501',
  'Provider application is unavailable',
  'non-customer role is rejected'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010206';
select throws_ok(
  $$select public.customer_submit_provider_application(
    'History Services', 20,
    array['00000000-0000-0000-0000-000000010290'::uuid],
    'provider-application-v1'
  )$$,
  '42501',
  'Provider application is unavailable',
  'customer marketplace history blocks single-role conversion'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010210';
select throws_ok(
  $$select public.customer_submit_provider_application(
    'Missing Profile Services', 20,
    array['00000000-0000-0000-0000-000000010290'::uuid],
    'provider-application-v1'
  )$$,
  '42501',
  'Provider application is unavailable',
  'missing protected profile is rejected'
);

reset role;

select is(
  (
    select pg_catalog.count(*)
    from public.provider_profiles
    where user_id in (
      '00000000-0000-0000-0000-000000010202'::uuid,
      '00000000-0000-0000-0000-000000010203'::uuid,
      '00000000-0000-0000-0000-000000010204'::uuid,
      '00000000-0000-0000-0000-000000010205'::uuid,
      '00000000-0000-0000-0000-000000010206'::uuid,
      '00000000-0000-0000-0000-000000010208'::uuid
    )
  ),
  0::bigint,
  'all rejected applications leave no provider profile'
);

-- Active pristine owner success.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010201';

select is(
  public.customer_submit_provider_application(
    '  Owner Services  ',
    25,
    array[
      '00000000-0000-0000-0000-000000010290'::uuid,
      '00000000-0000-0000-0000-000000010291'::uuid
    ],
    'provider-application-v1'
  ),
  'pending',
  'active pristine customer submits one pending application'
);

reset role;

select is(
  (select role::text from public.profiles where id = '00000000-0000-0000-0000-000000010201'),
  'provider',
  'successful application performs the guarded single-role conversion'
);

select is(
  (
    select pg_catalog.concat_ws(
      '|', business_name, service_radius_km::text,
      verification_status::text, review_status
    )
    from public.provider_profiles
    where user_id = '00000000-0000-0000-0000-000000010201'
  ),
  'Owner Services|25.00|not_started|pending',
  'provider profile contains only normalized application fields and safe pending statuses'
);

select ok(
  (
    select bio is null
       and verification_reference is null
       and bank_name_match is null
       and reviewed_by is null
       and reviewed_at is null
    from public.provider_profiles
    where user_id = '00000000-0000-0000-0000-000000010201'
  ),
  'application creates no verification, banking, approval, or reviewer state'
);

select is(
  (select count(*) from public.provider_services where provider_id = '00000000-0000-0000-0000-000000010201'),
  2::bigint,
  'application records every proposed category once'
);

select is(
  (
    select count(*)
    from public.provider_services
    where provider_id = '00000000-0000-0000-0000-000000010201'
      and active = false
      and description is null
      and base_price_minor is null
  ),
  2::bigint,
  'all category proposals remain inactive and contain no active-service details'
);

select is(
  (
    select count(*)
    from public.consents
    where user_id = '00000000-0000-0000-0000-000000010201'
      and purpose = 'provider_application_terms'
      and policy_version = 'provider-application-v1'
      and granted = true
      and source = 'customer_provider_application_rpc'
      and recorded_at is not null
      and withdrawn_at is null
  ),
  1::bigint,
  'application writes exactly one fixed server-timestamped terms record'
);

select is(
  (
    select count(*)
    from public.audit_events
    where actor_id = '00000000-0000-0000-0000-000000010201'
      and action = 'customer.provider_application_submitted'
      and occurred_at is not null
      and metadata ->> 'terms_version' = 'provider-application-v1'
  ),
  1::bigint,
  'terms version and acceptance timestamp are recorded in the append-only audit boundary'
);

select is(
  (
    select count(*)
    from public.audit_events
    where actor_id = '00000000-0000-0000-0000-000000010201'
      and action = 'customer.provider_application_submitted'
      and object_type = 'provider_profile'
      and object_id = '00000000-0000-0000-0000-000000010201'
      and reason = 'Customer submitted closed-pilot provider application'
      and metadata = jsonb_build_object(
        'source', 'customer_provider_application_rpc',
        'version', '1',
        'terms_version', 'provider-application-v1'
      )
  ),
  1::bigint,
  'application writes exactly one fixed privacy-safe audit event'
);

select is(
  (select count(*) from public.identity_verifications where user_id = '00000000-0000-0000-0000-000000010201'),
  0::bigint,
  'application creates no identity-verification record'
);

select is(
  public.is_approved_provider('00000000-0000-0000-0000-000000010201'),
  false,
  'pending applicant does not satisfy the approved-provider boundary'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010201';

select is(
  pg_temp.try_activate_provider_service('00000000-0000-0000-0000-000000010201'),
  false,
  'pending applicant cannot activate proposed services'
);

select is(
  pg_temp.try_self_approve('00000000-0000-0000-0000-000000010201'),
  false,
  'pending applicant cannot self-approve'
);

reset role;

select is(
  pg_temp.try_delete_provider_terms('00000000-0000-0000-0000-000000010201'),
  false,
  'provider application terms remain immutable even to direct table-owner mutation'
);

select is(
  pg_temp.try_duplicate_provider_terms('00000000-0000-0000-0000-000000010201'),
  false,
  'provider application terms reject a duplicate record'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010201';

select throws_ok(
  $$select public.provider_submit_bid(
    '00000000-0000-0000-0000-000000010299'::uuid,
    50000
  )$$,
  '42501',
  'Provider bid is unavailable',
  'pending applicant cannot submit a bid'
);

select is(
  (
    select count(*)
    from public.service_requests
    where id = '00000000-0000-0000-0000-000000010299'
  ),
  0::bigint,
  'pending applicant cannot discover open customer requests'
);

select is(
  public.customer_submit_provider_application(
    'Owner Services',
    25,
    array[
      '00000000-0000-0000-0000-000000010290'::uuid,
      '00000000-0000-0000-0000-000000010291'::uuid
    ],
    'provider-application-v1'
  ),
  'pending',
  'identical replay is a safe no-op'
);

select throws_ok(
  $$select public.customer_submit_provider_application(
    'Changed Services',
    25,
    array[
      '00000000-0000-0000-0000-000000010290'::uuid,
      '00000000-0000-0000-0000-000000010291'::uuid
    ],
    'provider-application-v1'
  )$$,
  '42501',
  'Provider application is unavailable',
  'non-identical replay fails closed rather than mutating the application'
);

reset role;

select is(
  (select count(*) from public.audit_events where actor_id = '00000000-0000-0000-0000-000000010201' and action = 'customer.provider_application_submitted'),
  1::bigint,
  'replay creates no duplicate audit event'
);

select is(
  (select count(*) from public.provider_profiles where user_id = '00000000-0000-0000-0000-000000010201'),
  1::bigint,
  'replay creates no duplicate provider profile'
);

select is(
  (select count(*) from public.consents where user_id = '00000000-0000-0000-0000-000000010201' and purpose = 'provider_application_terms'),
  1::bigint,
  'replay creates no duplicate terms record'
);

select is(
  (select count(*) from public.provider_services where provider_id = '00000000-0000-0000-0000-000000010201'),
  2::bigint,
  'replay creates no duplicate category proposal'
);

-- Hostile Auth metadata cannot supply application authority or approval.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010207';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000010207","role":"authenticated","user_metadata":{"role":"admin","review_status":"approved"}}';

select is(
  public.customer_submit_provider_application(
    'Metadata Safe Services',
    15,
    array['00000000-0000-0000-0000-000000010290'::uuid],
    'provider-application-v1'
  ),
  'pending',
  'application derives authority from the protected profile instead of hostile Auth metadata'
);

reset role;

select is(
  (
    select verification_status::text || '|' || review_status
    from public.provider_profiles
    where user_id = '00000000-0000-0000-0000-000000010207'
  ),
  'not_started|pending',
  'hostile metadata cannot obtain verified or approved state'
);

-- Audit failure rolls back role, provider profile, and proposals.
create trigger fail_ticket10a_audit_insert
before insert on public.audit_events
for each row execute function pg_temp.fail_ticket10a_audit();

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010209';

select throws_ok(
  $$select public.customer_submit_provider_application(
    'Rollback Services', 20,
    array['00000000-0000-0000-0000-000000010290'::uuid],
    'provider-application-v1'
  )$$,
  'P0001',
  'Synthetic Ticket 10A audit failure',
  'audit insertion failure aborts the application'
);

reset role;

drop trigger fail_ticket10a_audit_insert on public.audit_events;

select is(
  (select role::text from public.profiles where id = '00000000-0000-0000-0000-000000010209'),
  'customer',
  'audit failure rolls back the role conversion'
);

select is(
  (select count(*) from public.provider_profiles where user_id = '00000000-0000-0000-0000-000000010209'),
  0::bigint,
  'audit failure rolls back the provider profile'
);

select is(
  (select count(*) from public.provider_services where provider_id = '00000000-0000-0000-0000-000000010209'),
  0::bigint,
  'audit failure rolls back category proposals'
);

select is(
  (select count(*) from public.audit_events where actor_id = '00000000-0000-0000-0000-000000010209' and action = 'customer.provider_application_submitted'),
  0::bigint,
  'audit failure leaves no partial terms or application event'
);

select is(
  (select count(*) from public.consents where user_id = '00000000-0000-0000-0000-000000010209' and purpose = 'provider_application_terms'),
  0::bigint,
  'audit failure rolls back the provider terms record'
);

select is(
  coalesce(current_setting('lekkadeall.allow_privileged_profile_update', true), 'off'),
  'off',
  'privileged role-transition guard is disabled after success and failure'
);

select is(
  (select relrowsecurity from pg_catalog.pg_class where oid = 'public.profiles'::regclass),
  true,
  'profiles RLS remains enabled'
);

select is(
  (select relrowsecurity from pg_catalog.pg_class where oid = 'public.provider_profiles'::regclass),
  true,
  'provider_profiles RLS remains enabled'
);

select is(
  (select relrowsecurity from pg_catalog.pg_class where oid = 'public.provider_services'::regclass),
  true,
  'provider_services RLS remains enabled'
);

select is(
  has_column_privilege('authenticated', 'public.profiles', 'role', 'UPDATE'),
  false,
  'authenticated still cannot directly update the protected role column'
);

select * from finish();

rollback;

-- Remove the committed concurrency-only fixture without retaining synthetic
-- rows or weakening production triggers outside this cleanup transaction.
begin;

alter table public.audit_events disable trigger audit_events_append_only;
delete from public.audit_events
where actor_id = '00000000-0000-0000-0000-000000010211'
  and action = 'customer.provider_application_submitted';
alter table public.audit_events enable trigger audit_events_append_only;

alter table public.consents disable trigger protect_provider_application_terms;
delete from auth.users
where id = '00000000-0000-0000-0000-000000010211';
alter table public.consents enable trigger protect_provider_application_terms;

delete from public.service_categories
where id = '00000000-0000-0000-0000-000000010293';

commit;

drop role ticket10a_concurrency_login;
