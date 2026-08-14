create extension if not exists pgtap with schema extensions;

begin;
select plan(89);

create function pg_temp.set_ticket10e_actor(p_actor_id pg_catalog.uuid)
returns pg_catalog.void
language plpgsql
set search_path = pg_catalog
as $$
begin
  perform pg_catalog.set_config(
    'request.jwt.claim.sub',
    pg_catalog.coalesce(p_actor_id::pg_catalog.text, ''),
    true
  );
  perform pg_catalog.set_config(
    'request.jwt.claims',
    case when p_actor_id is null then '{"role":"authenticated","aal":"aal1"}'
      else pg_catalog.format(
        '{"sub":"%s","role":"authenticated","aal":"aal1"}',
        p_actor_id
      )
    end,
    true
  );
end;
$$;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000a0001', 'ticket10e-admin@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000a0002', 'ticket10e-owner@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000a0003', 'ticket10e-other@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000a0004', 'ticket10e-restricted@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000a0005', 'ticket10e-suspended@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000a0006', 'ticket10e-closed@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000a0007', 'ticket10e-provider-role@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000a0008', 'ticket10e-support-role@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000a0009', 'ticket10e-admin-role@lekkadeall.test'),
  ('00000000-0000-4000-8000-0000000a0010', 'ticket10e-missing-profile@lekkadeall.test');

insert into auth.users (id, email)
select
  pg_catalog.format(
    '00000000-0000-4000-8000-0000000e%s',
    pg_catalog.lpad(provider_number::pg_catalog.text, 4, '0')
  )::pg_catalog.uuid,
  pg_catalog.format('ticket10e-provider-%s@lekkadeall.test', provider_number)
from pg_catalog.generate_series(1, 31) as provider_number;

set local lekkadeall.allow_privileged_profile_update = 'on';
update public.profiles set role = 'admin'::public.user_role
where id in (
  '00000000-0000-4000-8000-0000000a0001',
  '00000000-0000-4000-8000-0000000a0009'
);
update public.profiles set role = 'provider'::public.user_role
where id = '00000000-0000-4000-8000-0000000a0007'
   or id::pg_catalog.text like '00000000-0000-4000-8000-0000000e%';
update public.profiles set role = 'support'::public.user_role
where id = '00000000-0000-4000-8000-0000000a0008';
update public.profiles set account_status = 'restricted'
where id = '00000000-0000-4000-8000-0000000a0004';
update public.profiles set account_status = 'suspended'
where id = '00000000-0000-4000-8000-0000000a0005';
update public.profiles set account_status = 'closed'
where id = '00000000-0000-4000-8000-0000000a0006';
set local lekkadeall.allow_privileged_profile_update = 'off';

delete from public.profiles
where id = '00000000-0000-4000-8000-0000000a0010';

insert into public.service_categories (id, slug, name, active) values
  ('00000000-0000-4000-8000-0000000c0100', 'ticket10e-active', 'Ticket 10E Active', true),
  ('00000000-0000-4000-8000-0000000c0101', 'ticket10e-inactive', 'Ticket 10E Inactive', false);

insert into public.provider_profiles (
  user_id, business_name, service_radius_km, verification_status, review_status
)
select
  pg_catalog.format(
    '00000000-0000-4000-8000-0000000e%s',
    pg_catalog.lpad(provider_number::pg_catalog.text, 4, '0')
  )::pg_catalog.uuid,
  pg_catalog.format('Ticket 10E provider %s', provider_number),
  20,
  'not_started'::public.verification_status,
  'approved'
from pg_catalog.generate_series(1, 31) as provider_number;

create temporary table ticket10e_decisions on commit drop as
select
  provider.user_id as provider_id,
  pg_catalog.gen_random_uuid() as decision_id,
  pg_catalog.gen_random_uuid() as idempotency_key
from public.provider_profiles as provider
where provider.user_id::pg_catalog.text like '00000000-0000-4000-8000-0000000e%';

insert into private.provider_eligibility_decisions (
  id, provider_id, reviewer_id, action, previous_status, new_status, basis,
  policy_version, expires_at, reason_code, idempotency_key,
  intent_fingerprint, decided_at
)
select
  decision.decision_id,
  decision.provider_id,
  '00000000-0000-4000-8000-0000000a0001'::pg_catalog.uuid,
  'approve_manual_pilot',
  'pending',
  'approved',
  'manual_pilot',
  'provider-eligibility-v1',
  pg_catalog.statement_timestamp() + '30 days'::pg_catalog.interval,
  'manual_pilot_approved',
  decision.idempotency_key,
  pg_catalog.format('ticket10e-%s', decision.provider_id),
  pg_catalog.statement_timestamp()
from ticket10e_decisions as decision;

update private.provider_marketplace_eligibility as eligibility
set status = 'approved',
    basis = 'manual_pilot',
    policy_version = 'provider-eligibility-v1',
    expires_at = pg_catalog.statement_timestamp() + '30 days'::pg_catalog.interval,
    current_decision_id = decision.decision_id,
    reviewer_id = '00000000-0000-4000-8000-0000000a0001'::pg_catalog.uuid,
    reason_code = 'manual_pilot_approved'
from ticket10e_decisions as decision
where decision.provider_id = eligibility.provider_id;

set local lekkadeall.allow_privileged_provider_profile_update = 'on';
update public.provider_profiles
set review_status = 'suspended'
where user_id = '00000000-0000-4000-8000-0000000e0028';
set local lekkadeall.allow_privileged_provider_profile_update = 'off';
update private.provider_marketplace_eligibility
set status = 'suspended'
where provider_id = '00000000-0000-4000-8000-0000000e0028';

insert into public.provider_services (
  provider_id, category_id, description, base_price_minor, active
)
select
  pg_catalog.format(
    '00000000-0000-4000-8000-0000000e%s',
    pg_catalog.lpad(provider_number::pg_catalog.text, 4, '0')
  )::pg_catalog.uuid,
  '00000000-0000-4000-8000-0000000c0100'::pg_catalog.uuid,
  null,
  null,
  provider_number <> 29
from pg_catalog.generate_series(1, 31) as provider_number;

insert into public.provider_services (
  provider_id, category_id, description, base_price_minor, active
) values (
  '00000000-0000-4000-8000-0000000e0001',
  '00000000-0000-4000-8000-0000000c0101',
  null,
  null,
  true
);

create temporary table ticket10e_clock (
  decision_at pg_catalog.timestamptz not null
) on commit drop;
insert into ticket10e_clock values (pg_catalog.statement_timestamp());

set local lekkadeall.allow_marketplace_state_transition = 'on';
insert into public.service_requests (
  id, customer_id, category_id, title, description, suburb, city,
  requested_start, budget_minor, status, closes_at, published_at,
  awarded_at, cancelled_at
)
select request.*
from (
  values
    ('00000000-0000-4000-8000-0000000b0201'::pg_catalog.uuid, '00000000-0000-4000-8000-0000000a0002'::pg_catalog.uuid, '00000000-0000-4000-8000-0000000c0100'::pg_catalog.uuid, 'Live customer bid request'::pg_catalog.text, 'Canonical public request for current customer bid viewing.'::pg_catalog.text, 'Die Bult'::pg_catalog.text, 'Potchefstroom'::pg_catalog.text, (select decision_at + '5 days'::pg_catalog.interval from ticket10e_clock), 90000::pg_catalog.int4, 'open'::public.request_status, (select decision_at + '3 days'::pg_catalog.interval from ticket10e_clock), (select decision_at - '1 hour'::pg_catalog.interval from ticket10e_clock), null::pg_catalog.timestamptz, null::pg_catalog.timestamptz),
    ('00000000-0000-4000-8000-0000000b0202', '00000000-0000-4000-8000-0000000a0002', '00000000-0000-4000-8000-0000000c0100', 'Live request without bids', 'Canonical public request with no visible provider bids.', 'Die Bult', 'Potchefstroom', (select decision_at + '5 days' from ticket10e_clock), 90000, 'open', (select decision_at + '3 days' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), null, null),
    ('00000000-0000-4000-8000-0000000b0203', '00000000-0000-4000-8000-0000000a0003', '00000000-0000-4000-8000-0000000c0100', 'Foreign customer bid request', 'Canonical public request owned by another customer.', 'Die Bult', 'Potchefstroom', (select decision_at + '5 days' from ticket10e_clock), 90000, 'open', (select decision_at + '3 days' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), null, null),
    ('00000000-0000-4000-8000-0000000b0204', '00000000-0000-4000-8000-0000000a0002', '00000000-0000-4000-8000-0000000c0100', 'Draft customer bid request', 'Draft request is unavailable for bid viewing.', 'Die Bult', 'Potchefstroom', (select decision_at + '5 days' from ticket10e_clock), 90000, 'draft', null, null, null, null),
    ('00000000-0000-4000-8000-0000000b0205', '00000000-0000-4000-8000-0000000a0002', '00000000-0000-4000-8000-0000000c0100', 'Cancelled customer bid request', 'Cancelled request is unavailable for bid viewing.', 'Die Bult', 'Potchefstroom', (select decision_at + '5 days' from ticket10e_clock), 90000, 'cancelled', null, (select decision_at - '2 hours' from ticket10e_clock), null, (select decision_at - '1 hour' from ticket10e_clock)),
    ('00000000-0000-4000-8000-0000000b0206', '00000000-0000-4000-8000-0000000a0002', '00000000-0000-4000-8000-0000000c0100', 'Awarded customer bid request', 'Awarded request is unavailable for bid viewing.', 'Die Bult', 'Potchefstroom', (select decision_at + '5 days' from ticket10e_clock), 90000, 'awarded', (select decision_at + '3 days' from ticket10e_clock), (select decision_at - '2 hours' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), null),
    ('00000000-0000-4000-8000-0000000b0207', '00000000-0000-4000-8000-0000000a0002', '00000000-0000-4000-8000-0000000c0100', 'Unpublished customer bid request', 'Unpublished request is unavailable for bid viewing.', 'Die Bult', 'Potchefstroom', (select decision_at + '5 days' from ticket10e_clock), 90000, 'open', (select decision_at + '3 days' from ticket10e_clock), null, null, null),
    ('00000000-0000-4000-8000-0000000b0208', '00000000-0000-4000-8000-0000000a0002', '00000000-0000-4000-8000-0000000c0100', 'Past close customer bid request', 'Past-close request is unavailable for bid viewing.', 'Die Bult', 'Potchefstroom', (select decision_at + '5 days' from ticket10e_clock), 90000, 'open', (select decision_at - '1 minute' from ticket10e_clock), (select decision_at - '2 hours' from ticket10e_clock), null, null),
    ('00000000-0000-4000-8000-0000000b0209', '00000000-0000-4000-8000-0000000a0002', '00000000-0000-4000-8000-0000000c0100', 'Inconsistent customer bid request', 'Inconsistent request timing is unavailable for bid viewing.', 'Die Bult', 'Potchefstroom', (select decision_at + '2 days' from ticket10e_clock), 90000, 'open', (select decision_at + '3 days' from ticket10e_clock), (select decision_at - '2 hours' from ticket10e_clock), null, null),
    ('00000000-0000-4000-8000-0000000b0210', '00000000-0000-4000-8000-0000000a0002', '00000000-0000-4000-8000-0000000c0100', 'Expired customer bid request', 'Expired request is unavailable for bid viewing.', 'Die Bult', 'Potchefstroom', (select decision_at + '2 days' from ticket10e_clock), 90000, 'expired', (select decision_at - '1 day' from ticket10e_clock), (select decision_at - '3 days' from ticket10e_clock), null, null),
    ('00000000-0000-4000-8000-0000000b0211', '00000000-0000-4000-8000-0000000a0002', '00000000-0000-4000-8000-0000000c0101', 'Inactive category bid request', 'Inactive category request is unavailable for bid viewing.', 'Die Bult', 'Potchefstroom', (select decision_at + '5 days' from ticket10e_clock), 90000, 'open', (select decision_at + '3 days' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), null, null),
    ('00000000-0000-4000-8000-0000000b0212', '00000000-0000-4000-8000-0000000a0002', '00000000-0000-4000-8000-0000000c0100', 'Future publication bid request', 'Future publication state is unavailable for bid viewing.', 'Die Bult', 'Potchefstroom', (select decision_at + '5 days' from ticket10e_clock), 90000, 'open', (select decision_at + '3 days' from ticket10e_clock), (select decision_at + '1 hour' from ticket10e_clock), null, null)
) as request(
  id, customer_id, category_id, title, description, suburb, city,
  requested_start, budget_minor, status, closes_at, published_at,
  awarded_at, cancelled_at
);

insert into public.bids (
  id, request_id, provider_id, amount_minor, currency, proposed_start,
  message, perks, status, expires_at, created_at, updated_at
)
select
  pg_catalog.format(
    '00000000-0000-4000-8000-0000000d%s',
    pg_catalog.lpad((300 + provider_number)::pg_catalog.text, 4, '0')
  )::pg_catalog.uuid,
  '00000000-0000-4000-8000-0000000b0201'::pg_catalog.uuid,
  pg_catalog.format(
    '00000000-0000-4000-8000-0000000e%s',
    pg_catalog.lpad(provider_number::pg_catalog.text, 4, '0')
  )::pg_catalog.uuid,
  50000 + provider_number,
  'ZAR',
  (select decision_at + '5 days'::pg_catalog.interval from ticket10e_clock),
  null,
  '{}'::pg_catalog.text[],
  'submitted'::public.bid_status,
  (select decision_at + '3 days'::pg_catalog.interval from ticket10e_clock),
  (select decision_at - '2 hours'::pg_catalog.interval
    + case when provider_number > 20 then '21 minutes'::pg_catalog.interval
      else provider_number * '1 minute'::pg_catalog.interval end
    from ticket10e_clock),
  (select decision_at - '2 hours'::pg_catalog.interval
    + case when provider_number > 20 then '21 minutes'::pg_catalog.interval
      else provider_number * '1 minute'::pg_catalog.interval end
    from ticket10e_clock)
from pg_catalog.generate_series(1, 22) as provider_number;

insert into public.bids (
  id, request_id, provider_id, amount_minor, currency, proposed_start,
  message, perks, status, expires_at, created_at, updated_at,
  accepted_at, declined_at, withdrawn_at
)
select hidden.*
from (
  values
    ('00000000-0000-4000-8000-0000000d0323'::pg_catalog.uuid, '00000000-0000-4000-8000-0000000b0201'::pg_catalog.uuid, '00000000-0000-4000-8000-0000000e0023'::pg_catalog.uuid, 51023::pg_catalog.int4, 'ZAR'::pg_catalog.bpchar, (select decision_at + '5 days' from ticket10e_clock), null::pg_catalog.text, '{}'::pg_catalog.text[], 'withdrawn'::public.bid_status, (select decision_at + '3 days' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), null::pg_catalog.timestamptz, null::pg_catalog.timestamptz, (select decision_at - '30 minutes' from ticket10e_clock)),
    ('00000000-0000-4000-8000-0000000d0324', '00000000-0000-4000-8000-0000000b0201', '00000000-0000-4000-8000-0000000e0024', 51024, 'ZAR', (select decision_at + '5 days' from ticket10e_clock), null, '{}', 'declined', (select decision_at + '3 days' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), null, (select decision_at - '30 minutes' from ticket10e_clock), null),
    ('00000000-0000-4000-8000-0000000d0325', '00000000-0000-4000-8000-0000000b0201', '00000000-0000-4000-8000-0000000e0025', 51025, 'ZAR', (select decision_at + '5 days' from ticket10e_clock), null, '{}', 'accepted', (select decision_at + '3 days' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), (select decision_at - '30 minutes' from ticket10e_clock), null, null),
    ('00000000-0000-4000-8000-0000000d0326', '00000000-0000-4000-8000-0000000b0201', '00000000-0000-4000-8000-0000000e0026', 51026, 'ZAR', (select decision_at + '5 days' from ticket10e_clock), null, '{}', 'expired', (select decision_at - '1 minute' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), null, null, null),
    ('00000000-0000-4000-8000-0000000d0327', '00000000-0000-4000-8000-0000000b0201', '00000000-0000-4000-8000-0000000e0027', 51027, 'ZAR', (select decision_at + '5 days' from ticket10e_clock), null, '{}', 'submitted', (select decision_at - '1 minute' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), null, null, null),
    ('00000000-0000-4000-8000-0000000d0328', '00000000-0000-4000-8000-0000000b0201', '00000000-0000-4000-8000-0000000e0028', 51028, 'ZAR', (select decision_at + '5 days' from ticket10e_clock), null, '{}', 'submitted', (select decision_at + '3 days' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), null, null, null),
    ('00000000-0000-4000-8000-0000000d0329', '00000000-0000-4000-8000-0000000b0201', '00000000-0000-4000-8000-0000000e0029', 51029, 'ZAR', (select decision_at + '5 days' from ticket10e_clock), null, '{}', 'submitted', (select decision_at + '3 days' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), null, null, null),
    ('00000000-0000-4000-8000-0000000d0330', '00000000-0000-4000-8000-0000000b0201', '00000000-0000-4000-8000-0000000e0030', 51030, 'ZAR', (select decision_at + '5 days' from ticket10e_clock), 'legacy hidden message', '{}', 'submitted', (select decision_at + '3 days' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), null, null, null),
    ('00000000-0000-4000-8000-0000000d0331', '00000000-0000-4000-8000-0000000b0201', '00000000-0000-4000-8000-0000000e0031', 51031, 'ZAR', (select decision_at + '5 days' from ticket10e_clock), null, array['legacy hidden perk'], 'submitted', (select decision_at + '3 days' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), null, null, null),
    ('00000000-0000-4000-8000-0000000d0332', '00000000-0000-4000-8000-0000000b0203', '00000000-0000-4000-8000-0000000e0001', 52000, 'ZAR', (select decision_at + '5 days' from ticket10e_clock), null, '{}', 'submitted', (select decision_at + '3 days' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), null, null, null),
    ('00000000-0000-4000-8000-0000000d0333', '00000000-0000-4000-8000-0000000b0211', '00000000-0000-4000-8000-0000000e0001', 53000, 'ZAR', (select decision_at + '5 days' from ticket10e_clock), null, '{}', 'submitted', (select decision_at + '3 days' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), (select decision_at - '1 hour' from ticket10e_clock), null, null, null)
) as hidden(
  id, request_id, provider_id, amount_minor, currency, proposed_start,
  message, perks, status, expires_at, created_at, updated_at,
  accepted_at, declined_at, withdrawn_at
);
set local lekkadeall.allow_marketplace_state_transition = 'off';

create temporary table ticket10e_counts on commit drop as
select
  (select pg_catalog.count(*) from public.bids) as bids,
  (select pg_catalog.count(*) from public.service_requests) as requests,
  (select pg_catalog.count(*) from public.bookings) as bookings,
  (select pg_catalog.count(*) from public.payments) as payments,
  (select pg_catalog.count(*) from public.audit_events) as audits;

-- Exact function contract, grants and raw-table denial.
select has_function('public', 'customer_list_current_bids', array['uuid', 'timestamp with time zone', 'uuid'], 'one customer current-bid function exists');
select is((select pg_catalog.count(*) from pg_catalog.pg_proc as proc join pg_catalog.pg_namespace as namespace on namespace.oid = proc.pronamespace where namespace.nspname = 'public' and proc.proname = 'customer_list_current_bids'), 1::pg_catalog.int8, 'no customer bid-view overload exists');
select is((select proc.proretset from pg_catalog.pg_proc as proc where proc.oid = 'public.customer_list_current_bids(uuid,timestamptz,uuid)'::pg_catalog.regprocedure), true, 'customer bid view returns a set');
select is((select proc.prorettype::pg_catalog.regtype::pg_catalog.text from pg_catalog.pg_proc as proc where proc.oid = 'public.customer_list_current_bids(uuid,timestamptz,uuid)'::pg_catalog.regprocedure), 'record', 'customer bid view returns a strict record projection');
select is((select proc.provolatile from pg_catalog.pg_proc as proc where proc.oid = 'public.customer_list_current_bids(uuid,timestamptz,uuid)'::pg_catalog.regprocedure), 's'::pg_catalog.char, 'customer bid view is STABLE');
select is((select proc.prosecdef from pg_catalog.pg_proc as proc where proc.oid = 'public.customer_list_current_bids(uuid,timestamptz,uuid)'::pg_catalog.regprocedure), true, 'customer bid view is SECURITY DEFINER');
select is((select proc.proconfig from pg_catalog.pg_proc as proc where proc.oid = 'public.customer_list_current_bids(uuid,timestamptz,uuid)'::pg_catalog.regprocedure), array['search_path=pg_catalog']::pg_catalog.text[], 'customer bid view fixes search path');
select is((select pg_catalog.array_agg(parameter.parameter_name::pg_catalog.text order by parameter.ordinal_position) from information_schema.parameters as parameter where parameter.specific_schema = 'public' and parameter.specific_name = (select routine.specific_name from information_schema.routines as routine where routine.routine_schema = 'public' and routine.routine_name = 'customer_list_current_bids') and parameter.parameter_mode = 'OUT'), array['bid_id','amount_minor','currency','proposed_start','status','expires_at','submitted_at']::pg_catalog.text[], 'customer bid view returns exactly seven named fields');
select is((select pg_catalog.array_agg((parameter.udt_schema || '.' || parameter.udt_name)::pg_catalog.text order by parameter.ordinal_position) from information_schema.parameters as parameter where parameter.specific_schema = 'public' and parameter.specific_name = (select routine.specific_name from information_schema.routines as routine where routine.routine_schema = 'public' and routine.routine_name = 'customer_list_current_bids') and parameter.parameter_mode = 'OUT'), array['pg_catalog.uuid','pg_catalog.int4','pg_catalog.bpchar','pg_catalog.timestamptz','public.bid_status','pg_catalog.timestamptz','pg_catalog.timestamptz']::pg_catalog.text[], 'customer bid view returns exact reviewed types');
select is(pg_catalog.pg_get_functiondef('public.customer_list_current_bids(uuid,timestamptz,uuid)'::pg_catalog.regprocedure) ~* 'select[[:space:]]+\*|%rowtype', false, 'customer bid view contains no broad projection');
select is(pg_catalog.pg_get_functiondef('public.customer_list_current_bids(uuid,timestamptz,uuid)'::pg_catalog.regprocedure) ~* '\mexecute\M|\mformat\M', false, 'customer bid view contains no dynamic SQL');
select is(pg_catalog.pg_get_functiondef('public.customer_list_current_bids(uuid,timestamptz,uuid)'::pg_catalog.regprocedure) ~* 'for[[:space:]]+(update|share)', false, 'customer bid view takes no row lock');
select is(pg_catalog.pg_get_functiondef('public.customer_list_current_bids(uuid,timestamptz,uuid)'::pg_catalog.regprocedure) ~* '\m(insert|update|delete)\M|set_config|append_audit', false, 'customer bid view contains no mutation or audit operation');
select is(pg_catalog.pg_get_functiondef('public.customer_list_current_bids(uuid,timestamptz,uuid)'::pg_catalog.regprocedure) ~* 'service_request_addresses|precise_address|bookings|payments|audit_events', false, 'customer bid view reads no prohibited adjacent relation or address field');
select is(pg_catalog.pg_get_functiondef('public.customer_list_current_bids(uuid,timestamptz,uuid)'::pg_catalog.regprocedure) ~* 'statement_timestamp\(\)', true, 'customer bid view uses one statement-time decision clock');
select is(pg_catalog.pg_get_functiondef('public.customer_list_current_bids(uuid,timestamptz,uuid)'::pg_catalog.regprocedure) ~* 'limit[[:space:]]+20', true, 'customer bid view has a fixed twenty-row page');
select is(pg_catalog.pg_get_functiondef('public.customer_list_current_bids(uuid,timestamptz,uuid)'::pg_catalog.regprocedure) ~* 'order by bid\.created_at asc, bid\.id asc', true, 'customer bid view uses chronological keyset ordering');
select is(has_function_privilege('public', 'public.customer_list_current_bids(uuid,timestamptz,uuid)', 'EXECUTE'), false, 'PUBLIC cannot execute customer bid view');
select is(has_function_privilege('anon', 'public.customer_list_current_bids(uuid,timestamptz,uuid)', 'EXECUTE'), false, 'anon cannot execute customer bid view');
select is(has_function_privilege('authenticated', 'public.customer_list_current_bids(uuid,timestamptz,uuid)', 'EXECUTE'), true, 'authenticated can execute customer bid view');
select is(has_function_privilege('service_role', 'public.customer_list_current_bids(uuid,timestamptz,uuid)', 'EXECUTE'), false, 'service role cannot execute customer bid view');
select is(has_function_privilege('public', 'public.customer_accept_bid(uuid)', 'EXECUTE'), false, 'PUBLIC cannot execute legacy acceptance');
select is(has_function_privilege('anon', 'public.customer_accept_bid(uuid)', 'EXECUTE'), false, 'anon cannot execute legacy acceptance');
select is(has_function_privilege('authenticated', 'public.customer_accept_bid(uuid)', 'EXECUTE'), false, 'authenticated cannot execute legacy acceptance');
select is(has_function_privilege('service_role', 'public.customer_accept_bid(uuid)', 'EXECUTE'), false, 'service role cannot execute legacy acceptance');
select is((select class.relrowsecurity from pg_catalog.pg_class as class where class.oid = 'public.bids'::pg_catalog.regclass), true, 'bid RLS remains enabled');
select is(has_table_privilege('authenticated', 'public.bids', 'SELECT'), false, 'authenticated still has no raw bid SELECT');
select is(has_table_privilege('authenticated', 'public.bids', 'INSERT'), false, 'authenticated still has no raw bid INSERT');
select is(has_table_privilege('authenticated', 'public.bids', 'UPDATE'), false, 'authenticated still has no raw bid UPDATE');
select is(has_table_privilege('authenticated', 'public.bids', 'DELETE'), false, 'authenticated still has no raw bid DELETE');
select is((select pg_catalog.count(*) from pg_catalog.pg_policies as policy where policy.schemaname = 'public' and policy.tablename = 'bids'), 0::pg_catalog.int8, 'no raw bid policy was restored');
select is((select pg_catalog.count(*) from pg_catalog.pg_proc as proc join pg_catalog.pg_namespace as namespace on namespace.oid = proc.pronamespace where namespace.nspname = 'public' and proc.proname like 'customer%bid%' and proc.proname <> 'customer_accept_bid'), 1::pg_catalog.int8, 'no alternate customer bid endpoint exists');
select is(has_function_privilege('authenticated', 'public.provider_read_own_bid(uuid)', 'EXECUTE'), true, 'provider own-bid reconciliation grant remains intact');
select is(has_function_privilege('authenticated', 'public.provider_submit_bid(uuid,integer)', 'EXECUTE'), true, 'provider submit grant remains intact');
select is(has_function_privilege('authenticated', 'public.provider_withdraw_bid(uuid)', 'EXECUTE'), true, 'provider withdraw grant remains intact');

-- Positive owner read, exact projection and keyset behavior.
select pg_temp.set_ticket10e_actor('00000000-0000-4000-8000-0000000a0002');
set local role authenticated;
select is((select pg_catalog.count(*) from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201')), 20::pg_catalog.int8, 'first customer bid page is capped at twenty');
select is((select bid_id from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201') order by submitted_at, bid_id limit 1), '00000000-0000-4000-8000-0000000d0301'::pg_catalog.uuid, 'first page starts at earliest submitted bid');
select is((select bid_id from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201') order by submitted_at desc, bid_id desc limit 1), '00000000-0000-4000-8000-0000000d0320'::pg_catalog.uuid, 'first page ends at deterministic twentieth bid');
select is((select pg_catalog.count(*) from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201') where status = 'submitted'::public.bid_status and currency = 'ZAR'), 20::pg_catalog.int8, 'page contains only submitted ZAR bids');
select is((select pg_catalog.count(*) from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0202')), 0::pg_catalog.int8, 'eligible owned request with no bids returns an empty set');
reset role;

create temporary table ticket10e_page_one on commit drop as
select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201');
create temporary table ticket10e_page_two on commit drop as
select * from public.customer_list_current_bids(
  '00000000-0000-4000-8000-0000000b0201',
  (select submitted_at from ticket10e_page_one where bid_id = '00000000-0000-4000-8000-0000000d0320'),
  '00000000-0000-4000-8000-0000000d0320'
);
select is((select pg_catalog.count(*) from ticket10e_page_two), 2::pg_catalog.int8, 'second keyset page returns remaining two bids');
select is((select pg_catalog.array_agg(bid_id order by submitted_at, bid_id) from ticket10e_page_two), array['00000000-0000-4000-8000-0000000d0321'::pg_catalog.uuid,'00000000-0000-4000-8000-0000000d0322'::pg_catalog.uuid], 'second page uses opaque bid ID tie-breaker');
select is((select pg_catalog.count(*) from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201', (select submitted_at from ticket10e_page_two where bid_id = '00000000-0000-4000-8000-0000000d0321'), '00000000-0000-4000-8000-0000000d0321')), 1::pg_catalog.int8, 'cursor inside equal timestamp returns only later opaque ID');
select is((select pg_catalog.count(distinct bid_id) from (select bid_id from ticket10e_page_one union all select bid_id from ticket10e_page_two) as pages), 22::pg_catalog.int8, 'keyset pages contain no duplicate bid');
select is((select pg_catalog.count(*) from ticket10e_page_one where bid_id = '00000000-0000-4000-8000-0000000d0332'), 0::pg_catalog.int8, 'bid from another request never enters owner page');

create temporary table ticket10e_after_visible on commit drop as
select * from public.customer_list_current_bids(
  '00000000-0000-4000-8000-0000000b0201',
  (select submitted_at from ticket10e_page_two where bid_id = '00000000-0000-4000-8000-0000000d0322'),
  '00000000-0000-4000-8000-0000000d0322'
);

-- Every denied actor/input/request receives the same fixed unavailable response.
select pg_temp.set_ticket10e_actor(null); set local role authenticated;
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201')$$, '42501', 'Customer bid viewing is unavailable', 'signed-out caller is denied generically'); reset role;
select pg_temp.set_ticket10e_actor('00000000-0000-4000-8000-0000000a0007'); set local role authenticated;
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201')$$, '42501', 'Customer bid viewing is unavailable', 'provider role is denied generically'); reset role;
select pg_temp.set_ticket10e_actor('00000000-0000-4000-8000-0000000a0008'); set local role authenticated;
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201')$$, '42501', 'Customer bid viewing is unavailable', 'support role is denied generically'); reset role;
select pg_temp.set_ticket10e_actor('00000000-0000-4000-8000-0000000a0009'); set local role authenticated;
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201')$$, '42501', 'Customer bid viewing is unavailable', 'admin role is denied generically'); reset role;
select pg_temp.set_ticket10e_actor('00000000-0000-4000-8000-0000000a0010'); set local role authenticated;
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201')$$, '42501', 'Customer bid viewing is unavailable', 'missing profile is denied generically'); reset role;
select pg_temp.set_ticket10e_actor('00000000-0000-4000-8000-0000000a0004'); set local role authenticated;
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201')$$, '42501', 'Customer bid viewing is unavailable', 'restricted customer is denied generically'); reset role;
select pg_temp.set_ticket10e_actor('00000000-0000-4000-8000-0000000a0005'); set local role authenticated;
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201')$$, '42501', 'Customer bid viewing is unavailable', 'suspended customer is denied generically'); reset role;
select pg_temp.set_ticket10e_actor('00000000-0000-4000-8000-0000000a0006'); set local role authenticated;
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201')$$, '42501', 'Customer bid viewing is unavailable', 'closed customer is denied generically'); reset role;
select pg_temp.set_ticket10e_actor('00000000-0000-4000-8000-0000000a0002'); set local role authenticated;
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0203')$$, '42501', 'Customer bid viewing is unavailable', 'foreign request is denied generically');
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0299')$$, '42501', 'Customer bid viewing is unavailable', 'missing request is denied generically');
select throws_ok($$select * from public.customer_list_current_bids(null)$$, '42501', 'Customer bid viewing is unavailable', 'null request is denied generically');
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-0000-0000-000000000000')$$, '42501', 'Customer bid viewing is unavailable', 'nil request is denied generically');
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201', pg_catalog.statement_timestamp() - interval '1 hour', null)$$, '42501', 'Customer bid viewing is unavailable', 'timestamp-only cursor is denied generically');
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201', null, '00000000-0000-4000-8000-0000000d0301')$$, '42501', 'Customer bid viewing is unavailable', 'ID-only cursor is denied generically');
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201', pg_catalog.statement_timestamp() + interval '1 hour', '00000000-0000-4000-8000-0000000d0301')$$, '42501', 'Customer bid viewing is unavailable', 'future cursor is denied generically');
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201', pg_catalog.statement_timestamp() - interval '1 hour', '00000000-0000-0000-0000-000000000000')$$, '42501', 'Customer bid viewing is unavailable', 'nil cursor ID is denied generically');
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0204')$$, '42501', 'Customer bid viewing is unavailable', 'draft request is denied generically');
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0205')$$, '42501', 'Customer bid viewing is unavailable', 'cancelled request is denied generically');
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0206')$$, '42501', 'Customer bid viewing is unavailable', 'awarded request is denied generically');
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0210')$$, '42501', 'Customer bid viewing is unavailable', 'expired request is denied generically');
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0207')$$, '42501', 'Customer bid viewing is unavailable', 'unpublished request is denied generically');
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0208')$$, '42501', 'Customer bid viewing is unavailable', 'past-close request is denied generically');
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0209')$$, '42501', 'Customer bid viewing is unavailable', 'inconsistent request is denied generically');
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0211')$$, '42501', 'Customer bid viewing is unavailable', 'inactive-category request is denied generically');
select throws_ok($$select * from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0212')$$, '42501', 'Customer bid viewing is unavailable', 'future-published request is denied generically');
reset role;

-- Hidden bid/provider states and fresh current-authority decisions.
select is((select pg_catalog.count(*) from ticket10e_after_visible where bid_id between '00000000-0000-4000-8000-0000000d0323' and '00000000-0000-4000-8000-0000000d0326'), 0::pg_catalog.int8, 'terminal bids are hidden');
select is((select pg_catalog.count(*) from ticket10e_after_visible where bid_id = '00000000-0000-4000-8000-0000000d0327'), 0::pg_catalog.int8, 'expired submission is hidden');
select is((select pg_catalog.count(*) from ticket10e_after_visible where bid_id = '00000000-0000-4000-8000-0000000d0328'), 0::pg_catalog.int8, 'ineligible provider bid is hidden');
select is((select pg_catalog.count(*) from ticket10e_after_visible where bid_id = '00000000-0000-4000-8000-0000000d0329'), 0::pg_catalog.int8, 'inactive-service bid is hidden');
select is((select pg_catalog.count(*) from ticket10e_after_visible where bid_id = '00000000-0000-4000-8000-0000000d0330'), 0::pg_catalog.int8, 'legacy message bid is hidden');
select is((select pg_catalog.count(*) from ticket10e_after_visible where bid_id = '00000000-0000-4000-8000-0000000d0331'), 0::pg_catalog.int8, 'legacy perks bid is hidden');

set local lekkadeall.allow_privileged_provider_profile_update = 'on';
update public.provider_profiles set review_status = 'approved'
where user_id = '00000000-0000-4000-8000-0000000e0028';
set local lekkadeall.allow_privileged_provider_profile_update = 'off';
update private.provider_marketplace_eligibility
set status = 'expired',
    expires_at = pg_catalog.statement_timestamp() - '1 second'::pg_catalog.interval
where provider_id = '00000000-0000-4000-8000-0000000e0028';
select is((select pg_catalog.count(*) from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201', (select submitted_at from ticket10e_page_two where bid_id = '00000000-0000-4000-8000-0000000d0322'), '00000000-0000-4000-8000-0000000d0322') where bid_id = '00000000-0000-4000-8000-0000000d0328'), 0::pg_catalog.int8, 'expired provider bid remains hidden on a fresh read');

update private.provider_marketplace_eligibility set status = 'suspended'
where provider_id = '00000000-0000-4000-8000-0000000e0001';
select is((select pg_catalog.count(*) from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201') where bid_id = '00000000-0000-4000-8000-0000000d0301'), 0::pg_catalog.int8, 'fresh read hides newly suspended provider bid');
update private.provider_marketplace_eligibility set status = 'approved'
where provider_id = '00000000-0000-4000-8000-0000000e0001';
select is((select pg_catalog.count(*) from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201') where bid_id = '00000000-0000-4000-8000-0000000d0301'), 1::pg_catalog.int8, 'fresh read restores currently eligible provider bid');
update public.provider_services set active = false
where provider_id = '00000000-0000-4000-8000-0000000e0002'
  and category_id = '00000000-0000-4000-8000-0000000c0100';
select is((select pg_catalog.count(*) from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201') where bid_id = '00000000-0000-4000-8000-0000000d0302'), 0::pg_catalog.int8, 'fresh read hides newly inactive-service bid');
update public.provider_services set active = true
where provider_id = '00000000-0000-4000-8000-0000000e0002'
  and category_id = '00000000-0000-4000-8000-0000000c0100';
select is((select pg_catalog.count(*) from public.customer_list_current_bids('00000000-0000-4000-8000-0000000b0201') where bid_id = '00000000-0000-4000-8000-0000000d0302'), 1::pg_catalog.int8, 'fresh read restores active-service bid');

-- Viewed bid UUID cannot reach acceptance or any adjacent mutation.
select pg_temp.set_ticket10e_actor('00000000-0000-4000-8000-0000000a0002');
set local role authenticated;
select throws_ok($$select public.customer_accept_bid('00000000-0000-4000-8000-0000000d0301')$$, '42501', 'permission denied for function customer_accept_bid', 'viewed bid UUID cannot execute legacy acceptance');
select is((select pg_catalog.count(*) from public.provider_read_own_bid('00000000-0000-4000-8000-0000000b0201')), 0::pg_catalog.int8, 'customer cannot repurpose provider own-bid read');
reset role;
select is((select status::pg_catalog.text from public.bids where id = '00000000-0000-4000-8000-0000000d0301'), 'submitted', 'blocked acceptance leaves bid submitted');
select is((select pg_catalog.count(*) from public.bookings), (select bookings from ticket10e_counts), 'blocked acceptance and viewing create no booking');
select is((select pg_catalog.count(*) from public.payments), (select payments from ticket10e_counts), 'blocked acceptance and viewing create no payment');
select is((select pg_catalog.count(*) from public.audit_events), (select audits from ticket10e_counts), 'blocked acceptance and viewing create no audit');
select is((select pg_catalog.count(*) from public.bids), (select bids from ticket10e_counts), 'viewing creates or deletes no bid');
select is((select pg_catalog.count(*) from public.service_requests), (select requests from ticket10e_counts), 'viewing mutates no request');

select * from finish();
rollback;
