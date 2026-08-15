create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;

-- Committed synthetic fixtures are required so two independent dblink sessions
-- can exercise real row-lock races. Cleanup at the end removes every fixture.
begin;

create function public.ticket10f_test_accept(
  p_request_id pg_catalog.uuid,
  p_bid_id pg_catalog.uuid,
  p_idempotency_key pg_catalog.uuid
)
returns pg_catalog.text
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  select pg_catalog.concat_ws(
    ':',
    result.request_id::pg_catalog.text,
    result.accepted_bid_id::pg_catalog.text,
    result.request_status::pg_catalog.text,
    result.bid_status::pg_catalog.text
  )
  from public.customer_accept_current_bid(
    p_request_id,
    p_bid_id,
    (select request.updated_at from public.service_requests as request
      where request.id = p_request_id),
    (select bid.created_at from public.bids as bid where bid.id = p_bid_id),
    p_idempotency_key
  ) as result;
$$;

create function public.ticket10f_test_cancel_request(p_request_id pg_catalog.uuid)
returns pg_catalog.text
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_now pg_catalog.timestamptz := pg_catalog.clock_timestamp();
begin
  perform request.id from public.service_requests as request
  where request.id = p_request_id for update;
  perform pg_catalog.set_config('lekkadeall.allow_marketplace_state_transition', 'on', true);
  update public.service_requests as request
  set status = 'cancelled'::public.request_status,
      cancelled_at = v_now
  where request.id = p_request_id
    and request.status = 'open'::public.request_status;
  perform pg_catalog.set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
  return 'cancelled';
exception when others then
  perform pg_catalog.set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
  raise;
end;
$$;

create function public.ticket10f_test_expire_request(p_request_id pg_catalog.uuid)
returns pg_catalog.text
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_now pg_catalog.timestamptz := pg_catalog.clock_timestamp();
begin
  perform request.id from public.service_requests as request
  where request.id = p_request_id for update;
  perform pg_catalog.set_config('lekkadeall.allow_marketplace_state_transition', 'on', true);
  update public.service_requests as request
  set status = 'expired'::public.request_status,
      closes_at = v_now - '1 second'::pg_catalog.interval
  where request.id = p_request_id
    and request.status = 'open'::public.request_status;
  perform pg_catalog.set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
  return 'expired';
exception when others then
  perform pg_catalog.set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
  raise;
end;
$$;

create function public.ticket10f_test_close_request(p_request_id pg_catalog.uuid)
returns pg_catalog.text
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  perform request.id from public.service_requests as request
  where request.id = p_request_id for update;
  perform pg_catalog.set_config('lekkadeall.allow_marketplace_state_transition', 'on', true);
  update public.service_requests as request
  set closes_at = pg_catalog.clock_timestamp() - '1 second'::pg_catalog.interval
  where request.id = p_request_id
    and request.status = 'open'::public.request_status;
  perform pg_catalog.set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
  return 'closed';
exception when others then
  perform pg_catalog.set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
  raise;
end;
$$;

create function public.ticket10f_test_set_provider_eligibility(
  p_provider_id pg_catalog.uuid,
  p_status pg_catalog.text
)
returns pg_catalog.text
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  if p_status not in ('approved', 'suspended', 'expired') then
    raise exception 'unsupported test status';
  end if;
  update private.provider_marketplace_eligibility as eligibility
  set status = p_status,
      expires_at = case when p_status = 'expired'
        then pg_catalog.clock_timestamp() - '1 second'::pg_catalog.interval
        else pg_catalog.clock_timestamp() + '30 days'::pg_catalog.interval end,
      updated_at = pg_catalog.clock_timestamp()
  where eligibility.provider_id = p_provider_id;
  return p_status;
end;
$$;

create function public.ticket10f_test_set_service_active(
  p_provider_id pg_catalog.uuid,
  p_category_id pg_catalog.uuid,
  p_active pg_catalog.bool
)
returns pg_catalog.text
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  update public.provider_services as service
  set active = p_active
  where service.provider_id = p_provider_id
    and service.category_id = p_category_id;
  return case when p_active then 'active' else 'inactive' end;
end;
$$;

revoke all on function public.ticket10f_test_accept(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.ticket10f_test_cancel_request(pg_catalog.uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.ticket10f_test_expire_request(pg_catalog.uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.ticket10f_test_close_request(pg_catalog.uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.ticket10f_test_set_provider_eligibility(pg_catalog.uuid, pg_catalog.text)
  from public, anon, authenticated, service_role;
revoke all on function public.ticket10f_test_set_service_active(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.bool)
  from public, anon, authenticated, service_role;
grant execute on function public.ticket10f_test_accept(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid)
  to authenticated;
grant execute on function public.ticket10f_test_cancel_request(pg_catalog.uuid)
  to authenticated;
grant execute on function public.ticket10f_test_expire_request(pg_catalog.uuid)
  to authenticated;
grant execute on function public.ticket10f_test_close_request(pg_catalog.uuid)
  to authenticated;
grant execute on function public.ticket10f_test_set_provider_eligibility(pg_catalog.uuid, pg_catalog.text)
  to authenticated;
grant execute on function public.ticket10f_test_set_service_active(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.bool)
  to authenticated;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000f0001', 'ticket10f-reviewer@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000f0002', 'ticket10f-owner@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000f0003', 'ticket10f-other@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000f0004', 'ticket10f-restricted@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000f0005', 'ticket10f-suspended@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000f0006', 'ticket10f-closed@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000f0007', 'ticket10f-provider-role@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000f0008', 'ticket10f-support-role@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000f0009', 'ticket10f-admin-role@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000f0010', 'ticket10f-missing-profile@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000f0101', 'ticket10f-provider-1@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000f0102', 'ticket10f-provider-2@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000f0103', 'ticket10f-provider-3@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000f0104', 'ticket10f-provider-4@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000f0105', 'ticket10f-provider-5@lekkadeall.test');

set local lekkadeall.allow_privileged_profile_update = 'on';
update public.profiles set role = 'admin'::public.user_role
where id in ('00000000-0000-4000-8000-0000000f0001','00000000-0000-4000-8000-0000000f0009');
update public.profiles set role = 'provider'::public.user_role
where id in (
  '00000000-0000-4000-8000-0000000f0007',
  '00000000-0000-4000-8000-0000000f0101',
  '00000000-0000-4000-8000-0000000f0102',
  '00000000-0000-4000-8000-0000000f0103',
  '00000000-0000-4000-8000-0000000f0104',
  '00000000-0000-4000-8000-0000000f0105'
);
update public.profiles set role = 'support'::public.user_role
where id = '00000000-0000-4000-8000-0000000f0008';
update public.profiles set account_status = 'restricted'
where id = '00000000-0000-4000-8000-0000000f0004';
update public.profiles set account_status = 'suspended'
where id = '00000000-0000-4000-8000-0000000f0005';
update public.profiles set account_status = 'closed'
where id = '00000000-0000-4000-8000-0000000f0006';
set local lekkadeall.allow_privileged_profile_update = 'off';
delete from public.profiles where id = '00000000-0000-4000-8000-0000000f0010';

insert into public.service_categories (id, slug, name, active) values
  ('00000000-0000-4000-8000-0000000f0201', 'ticket10f-active', 'Ticket 10F Active', true),
  ('00000000-0000-4000-8000-0000000f0202', 'ticket10f-inactive', 'Ticket 10F Inactive', false);

insert into public.provider_profiles (
  user_id, business_name, service_radius_km, verification_status, review_status
) values
  ('00000000-0000-4000-8000-0000000f0101', 'Ticket 10F Provider 1', 20, 'not_started', 'approved'),
  ('00000000-0000-4000-8000-0000000f0102', 'Ticket 10F Provider 2', 20, 'not_started', 'approved'),
  ('00000000-0000-4000-8000-0000000f0103', 'Ticket 10F Provider 3', 20, 'not_started', 'approved'),
  ('00000000-0000-4000-8000-0000000f0104', 'Ticket 10F Provider 4', 20, 'not_started', 'approved'),
  ('00000000-0000-4000-8000-0000000f0105', 'Ticket 10F Provider 5', 20, 'not_started', 'approved');

create temporary table ticket10f_decisions on commit drop as
select provider.user_id as provider_id,
  pg_catalog.gen_random_uuid() as decision_id,
  pg_catalog.gen_random_uuid() as idempotency_key
from public.provider_profiles as provider
where provider.user_id between '00000000-0000-4000-8000-0000000f0101'
  and '00000000-0000-4000-8000-0000000f0105';

insert into private.provider_eligibility_decisions (
  id, provider_id, reviewer_id, action, previous_status, new_status, basis,
  policy_version, expires_at, reason_code, idempotency_key,
  intent_fingerprint, decided_at
)
select decision.decision_id, decision.provider_id,
  '00000000-0000-4000-8000-0000000f0001', 'approve_manual_pilot',
  'pending', 'approved', 'manual_pilot', 'provider-eligibility-v1',
  pg_catalog.statement_timestamp() + '30 days'::pg_catalog.interval,
  'manual_pilot_approved', decision.idempotency_key,
  pg_catalog.format('ticket10f-%s', decision.provider_id),
  pg_catalog.statement_timestamp()
from ticket10f_decisions as decision;

update private.provider_marketplace_eligibility as eligibility
set status = case when eligibility.provider_id = '00000000-0000-4000-8000-0000000f0103'
      then 'suspended' else 'approved' end,
    basis = 'manual_pilot',
    policy_version = 'provider-eligibility-v1',
    expires_at = pg_catalog.statement_timestamp() + '30 days'::pg_catalog.interval,
    current_decision_id = decision.decision_id,
    reviewer_id = '00000000-0000-4000-8000-0000000f0001',
    reason_code = 'manual_pilot_approved'
from ticket10f_decisions as decision
where decision.provider_id = eligibility.provider_id;

insert into public.provider_services (
  provider_id, category_id, description, base_price_minor, active
) values
  ('00000000-0000-4000-8000-0000000f0101', '00000000-0000-4000-8000-0000000f0201', null, null, true),
  ('00000000-0000-4000-8000-0000000f0102', '00000000-0000-4000-8000-0000000f0201', null, null, true),
  ('00000000-0000-4000-8000-0000000f0103', '00000000-0000-4000-8000-0000000f0201', null, null, true),
  ('00000000-0000-4000-8000-0000000f0104', '00000000-0000-4000-8000-0000000f0201', null, null, false),
  ('00000000-0000-4000-8000-0000000f0105', '00000000-0000-4000-8000-0000000f0201', null, null, true),
  ('00000000-0000-4000-8000-0000000f0101', '00000000-0000-4000-8000-0000000f0202', null, null, true);

create temporary table ticket10f_clock on commit drop as
select pg_catalog.statement_timestamp() as decision_at;

set local lekkadeall.allow_marketplace_state_transition = 'on';
insert into public.service_requests (
  id, customer_id, category_id, title, description, suburb, city,
  requested_start, budget_minor, status, closes_at, published_at,
  awarded_at, cancelled_at
)
select
  pg_catalog.format('00000000-0000-4000-8000-0000000f%s', suffix)::pg_catalog.uuid,
  case when suffix = '1002' then '00000000-0000-4000-8000-0000000f0003'::pg_catalog.uuid
    else '00000000-0000-4000-8000-0000000f0002'::pg_catalog.uuid end,
  case when suffix = '1011' then '00000000-0000-4000-8000-0000000f0202'::pg_catalog.uuid
    else '00000000-0000-4000-8000-0000000f0201'::pg_catalog.uuid end,
  'Canonical customer request',
  'Canonical public request used for guarded customer bid acceptance.',
  'Die Bult', 'Potchefstroom',
  clock.decision_at + case when suffix = '1010' then '2 days'::pg_catalog.interval else '5 days'::pg_catalog.interval end,
  90000,
  case suffix
    when '1003' then 'draft'::public.request_status
    when '1004' then 'cancelled'::public.request_status
    when '1005' then 'awarded'::public.request_status
    when '1006' then 'expired'::public.request_status
    else 'open'::public.request_status end,
  case when suffix = '1003' then null
    when suffix in ('1008','1006') then clock.decision_at - '1 minute'::pg_catalog.interval
    else clock.decision_at + '3 days'::pg_catalog.interval end,
  case when suffix in ('1003','1007') then null
    when suffix = '1009' then clock.decision_at + '1 hour'::pg_catalog.interval
    else clock.decision_at - '1 hour'::pg_catalog.interval end,
  case when suffix = '1005' then clock.decision_at - '30 minutes'::pg_catalog.interval else null end,
  case when suffix = '1004' then clock.decision_at - '30 minutes'::pg_catalog.interval else null end
from ticket10f_clock as clock
cross join (values
  ('1001'),('1002'),('1003'),('1004'),('1005'),('1006'),('1007'),('1008'),('1009'),('1010'),('1011'),
  ('1012'),('1013'),('1014'),('1015'),('1016'),('1017'),('1018'),('1019'),('1020'),('1021'),('1022'),('1023'),
  ('1201'),('1202'),('1203'),('1204'),('1205'),('1206'),('1207'),('1208'),('1209'),('1210')
) as fixture(suffix);

insert into public.bids (
  id, request_id, provider_id, amount_minor, currency, proposed_start,
  message, perks, status, expires_at, created_at, updated_at,
  accepted_at, declined_at, withdrawn_at
)
select
  pg_catalog.format('00000000-0000-4000-8000-0000000f%s',
    (3000 + (suffix::pg_catalog.int4 - 1000))::pg_catalog.text)::pg_catalog.uuid,
  pg_catalog.format('00000000-0000-4000-8000-0000000f%s', suffix)::pg_catalog.uuid,
  case when suffix = '1019' then '00000000-0000-4000-8000-0000000f0103'::pg_catalog.uuid
    when suffix = '1020' then '00000000-0000-4000-8000-0000000f0104'::pg_catalog.uuid
    when suffix = '1208' then '00000000-0000-4000-8000-0000000f0102'::pg_catalog.uuid
    when suffix = '1209' then '00000000-0000-4000-8000-0000000f0105'::pg_catalog.uuid
    else '00000000-0000-4000-8000-0000000f0101'::pg_catalog.uuid end,
  50000, 'ZAR',
  clock.decision_at + case when suffix = '1018' then '6 days'::pg_catalog.interval else '5 days'::pg_catalog.interval end,
  case when suffix = '1017' then 'legacy hidden message' else null end,
  '{}'::pg_catalog.text[],
  case suffix
    when '1012' then 'withdrawn'::public.bid_status
    when '1014' then 'declined'::public.bid_status
    when '1015' then 'accepted'::public.bid_status
    else 'submitted'::public.bid_status end,
  case when suffix = '1013' then clock.decision_at - '1 minute'::pg_catalog.interval
    else clock.decision_at + '3 days'::pg_catalog.interval end,
  clock.decision_at - '30 minutes'::pg_catalog.interval,
  clock.decision_at - '30 minutes'::pg_catalog.interval,
  case when suffix = '1015' then clock.decision_at - '10 minutes'::pg_catalog.interval else null end,
  case when suffix = '1014' then clock.decision_at - '10 minutes'::pg_catalog.interval else null end,
  case when suffix = '1012' then clock.decision_at - '10 minutes'::pg_catalog.interval else null end
from ticket10f_clock as clock
cross join (values
  ('1001'),('1002'),('1003'),('1004'),('1005'),('1006'),('1007'),('1008'),('1009'),('1010'),('1011'),
  ('1012'),('1013'),('1014'),('1015'),('1016'),('1017'),('1018'),('1019'),('1020'),('1021'),('1022'),('1023'),
  ('1201'),('1202'),('1203'),('1204'),('1205'),('1206'),('1207'),('1208'),('1209'),('1210')
) as fixture(suffix);

-- A second current bid proves deterministic competitor decline and races.
insert into public.bids (
  id, request_id, provider_id, amount_minor, currency, proposed_start,
  message, perks, status, expires_at, created_at, updated_at
)
select
  pg_catalog.format('00000000-0000-4000-8000-0000000f%s', suffix)::pg_catalog.uuid,
  pg_catalog.format('00000000-0000-4000-8000-0000000f%s', request_suffix)::pg_catalog.uuid,
  '00000000-0000-4000-8000-0000000f0102', 51000, 'ZAR',
  clock.decision_at + '5 days'::pg_catalog.interval, null, '{}', 'submitted',
  clock.decision_at + '3 days'::pg_catalog.interval,
  clock.decision_at - '20 minutes'::pg_catalog.interval,
  clock.decision_at - '20 minutes'::pg_catalog.interval
from ticket10f_clock as clock
cross join (values
  ('4001','1001'),('4201','1201'),('4202','1202'),('4203','1203')
) as fixture(suffix, request_suffix);
set local lekkadeall.allow_marketplace_state_transition = 'off';

-- One fixture contains invalid public text that the normal write validator
-- would reject; this proves acceptance repeats the authority check.
alter table public.service_requests disable trigger enforce_service_request_public_fields;
update public.service_requests set title = 'Contact me at unsafe@example.test'
where id = '00000000-0000-4000-8000-0000000f1016';
alter table public.service_requests enable trigger enforce_service_request_public_fields;

do $$
declare
  v_password pg_catalog.text := pg_catalog.replace(
    pg_catalog.gen_random_uuid()::pg_catalog.text, '-', ''
  );
begin
  execute pg_catalog.format(
    'create role ticket10f_concurrency_login login password %L', v_password
  );
  perform pg_catalog.set_config(
    'lekkadeall.ticket10f_concurrency_password', v_password, false
  );
end;
$$;
grant authenticated to ticket10f_concurrency_login;
commit;

begin;
set local search_path = public, extensions, auth;
select no_plan();

create function pg_temp.set_ticket10f_actor(p_actor_id pg_catalog.uuid)
returns pg_catalog.void language plpgsql set search_path = pg_catalog as $$
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(p_actor_id::pg_catalog.text, ''), true);
  perform pg_catalog.set_config(
    'request.jwt.claims',
    case when p_actor_id is null then '{"role":"authenticated","aal":"aal1"}'
      else pg_catalog.format('{"sub":"%s","role":"authenticated","aal":"aal1"}', p_actor_id) end,
    true
  );
end;
$$;

create function pg_temp.ticket10f_accept_error(
  p_actor_id pg_catalog.uuid,
  p_idempotency_key pg_catalog.uuid
)
returns pg_catalog.text
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform pg_catalog.set_config(
    'request.jwt.claim.sub', coalesce(p_actor_id::pg_catalog.text, ''), true
  );
  perform pg_catalog.set_config(
    'request.jwt.claims',
    case when p_actor_id is null then '{"role":"authenticated","aal":"aal1"}'
      else pg_catalog.format(
        '{"sub":"%s","role":"authenticated","aal":"aal1"}', p_actor_id
      ) end,
    true
  );
  begin
    perform result.request_id
    from public.customer_accept_current_bid(
      '00000000-0000-4000-8000-0000000f1001',
      '00000000-0000-4000-8000-0000000f3001',
      (select request.updated_at from public.service_requests as request
        where request.id = '00000000-0000-4000-8000-0000000f1001'),
      (select bid.created_at from public.bids as bid
        where bid.id = '00000000-0000-4000-8000-0000000f3001'),
      p_idempotency_key
    ) as result;
    return 'unexpected-success';
  exception when others then
    return sqlstate || ':' || sqlerrm;
  end;
end;
$$;

-- Exact metadata, projection and privilege boundary.
select has_function('public', 'customer_accept_current_bid', array['uuid','uuid','timestamp with time zone','timestamp with time zone','uuid'], 'one hardened customer acceptance mutation exists');
select has_function('public', 'customer_reconcile_bid_acceptance', array['uuid','uuid'], 'one minimal acceptance reconciliation exists');
select is((select pg_catalog.count(*) from pg_catalog.pg_proc as proc join pg_catalog.pg_namespace as namespace on namespace.oid = proc.pronamespace where namespace.nspname = 'public' and proc.proname = 'customer_accept_current_bid'), 1::pg_catalog.int8, 'acceptance has no overload');
select is((select pg_catalog.count(*) from pg_catalog.pg_proc as proc join pg_catalog.pg_namespace as namespace on namespace.oid = proc.pronamespace where namespace.nspname = 'public' and proc.proname = 'customer_reconcile_bid_acceptance'), 1::pg_catalog.int8, 'reconciliation has no overload');
select is((select proc.provolatile from pg_catalog.pg_proc as proc where proc.oid = 'public.customer_accept_current_bid(uuid,uuid,timestamptz,timestamptz,uuid)'::pg_catalog.regprocedure), 'v'::pg_catalog.char, 'acceptance is VOLATILE');
select is((select proc.provolatile from pg_catalog.pg_proc as proc where proc.oid = 'public.customer_reconcile_bid_acceptance(uuid,uuid)'::pg_catalog.regprocedure), 'v'::pg_catalog.char, 'reconciliation is VOLATILE');
select is((select proc.prosecdef from pg_catalog.pg_proc as proc where proc.oid = 'public.customer_accept_current_bid(uuid,uuid,timestamptz,timestamptz,uuid)'::pg_catalog.regprocedure), true, 'acceptance is SECURITY DEFINER');
select is((select proc.prosecdef from pg_catalog.pg_proc as proc where proc.oid = 'public.customer_reconcile_bid_acceptance(uuid,uuid)'::pg_catalog.regprocedure), true, 'reconciliation is SECURITY DEFINER');
select is((select proc.proconfig from pg_catalog.pg_proc as proc where proc.oid = 'public.customer_accept_current_bid(uuid,uuid,timestamptz,timestamptz,uuid)'::pg_catalog.regprocedure), array['search_path=pg_catalog']::pg_catalog.text[], 'acceptance fixes search path');
select is((select proc.proconfig from pg_catalog.pg_proc as proc where proc.oid = 'public.customer_reconcile_bid_acceptance(uuid,uuid)'::pg_catalog.regprocedure), array['search_path=pg_catalog']::pg_catalog.text[], 'reconciliation fixes search path');
select is(pg_catalog.pg_get_functiondef('public.customer_accept_current_bid(uuid,uuid,timestamptz,timestamptz,uuid)'::pg_catalog.regprocedure) ~* 'select[[:space:]]+\*|%rowtype|\mexecute\M', false, 'acceptance has explicit static projections');
select is(pg_catalog.pg_get_functiondef('public.customer_reconcile_bid_acceptance(uuid,uuid)'::pg_catalog.regprocedure) ~* 'select[[:space:]]+\*|%rowtype|\mexecute\M', false, 'reconciliation has explicit static projections');
select is(pg_catalog.pg_get_functiondef('public.customer_accept_current_bid(uuid,uuid,timestamptz,timestamptz,uuid)'::pg_catalog.regprocedure) ~* 'bookings|payments|payment_events|service_request_addresses|precise_address|address_reveal', false, 'acceptance contains no downstream or address relation');
select is(pg_catalog.pg_get_functiondef('public.customer_reconcile_bid_acceptance(uuid,uuid)'::pg_catalog.regprocedure) ~* 'provider_id|bookings|payments|service_request_addresses|audit_events', false, 'reconciliation exposes no provider or adjacent authority');
select is((select pg_catalog.array_agg(parameter.parameter_name::pg_catalog.text order by parameter.ordinal_position) from information_schema.parameters as parameter where parameter.specific_schema = 'public' and parameter.specific_name = (select routine.specific_name from information_schema.routines as routine where routine.routine_schema = 'public' and routine.routine_name = 'customer_accept_current_bid') and parameter.parameter_mode = 'OUT'), array['request_id','accepted_bid_id','request_status','bid_status','awarded_at','accepted_at']::pg_catalog.text[], 'acceptance returns exactly six minimal fields');
select is((select pg_catalog.array_agg(parameter.parameter_name::pg_catalog.text order by parameter.ordinal_position) from information_schema.parameters as parameter where parameter.specific_schema = 'public' and parameter.specific_name = (select routine.specific_name from information_schema.routines as routine where routine.routine_schema = 'public' and routine.routine_name = 'customer_reconcile_bid_acceptance') and parameter.parameter_mode = 'OUT'), array['request_id','accepted_bid_id','request_status','bid_status','awarded_at','accepted_at']::pg_catalog.text[], 'reconciliation returns exactly six minimal fields');

select is(has_function_privilege('public', 'public.customer_accept_current_bid(uuid,uuid,timestamptz,timestamptz,uuid)', 'EXECUTE'), false, 'PUBLIC cannot accept');
select is(has_function_privilege('anon', 'public.customer_accept_current_bid(uuid,uuid,timestamptz,timestamptz,uuid)', 'EXECUTE'), false, 'anon cannot accept');
select is(has_function_privilege('authenticated', 'public.customer_accept_current_bid(uuid,uuid,timestamptz,timestamptz,uuid)', 'EXECUTE'), true, 'authenticated may call guarded acceptance');
select is(has_function_privilege('service_role', 'public.customer_accept_current_bid(uuid,uuid,timestamptz,timestamptz,uuid)', 'EXECUTE'), false, 'service role cannot accept');
select is(has_function_privilege('public', 'public.customer_reconcile_bid_acceptance(uuid,uuid)', 'EXECUTE'), false, 'PUBLIC cannot reconcile');
select is(has_function_privilege('anon', 'public.customer_reconcile_bid_acceptance(uuid,uuid)', 'EXECUTE'), false, 'anon cannot reconcile');
select is(has_function_privilege('authenticated', 'public.customer_reconcile_bid_acceptance(uuid,uuid)', 'EXECUTE'), true, 'authenticated may call guarded reconciliation');
select is(has_function_privilege('service_role', 'public.customer_reconcile_bid_acceptance(uuid,uuid)', 'EXECUTE'), false, 'service role cannot reconcile');
select is(has_function_privilege('public', 'public.customer_accept_bid(uuid)', 'EXECUTE'), false, 'legacy acceptance remains unavailable to PUBLIC');
select is(has_function_privilege('anon', 'public.customer_accept_bid(uuid)', 'EXECUTE'), false, 'legacy acceptance remains unavailable to anon');
select is(has_function_privilege('authenticated', 'public.customer_accept_bid(uuid)', 'EXECUTE'), false, 'legacy acceptance remains unavailable to authenticated');
select is(has_function_privilege('service_role', 'public.customer_accept_bid(uuid)', 'EXECUTE'), false, 'legacy acceptance remains unavailable to service role');
select is((select class.relrowsecurity from pg_catalog.pg_class as class where class.oid = 'private.customer_bid_acceptance_receipts'::pg_catalog.regclass), true, 'private receipts have RLS enabled');
select is(has_table_privilege('authenticated', 'private.customer_bid_acceptance_receipts', 'SELECT'), false, 'authenticated cannot read receipts');
select is(has_table_privilege('authenticated', 'private.customer_bid_acceptance_receipts', 'INSERT'), false, 'authenticated cannot insert receipts');
select is(has_table_privilege('authenticated', 'private.customer_bid_acceptance_receipts', 'UPDATE'), false, 'authenticated cannot update receipts');
select is(has_table_privilege('authenticated', 'private.customer_bid_acceptance_receipts', 'DELETE'), false, 'authenticated cannot delete receipts');
select is(has_table_privilege('authenticated', 'public.bids', 'SELECT'), false, 'raw bid reads remain blocked');
select is(has_table_privilege('authenticated', 'public.bids', 'UPDATE'), false, 'raw bid updates remain blocked');
select is(has_table_privilege('authenticated', 'public.service_requests', 'UPDATE'), false, 'raw request updates remain blocked');
select is(has_function_privilege('authenticated', 'public.customer_list_current_bids(uuid,timestamptz,uuid)', 'EXECUTE'), true, 'Ticket 10E viewer grant remains unchanged');

create temporary table ticket10f_expected on commit drop as
select request.updated_at as request_updated_at, bid.created_at as bid_submitted_at
from public.service_requests as request
join public.bids as bid on bid.request_id = request.id
where request.id = '00000000-0000-4000-8000-0000000f1001'
  and bid.id = '00000000-0000-4000-8000-0000000f3001';
grant select on ticket10f_expected to authenticated;

-- Every denied actor, ownership, stale input and state uses one fixed surface.
select pg_temp.set_ticket10f_actor(null); set local role authenticated;
select throws_ok($$select * from public.customer_accept_current_bid('00000000-0000-4000-8000-0000000f1001','00000000-0000-4000-8000-0000000f3001',(select request_updated_at from ticket10f_expected),(select bid_submitted_at from ticket10f_expected),'00000000-0000-4000-8000-0000000f5001')$$, '42501', 'Customer bid acceptance is unavailable', 'signed-out acceptance fails closed'); reset role;

select is(
  pg_temp.ticket10f_accept_error(
    actor_id,
    pg_catalog.format('00000000-0000-4000-8000-0000000f%s', key_suffix)::pg_catalog.uuid
  ),
  '42501:Customer bid acceptance is unavailable',
  label
)
from (values
  ('00000000-0000-4000-8000-0000000f0004'::pg_catalog.uuid,'5004','restricted customer fails closed'),
  ('00000000-0000-4000-8000-0000000f0005','5005','suspended customer fails closed'),
  ('00000000-0000-4000-8000-0000000f0006','5006','closed customer fails closed'),
  ('00000000-0000-4000-8000-0000000f0007','5007','provider role fails closed'),
  ('00000000-0000-4000-8000-0000000f0008','5008','support role fails closed'),
  ('00000000-0000-4000-8000-0000000f0009','5009','admin role fails closed'),
  ('00000000-0000-4000-8000-0000000f0010','5010','missing profile fails closed')
) as denied(actor_id,key_suffix,label);

select pg_temp.set_ticket10f_actor('00000000-0000-4000-8000-0000000f0003'); set local role authenticated;
select throws_ok($$select * from public.customer_accept_current_bid('00000000-0000-4000-8000-0000000f1001','00000000-0000-4000-8000-0000000f3001',(select request_updated_at from ticket10f_expected),(select bid_submitted_at from ticket10f_expected),'00000000-0000-4000-8000-0000000f5011')$$, '42501', 'Customer bid acceptance is unavailable', 'foreign customer receives no existence oracle'); reset role;

select pg_temp.set_ticket10f_actor('00000000-0000-4000-8000-0000000f0002'); set local role authenticated;
select throws_ok($$select * from public.customer_accept_current_bid(null,'00000000-0000-4000-8000-0000000f3001',pg_catalog.statement_timestamp(),pg_catalog.statement_timestamp(),'00000000-0000-4000-8000-0000000f5012')$$, '42501', 'Customer bid acceptance is unavailable', 'null request fails closed');
select throws_ok($$select * from public.customer_accept_current_bid('00000000-0000-0000-0000-000000000000','00000000-0000-4000-8000-0000000f3001',pg_catalog.statement_timestamp(),pg_catalog.statement_timestamp(),'00000000-0000-4000-8000-0000000f5013')$$, '42501', 'Customer bid acceptance is unavailable', 'nil request fails closed');
select throws_ok($$select * from public.customer_accept_current_bid('00000000-0000-4000-8000-0000000f1001','00000000-0000-0000-0000-000000000000',pg_catalog.statement_timestamp(),pg_catalog.statement_timestamp(),'00000000-0000-4000-8000-0000000f5014')$$, '42501', 'Customer bid acceptance is unavailable', 'nil bid fails closed');
select throws_ok($$select * from public.customer_accept_current_bid('00000000-0000-4000-8000-0000000f9999','00000000-0000-4000-8000-0000000f3999',pg_catalog.statement_timestamp(),pg_catalog.statement_timestamp(),'00000000-0000-4000-8000-0000000f5015')$$, '42501', 'Customer bid acceptance is unavailable', 'missing identifiers fail closed');
select throws_ok($$select * from public.customer_accept_current_bid('00000000-0000-4000-8000-0000000f1001','00000000-0000-4000-8000-0000000f3002',(select request_updated_at from ticket10f_expected),(select bid_submitted_at from ticket10f_expected),'00000000-0000-4000-8000-0000000f5016')$$, '42501', 'Customer bid acceptance is unavailable', 'bid from another request fails closed');
select throws_ok($$select * from public.customer_accept_current_bid('00000000-0000-4000-8000-0000000f1001','00000000-0000-4000-8000-0000000f3001',(select request_updated_at - interval '1 second' from ticket10f_expected),(select bid_submitted_at from ticket10f_expected),'00000000-0000-4000-8000-0000000f5017')$$, '42501', 'Customer bid acceptance is unavailable', 'stale request version fails closed');
select throws_ok($$select * from public.customer_accept_current_bid('00000000-0000-4000-8000-0000000f1001','00000000-0000-4000-8000-0000000f3001',(select request_updated_at from ticket10f_expected),(select bid_submitted_at - interval '1 second' from ticket10f_expected),'00000000-0000-4000-8000-0000000f5018')$$, '42501', 'Customer bid acceptance is unavailable', 'stale bid version fails closed');
select throws_ok($$select * from public.customer_accept_current_bid('00000000-0000-4000-8000-0000000f1001','00000000-0000-4000-8000-0000000f3001',(select request_updated_at from ticket10f_expected),(select bid_submitted_at from ticket10f_expected),'00000000-0000-0000-0000-000000000000')$$, '42501', 'Customer bid acceptance is unavailable', 'nil idempotency key fails closed');

select throws_ok(pg_catalog.format($sql$select * from public.ticket10f_test_accept('00000000-0000-4000-8000-0000000f%s','00000000-0000-4000-8000-0000000f%s','00000000-0000-4000-8000-0000000f%s')$sql$, request_suffix, bid_suffix, key_suffix), '42501', 'Customer bid acceptance is unavailable', label)
from (values
  ('1003','3003','5103','draft request fails closed'),
  ('1004','3004','5104','cancelled request fails closed'),
  ('1005','3005','5105','awarded request without matching receipt fails closed'),
  ('1006','3006','5106','expired request fails closed'),
  ('1007','3007','5107','unpublished request fails closed'),
  ('1008','3008','5108','past-close request fails closed'),
  ('1009','3009','5109','future publication fails closed'),
  ('1010','3010','5110','inconsistent request timing fails closed'),
  ('1011','3011','5111','inactive category fails closed'),
  ('1012','3012','5112','withdrawn bid fails closed'),
  ('1013','3013','5113','expired bid fails closed'),
  ('1014','3014','5114','declined bid fails closed'),
  ('1015','3015','5115','accepted bid without matching receipt fails closed'),
  ('1016','3016','5116','unsafe public field fails closed'),
  ('1017','3017','5117','bid with hidden message fails closed'),
  ('1018','3018','5118','bid schedule mismatch fails closed'),
  ('1019','3019','5119','ineligible provider fails closed'),
  ('1020','3020','5120','inactive provider service fails closed')
) as denied(request_suffix,bid_suffix,key_suffix,label);
reset role;

-- Positive selection, exact replay and owner-only reconciliation.
select pg_temp.set_ticket10f_actor('00000000-0000-4000-8000-0000000f0002'); set local role authenticated;
create temporary table ticket10f_result on commit drop as
select * from public.customer_accept_current_bid(
  '00000000-0000-4000-8000-0000000f1001',
  '00000000-0000-4000-8000-0000000f3001',
  (select request_updated_at from ticket10f_expected),
  (select bid_submitted_at from ticket10f_expected),
  '00000000-0000-4000-8000-0000000f5001'
);
select is((select pg_catalog.count(*) from ticket10f_result), 1::pg_catalog.int8, 'owner acceptance returns one canonical result');
select is((select request_status from ticket10f_result), 'awarded'::public.request_status, 'result reports awarded request');
select is((select bid_status from ticket10f_result), 'accepted'::public.bid_status, 'result reports accepted bid');
select is((select request_id from ticket10f_result), '00000000-0000-4000-8000-0000000f1001'::pg_catalog.uuid, 'result contains same request ID');
select is((select accepted_bid_id from ticket10f_result), '00000000-0000-4000-8000-0000000f3001'::pg_catalog.uuid, 'result contains selected opaque bid ID');
select is((select awarded_at from ticket10f_result), (select accepted_at from ticket10f_result), 'result uses one server decision timestamp');
reset role;

select is((select status from public.service_requests where id='00000000-0000-4000-8000-0000000f1001'), 'awarded'::public.request_status, 'request is awarded');
select is((select status from public.bids where id='00000000-0000-4000-8000-0000000f3001'), 'accepted'::public.bid_status, 'selected bid is accepted');
select is((select status from public.bids where id='00000000-0000-4000-8000-0000000f4001'), 'declined'::public.bid_status, 'submitted competitor is declined');
select is((select pg_catalog.count(*) from private.customer_bid_acceptance_receipts where request_id='00000000-0000-4000-8000-0000000f1001'), 1::pg_catalog.int8, 'exactly one private receipt exists');
select is((select pg_catalog.count(*) from public.audit_events where action='customer.bid_accepted' and object_id='00000000-0000-4000-8000-0000000f3001'), 1::pg_catalog.int8, 'exactly one acceptance audit exists');
select is((select metadata from public.audit_events where action='customer.bid_accepted' and object_id='00000000-0000-4000-8000-0000000f3001'), pg_catalog.jsonb_build_object('request_id','00000000-0000-4000-8000-0000000f1001'::pg_catalog.uuid), 'audit metadata contains only request ID');
select is((select reason from public.audit_events where action='customer.bid_accepted' and object_id='00000000-0000-4000-8000-0000000f3001'), null::pg_catalog.text, 'acceptance audit has no free-form reason');
select is((select pg_catalog.count(*) from public.bookings where request_id='00000000-0000-4000-8000-0000000f1001'), 0::pg_catalog.int8, 'acceptance creates no booking');
select is((select pg_catalog.count(*) from public.payments), 0::pg_catalog.int8, 'acceptance creates no payment');
select is((select pg_catalog.count(*) from private.service_request_addresses where request_id='00000000-0000-4000-8000-0000000f1001'), 0::pg_catalog.int8, 'acceptance creates and requires no exact-address row');
select is((select pg_catalog.count(*) from public.audit_events where action='booking.address_revealed' and metadata ->> 'request_id'='00000000-0000-4000-8000-0000000f1001'), 0::pg_catalog.int8, 'acceptance creates no address-reveal audit');

select pg_temp.set_ticket10f_actor('00000000-0000-4000-8000-0000000f0002'); set local role authenticated;
select is((select request_id from public.customer_accept_current_bid('00000000-0000-4000-8000-0000000f1001','00000000-0000-4000-8000-0000000f3001',(select request_updated_at from ticket10f_expected),(select bid_submitted_at from ticket10f_expected),'00000000-0000-4000-8000-0000000f5001')), '00000000-0000-4000-8000-0000000f1001'::pg_catalog.uuid, 'exact replay returns the same canonical result');
select throws_ok($$select * from public.customer_accept_current_bid('00000000-0000-4000-8000-0000000f1001','00000000-0000-4000-8000-0000000f3001',(select request_updated_at from ticket10f_expected),(select bid_submitted_at from ticket10f_expected),'00000000-0000-4000-8000-0000000f5999')$$, '42501', 'Customer bid acceptance is unavailable', 'different key after award fails closed');
select throws_ok($$select * from public.customer_accept_current_bid('00000000-0000-4000-8000-0000000f1001','00000000-0000-4000-8000-0000000f3001',(select request_updated_at + interval '1 second' from ticket10f_expected),(select bid_submitted_at from ticket10f_expected),'00000000-0000-4000-8000-0000000f5001')$$, '42501', 'Customer bid acceptance is unavailable', 'same key with different fingerprint fails closed');
select is((select request_status from public.customer_reconcile_bid_acceptance('00000000-0000-4000-8000-0000000f1001','00000000-0000-4000-8000-0000000f5001')), 'awarded'::public.request_status, 'owner reconciliation proves awarded state');
reset role;
select is((select pg_catalog.count(*) from private.customer_bid_acceptance_receipts where request_id='00000000-0000-4000-8000-0000000f1001'), 1::pg_catalog.int8, 'replay adds no receipt');
select is((select pg_catalog.count(*) from public.audit_events where action='customer.bid_accepted' and object_id='00000000-0000-4000-8000-0000000f3001'), 1::pg_catalog.int8, 'replay adds no audit');

select pg_temp.set_ticket10f_actor('00000000-0000-4000-8000-0000000f0003'); set local role authenticated;
select throws_ok($$select * from public.customer_reconcile_bid_acceptance('00000000-0000-4000-8000-0000000f1001','00000000-0000-4000-8000-0000000f5001')$$, '42501', 'Customer bid acceptance reconciliation is unavailable', 'foreign reconciliation fails closed');
reset role;

select throws_ok($$update private.customer_bid_acceptance_receipts set intent_fingerprint=intent_fingerprint where request_id='00000000-0000-4000-8000-0000000f1001'$$, '42501', 'Customer bid acceptance receipts are append-only', 'receipt cannot be updated');
select throws_ok($$delete from private.customer_bid_acceptance_receipts where request_id='00000000-0000-4000-8000-0000000f1001'$$, '42501', 'Customer bid acceptance receipts are append-only', 'receipt cannot be deleted');

-- Forced downstream failures prove complete rollback and guard cleanup.
create function pg_temp.fail_ticket10f_audit() returns pg_catalog.trigger language plpgsql set search_path=pg_catalog as $$ begin if new.action='customer.bid_accepted' and new.metadata->>'request_id'='00000000-0000-4000-8000-0000000f1021' then raise exception 'forced audit failure'; end if; return new; end; $$;
create trigger fail_ticket10f_audit_insert before insert on public.audit_events for each row execute function pg_temp.fail_ticket10f_audit();
select pg_temp.set_ticket10f_actor('00000000-0000-4000-8000-0000000f0002'); set local role authenticated;
select throws_ok($$select * from public.ticket10f_test_accept('00000000-0000-4000-8000-0000000f1021','00000000-0000-4000-8000-0000000f3021','00000000-0000-4000-8000-0000000f5021')$$, '42501', 'Customer bid acceptance is unavailable', 'audit failure is privacy-safe'); reset role;
drop trigger fail_ticket10f_audit_insert on public.audit_events;
select is((select status from public.service_requests where id='00000000-0000-4000-8000-0000000f1021'), 'open'::public.request_status, 'audit failure rolls request back');
select is((select status from public.bids where id='00000000-0000-4000-8000-0000000f3021'), 'submitted'::public.bid_status, 'audit failure rolls selected bid back');
select is((select pg_catalog.count(*) from private.customer_bid_acceptance_receipts where request_id='00000000-0000-4000-8000-0000000f1021'), 0::pg_catalog.int8, 'audit failure rolls receipt back');
select is(coalesce(pg_catalog.current_setting('lekkadeall.allow_marketplace_state_transition', true), 'off'), 'off', 'audit failure clears transition guard');

create function pg_temp.fail_ticket10f_receipt() returns pg_catalog.trigger language plpgsql set search_path=pg_catalog as $$ begin if new.request_id='00000000-0000-4000-8000-0000000f1022' then raise exception 'forced receipt failure'; end if; return new; end; $$;
create trigger fail_ticket10f_receipt_insert before insert on private.customer_bid_acceptance_receipts for each row execute function pg_temp.fail_ticket10f_receipt();
select pg_temp.set_ticket10f_actor('00000000-0000-4000-8000-0000000f0002'); set local role authenticated;
select throws_ok($$select * from public.ticket10f_test_accept('00000000-0000-4000-8000-0000000f1022','00000000-0000-4000-8000-0000000f3022','00000000-0000-4000-8000-0000000f5022')$$, '42501', 'Customer bid acceptance is unavailable', 'receipt failure is privacy-safe'); reset role;
drop trigger fail_ticket10f_receipt_insert on private.customer_bid_acceptance_receipts;
select is((select status from public.service_requests where id='00000000-0000-4000-8000-0000000f1022'), 'open'::public.request_status, 'receipt failure rolls request back');
select is((select status from public.bids where id='00000000-0000-4000-8000-0000000f3022'), 'submitted'::public.bid_status, 'receipt failure rolls bid back');
select is((select pg_catalog.count(*) from public.audit_events where metadata->>'request_id'='00000000-0000-4000-8000-0000000f1022'), 0::pg_catalog.int8, 'receipt failure leaves no audit');
select is(coalesce(pg_catalog.current_setting('lekkadeall.allow_marketplace_state_transition', true), 'off'), 'off', 'receipt failure clears transition guard');

create function pg_temp.fail_ticket10f_request_update() returns pg_catalog.trigger language plpgsql set search_path=pg_catalog as $$ begin if new.id='00000000-0000-4000-8000-0000000f1023' then raise exception 'forced request update failure'; end if; return new; end; $$;
create trigger fail_ticket10f_request_update before update on public.service_requests for each row execute function pg_temp.fail_ticket10f_request_update();
select pg_temp.set_ticket10f_actor('00000000-0000-4000-8000-0000000f0002'); set local role authenticated;
select throws_ok($$select * from public.ticket10f_test_accept('00000000-0000-4000-8000-0000000f1023','00000000-0000-4000-8000-0000000f3023','00000000-0000-4000-8000-0000000f5023')$$, '42501', 'Customer bid acceptance is unavailable', 'request update failure is privacy-safe'); reset role;
drop trigger fail_ticket10f_request_update on public.service_requests;
select is((select status from public.service_requests where id='00000000-0000-4000-8000-0000000f1023'), 'open'::public.request_status, 'update failure leaves request open');
select is((select status from public.bids where id='00000000-0000-4000-8000-0000000f3023'), 'submitted'::public.bid_status, 'update failure rolls selected bid back');
select is((select pg_catalog.count(*) from private.customer_bid_acceptance_receipts where request_id='00000000-0000-4000-8000-0000000f1023'), 0::pg_catalog.int8, 'update failure leaves no receipt');
select is(coalesce(pg_catalog.current_setting('lekkadeall.allow_marketplace_state_transition', true), 'off'), 'off', 'update failure clears transition guard');

-- Release locks retained by the functional assertions before independent
-- sessions establish the concurrency barriers. pgTAP state and temporary
-- helper functions are session-scoped; committed synthetic rows are removed
-- by the explicit cleanup below.
commit;
begin;
set local search_path = public, extensions, auth;

-- True two-session races use the disposable local database only. The login
-- password is generated at runtime, never printed, and cleared after connect.
select is(
  extensions.dblink_connect(
    'ticket10f_a',
    pg_catalog.format(
      'hostaddr=%s port=%s dbname=%L user=%L password=%L',
      pg_catalog.inet_server_addr(), pg_catalog.current_setting('port'),
      pg_catalog.current_database(), 'ticket10f_concurrency_login',
      pg_catalog.current_setting('lekkadeall.ticket10f_concurrency_password')
    )
  ), 'OK', 'first independent acceptance session connects'
);
select is(
  extensions.dblink_connect(
    'ticket10f_b',
    pg_catalog.format(
      'hostaddr=%s port=%s dbname=%L user=%L password=%L',
      pg_catalog.inet_server_addr(), pg_catalog.current_setting('port'),
      pg_catalog.current_database(), 'ticket10f_concurrency_login',
      pg_catalog.current_setting('lekkadeall.ticket10f_concurrency_password')
    )
  ), 'OK', 'second independent acceptance session connects'
);

create function pg_temp.set_ticket10f_remote_actor(
  p_connection pg_catalog.text,
  p_actor_id pg_catalog.uuid
)
returns pg_catalog.void language plpgsql set search_path=pg_catalog as $$
begin
  perform extensions.dblink_exec(p_connection, 'set role authenticated');
  perform extensions.dblink_exec(
    p_connection,
    pg_catalog.format('set request.jwt.claim.sub = %L', p_actor_id::pg_catalog.text)
  );
  perform extensions.dblink_exec(
    p_connection,
    pg_catalog.format(
      'set request.jwt.claims = %L',
      pg_catalog.format('{"sub":"%s","role":"authenticated","aal":"aal1"}', p_actor_id)
    )
  );
end;
$$;

do $$
begin
  perform pg_catalog.set_config('lekkadeall.ticket10f_concurrency_password', '', false);
  perform extensions.dblink_exec('ticket10f_a', 'set application_name = ''ticket10f_a''');
  perform extensions.dblink_exec('ticket10f_b', 'set application_name = ''ticket10f_b''');
  perform extensions.dblink_exec('ticket10f_a', 'set lock_timeout = ''10s''');
  perform extensions.dblink_exec('ticket10f_b', 'set lock_timeout = ''10s''');
  perform extensions.dblink_exec('ticket10f_a', 'set statement_timeout = ''30s''');
  perform extensions.dblink_exec('ticket10f_b', 'set statement_timeout = ''30s''');
end;
$$;

create temporary table ticket10f_race_results (
  name pg_catalog.text primary key,
  result_value pg_catalog.text
) on commit drop;

-- Same request, bid and key: the waiter replays the one canonical result.
select pg_temp.set_ticket10f_remote_actor('ticket10f_a','00000000-0000-4000-8000-0000000f0002');
select pg_temp.set_ticket10f_remote_actor('ticket10f_b','00000000-0000-4000-8000-0000000f0002');
select is(extensions.dblink_exec('ticket10f_a','begin'), 'BEGIN', 'same-key winner begins');
select is(extensions.dblink_send_query('ticket10f_a',$q$select public.ticket10f_test_accept('00000000-0000-4000-8000-0000000f1201','00000000-0000-4000-8000-0000000f3201','00000000-0000-4000-8000-0000000f5201')$q$), 1, 'same-key winner starts');
insert into ticket10f_race_results select 'same-key-a', remote.result_value from extensions.dblink_get_result('ticket10f_a',false) as remote(result_value pg_catalog.text);
select is(extensions.dblink_send_query('ticket10f_b',$q$select public.ticket10f_test_accept('00000000-0000-4000-8000-0000000f1201','00000000-0000-4000-8000-0000000f3201','00000000-0000-4000-8000-0000000f5201')$q$), 1, 'same-key replay starts behind held request lock');
select is(extensions.dblink_is_busy('ticket10f_b'), 1, 'same-key replay is lock-blocked without a sleep');
select is(extensions.dblink_exec('ticket10f_a','commit'), 'COMMIT', 'same-key winner commits');
insert into ticket10f_race_results select 'same-key-b', remote.result_value from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text);
select is((select result_value from ticket10f_race_results where name='same-key-b'), (select result_value from ticket10f_race_results where name='same-key-a'), 'same-key waiter receives identical canonical result');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'same-key waiter result is fully drained');
select is((select pg_catalog.count(*) from private.customer_bid_acceptance_receipts where request_id='00000000-0000-4000-8000-0000000f1201'), 1::pg_catalog.int8, 'same-key race creates one receipt');
select is((select pg_catalog.count(*) from public.audit_events where action='customer.bid_accepted' and metadata->>'request_id'='00000000-0000-4000-8000-0000000f1201'), 1::pg_catalog.int8, 'same-key race creates one audit');

-- Same bid with a different key: one transition wins and the waiter fails.
select is(extensions.dblink_exec('ticket10f_a','begin'), 'BEGIN', 'different-key winner begins');
select is(extensions.dblink_send_query('ticket10f_a',$q$select public.ticket10f_test_accept('00000000-0000-4000-8000-0000000f1202','00000000-0000-4000-8000-0000000f3202','00000000-0000-4000-8000-0000000f5202')$q$), 1, 'different-key winner starts');
insert into ticket10f_race_results select 'different-key-a', remote.result_value from extensions.dblink_get_result('ticket10f_a',false) as remote(result_value pg_catalog.text);
select is(extensions.dblink_send_query('ticket10f_b',$q$select public.ticket10f_test_accept('00000000-0000-4000-8000-0000000f1202','00000000-0000-4000-8000-0000000f3202','00000000-0000-4000-8000-0000000f5292')$q$), 1, 'different-key waiter starts');
select is(extensions.dblink_is_busy('ticket10f_b'), 1, 'different-key waiter is lock-blocked');
select is(extensions.dblink_exec('ticket10f_a','commit'), 'COMMIT', 'different-key winner commits');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'different-key waiter fails generically');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'different-key waiter result is fully drained');
select is((select pg_catalog.count(*) from private.customer_bid_acceptance_receipts where request_id='00000000-0000-4000-8000-0000000f1202'), 1::pg_catalog.int8, 'different-key race creates one receipt');

-- Two selected bids on one request: request and ordered bid locks admit one.
select is(extensions.dblink_exec('ticket10f_a','begin'), 'BEGIN', 'different-bid winner begins');
select is(extensions.dblink_send_query('ticket10f_a',$q$select public.ticket10f_test_accept('00000000-0000-4000-8000-0000000f1203','00000000-0000-4000-8000-0000000f3203','00000000-0000-4000-8000-0000000f5203')$q$), 1, 'first selected bid starts');
insert into ticket10f_race_results select 'different-bid-a', remote.result_value from extensions.dblink_get_result('ticket10f_a',false) as remote(result_value pg_catalog.text);
select is(extensions.dblink_send_query('ticket10f_b',$q$select public.ticket10f_test_accept('00000000-0000-4000-8000-0000000f1203','00000000-0000-4000-8000-0000000f4203','00000000-0000-4000-8000-0000000f5293')$q$), 1, 'competing selected bid starts');
select is(extensions.dblink_is_busy('ticket10f_b'), 1, 'competing selection waits on request lock');
select is(extensions.dblink_exec('ticket10f_a','commit'), 'COMMIT', 'different-bid winner commits');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'competing selection loses generically');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'competing selection result is fully drained');
select is((select pg_catalog.count(*) from public.bids where request_id='00000000-0000-4000-8000-0000000f1203' and status='accepted'), 1::pg_catalog.int8, 'different-bid race has one accepted bid');
select is((select status from public.bids where id='00000000-0000-4000-8000-0000000f4203'), 'declined'::public.bid_status, 'losing submitted bid is declined once');

-- Withdrawal wins while holding the selected-bid lock.
select pg_temp.set_ticket10f_remote_actor('ticket10f_a','00000000-0000-4000-8000-0000000f0101');
select is(extensions.dblink_exec('ticket10f_a','begin'), 'BEGIN', 'withdrawal winner begins');
select is(extensions.dblink_send_query('ticket10f_a',$q$select public.provider_withdraw_bid('00000000-0000-4000-8000-0000000f3204')::pg_catalog.text$q$), 1, 'withdrawal starts first');
insert into ticket10f_race_results select 'withdraw-a', remote.result_value from extensions.dblink_get_result('ticket10f_a',false) as remote(result_value pg_catalog.text);
select is(extensions.dblink_send_query('ticket10f_b',$q$select public.ticket10f_test_accept('00000000-0000-4000-8000-0000000f1204','00000000-0000-4000-8000-0000000f3204','00000000-0000-4000-8000-0000000f5204')$q$), 1, 'acceptance starts behind withdrawal');
select is(extensions.dblink_is_busy('ticket10f_b'), 1, 'acceptance waits on withdrawn bid lock');
select is(extensions.dblink_exec('ticket10f_a','commit'), 'COMMIT', 'withdrawal commits');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'acceptance loses withdrawal race');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'withdrawal race result is fully drained');
select is((select status from public.bids where id='00000000-0000-4000-8000-0000000f3204'), 'withdrawn'::public.bid_status, 'withdrawal is authoritative');
select is((select status from public.service_requests where id='00000000-0000-4000-8000-0000000f1204'), 'open'::public.request_status, 'withdrawal race leaves request open');

-- Cancellation, close and expiry each win through the request lock.
select pg_temp.set_ticket10f_remote_actor('ticket10f_a','00000000-0000-4000-8000-0000000f0002');
select is(extensions.dblink_exec('ticket10f_a','begin'), 'BEGIN', 'cancellation winner begins');
select is(extensions.dblink_send_query('ticket10f_a',$q$select public.ticket10f_test_cancel_request('00000000-0000-4000-8000-0000000f1205')$q$), 1, 'cancellation starts first');
insert into ticket10f_race_results select 'cancel-a', remote.result_value from extensions.dblink_get_result('ticket10f_a',false) as remote(result_value pg_catalog.text);
select is(extensions.dblink_send_query('ticket10f_b',$q$select public.ticket10f_test_accept('00000000-0000-4000-8000-0000000f1205','00000000-0000-4000-8000-0000000f3205','00000000-0000-4000-8000-0000000f5205')$q$), 1, 'acceptance starts behind cancellation');
select is(extensions.dblink_is_busy('ticket10f_b'), 1, 'acceptance waits on cancellation request lock');
select is(extensions.dblink_exec('ticket10f_a','commit'), 'COMMIT', 'cancellation commits');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'acceptance loses cancellation race');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'cancellation race result is fully drained');
select is((select status from public.service_requests where id='00000000-0000-4000-8000-0000000f1205'), 'cancelled'::public.request_status, 'cancellation is authoritative');

select is(extensions.dblink_exec('ticket10f_a','begin'), 'BEGIN', 'close winner begins');
select is(extensions.dblink_send_query('ticket10f_a',$q$select public.ticket10f_test_close_request('00000000-0000-4000-8000-0000000f1206')$q$), 1, 'close starts first');
insert into ticket10f_race_results select 'close-a', remote.result_value from extensions.dblink_get_result('ticket10f_a',false) as remote(result_value pg_catalog.text);
select is(extensions.dblink_send_query('ticket10f_b',$q$select public.ticket10f_test_accept('00000000-0000-4000-8000-0000000f1206','00000000-0000-4000-8000-0000000f3206','00000000-0000-4000-8000-0000000f5206')$q$), 1, 'acceptance starts behind close');
select is(extensions.dblink_is_busy('ticket10f_b'), 1, 'acceptance waits on close request lock');
select is(extensions.dblink_exec('ticket10f_a','commit'), 'COMMIT', 'close commits');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'acceptance loses close race');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'close race result is fully drained');

select is(extensions.dblink_exec('ticket10f_a','begin'), 'BEGIN', 'expiry winner begins');
select is(extensions.dblink_send_query('ticket10f_a',$q$select public.ticket10f_test_expire_request('00000000-0000-4000-8000-0000000f1207')$q$), 1, 'expiry starts first');
insert into ticket10f_race_results select 'expiry-a', remote.result_value from extensions.dblink_get_result('ticket10f_a',false) as remote(result_value pg_catalog.text);
select is(extensions.dblink_send_query('ticket10f_b',$q$select public.ticket10f_test_accept('00000000-0000-4000-8000-0000000f1207','00000000-0000-4000-8000-0000000f3207','00000000-0000-4000-8000-0000000f5207')$q$), 1, 'acceptance starts behind expiry');
select is(extensions.dblink_is_busy('ticket10f_b'), 1, 'acceptance waits on expiry request lock');
select is(extensions.dblink_exec('ticket10f_a','commit'), 'COMMIT', 'expiry commits');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'acceptance loses expiry race');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'expiry race result is fully drained');

-- Provider suspension and expiry win while acceptance waits on authority locks.
select is(extensions.dblink_exec('ticket10f_a','begin'), 'BEGIN', 'provider suspension begins');
select is(extensions.dblink_send_query('ticket10f_a',$q$select public.ticket10f_test_set_provider_eligibility('00000000-0000-4000-8000-0000000f0102','suspended')$q$), 1, 'provider suspension starts first');
insert into ticket10f_race_results select 'suspend-a', remote.result_value from extensions.dblink_get_result('ticket10f_a',false) as remote(result_value pg_catalog.text);
select is(extensions.dblink_send_query('ticket10f_b',$q$select public.ticket10f_test_accept('00000000-0000-4000-8000-0000000f1208','00000000-0000-4000-8000-0000000f3208','00000000-0000-4000-8000-0000000f5208')$q$), 1, 'acceptance starts behind suspension');
select is(extensions.dblink_is_busy('ticket10f_b'), 1, 'acceptance waits on provider authority lock');
select is(extensions.dblink_exec('ticket10f_a','commit'), 'COMMIT', 'provider suspension commits');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'acceptance loses suspension race');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'suspension race result is fully drained');
select is(extensions.dblink_send_query('ticket10f_a',$q$select public.ticket10f_test_set_provider_eligibility('00000000-0000-4000-8000-0000000f0102','approved')$q$), 1, 'provider restore starts for isolated expiry race');
insert into ticket10f_race_results select 'restore-provider-a', remote.result_value from extensions.dblink_get_result('ticket10f_a',false) as remote(result_value pg_catalog.text);
select is((select result_value from ticket10f_race_results where name='restore-provider-a'), 'approved', 'provider is restored for isolated expiry race');

select is(extensions.dblink_exec('ticket10f_a','begin'), 'BEGIN', 'provider expiry begins');
select is(extensions.dblink_send_query('ticket10f_a',$q$select public.ticket10f_test_set_provider_eligibility('00000000-0000-4000-8000-0000000f0102','expired')$q$), 1, 'provider expiry starts first');
insert into ticket10f_race_results select 'provider-expiry-a', remote.result_value from extensions.dblink_get_result('ticket10f_a',false) as remote(result_value pg_catalog.text);
select is(extensions.dblink_send_query('ticket10f_b',$q$select public.ticket10f_test_accept('00000000-0000-4000-8000-0000000f1208','00000000-0000-4000-8000-0000000f3208','00000000-0000-4000-8000-0000000f5288')$q$), 1, 'acceptance starts behind provider expiry');
select is(extensions.dblink_is_busy('ticket10f_b'), 1, 'acceptance waits on expiring provider lock');
select is(extensions.dblink_exec('ticket10f_a','commit'), 'COMMIT', 'provider expiry commits');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'acceptance loses provider expiry race');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'provider expiry race result is fully drained');
select is(extensions.dblink_send_query('ticket10f_a',$q$select public.ticket10f_test_set_provider_eligibility('00000000-0000-4000-8000-0000000f0102','approved')$q$), 1, 'provider restore starts after expiry race');
insert into ticket10f_race_results select 'restore-provider-b', remote.result_value from extensions.dblink_get_result('ticket10f_a',false) as remote(result_value pg_catalog.text);
select is((select result_value from ticket10f_race_results where name='restore-provider-b'), 'approved', 'provider is restored after expiry race');

-- Service deactivation wins while acceptance waits on the service row.
select is(extensions.dblink_exec('ticket10f_a','begin'), 'BEGIN', 'service deactivation begins');
select is(extensions.dblink_send_query('ticket10f_a',$q$select public.ticket10f_test_set_service_active('00000000-0000-4000-8000-0000000f0105','00000000-0000-4000-8000-0000000f0201',false)$q$), 1, 'service deactivation starts first');
insert into ticket10f_race_results select 'service-a', remote.result_value from extensions.dblink_get_result('ticket10f_a',false) as remote(result_value pg_catalog.text);
select is(extensions.dblink_send_query('ticket10f_b',$q$select public.ticket10f_test_accept('00000000-0000-4000-8000-0000000f1209','00000000-0000-4000-8000-0000000f3209','00000000-0000-4000-8000-0000000f5209')$q$), 1, 'acceptance starts behind service deactivation');
select is(extensions.dblink_is_busy('ticket10f_b'), 1, 'acceptance waits on provider-service lock');
select is(extensions.dblink_exec('ticket10f_a','commit'), 'COMMIT', 'service deactivation commits');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'acceptance loses service race');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'service race result is fully drained');
select is(extensions.dblink_send_query('ticket10f_a',$q$select public.ticket10f_test_set_service_active('00000000-0000-4000-8000-0000000f0105','00000000-0000-4000-8000-0000000f0201',true)$q$), 1, 'service restore starts after isolated race');
insert into ticket10f_race_results select 'restore-service', remote.result_value from extensions.dblink_get_result('ticket10f_a',false) as remote(result_value pg_catalog.text);
select is((select result_value from ticket10f_race_results where name='restore-service'), 'active', 'service is restored after isolated race');

-- Acceptance wins before a late competing provider can submit.
select pg_temp.set_ticket10f_remote_actor('ticket10f_a','00000000-0000-4000-8000-0000000f0002');
select pg_temp.set_ticket10f_remote_actor('ticket10f_b','00000000-0000-4000-8000-0000000f0102');
select is(extensions.dblink_exec('ticket10f_a','begin'), 'BEGIN', 'late-bid acceptance begins');
select is(extensions.dblink_send_query('ticket10f_a',$q$select public.ticket10f_test_accept('00000000-0000-4000-8000-0000000f1210','00000000-0000-4000-8000-0000000f3210','00000000-0000-4000-8000-0000000f5210')$q$), 1, 'acceptance starts before late bid');
insert into ticket10f_race_results select 'late-a', remote.result_value from extensions.dblink_get_result('ticket10f_a',false) as remote(result_value pg_catalog.text);
select is(extensions.dblink_send_query('ticket10f_b',$q$select public.provider_submit_bid('00000000-0000-4000-8000-0000000f1210',52000)::pg_catalog.text$q$), 1, 'late competing bid starts');
select is(extensions.dblink_is_busy('ticket10f_b'), 1, 'late competing bid waits on request lock');
select is(extensions.dblink_exec('ticket10f_a','commit'), 'COMMIT', 'acceptance commits before late bid');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'late competing bid fails after award');
select is((select pg_catalog.count(*) from extensions.dblink_get_result('ticket10f_b',false) as remote(result_value pg_catalog.text)), 0::pg_catalog.int8, 'late competing bid result is fully drained');
select is((select pg_catalog.count(*) from public.bids where request_id='00000000-0000-4000-8000-0000000f1210'), 1::pg_catalog.int8, 'late race creates no extra bid');

select is(extensions.dblink_disconnect('ticket10f_a'), 'OK', 'first acceptance session disconnects');
select is(extensions.dblink_disconnect('ticket10f_b'), 'OK', 'second acceptance session disconnects');
select is((select pg_catalog.count(*) from public.bookings where request_id between '00000000-0000-4000-8000-0000000f1201' and '00000000-0000-4000-8000-0000000f1210'), 0::pg_catalog.int8, 'all races create zero bookings');
select is((select pg_catalog.count(*) from public.payments), 0::pg_catalog.int8, 'all races create zero payments');
select is((select pg_catalog.count(*) from public.audit_events where action='booking.address_revealed' and metadata->>'request_id' between '00000000-0000-4000-8000-0000000f1201' and '00000000-0000-4000-8000-0000000f1210'), 0::pg_catalog.int8, 'all races create zero address-reveal audits');

select * from finish();
rollback;

-- Remove committed concurrency fixtures and runtime-only login without
-- retaining its generated credential or any test-owned row.
begin;
alter table private.customer_bid_acceptance_receipts disable trigger customer_bid_acceptance_receipts_append_only;
delete from private.customer_bid_acceptance_receipts
where request_id between '00000000-0000-4000-8000-0000000f1001'
  and '00000000-0000-4000-8000-0000000f1210';
alter table private.customer_bid_acceptance_receipts enable trigger customer_bid_acceptance_receipts_append_only;

alter table public.audit_events disable trigger audit_events_append_only;
delete from public.audit_events
where actor_id between '00000000-0000-4000-8000-0000000f0001'
  and '00000000-0000-4000-8000-0000000f0105'
   or metadata ->> 'request_id' between '00000000-0000-4000-8000-0000000f1001'
     and '00000000-0000-4000-8000-0000000f1210';
alter table public.audit_events enable trigger audit_events_append_only;

set local lekkadeall.allow_marketplace_state_transition = 'on';
delete from public.bids where request_id between '00000000-0000-4000-8000-0000000f1001' and '00000000-0000-4000-8000-0000000f1210';
delete from public.service_requests where id between '00000000-0000-4000-8000-0000000f1001' and '00000000-0000-4000-8000-0000000f1210';
set local lekkadeall.allow_marketplace_state_transition = 'off';

alter table private.provider_eligibility_decisions disable trigger provider_eligibility_decisions_append_only;
delete from private.provider_marketplace_eligibility where provider_id between '00000000-0000-4000-8000-0000000f0101' and '00000000-0000-4000-8000-0000000f0105';
delete from private.provider_eligibility_decisions where provider_id between '00000000-0000-4000-8000-0000000f0101' and '00000000-0000-4000-8000-0000000f0105';
alter table private.provider_eligibility_decisions enable trigger provider_eligibility_decisions_append_only;
delete from public.provider_services where provider_id between '00000000-0000-4000-8000-0000000f0101' and '00000000-0000-4000-8000-0000000f0105';
delete from auth.users where id between '00000000-0000-4000-8000-0000000f0001' and '00000000-0000-4000-8000-0000000f0105';
delete from public.service_categories where id in ('00000000-0000-4000-8000-0000000f0201','00000000-0000-4000-8000-0000000f0202');
drop function public.ticket10f_test_accept(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid);
drop function public.ticket10f_test_cancel_request(pg_catalog.uuid);
drop function public.ticket10f_test_close_request(pg_catalog.uuid);
drop function public.ticket10f_test_expire_request(pg_catalog.uuid);
drop function public.ticket10f_test_set_provider_eligibility(pg_catalog.uuid, pg_catalog.text);
drop function public.ticket10f_test_set_service_active(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.bool);
commit;
drop role ticket10f_concurrency_login;
