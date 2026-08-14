create extension if not exists pgtap with schema extensions;

-- Commit only the genuine two-session fixtures before pgTAP begins.
begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000012001', 'ticket10d-admin@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000012002', 'ticket10d-provider@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000012003', 'ticket10d-customer@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000012004', 'ticket10d-competing-provider@lekkadeall.test');

set local lekkadeall.allow_privileged_profile_update = 'on';
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-000000012001';
update public.profiles set role = 'provider' where id = '00000000-0000-0000-0000-000000012002';
update public.profiles set role = 'provider' where id = '00000000-0000-0000-0000-000000012004';
set local lekkadeall.allow_privileged_profile_update = 'off';

insert into public.service_categories (id, slug, name, active) values (
  '00000000-0000-0000-0000-000000012010',
  'ticket10d-concurrent',
  'Ticket 10D Concurrent',
  true
);

insert into public.provider_profiles (
  user_id, business_name, service_radius_km, verification_status, review_status
) values
(
  '00000000-0000-0000-0000-000000012002',
  'Ticket 10D Concurrent Services',
  20,
  'not_started',
  'approved'
),
(
  '00000000-0000-0000-0000-000000012004',
  'Ticket 10D Competing Services',
  20,
  'not_started',
  'approved'
);

insert into public.provider_services (
  provider_id, category_id, description, base_price_minor, active
) values
(
  '00000000-0000-0000-0000-000000012002',
  '00000000-0000-0000-0000-000000012010',
  null,
  null,
  true
),
(
  '00000000-0000-0000-0000-000000012004',
  '00000000-0000-0000-0000-000000012010',
  null,
  null,
  true
);

insert into public.consents (
  user_id, purpose, policy_version, granted, source, withdrawn_at
) values
(
  '00000000-0000-0000-0000-000000012002',
  'provider_application_terms',
  'provider-application-v1',
  true,
  'customer_provider_application_rpc',
  null
),
(
  '00000000-0000-0000-0000-000000012004',
  'provider_application_terms',
  'provider-application-v1',
  true,
  'customer_provider_application_rpc',
  null
);

insert into public.audit_events (
  actor_id, action, object_type, object_id, reason, metadata
) values
(
  '00000000-0000-0000-0000-000000012002',
  'customer.provider_application_submitted',
  'provider_profile',
  '00000000-0000-0000-0000-000000012002',
  'Customer submitted closed-pilot provider application',
  '{}'::pg_catalog.jsonb
),
(
  '00000000-0000-0000-0000-000000012004',
  'customer.provider_application_submitted',
  'provider_profile',
  '00000000-0000-0000-0000-000000012004',
  'Customer submitted closed-pilot provider application',
  '{}'::pg_catalog.jsonb
);

insert into private.provider_eligibility_decisions (
  id, provider_id, reviewer_id, action, previous_status, new_status, basis,
  policy_version, expires_at, reason_code, idempotency_key,
  intent_fingerprint, decided_at
) values
(
  '00000000-0000-0000-0000-000000012020',
  '00000000-0000-0000-0000-000000012002',
  '00000000-0000-0000-0000-000000012001',
  'approve_manual_pilot', 'pending', 'approved', 'manual_pilot',
  'provider-eligibility-v1', pg_catalog.now() + interval '30 days',
  'manual_pilot_approved',
  '00000000-0000-0000-0000-000000012021',
  'ticket10d-concurrent-approval', pg_catalog.now()
),
(
  '00000000-0000-0000-0000-000000012030',
  '00000000-0000-0000-0000-000000012004',
  '00000000-0000-0000-0000-000000012001',
  'approve_manual_pilot', 'pending', 'approved', 'manual_pilot',
  'provider-eligibility-v1', pg_catalog.now() + interval '30 days',
  'manual_pilot_approved',
  '00000000-0000-0000-0000-000000012031',
  'ticket10d-competing-approval', pg_catalog.now()
);

update private.provider_marketplace_eligibility
set status = 'approved',
    basis = 'manual_pilot',
    policy_version = 'provider-eligibility-v1',
    expires_at = pg_catalog.now() + interval '30 days',
    current_decision_id = '00000000-0000-0000-0000-000000012020',
    reviewer_id = '00000000-0000-0000-0000-000000012001',
    reason_code = 'manual_pilot_approved',
    updated_at = pg_catalog.now()
where provider_id = '00000000-0000-0000-0000-000000012002';

update private.provider_marketplace_eligibility
set status = 'approved',
    basis = 'manual_pilot',
    policy_version = 'provider-eligibility-v1',
    expires_at = pg_catalog.now() + interval '30 days',
    current_decision_id = '00000000-0000-0000-0000-000000012030',
    reviewer_id = '00000000-0000-0000-0000-000000012001',
    reason_code = 'manual_pilot_approved',
    updated_at = pg_catalog.now()
where provider_id = '00000000-0000-0000-0000-000000012004';

set local lekkadeall.allow_marketplace_state_transition = 'on';
insert into public.service_requests (
  id, customer_id, category_id, title, description, suburb, city,
  requested_start, budget_minor, status, closes_at, published_at
) values
  ('00000000-0000-0000-0000-000000012101', '00000000-0000-0000-0000-000000012003', '00000000-0000-0000-0000-000000012010', 'Concurrent duplicate bid request', 'Safe public request for concurrent duplicate bid serialization.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 50000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '1 hour'),
  ('00000000-0000-0000-0000-000000012102', '00000000-0000-0000-0000-000000012003', '00000000-0000-0000-0000-000000012010', 'Concurrent suspension bid request', 'Safe public request for suspension versus bid serialization.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 51000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '1 hour'),
  ('00000000-0000-0000-0000-000000012103', '00000000-0000-0000-0000-000000012003', '00000000-0000-0000-0000-000000012010', 'Concurrent cancellation bid request', 'Safe public request for cancellation versus bid serialization.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 52000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '1 hour'),
  ('00000000-0000-0000-0000-000000012104', '00000000-0000-0000-0000-000000012003', '00000000-0000-0000-0000-000000012010', 'Concurrent acceptance bid request', 'Safe public request for acceptance versus withdrawal serialization.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 53000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '1 hour'),
  ('00000000-0000-0000-0000-000000012105', '00000000-0000-0000-0000-000000012003', '00000000-0000-0000-0000-000000012010', 'Concurrent award bid request', 'Safe public request for award versus competing bid serialization.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 54000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '1 hour'),
  ('00000000-0000-0000-0000-000000012106', '00000000-0000-0000-0000-000000012003', '00000000-0000-0000-0000-000000012010', 'Concurrent close bid request', 'Safe public request for close versus bid serialization.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 55000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '1 hour'),
  ('00000000-0000-0000-0000-000000012107', '00000000-0000-0000-0000-000000012003', '00000000-0000-0000-0000-000000012010', 'Replay cancellation request', 'Safe public request for replay versus cancellation serialization.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 56000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '1 hour'),
  ('00000000-0000-0000-0000-000000012108', '00000000-0000-0000-0000-000000012003', '00000000-0000-0000-0000-000000012010', 'Selected replay acceptance request', 'Safe public request for selected replay versus acceptance serialization.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 57000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '1 hour'),
  ('00000000-0000-0000-0000-000000012109', '00000000-0000-0000-0000-000000012003', '00000000-0000-0000-0000-000000012010', 'Competing replay acceptance request', 'Safe public request for competing replay versus acceptance serialization.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 58000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '1 hour');

insert into public.bids (
  id, request_id, provider_id, amount_minor, currency, proposed_start,
  message, perks, status, expires_at
) values (
  '00000000-0000-0000-0000-000000012110',
  '00000000-0000-0000-0000-000000012105',
  '00000000-0000-0000-0000-000000012002',
  49000,
  'ZAR',
  pg_catalog.now() + interval '5 days',
  null,
  '{}'::pg_catalog.text[],
  'submitted',
  pg_catalog.now() + interval '2 days'
);

insert into public.bids (
  id, request_id, provider_id, amount_minor, currency, proposed_start,
  message, perks, status, expires_at
)
select
  fixture.bid_id,
  request.id,
  fixture.provider_id,
  fixture.amount_minor,
  'ZAR',
  request.requested_start,
  null,
  '{}'::pg_catalog.text[],
  'submitted',
  request.closes_at
from public.service_requests as request
join (
  values
    ('00000000-0000-0000-0000-000000012111'::pg_catalog.uuid, '00000000-0000-0000-0000-000000012107'::pg_catalog.uuid, '00000000-0000-0000-0000-000000012002'::pg_catalog.uuid, 49100),
    ('00000000-0000-0000-0000-000000012112'::pg_catalog.uuid, '00000000-0000-0000-0000-000000012108'::pg_catalog.uuid, '00000000-0000-0000-0000-000000012002'::pg_catalog.uuid, 49200),
    ('00000000-0000-0000-0000-000000012113'::pg_catalog.uuid, '00000000-0000-0000-0000-000000012109'::pg_catalog.uuid, '00000000-0000-0000-0000-000000012002'::pg_catalog.uuid, 49300),
    ('00000000-0000-0000-0000-000000012114'::pg_catalog.uuid, '00000000-0000-0000-0000-000000012109'::pg_catalog.uuid, '00000000-0000-0000-0000-000000012004'::pg_catalog.uuid, 49400)
) as fixture(bid_id, request_id, provider_id, amount_minor)
  on fixture.request_id = request.id;

insert into public.audit_events (
  actor_id, action, object_type, object_id, reason, metadata
)
select
  bid.provider_id,
  'provider.bid_submitted',
  'bid',
  bid.id::pg_catalog.text,
  'Provider submitted bid through controlled boundary',
  pg_catalog.jsonb_build_object(
    'request_id', bid.request_id,
    'amount_minor', bid.amount_minor,
    'expires_at', bid.expires_at
  )
from public.bids as bid
where bid.id between '00000000-0000-0000-0000-000000012111' and '00000000-0000-0000-0000-000000012114';
set local lekkadeall.allow_marketplace_state_transition = 'off';

create function public.ticket10d_test_close_request(p_request_id pg_catalog.uuid)
returns pg_catalog.text
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform pg_catalog.set_config('lekkadeall.allow_marketplace_state_transition', 'on', true);
  begin
    update public.service_requests as request
    set closes_at = pg_catalog.clock_timestamp() - interval '1 second',
        updated_at = pg_catalog.clock_timestamp()
    where request.id = p_request_id
      and request.status = 'open'::public.request_status;
  exception
    when others then
      perform pg_catalog.set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
      raise;
  end;
  perform pg_catalog.set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
  return 'closed';
end;
$$;
revoke all on function public.ticket10d_test_close_request(pg_catalog.uuid) from public, anon, authenticated, service_role;
grant execute on function public.ticket10d_test_close_request(pg_catalog.uuid) to authenticated;

create function public.ticket10d_test_cancel_request(p_request_id pg_catalog.uuid)
returns pg_catalog.text
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform public.customer_cancel_request(
    p_request_id,
    'Synthetic concurrency cancellation'
  );
  return 'cancelled';
end;
$$;
revoke all on function public.ticket10d_test_cancel_request(pg_catalog.uuid) from public, anon, authenticated, service_role;
grant execute on function public.ticket10d_test_cancel_request(pg_catalog.uuid) to authenticated;

create function public.ticket10d_test_lock_request(p_request_id pg_catalog.uuid)
returns pg_catalog.text
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform request.id
  from public.service_requests as request
  where request.id = p_request_id
  for update;

  if not found then
    raise exception 'Synthetic request fixture is unavailable';
  end if;

  return 'locked';
end;
$$;
revoke all on function public.ticket10d_test_lock_request(pg_catalog.uuid) from public, anon, authenticated, service_role;
grant execute on function public.ticket10d_test_lock_request(pg_catalog.uuid) to authenticated;

create function public.ticket10d_test_accept_bid(p_bid_id pg_catalog.uuid)
returns pg_catalog.uuid
language sql
security definer
set search_path = pg_catalog
as $$
  select public.customer_accept_bid(p_bid_id);
$$;
revoke all on function public.ticket10d_test_accept_bid(pg_catalog.uuid) from public, anon, authenticated, service_role;
grant execute on function public.ticket10d_test_accept_bid(pg_catalog.uuid) to authenticated;

do $$
declare
  v_password pg_catalog.text := pg_catalog.replace(
    pg_catalog.gen_random_uuid()::pg_catalog.text,
    '-',
    ''
  );
begin
  execute pg_catalog.format(
    'create role ticket10d_concurrency_login login password %L',
    v_password
  );
  perform pg_catalog.set_config(
    'lekkadeall.ticket10d_concurrency_password',
    v_password,
    false
  );
end;
$$;

grant authenticated to ticket10d_concurrency_login;
commit;

begin;
create extension if not exists dblink with schema extensions;
set local search_path = public, extensions, auth;
select no_plan();

select is(
  extensions.dblink_connect(
    'ticket10d_a',
    pg_catalog.format(
      'hostaddr=%s port=%s dbname=%L user=%L password=%L',
      pg_catalog.inet_server_addr(),
      pg_catalog.current_setting('port'),
      pg_catalog.current_database(),
      'ticket10d_concurrency_login',
      pg_catalog.current_setting('lekkadeall.ticket10d_concurrency_password')
    )
  ),
  'OK',
  'first independent bidding session connects'
);

select is(
  extensions.dblink_connect(
    'ticket10d_b',
    pg_catalog.format(
      'hostaddr=%s port=%s dbname=%L user=%L password=%L',
      pg_catalog.inet_server_addr(),
      pg_catalog.current_setting('port'),
      pg_catalog.current_database(),
      'ticket10d_concurrency_login',
      pg_catalog.current_setting('lekkadeall.ticket10d_concurrency_password')
    )
  ),
  'OK',
  'second independent bidding session connects'
);

do $$
begin
  perform pg_catalog.set_config('lekkadeall.ticket10d_concurrency_password', '', false);
  perform extensions.dblink_exec('ticket10d_a', 'set role authenticated');
  perform extensions.dblink_exec('ticket10d_b', 'set role authenticated');
  perform extensions.dblink_exec(
    'ticket10d_a',
    'set request.jwt.claim.sub = ''00000000-0000-0000-0000-000000012002'''
  );
  perform extensions.dblink_exec(
    'ticket10d_b',
    'set request.jwt.claim.sub = ''00000000-0000-0000-0000-000000012002'''
  );
  perform extensions.dblink_exec(
    'ticket10d_a',
    'set request.jwt.claims = ''{"sub":"00000000-0000-0000-0000-000000012002","role":"authenticated","aal":"aal1"}'''
  );
  perform extensions.dblink_exec(
    'ticket10d_b',
    'set request.jwt.claims = ''{"sub":"00000000-0000-0000-0000-000000012002","role":"authenticated","aal":"aal1"}'''
  );
end;
$$;

-- Exact concurrent duplicate submission returns one canonical bid and audit.
select is(extensions.dblink_exec('ticket10d_a', 'begin'), 'BEGIN', 'first duplicate session begins');
select is(
  extensions.dblink_send_query(
    'ticket10d_a',
    $$select public.provider_submit_bid('00000000-0000-0000-0000-000000012101', 45000)::pg_catalog.text$$
  ),
  1,
  'first duplicate submission starts'
);

create temporary table ticket10d_results (
  name pg_catalog.text primary key,
  result_value pg_catalog.text,
  error_message pg_catalog.text
) on commit drop;
insert into ticket10d_results (name) values ('first'), ('second'), ('blocked'), ('withdraw');

update ticket10d_results as result
set result_value = remote.result_value
from extensions.dblink_get_result('ticket10d_a', false) as remote(result_value pg_catalog.text)
where result.name = 'first';

select is(
  extensions.dblink_send_query(
    'ticket10d_b',
    $$select public.provider_submit_bid('00000000-0000-0000-0000-000000012101', 45000)::pg_catalog.text$$
  ),
  1,
  'second duplicate submission starts while the first bid is uncommitted'
);
select is(extensions.dblink_is_busy('ticket10d_b'), 1, 'duplicate submission waits on the canonical lock order');
select is(extensions.dblink_exec('ticket10d_a', 'commit'), 'COMMIT', 'first duplicate transaction commits');

update ticket10d_results as result
set result_value = remote.result_value
from extensions.dblink_get_result('ticket10d_b', false) as remote(result_value pg_catalog.text)
where result.name = 'second';

select is(
  (select result_value from ticket10d_results where name = 'second'),
  (select result_value from ticket10d_results where name = 'first'),
  'concurrent exact replay returns the same canonical bid identifier'
);
select is(
  (select pg_catalog.count(*) from public.bids where request_id = '00000000-0000-0000-0000-000000012101'),
  1::pg_catalog.int8,
  'concurrent duplicate submission creates one bid row'
);
select is(
  (select pg_catalog.count(*) from public.audit_events where action = 'provider.bid_submitted' and metadata ->> 'request_id' = '00000000-0000-0000-0000-000000012101'),
  1::pg_catalog.int8,
  'concurrent duplicate submission creates one audit event'
);
select is(
  (select pg_catalog.count(*) from extensions.dblink_get_result('ticket10d_b', false) as remote(result_value pg_catalog.text)),
  0::pg_catalog.int8,
  'successful duplicate result is fully drained before connection reuse'
);

-- A committed suspension wins before the waiting submit performs its final check.
do $$
begin
  perform extensions.dblink_exec(
    'ticket10d_a',
    'set request.jwt.claim.sub = ''00000000-0000-0000-0000-000000012001'''
  );
  perform extensions.dblink_exec(
    'ticket10d_a',
    'set request.jwt.claims = ''{"sub":"00000000-0000-0000-0000-000000012001","role":"authenticated","aal":"aal2"}'''
  );
end;
$$;
select is(extensions.dblink_exec('ticket10d_a', 'begin'), 'BEGIN', 'suspension session begins');
select is(
  extensions.dblink_send_query(
    'ticket10d_a',
    $$select public.admin_transition_provider_marketplace_review(
      '00000000-0000-0000-0000-000000012002',
      'suspend',
      'approved',
      '00000000-0000-0000-0000-000000012022'
    )$$
  ),
  1,
  'suspension starts before the competing bid'
);
update ticket10d_results as result
set result_value = remote.result_value
from extensions.dblink_get_result('ticket10d_a', false) as remote(result_value pg_catalog.text)
where result.name = 'blocked';
select is((select result_value from ticket10d_results where name = 'blocked'), 'suspended', 'suspension reaches its guarded result');

select is(
  extensions.dblink_send_query(
    'ticket10d_b',
    $$select public.provider_submit_bid('00000000-0000-0000-0000-000000012102', 46000)::pg_catalog.text$$
  ),
  1,
  'bid starts while suspension retains authority locks'
);
select is(extensions.dblink_is_busy('ticket10d_b'), 1, 'bid waits for the authority transition');
select is(extensions.dblink_exec('ticket10d_a', 'commit'), 'COMMIT', 'suspension commits before bid authority is decided');

update ticket10d_results as result
set result_value = remote.result_value
from extensions.dblink_get_result('ticket10d_b', false) as remote(result_value pg_catalog.text)
where result.name = 'blocked';
update ticket10d_results
set error_message = extensions.dblink_error_message('ticket10d_b')
where name = 'blocked';
select is(
  (select pg_catalog.split_part(error_message, E'\n', 1) from ticket10d_results where name = 'blocked'),
  'ERROR:  Provider bid is unavailable',
  'waiting bid fails with the fixed error after committed suspension'
);
select is(
  (select pg_catalog.count(*) from extensions.dblink_get_result('ticket10d_b', false) as remote(result_value pg_catalog.text)),
  0::pg_catalog.int8,
  'failed suspension race result is drained'
);
select is((select pg_catalog.count(*) from public.bids where request_id = '00000000-0000-0000-0000-000000012102'), 0::pg_catalog.int8, 'suspension race creates no bid');

-- Reinstate through the same reviewed authority boundary for later races.
select is(
  (
    select result.review_status
    from extensions.dblink(
      'ticket10d_a',
      $$select public.admin_transition_provider_marketplace_review(
        '00000000-0000-0000-0000-000000012002',
        'reinstate_manual_pilot',
        'suspended',
        '00000000-0000-0000-0000-000000012023'
      )$$
    ) as result(review_status pg_catalog.text)
  ),
  'approved',
  'provider is explicitly reinstated for the request-state races'
);

-- A committed expiry is re-evaluated after the Ticket 10B authority locks.
select is(extensions.dblink_exec('ticket10d_a', 'begin'), 'BEGIN', 'expiry session begins');
select is(
  extensions.dblink_send_query(
    'ticket10d_a',
    $$select public.admin_transition_provider_marketplace_review(
      '00000000-0000-0000-0000-000000012002',
      'expire',
      'approved',
      '00000000-0000-0000-0000-000000012024'
    )$$
  ),
  1,
  'expiry starts before the competing bid'
);
update ticket10d_results as result
set result_value = remote.result_value
from extensions.dblink_get_result('ticket10d_a', false) as remote(result_value pg_catalog.text)
where result.name = 'blocked';
select is((select result_value from ticket10d_results where name = 'blocked'), 'expired', 'expiry reaches its guarded result');
select is(
  extensions.dblink_send_query(
    'ticket10d_b',
    $$select public.provider_submit_bid('00000000-0000-0000-0000-000000012102', 46000)::pg_catalog.text$$
  ),
  1,
  'bid starts while expiry retains authority locks'
);
select is(extensions.dblink_is_busy('ticket10d_b'), 1, 'bid waits for the expiry transition');
select is(extensions.dblink_exec('ticket10d_a', 'commit'), 'COMMIT', 'expiry commits before bid authority is decided');
update ticket10d_results as result
set result_value = remote.result_value
from extensions.dblink_get_result('ticket10d_b', false) as remote(result_value pg_catalog.text)
where result.name = 'blocked';
update ticket10d_results
set error_message = extensions.dblink_error_message('ticket10d_b')
where name = 'blocked';
select is(
  (select pg_catalog.split_part(error_message, E'\n', 1) from ticket10d_results where name = 'blocked'),
  'ERROR:  Provider bid is unavailable',
  'waiting bid fails with the fixed error after committed expiry'
);
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10d_b', false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'failed expiry race result is drained');
select is((select pg_catalog.count(*) from public.bids where request_id = '00000000-0000-0000-0000-000000012102'), 0::pg_catalog.int8, 'expiry race creates no bid');

select is(
  (
    select result.review_status
    from extensions.dblink(
      'ticket10d_a',
      $$select public.admin_transition_provider_marketplace_review(
        '00000000-0000-0000-0000-000000012002',
        'renew_manual_pilot',
        'expired',
        '00000000-0000-0000-0000-000000012025'
      )$$
    ) as result(review_status pg_catalog.text)
  ),
  'approved',
  'provider is explicitly renewed for the remaining request-state races'
);

-- Cancellation holds the request lock; submit must re-evaluate after commit.
do $$
begin
  perform extensions.dblink_exec(
    'ticket10d_a',
    'set request.jwt.claim.sub = ''00000000-0000-0000-0000-000000012003'''
  );
  perform extensions.dblink_exec(
    'ticket10d_a',
    'set request.jwt.claims = ''{"sub":"00000000-0000-0000-0000-000000012003","role":"authenticated","aal":"aal1"}'''
  );
end;
$$;
select is(extensions.dblink_exec('ticket10d_a', 'begin'), 'BEGIN', 'customer cancellation session begins');
select is(
  extensions.dblink_send_query(
    'ticket10d_a',
    $$select public.ticket10d_test_cancel_request('00000000-0000-0000-0000-000000012103')$$
  ),
  1,
  'customer cancellation starts before the competing bid'
);
update ticket10d_results as result
set result_value = remote.result_value
from extensions.dblink_get_result('ticket10d_a', false) as remote(result_value pg_catalog.text)
where result.name = 'blocked';
select is(
  extensions.dblink_send_query(
    'ticket10d_b',
    $$select public.provider_submit_bid('00000000-0000-0000-0000-000000012103', 47000)::pg_catalog.text$$
  ),
  1,
  'bid starts while cancellation retains the request lock'
);
select is(extensions.dblink_is_busy('ticket10d_b'), 1, 'bid waits for cancellation');
select is(extensions.dblink_exec('ticket10d_a', 'commit'), 'COMMIT', 'cancellation commits before bid state is decided');
update ticket10d_results as result
set result_value = remote.result_value
from extensions.dblink_get_result('ticket10d_b', false) as remote(result_value pg_catalog.text)
where result.name = 'blocked';
update ticket10d_results
set error_message = extensions.dblink_error_message('ticket10d_b')
where name = 'blocked';
select is(
  (select pg_catalog.split_part(error_message, E'\n', 1) from ticket10d_results where name = 'blocked'),
  'ERROR:  Provider bid is unavailable',
  'waiting bid fails after committed cancellation'
);
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10d_b', false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'failed cancellation race result is drained');
select is((select status::pg_catalog.text from public.service_requests where id = '00000000-0000-0000-0000-000000012103'), 'cancelled', 'cancellation remains authoritative');
select is((select pg_catalog.count(*) from public.bids where request_id = '00000000-0000-0000-0000-000000012103'), 0::pg_catalog.int8, 'cancellation race creates no bid');

-- An exact replay follows request -> bid, so cancellation can complete while
-- replay waits without forming the former request/bid deadlock cycle.
select is(extensions.dblink_exec('ticket10d_a', 'begin'), 'BEGIN', 'replay cancellation session begins');
select is(
  (
    select result.lock_state
    from extensions.dblink(
      'ticket10d_a',
      $$select public.ticket10d_test_lock_request('00000000-0000-0000-0000-000000012107')$$
    ) as result(lock_state pg_catalog.text)
  ),
  'locked',
  'cancellation session holds the canonical request lock before replay'
);
select is(
  extensions.dblink_send_query(
    'ticket10d_b',
    $$select public.provider_submit_bid('00000000-0000-0000-0000-000000012107', 49100)::pg_catalog.text$$
  ),
  1,
  'exact replay starts while cancellation owns the request lock'
);
select is(extensions.dblink_is_busy('ticket10d_b'), 1, 'exact replay waits on request before its bid');
select is(
  (
    select result.cancel_state
    from extensions.dblink(
      'ticket10d_a',
      $$select public.ticket10d_test_cancel_request('00000000-0000-0000-0000-000000012107')$$
    ) as result(cancel_state pg_catalog.text)
  ),
  'cancelled',
  'cancellation completes without waiting on a replay-held bid'
);
select is(extensions.dblink_exec('ticket10d_a', 'commit'), 'COMMIT', 'replay cancellation commits its serial outcome');
update ticket10d_results as result
set result_value = remote.result_value
from extensions.dblink_get_result('ticket10d_b', false) as remote(result_value pg_catalog.text)
where result.name = 'blocked';
update ticket10d_results
set error_message = extensions.dblink_error_message('ticket10d_b')
where name = 'blocked';
select is(
  (select pg_catalog.split_part(error_message, E'\n', 1) from ticket10d_results where name = 'blocked'),
  'ERROR:  Provider bid is unavailable',
  'waiting exact replay fails closed after cancellation'
);
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10d_b', false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'failed replay cancellation result is drained');
select is((select status::pg_catalog.text from public.service_requests where id = '00000000-0000-0000-0000-000000012107'), 'cancelled', 'replay cancellation leaves the request cancelled');
select is((select status::pg_catalog.text from public.bids where id = '00000000-0000-0000-0000-000000012111'), 'declined', 'replay cancellation leaves the existing bid declined');
select is((select pg_catalog.count(*) from public.bids where request_id = '00000000-0000-0000-0000-000000012107'), 1::pg_catalog.int8, 'replay cancellation creates no duplicate bid');
select is((select pg_catalog.count(*) from public.audit_events where action = 'provider.bid_submitted' and object_id = '00000000-0000-0000-0000-000000012111'), 1::pg_catalog.int8, 'replay cancellation creates no duplicate submit audit');

-- Selected-bid replay also waits on the request before the selected bid.
select is(extensions.dblink_exec('ticket10d_a', 'begin'), 'BEGIN', 'selected replay acceptance session begins');
select is(
  (
    select result.lock_state
    from extensions.dblink(
      'ticket10d_a',
      $$select public.ticket10d_test_lock_request('00000000-0000-0000-0000-000000012108')$$
    ) as result(lock_state pg_catalog.text)
  ),
  'locked',
  'acceptance session holds request before selected-bid replay'
);
select is(
  extensions.dblink_send_query(
    'ticket10d_b',
    $$select public.provider_submit_bid('00000000-0000-0000-0000-000000012108', 49200)::pg_catalog.text$$
  ),
  1,
  'selected-bid exact replay starts while acceptance owns request'
);
select is(extensions.dblink_is_busy('ticket10d_b'), 1, 'selected-bid replay waits on request before selected bid');
update ticket10d_results as result
set result_value = remote.booking_id
from extensions.dblink(
  'ticket10d_a',
  $$select public.ticket10d_test_accept_bid('00000000-0000-0000-0000-000000012112')::pg_catalog.text$$
) as remote(booking_id pg_catalog.text)
where result.name = 'blocked';
select isnt((select result_value from ticket10d_results where name = 'blocked'), null, 'selected-bid acceptance completes without replay deadlock');
select is(extensions.dblink_exec('ticket10d_a', 'commit'), 'COMMIT', 'selected-bid acceptance commits its serial outcome');
update ticket10d_results as result
set result_value = remote.result_value
from extensions.dblink_get_result('ticket10d_b', false) as remote(result_value pg_catalog.text)
where result.name = 'blocked';
update ticket10d_results set error_message = extensions.dblink_error_message('ticket10d_b') where name = 'blocked';
select is((select pg_catalog.split_part(error_message, E'\n', 1) from ticket10d_results where name = 'blocked'), 'ERROR:  Provider bid is unavailable', 'selected-bid replay fails closed after acceptance');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10d_b', false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'failed selected-bid replay result is drained');
select is((select status::pg_catalog.text from public.bids where id = '00000000-0000-0000-0000-000000012112'), 'accepted', 'selected replay race leaves bid accepted');
select is((select pg_catalog.count(*) from public.bookings where request_id = '00000000-0000-0000-0000-000000012108'), 1::pg_catalog.int8, 'selected replay race creates exactly one booking');
select is((select pg_catalog.count(*) from public.bids where request_id = '00000000-0000-0000-0000-000000012108'), 1::pg_catalog.int8, 'selected replay race creates no duplicate bid');
select is((select pg_catalog.count(*) from public.audit_events where action = 'provider.bid_submitted' and object_id = '00000000-0000-0000-0000-000000012112'), 1::pg_catalog.int8, 'selected replay race creates no duplicate submit audit');

-- Competing-bid replay waits at the same request boundary while acceptance
-- locks the selected bid and then declines the replayed competitor.
select is(extensions.dblink_exec('ticket10d_a', 'begin'), 'BEGIN', 'competing replay acceptance session begins');
select is(
  (
    select result.lock_state
    from extensions.dblink(
      'ticket10d_a',
      $$select public.ticket10d_test_lock_request('00000000-0000-0000-0000-000000012109')$$
    ) as result(lock_state pg_catalog.text)
  ),
  'locked',
  'acceptance session holds request before competing-bid replay'
);
select is(
  extensions.dblink_send_query(
    'ticket10d_b',
    $$select public.provider_submit_bid('00000000-0000-0000-0000-000000012109', 49300)::pg_catalog.text$$
  ),
  1,
  'competing exact replay starts while acceptance owns request'
);
select is(extensions.dblink_is_busy('ticket10d_b'), 1, 'competing replay waits on request before competing bid');
update ticket10d_results as result
set result_value = remote.booking_id
from extensions.dblink(
  'ticket10d_a',
  $$select public.ticket10d_test_accept_bid('00000000-0000-0000-0000-000000012114')::pg_catalog.text$$
) as remote(booking_id pg_catalog.text)
where result.name = 'blocked';
select isnt((select result_value from ticket10d_results where name = 'blocked'), null, 'competing-bid acceptance completes without replay deadlock');
select is(extensions.dblink_exec('ticket10d_a', 'commit'), 'COMMIT', 'competing-bid acceptance commits its serial outcome');
update ticket10d_results as result
set result_value = remote.result_value
from extensions.dblink_get_result('ticket10d_b', false) as remote(result_value pg_catalog.text)
where result.name = 'blocked';
update ticket10d_results set error_message = extensions.dblink_error_message('ticket10d_b') where name = 'blocked';
select is((select pg_catalog.split_part(error_message, E'\n', 1) from ticket10d_results where name = 'blocked'), 'ERROR:  Provider bid is unavailable', 'competing replay fails closed after request award');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10d_b', false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'failed competing replay result is drained');
select is((select status::pg_catalog.text from public.bids where id = '00000000-0000-0000-0000-000000012114'), 'accepted', 'competing replay race leaves selected bid accepted');
select is((select status::pg_catalog.text from public.bids where id = '00000000-0000-0000-0000-000000012113'), 'declined', 'competing replay race leaves replayed bid declined');
select is((select pg_catalog.count(*) from public.bookings where request_id = '00000000-0000-0000-0000-000000012109'), 1::pg_catalog.int8, 'competing replay race creates exactly one booking');
select is((select pg_catalog.count(*) from public.bids where request_id = '00000000-0000-0000-0000-000000012109'), 2::pg_catalog.int8, 'competing replay race creates no duplicate bid');
select is((select pg_catalog.count(*) from public.audit_events where action = 'provider.bid_submitted' and object_id = '00000000-0000-0000-0000-000000012113'), 1::pg_catalog.int8, 'competing replay race creates no duplicate submit audit');

-- A close-time transition retains the request lock; submit uses wall clock
-- only after that wait and cannot preserve stale pre-close authority.
select is(extensions.dblink_exec('ticket10d_a', 'begin'), 'BEGIN', 'request close session begins');
select is(
  extensions.dblink_send_query(
    'ticket10d_a',
    $$select public.ticket10d_test_close_request('00000000-0000-0000-0000-000000012106')$$
  ),
  1,
  'request close starts before the competing bid'
);
update ticket10d_results as result
set result_value = remote.result_value
from extensions.dblink_get_result('ticket10d_a', false) as remote(result_value pg_catalog.text)
where result.name = 'blocked';
select is((select result_value from ticket10d_results where name = 'blocked'), 'closed', 'request close reaches its guarded result');
select is(
  extensions.dblink_send_query(
    'ticket10d_b',
    $$select public.provider_submit_bid('00000000-0000-0000-0000-000000012106', 47500)::pg_catalog.text$$
  ),
  1,
  'bid starts while close retains the request lock'
);
select is(extensions.dblink_is_busy('ticket10d_b'), 1, 'bid waits for the close transition');
select is(extensions.dblink_exec('ticket10d_a', 'commit'), 'COMMIT', 'request close commits before bid state is decided');
update ticket10d_results as result
set result_value = remote.result_value
from extensions.dblink_get_result('ticket10d_b', false) as remote(result_value pg_catalog.text)
where result.name = 'blocked';
update ticket10d_results
set error_message = extensions.dblink_error_message('ticket10d_b')
where name = 'blocked';
select is(
  (select pg_catalog.split_part(error_message, E'\n', 1) from ticket10d_results where name = 'blocked'),
  'ERROR:  Provider bid is unavailable',
  'waiting bid fails after the request becomes closed'
);
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10d_b', false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'failed close race result is drained');
select is((select pg_catalog.count(*) from public.bids where request_id = '00000000-0000-0000-0000-000000012106'), 0::pg_catalog.int8, 'close race creates no bid');

-- Acceptance and withdrawal both start with the bid lock and have one serial result.
update ticket10d_results as result
set result_value = remote.bid_id
from extensions.dblink(
  'ticket10d_b',
  $$select public.provider_submit_bid('00000000-0000-0000-0000-000000012104', 48000)::pg_catalog.text$$
) as remote(bid_id pg_catalog.text)
where result.name = 'withdraw';
select isnt((select result_value from ticket10d_results where name = 'withdraw'), null, 'provider creates the submitted bid for the acceptance race');
select is(extensions.dblink_exec('ticket10d_a', 'begin'), 'BEGIN', 'customer acceptance session begins');
select is(
  extensions.dblink_send_query(
    'ticket10d_a',
    pg_catalog.format(
      'select public.ticket10d_test_accept_bid(%L::pg_catalog.uuid)::pg_catalog.text',
      (select result_value from ticket10d_results where name = 'withdraw')
    )
  ),
  1,
  'customer acceptance starts before withdrawal'
);
update ticket10d_results as result
set result_value = remote.result_value
from extensions.dblink_get_result('ticket10d_a', false) as remote(result_value pg_catalog.text)
where result.name = 'blocked';
select isnt((select result_value from ticket10d_results where name = 'blocked'), null, 'acceptance creates a canonical booking');

select is(
  extensions.dblink_send_query(
    'ticket10d_b',
    pg_catalog.format(
      'select public.provider_withdraw_bid(%L::pg_catalog.uuid)::pg_catalog.text',
      (select result_value from ticket10d_results where name = 'withdraw')
    )
  ),
  1,
  'withdrawal starts while acceptance retains the bid lock'
);
select is(extensions.dblink_is_busy('ticket10d_b'), 1, 'withdrawal waits for acceptance');
select is(extensions.dblink_exec('ticket10d_a', 'commit'), 'COMMIT', 'acceptance commits before withdrawal state is decided');
update ticket10d_results as result
set result_value = remote.result_value
from extensions.dblink_get_result('ticket10d_b', false) as remote(result_value pg_catalog.text)
where result.name = 'withdraw';
update ticket10d_results
set error_message = extensions.dblink_error_message('ticket10d_b')
where name = 'withdraw';
select is(
  (select pg_catalog.split_part(error_message, E'\n', 1) from ticket10d_results where name = 'withdraw'),
  'ERROR:  Provider bid is unavailable',
  'waiting withdrawal fails after accepted booking commits'
);
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10d_b', false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'failed withdrawal race result is drained');
select is((select status::pg_catalog.text from public.bids where request_id = '00000000-0000-0000-0000-000000012104'), 'accepted', 'booking-linked bid remains accepted');
select is((select pg_catalog.count(*) from public.bookings where request_id = '00000000-0000-0000-0000-000000012104'), 1::pg_catalog.int8, 'acceptance race creates exactly one booking');
select is((select pg_catalog.count(*) from public.audit_events where action = 'provider.bid_withdrawn' and metadata ->> 'request_id' = '00000000-0000-0000-0000-000000012104'), 0::pg_catalog.int8, 'accepted bid creates no withdrawal audit');

-- Awarding a request wins before a different provider's waiting submission.
do $$
begin
  perform extensions.dblink_exec(
    'ticket10d_b',
    'set request.jwt.claim.sub = ''00000000-0000-0000-0000-000000012004'''
  );
  perform extensions.dblink_exec(
    'ticket10d_b',
    'set request.jwt.claims = ''{"sub":"00000000-0000-0000-0000-000000012004","role":"authenticated","aal":"aal1"}'''
  );
end;
$$;
select is(extensions.dblink_exec('ticket10d_a', 'begin'), 'BEGIN', 'request award session begins');
select is(
  extensions.dblink_send_query(
    'ticket10d_a',
    $$select public.ticket10d_test_accept_bid('00000000-0000-0000-0000-000000012110')::pg_catalog.text$$
  ),
  1,
  'request award starts before the competing provider bid'
);
update ticket10d_results as result
set result_value = remote.result_value
from extensions.dblink_get_result('ticket10d_a', false) as remote(result_value pg_catalog.text)
where result.name = 'blocked';
select isnt((select result_value from ticket10d_results where name = 'blocked'), null, 'request award creates a canonical booking');
select is(
  extensions.dblink_send_query(
    'ticket10d_b',
    $$select public.provider_submit_bid('00000000-0000-0000-0000-000000012105', 48500)::pg_catalog.text$$
  ),
  1,
  'competing bid starts while award retains the request lock'
);
select is(extensions.dblink_is_busy('ticket10d_b'), 1, 'competing bid waits for request award');
select is(extensions.dblink_exec('ticket10d_a', 'commit'), 'COMMIT', 'request award commits before competing bid state is decided');
update ticket10d_results as result
set result_value = remote.result_value
from extensions.dblink_get_result('ticket10d_b', false) as remote(result_value pg_catalog.text)
where result.name = 'blocked';
update ticket10d_results
set error_message = extensions.dblink_error_message('ticket10d_b')
where name = 'blocked';
select is(
  (select pg_catalog.split_part(error_message, E'\n', 1) from ticket10d_results where name = 'blocked'),
  'ERROR:  Provider bid is unavailable',
  'waiting competing bid fails after committed request award'
);
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10d_b', false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'failed award race result is drained');
select is((select status::pg_catalog.text from public.service_requests where id = '00000000-0000-0000-0000-000000012105'), 'awarded', 'request award remains authoritative');
select is((select pg_catalog.count(*) from public.bids where request_id = '00000000-0000-0000-0000-000000012105'), 1::pg_catalog.int8, 'award race creates no competing bid');

select is(extensions.dblink_disconnect('ticket10d_a'), 'OK', 'first bidding session disconnects');
select is(extensions.dblink_disconnect('ticket10d_b'), 'OK', 'second bidding session disconnects');

-- Transactional fixtures for metadata, authorization, state and privacy tests.
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
  null,
  null,
  true
);

set local lekkadeall.allow_marketplace_state_transition = 'on';
insert into public.service_requests (
  id, customer_id, category_id, title, description, suburb, city,
  requested_start, budget_minor, status, closes_at, published_at,
  awarded_at, cancelled_at
) values
  ('00000000-0000-0000-0000-000000012201', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000100', 'Valid provider bid request', 'Safe public request for focused provider bidding coverage.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 60000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '1 hour', null, null),
  ('00000000-0000-0000-0000-000000012202', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000100', 'Null publication bid request', 'Safe but internally inconsistent publication state for bid denial.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 60000, 'open', pg_catalog.now() + interval '2 days', null, null, null),
  ('00000000-0000-0000-0000-000000012203', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000100', 'Future publication bid request', 'Safe but future-published request for bid denial.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 60000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() + interval '1 hour', null, null),
  ('00000000-0000-0000-0000-000000012204', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000100', 'Past start bid request', 'Safe request with a past requested start for bid denial.', 'Die Bult', 'Potchefstroom', pg_catalog.now() - interval '1 hour', 60000, 'open', pg_catalog.now() + interval '1 hour', pg_catalog.now() - interval '1 hour', null, null),
  ('00000000-0000-0000-0000-000000012205', '00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000100', 'Self-owned provider bid request', 'Safe request historically owned by the provider actor.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 60000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '1 hour', null, null),
  ('00000000-0000-0000-0000-000000012206', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000100', 'Declined terminal bid request', 'Safe request for declined bid withdrawal denial.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 60000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '1 hour', null, null),
  ('00000000-0000-0000-0000-000000012207', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000100', 'Expired terminal bid request', 'Safe request for expired bid withdrawal denial.', 'Die Bult', 'Potchefstroom', pg_catalog.now() + interval '5 days', 60000, 'open', pg_catalog.now() + interval '2 days', pg_catalog.now() - interval '1 hour', null, null);

insert into public.bids (
  id, request_id, provider_id, amount_minor, currency, proposed_start,
  message, perks, status, expires_at
) values
  ('00000000-0000-0000-0000-000000012211', '00000000-0000-0000-0000-000000012206', '00000000-0000-0000-0000-000000000011', 50000, 'ZAR', pg_catalog.now() + interval '5 days', null, '{}'::pg_catalog.text[], 'declined', pg_catalog.now() + interval '2 days'),
  ('00000000-0000-0000-0000-000000012212', '00000000-0000-0000-0000-000000012207', '00000000-0000-0000-0000-000000000011', 50000, 'ZAR', pg_catalog.now() + interval '5 days', null, '{}'::pg_catalog.text[], 'expired', pg_catalog.now() - interval '1 second');
set local lekkadeall.allow_marketplace_state_transition = 'off';

-- Function metadata, grants, fixed paths and legacy removal.
select has_function('public', 'provider_submit_bid', array['uuid', 'integer'], 'minimal submit signature exists');
select has_function('public', 'provider_withdraw_bid', array['uuid'], 'minimal withdraw signature exists');
select has_function('public', 'provider_read_own_bid', array['uuid'], 'minimal own-bid read signature exists');
select is((select pg_catalog.count(*) from pg_catalog.pg_proc as p join pg_catalog.pg_namespace as n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'provider_submit_bid'), 1::pg_catalog.int8, 'no legacy submit overload remains');
select is((select pg_catalog.count(*) from pg_catalog.pg_proc as p join pg_catalog.pg_namespace as n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'provider_withdraw_bid'), 1::pg_catalog.int8, 'no legacy withdraw overload remains');

select is((select p.prosecdef from pg_catalog.pg_proc as p where p.oid = 'public.provider_submit_bid(uuid,integer)'::pg_catalog.regprocedure), true, 'submit is SECURITY DEFINER');
select is((select p.prosecdef from pg_catalog.pg_proc as p where p.oid = 'public.provider_withdraw_bid(uuid)'::pg_catalog.regprocedure), true, 'withdraw is SECURITY DEFINER');
select is((select p.prosecdef from pg_catalog.pg_proc as p where p.oid = 'public.provider_read_own_bid(uuid)'::pg_catalog.regprocedure), true, 'own-bid read is SECURITY DEFINER');
select is((select p.proconfig from pg_catalog.pg_proc as p where p.oid = 'public.provider_submit_bid(uuid,integer)'::pg_catalog.regprocedure), array['search_path=pg_catalog']::pg_catalog.text[], 'submit fixes search path to pg_catalog');
select is((select p.proconfig from pg_catalog.pg_proc as p where p.oid = 'public.provider_withdraw_bid(uuid)'::pg_catalog.regprocedure), array['search_path=pg_catalog']::pg_catalog.text[], 'withdraw fixes search path to pg_catalog');
select is((select p.proconfig from pg_catalog.pg_proc as p where p.oid = 'public.provider_read_own_bid(uuid)'::pg_catalog.regprocedure), array['search_path=pg_catalog']::pg_catalog.text[], 'own-bid read fixes search path to pg_catalog');

select is(has_function_privilege('public', 'public.provider_submit_bid(uuid,integer)', 'EXECUTE'), false, 'PUBLIC cannot submit bids');
select is(has_function_privilege('anon', 'public.provider_submit_bid(uuid,integer)', 'EXECUTE'), false, 'anon cannot submit bids');
select is(has_function_privilege('authenticated', 'public.provider_submit_bid(uuid,integer)', 'EXECUTE'), true, 'authenticated can call submit boundary');
select is(has_function_privilege('service_role', 'public.provider_submit_bid(uuid,integer)', 'EXECUTE'), false, 'service_role has no submit grant');
select is(has_function_privilege('public', 'public.provider_withdraw_bid(uuid)', 'EXECUTE'), false, 'PUBLIC cannot withdraw bids');
select is(has_function_privilege('anon', 'public.provider_withdraw_bid(uuid)', 'EXECUTE'), false, 'anon cannot withdraw bids');
select is(has_function_privilege('authenticated', 'public.provider_withdraw_bid(uuid)', 'EXECUTE'), true, 'authenticated can call withdraw boundary');
select is(has_function_privilege('service_role', 'public.provider_withdraw_bid(uuid)', 'EXECUTE'), false, 'service_role has no withdraw grant');
select is(has_function_privilege('public', 'public.provider_read_own_bid(uuid)', 'EXECUTE'), false, 'PUBLIC cannot read provider bids');
select is(has_function_privilege('anon', 'public.provider_read_own_bid(uuid)', 'EXECUTE'), false, 'anon cannot read provider bids');
select is(has_function_privilege('authenticated', 'public.provider_read_own_bid(uuid)', 'EXECUTE'), true, 'authenticated can call own-bid read');
select is(has_function_privilege('service_role', 'public.provider_read_own_bid(uuid)', 'EXECUTE'), false, 'service_role has no own-bid read grant');

select is(has_table_privilege('authenticated', 'public.bids', 'SELECT'), false, 'authenticated has no raw bid SELECT');
select is(has_table_privilege('authenticated', 'public.bids', 'INSERT'), false, 'authenticated has no direct bid INSERT');
select is(has_table_privilege('authenticated', 'public.bids', 'UPDATE'), false, 'authenticated has no direct bid UPDATE');
select is(has_table_privilege('authenticated', 'public.bids', 'DELETE'), false, 'authenticated has no direct bid DELETE');
select is((select c.relrowsecurity from pg_catalog.pg_class as c where c.oid = 'public.bids'::pg_catalog.regclass), true, 'bids RLS remains enabled');
select is((select pg_catalog.count(*) from pg_catalog.pg_policies as p where p.schemaname = 'public' and p.tablename = 'bids'), 0::pg_catalog.int8, 'no raw browser bid policy remains');

select is(pg_catalog.pg_get_functiondef('public.provider_submit_bid(uuid,integer)'::pg_catalog.regprocedure) ~* 'select[[:space:]]+\*|%rowtype', false, 'submit uses explicit projections only');
select is(pg_catalog.pg_get_functiondef('public.provider_withdraw_bid(uuid)'::pg_catalog.regprocedure) ~* 'select[[:space:]]+\*|%rowtype', false, 'withdraw uses explicit projections only');
select is(pg_catalog.pg_get_functiondef('public.provider_read_own_bid(uuid)'::pg_catalog.regprocedure) ~* 'select[[:space:]]+\*|%rowtype', false, 'own-bid read uses explicit projections only');
select is(pg_catalog.pg_get_functiondef('public.provider_submit_bid(uuid,integer)'::pg_catalog.regprocedure) ~* '(p_message|p_perks|p_expires_at|p_proposed_start)', false, 'submit exposes no free-form or workflow-owned inputs');
select is(pg_catalog.pg_get_functiondef('public.provider_withdraw_bid(uuid)'::pg_catalog.regprocedure) ~* 'p_reason', false, 'withdraw exposes no caller-controlled audit reason');
select is(pg_catalog.pg_get_functiondef('public.provider_submit_bid(uuid,integer)'::pg_catalog.regprocedure) ~* 'private\.provider_request_is_discoverable', true, 'submit uses the shared Ticket 10C predicate');
select is(pg_catalog.pg_get_functiondef('public.provider_list_discoverable_requests(integer,timestamptz,uuid)'::pg_catalog.regprocedure) ~* 'private\.provider_request_is_discoverable', true, 'Ticket 10C discovery uses the same predicate');
select is(pg_catalog.pg_get_functiondef('public.provider_submit_bid(uuid,integer)'::pg_catalog.regprocedure) ~ 'raise;', false, 'submit does not rethrow raw internal failures');
select is(pg_catalog.pg_get_functiondef('public.provider_withdraw_bid(uuid)'::pg_catalog.regprocedure) ~ 'raise;', false, 'withdraw does not rethrow raw internal failures');

select is(
  (
    select pg_catalog.array_agg(parameter.parameter_name::pg_catalog.text order by parameter.ordinal_position)
    from information_schema.parameters as parameter
    where parameter.specific_schema = 'public'
      and parameter.specific_name = (
        select routine.specific_name from information_schema.routines as routine
        where routine.routine_schema = 'public' and routine.routine_name = 'provider_read_own_bid'
      )
      and parameter.parameter_mode = 'OUT'
  ),
  array['bid_id', 'request_id', 'amount_minor', 'currency', 'proposed_start', 'status', 'expires_at']::pg_catalog.text[],
  'own-bid read returns exactly seven reviewed fields'
);

-- Authorization, input, exact replay and reconciliation.
set local role anon;
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012201', 50000)$$, '42501', 'permission denied for function provider_submit_bid', 'signed-out caller cannot execute submit');
reset role;

-- The submit boundary rechecks the complete actor authority matrix itself.
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000012299';
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012201', 50000)$$, '42501', 'Provider bid is unavailable', 'missing profile fails closed');

set local request.jwt.claim.sub = '';
set local lekkadeall.allow_privileged_profile_update = 'on';
update public.profiles set account_status = 'restricted' where id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_profile_update = 'off';
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012201', 50000)$$, '42501', 'Provider bid is unavailable', 'restricted provider fails closed');
set local request.jwt.claim.sub = '';
set local lekkadeall.allow_privileged_profile_update = 'on';
update public.profiles set account_status = 'suspended' where id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_profile_update = 'off';
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012201', 50000)$$, '42501', 'Provider bid is unavailable', 'suspended account fails closed');
set local request.jwt.claim.sub = '';
set local lekkadeall.allow_privileged_profile_update = 'on';
update public.profiles set account_status = 'closed' where id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_profile_update = 'off';
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012201', 50000)$$, '42501', 'Provider bid is unavailable', 'closed account fails closed');
set local request.jwt.claim.sub = '';
set local lekkadeall.allow_privileged_profile_update = 'on';
update public.profiles set account_status = 'active' where id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_profile_update = 'off';

set local lekkadeall.allow_privileged_provider_profile_update = 'on';
update public.provider_profiles set review_status = 'pending' where user_id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_provider_profile_update = 'off';
update private.provider_marketplace_eligibility
set status = 'pending', basis = null, expires_at = null,
    current_decision_id = null, reviewer_id = null, reason_code = null
where provider_id = '00000000-0000-0000-0000-000000000011';
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012201', 50000)$$, '42501', 'Provider bid is unavailable', 'pending provider review fails closed');
set local request.jwt.claim.sub = '';

set local lekkadeall.allow_privileged_provider_profile_update = 'on';
update public.provider_profiles set review_status = 'rejected' where user_id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_provider_profile_update = 'off';
update private.provider_marketplace_eligibility set status = 'rejected' where provider_id = '00000000-0000-0000-0000-000000000011';
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012201', 50000)$$, '42501', 'Provider bid is unavailable', 'rejected provider review fails closed');
set local request.jwt.claim.sub = '';

set local lekkadeall.allow_privileged_provider_profile_update = 'on';
update public.provider_profiles set review_status = 'suspended' where user_id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_provider_profile_update = 'off';
update private.provider_marketplace_eligibility
set status = 'suspended', basis = 'manual_pilot',
    expires_at = pg_catalog.now() + interval '365 days',
    current_decision_id = '00000000-0000-0000-0000-000000000611',
    reviewer_id = '00000000-0000-0000-0000-000000000099',
    reason_code = 'marketplace_eligibility_suspended'
where provider_id = '00000000-0000-0000-0000-000000000011';
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012201', 50000)$$, '42501', 'Provider bid is unavailable', 'suspended provider review fails closed');
set local request.jwt.claim.sub = '';

set local lekkadeall.allow_privileged_provider_profile_update = 'on';
update public.provider_profiles set review_status = 'expired' where user_id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_provider_profile_update = 'off';
update private.provider_marketplace_eligibility
set status = 'expired', expires_at = pg_catalog.now() - interval '1 second',
    reason_code = 'marketplace_eligibility_expired'
where provider_id = '00000000-0000-0000-0000-000000000011';
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012201', 50000)$$, '42501', 'Provider bid is unavailable', 'expired provider review fails closed');
set local request.jwt.claim.sub = '';

set local lekkadeall.allow_privileged_provider_profile_update = 'on';
update public.provider_profiles set review_status = 'approved' where user_id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_provider_profile_update = 'off';
update private.provider_marketplace_eligibility
set status = 'approved', basis = 'manual_pilot',
    expires_at = pg_catalog.now() + interval '365 days',
    current_decision_id = null,
    reviewer_id = null,
    reason_code = null
where provider_id = '00000000-0000-0000-0000-000000000011';
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012201', 50000)$$, '42501', 'Provider bid is unavailable', 'incomplete current eligibility decision fails closed');
set local request.jwt.claim.sub = '';
update private.provider_marketplace_eligibility
set current_decision_id = '00000000-0000-0000-0000-000000000611',
    reviewer_id = '00000000-0000-0000-0000-000000000099',
    reason_code = 'manual_pilot_approved'
where provider_id = '00000000-0000-0000-0000-000000000011';

set local lekkadeall.allow_privileged_provider_profile_update = 'on';
update public.provider_profiles set verification_status = 'rejected' where user_id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_provider_profile_update = 'off';
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012201', 50000)$$, '42501', 'Provider bid is unavailable', 'rejected verification fails closed');
set local request.jwt.claim.sub = '';
set local lekkadeall.allow_privileged_provider_profile_update = 'on';
update public.provider_profiles set verification_status = 'expired' where user_id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_provider_profile_update = 'off';
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012201', 50000)$$, '42501', 'Provider bid is unavailable', 'expired verification fails closed');
set local request.jwt.claim.sub = '';
set local lekkadeall.allow_privileged_provider_profile_update = 'on';
update public.provider_profiles set verification_status = 'not_started' where user_id = '00000000-0000-0000-0000-000000000011';
set local lekkadeall.allow_privileged_provider_profile_update = 'off';

update public.provider_services set active = false where provider_id = '00000000-0000-0000-0000-000000000011' and category_id = '00000000-0000-0000-0000-000000000100';
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012201', 50000)$$, '42501', 'Provider bid is unavailable', 'inactive owned provider service fails closed');
set local request.jwt.claim.sub = '';
update public.provider_services set active = true where provider_id = '00000000-0000-0000-0000-000000000011' and category_id = '00000000-0000-0000-0000-000000000100';
update public.service_categories set active = false where id = '00000000-0000-0000-0000-000000000100';
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012201', 50000)$$, '42501', 'Provider bid is unavailable', 'inactive service category fails closed');
set local request.jwt.claim.sub = '';
update public.service_categories set active = true where id = '00000000-0000-0000-0000-000000000100';

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000011","role":"authenticated","aal":"aal1"}';

select throws_ok($$select public.provider_submit_bid(null, 50000)$$, '22023', 'Provider bid is unavailable', 'null request ID fails before mutation');
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012201', null)$$, '22023', 'Provider bid is unavailable', 'null amount fails before mutation');
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012201', 0)$$, '22023', 'Provider bid is unavailable', 'zero amount fails before mutation');
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012201', 100000001)$$, '22023', 'Provider bid is unavailable', 'oversized amount fails before mutation');

create temporary table ticket10d_functional_ids (name pg_catalog.text primary key, id pg_catalog.uuid) on commit drop;
insert into ticket10d_functional_ids (name, id)
select 'submitted', public.provider_submit_bid('00000000-0000-0000-0000-000000012201', 50000);

select isnt((select id from ticket10d_functional_ids where name = 'submitted'), null, 'eligible provider submits one minimal bid');
reset role;
select is(
  (
    select pg_catalog.count(*)
    from public.bids as bid
    where bid.id = (select id from ticket10d_functional_ids where name = 'submitted')
      and bid.provider_id = '00000000-0000-0000-0000-000000000011'
      and bid.amount_minor = 50000
      and bid.currency = 'ZAR'
      and bid.proposed_start = (select requested_start from public.service_requests where id = '00000000-0000-0000-0000-000000012201')
      and bid.expires_at = (select closes_at from public.service_requests where id = '00000000-0000-0000-0000-000000012201')
      and bid.message is null
      and pg_catalog.cardinality(bid.perks) = 0
      and bid.status = 'submitted'
  ),
  1::pg_catalog.int8,
  'server owns provider, currency, schedule, expiry, free-form fields and status'
);
select is((select pg_catalog.count(*) from public.audit_events where action = 'provider.bid_submitted' and object_id = (select id::pg_catalog.text from ticket10d_functional_ids where name = 'submitted')), 1::pg_catalog.int8, 'successful submit appends one fixed audit event');
set local role authenticated;
select is(public.provider_submit_bid('00000000-0000-0000-0000-000000012201', 50000), (select id from ticket10d_functional_ids where name = 'submitted'), 'exact submit replay returns the same bid');
reset role;
select is((select pg_catalog.count(*) from public.bids where request_id = '00000000-0000-0000-0000-000000012201' and provider_id = '00000000-0000-0000-0000-000000000011'), 1::pg_catalog.int8, 'exact replay creates no duplicate bid');
select is((select pg_catalog.count(*) from public.audit_events where action = 'provider.bid_submitted' and object_id = (select id::pg_catalog.text from ticket10d_functional_ids where name = 'submitted')), 1::pg_catalog.int8, 'exact replay creates no duplicate audit');
set local role authenticated;
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012201', 50001)$$, '40001', 'Provider bid is unavailable', 'divergent replay fails closed');
select is((select pg_catalog.count(*) from public.provider_read_own_bid('00000000-0000-0000-0000-000000012201')), 1::pg_catalog.int8, 'fresh own-bid read returns the submitted bid');
select is((select status::pg_catalog.text from public.provider_read_own_bid('00000000-0000-0000-0000-000000012201')), 'submitted', 'fresh own-bid read returns canonical submitted state');

select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012202', 50000)$$, '42501', 'Provider bid is unavailable', 'null publication request is not biddable');
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012203', 50000)$$, '42501', 'Provider bid is unavailable', 'future publication request is not biddable');
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012204', 50000)$$, '42501', 'Provider bid is unavailable', 'past requested start is not biddable');
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012205', 50000)$$, '42501', 'Provider bid is unavailable', 'provider cannot bid on own historical customer request');

select throws_ok($$select public.provider_withdraw_bid('00000000-0000-0000-0000-000000000301')$$, '42501', 'Provider bid is unavailable', 'accepted booking-linked bid cannot be withdrawn');
select throws_ok($$select public.provider_withdraw_bid('00000000-0000-0000-0000-000000000302')$$, '42501', 'Provider bid is unavailable', 'foreign bid cannot be withdrawn');
select throws_ok($$select public.provider_withdraw_bid('00000000-0000-0000-0000-000000012211')$$, '42501', 'Provider bid is unavailable', 'declined bid cannot be withdrawn');
select throws_ok($$select public.provider_withdraw_bid('00000000-0000-0000-0000-000000012212')$$, '42501', 'Provider bid is unavailable', 'expired bid cannot be withdrawn');

select is(public.provider_withdraw_bid((select id from ticket10d_functional_ids where name = 'submitted'))::pg_catalog.text, 'withdrawn', 'provider withdraws owned submitted bid');
select is((select status::pg_catalog.text from public.provider_read_own_bid('00000000-0000-0000-0000-000000012201')), 'withdrawn', 'fresh own-bid read confirms withdrawal');
reset role;
select is((select pg_catalog.count(*) from public.audit_events where action = 'provider.bid_withdrawn' and object_id = (select id::pg_catalog.text from ticket10d_functional_ids where name = 'submitted')), 1::pg_catalog.int8, 'withdrawal appends one fixed audit event');
set local role authenticated;
select is(public.provider_withdraw_bid((select id from ticket10d_functional_ids where name = 'submitted'))::pg_catalog.text, 'withdrawn', 'repeated withdrawal returns stable terminal state');
reset role;
select is((select pg_catalog.count(*) from public.audit_events where action = 'provider.bid_withdrawn' and object_id = (select id::pg_catalog.text from ticket10d_functional_ids where name = 'submitted')), 1::pg_catalog.int8, 'repeated withdrawal creates no duplicate audit');
select is(coalesce(pg_catalog.current_setting('lekkadeall.allow_marketplace_state_transition', true), 'off'), 'off', 'transition guard is disabled after submit and withdrawal paths');

-- Customer/wrong-role callers and other providers cannot gain bid access.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012202', 50000)$$, '42501', 'Provider bid is unavailable', 'customer role cannot submit a bid');
select is((select pg_catalog.count(*) from public.provider_read_own_bid('00000000-0000-0000-0000-000000012201')), 0::pg_catalog.int8, 'customer cannot read provider-owned bid');
select throws_ok($$select public.provider_withdraw_bid((select id from ticket10d_functional_ids where name = 'submitted'))$$, '42501', 'Provider bid is unavailable', 'foreign actor cannot withdraw provider bid');
reset role;

-- Audit failure rolls back a new bid and clears the transaction-local guard.
create function pg_temp.fail_ticket10d_audit()
returns trigger
language plpgsql
as $$
begin
  if new.action = 'provider.bid_submitted'
     and new.metadata ->> 'request_id' = '00000000-0000-0000-0000-000000012202' then
    raise exception 'Synthetic bid audit failure';
  end if;
  return new;
end;
$$;
create trigger fail_ticket10d_audit_insert before insert on public.audit_events for each row execute function pg_temp.fail_ticket10d_audit();

-- Make the audit-failure request valid only for this atomicity assertion.
set local lekkadeall.allow_marketplace_state_transition = 'on';
update public.service_requests set published_at = pg_catalog.now() - interval '1 hour' where id = '00000000-0000-0000-0000-000000012202';
set local lekkadeall.allow_marketplace_state_transition = 'off';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select throws_ok($$select public.provider_submit_bid('00000000-0000-0000-0000-000000012202', 51000)$$, '40001', 'Provider bid is unavailable', 'audit failure returns only the fixed generic response');
reset role;
drop trigger fail_ticket10d_audit_insert on public.audit_events;
select is((select pg_catalog.count(*) from public.bids where request_id = '00000000-0000-0000-0000-000000012202'), 0::pg_catalog.int8, 'audit failure rolls back bid insertion');
select is((select pg_catalog.count(*) from public.audit_events where action = 'provider.bid_submitted' and metadata ->> 'request_id' = '00000000-0000-0000-0000-000000012202'), 0::pg_catalog.int8, 'audit failure leaves no partial event');
select is(coalesce(pg_catalog.current_setting('lekkadeall.allow_marketplace_state_transition', true), 'off'), 'off', 'audit failure clears transition guard');

select * from finish();
rollback;

-- Remove committed concurrency-only rows and login without retaining secrets.
begin;
set local lekkadeall.allow_trusted_payment_update = 'on';
alter table public.payment_events disable trigger payment_events_append_only;
delete from public.payment_events
where payment_id in (
  select id
  from public.payments
  where booking_id in (
    select id
    from public.bookings
    where request_id between '00000000-0000-0000-0000-000000012101' and '00000000-0000-0000-0000-000000012109'
  )
);
alter table public.payment_events enable trigger payment_events_append_only;
set local lekkadeall.allow_marketplace_state_transition = 'on';
delete from public.payments where booking_id in (select id from public.bookings where request_id between '00000000-0000-0000-0000-000000012101' and '00000000-0000-0000-0000-000000012109');
set local lekkadeall.allow_trusted_payment_update = 'off';
delete from public.bookings where request_id between '00000000-0000-0000-0000-000000012101' and '00000000-0000-0000-0000-000000012109';
delete from public.bids where request_id between '00000000-0000-0000-0000-000000012101' and '00000000-0000-0000-0000-000000012109';
delete from public.service_requests where id between '00000000-0000-0000-0000-000000012101' and '00000000-0000-0000-0000-000000012109';
set local lekkadeall.allow_marketplace_state_transition = 'off';

alter table public.audit_events disable trigger audit_events_append_only;
delete from public.audit_events
where actor_id in (
  '00000000-0000-0000-0000-000000012001',
  '00000000-0000-0000-0000-000000012002',
  '00000000-0000-0000-0000-000000012003',
  '00000000-0000-0000-0000-000000012004'
)
or metadata ->> 'request_id' in (
  '00000000-0000-0000-0000-000000012101',
  '00000000-0000-0000-0000-000000012102',
  '00000000-0000-0000-0000-000000012103',
  '00000000-0000-0000-0000-000000012104',
  '00000000-0000-0000-0000-000000012105',
  '00000000-0000-0000-0000-000000012106',
  '00000000-0000-0000-0000-000000012107',
  '00000000-0000-0000-0000-000000012108',
  '00000000-0000-0000-0000-000000012109'
);
alter table public.audit_events enable trigger audit_events_append_only;

alter table private.provider_eligibility_decisions disable trigger provider_eligibility_decisions_append_only;
alter table public.consents disable trigger protect_provider_application_terms;
delete from private.provider_marketplace_eligibility where provider_id = '00000000-0000-0000-0000-000000012002';
delete from private.provider_marketplace_eligibility where provider_id = '00000000-0000-0000-0000-000000012004';
delete from private.provider_eligibility_decisions where provider_id in (
  '00000000-0000-0000-0000-000000012002',
  '00000000-0000-0000-0000-000000012004'
);
delete from public.provider_services where provider_id in (
  '00000000-0000-0000-0000-000000012002',
  '00000000-0000-0000-0000-000000012004'
);
set local lekkadeall.allow_privileged_provider_profile_update = 'on';
update public.provider_profiles
set reviewed_by = null,
    reviewed_at = null
where user_id in (
  '00000000-0000-0000-0000-000000012002',
  '00000000-0000-0000-0000-000000012004'
);
set local lekkadeall.allow_privileged_provider_profile_update = 'off';
delete from auth.users where id in (
  '00000000-0000-0000-0000-000000012001',
  '00000000-0000-0000-0000-000000012002',
  '00000000-0000-0000-0000-000000012003',
  '00000000-0000-0000-0000-000000012004'
);
alter table public.consents enable trigger protect_provider_application_terms;
alter table private.provider_eligibility_decisions enable trigger provider_eligibility_decisions_append_only;
delete from public.service_categories where id = '00000000-0000-0000-0000-000000012010';
drop function public.ticket10d_test_cancel_request(pg_catalog.uuid);
drop function public.ticket10d_test_close_request(pg_catalog.uuid);
drop function public.ticket10d_test_lock_request(pg_catalog.uuid);
drop function public.ticket10d_test_accept_bid(pg_catalog.uuid);
commit;

drop role ticket10d_concurrency_login;
