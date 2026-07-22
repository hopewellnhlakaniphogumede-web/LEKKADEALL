begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, auth;

select plan(62);

\ir rls_test_seed.inc

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000009001', 'ticket9a7-active@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000009002', 'ticket9a7-other@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000009003', 'ticket9a7-restricted@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000009004', 'ticket9a7-suspended@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000009005', 'ticket9a7-closed@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000009006', 'ticket9a7-support@lekkadeall.test');

set local lekkadeall.allow_privileged_profile_update = 'on';

update public.profiles as p
set display_name = v.display_name,
    account_status = v.account_status,
    updated_at = now()
from (values
  ('00000000-0000-0000-0000-000000009001'::uuid, 'Active Customer', 'active'),
  ('00000000-0000-0000-0000-000000009002'::uuid, 'Other Customer', 'active'),
  ('00000000-0000-0000-0000-000000009003'::uuid, 'Restricted Customer', 'restricted'),
  ('00000000-0000-0000-0000-000000009004'::uuid, 'Suspended Customer', 'suspended'),
  ('00000000-0000-0000-0000-000000009005'::uuid, 'Closed Customer', 'closed'),
  ('00000000-0000-0000-0000-000000009006'::uuid, 'Support User', 'active')
) as v(id, display_name, account_status)
where p.id = v.id;

update public.profiles
set role = 'support'::public.user_role,
    updated_at = now()
where id = '00000000-0000-0000-0000-000000009006';

set local lekkadeall.allow_privileged_profile_update = 'off';

set local lekkadeall.allow_marketplace_state_transition = 'on';

insert into public.service_requests (
  id, customer_id, category_id, title, description, suburb, city,
  requested_start, budget_minor, status, closes_at,
  published_at, awarded_at, cancelled_at, created_at, updated_at
) values
  (
    '00000000-0000-0000-0000-000000009101', '00000000-0000-0000-0000-000000009001',
    '00000000-0000-0000-0000-000000000100', 'Strict success draft',
    'Safe service request fixture for draft cancellation testing.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 81000,
    'draft', null, null, null, null, now() - interval '2 hours', now() - interval '2 hours'
  ),
  (
    '00000000-0000-0000-0000-000000009102', '00000000-0000-0000-0000-000000009002',
    '00000000-0000-0000-0000-000000000100', 'Other customer draft',
    'Safe draft fixture belonging to another active customer.',
    'Miederpark', 'Potchefstroom', now() + interval '8 days', 82000,
    'draft', null, null, null, null, now() - interval '2 hours', now() - interval '2 hours'
  ),
  (
    '00000000-0000-0000-0000-000000009103', '00000000-0000-0000-0000-000000009001',
    '00000000-0000-0000-0000-000000000100', 'Open request fixture',
    'Safe open request fixture for strict state rejection.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 83000,
    'open', now() + interval '2 days', now(), null, null, now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009104', '00000000-0000-0000-0000-000000009001',
    '00000000-0000-0000-0000-000000000100', 'Awarded request fixture',
    'Safe awarded request fixture for strict state rejection.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 84000,
    'awarded', now() + interval '2 days', now(), now(), null, now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009105', '00000000-0000-0000-0000-000000009001',
    '00000000-0000-0000-0000-000000000100', 'Cancelled request fixture',
    'Safe cancelled request fixture for repeat-call rejection.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 85000,
    'cancelled', null, null, null, now(), now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009106', '00000000-0000-0000-0000-000000009001',
    '00000000-0000-0000-0000-000000000100', 'Expired request fixture',
    'Safe expired request fixture for strict state rejection.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 86000,
    'expired', now() - interval '1 hour', now() - interval '3 days', null, null, now() - interval '4 days', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009107', '00000000-0000-0000-0000-000000009001',
    '00000000-0000-0000-0000-000000000100', 'Inconsistent close draft',
    'Safe draft fixture with inconsistent close state.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 87000,
    'draft', now() + interval '2 days', null, null, null, now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009108', '00000000-0000-0000-0000-000000009001',
    '00000000-0000-0000-0000-000000000100', 'Inconsistent published draft',
    'Safe draft fixture with inconsistent publication state.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 88000,
    'draft', null, now(), null, null, now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009109', '00000000-0000-0000-0000-000000009001',
    '00000000-0000-0000-0000-000000000100', 'Inconsistent awarded draft',
    'Safe draft fixture with inconsistent award state.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 89000,
    'draft', null, null, now(), null, now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009110', '00000000-0000-0000-0000-000000009001',
    '00000000-0000-0000-0000-000000000100', 'Inconsistent cancelled draft',
    'Safe draft fixture with inconsistent cancellation state.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 90000,
    'draft', null, null, null, now(), now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009111', '00000000-0000-0000-0000-000000009001',
    '00000000-0000-0000-0000-000000000100', 'Bid contaminated draft',
    'Safe draft fixture with inconsistent provider bid state.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 91000,
    'draft', null, null, null, null, now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009112', '00000000-0000-0000-0000-000000009001',
    '00000000-0000-0000-0000-000000000100', 'Selected provider draft',
    'Safe draft fixture with inconsistent accepted provider state.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 92000,
    'draft', null, null, null, null, now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009113', '00000000-0000-0000-0000-000000009001',
    '00000000-0000-0000-0000-000000000100', 'Booked draft fixture',
    'Safe draft fixture with inconsistent booking state.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 93000,
    'draft', null, null, null, null, now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009130', '00000000-0000-0000-0000-000000009001',
    '00000000-0000-0000-0000-000000000100', 'Audit rollback draft',
    'Safe draft fixture for atomic audit rollback testing.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 94000,
    'draft', null, null, null, null, now() - interval '2 hours', now() - interval '1 hour'
  );

insert into public.bids (
  id, request_id, provider_id, amount_minor, currency, proposed_start,
  message, status, expires_at, accepted_at
) values
  (
    '00000000-0000-0000-0000-000000009201',
    '00000000-0000-0000-0000-000000009111',
    '00000000-0000-0000-0000-000000000011',
    70000, 'ZAR', now() + interval '8 days',
    'Inconsistent submitted bid fixture.', 'submitted', now() + interval '2 days', null
  ),
  (
    '00000000-0000-0000-0000-000000009202',
    '00000000-0000-0000-0000-000000009112',
    '00000000-0000-0000-0000-000000000011',
    71000, 'ZAR', now() + interval '8 days',
    'Inconsistent accepted bid fixture.', 'accepted', now() + interval '2 days', now()
  ),
  (
    '00000000-0000-0000-0000-000000009203',
    '00000000-0000-0000-0000-000000009113',
    '00000000-0000-0000-0000-000000000011',
    72000, 'ZAR', now() + interval '8 days',
    'Inconsistent booked bid fixture.', 'accepted', now() + interval '2 days', now()
  );

insert into public.bookings (
  id, public_reference, request_id, bid_id, customer_id, provider_id,
  service_amount_minor, platform_fee_minor, currency, scheduled_start, status
) values (
  '00000000-0000-0000-0000-000000009301', 'TICKET-NINE-A-SEVEN-BOOKING',
  '00000000-0000-0000-0000-000000009113', '00000000-0000-0000-0000-000000009203',
  '00000000-0000-0000-0000-000000009001', '00000000-0000-0000-0000-000000000011',
  72000, 3600, 'ZAR', now() + interval '8 days', 'scheduled'
);

set local lekkadeall.allow_marketplace_state_transition = 'off';

create function pg_temp.cancel_draft_error(p_request_id uuid)
returns text
language plpgsql
as $$
begin
  perform public.customer_cancel_draft_request(p_request_id);
  return '<no error>';
exception
  when others then return sqlstate || ':' || sqlerrm;
end;
$$;

create function pg_temp.try_direct_cancel_draft(p_request_id uuid)
returns boolean
language plpgsql
as $$
begin
  update public.service_requests
  set status = 'cancelled', cancelled_at = now()
  where id = p_request_id;
  return true;
exception
  when others then return false;
end;
$$;

-- 1-19. Function contract, fixed authority, and restrictive grants.
select ok(
  to_regprocedure('public.customer_cancel_draft_request(uuid)') is not null,
  'strict customer draft cancellation function exists'
);

select ok(
  (select p.prorettype = 'public.request_status'::regtype
   from pg_proc p where p.oid = 'public.customer_cancel_draft_request(uuid)'::regprocedure),
  'strict cancellation returns only public.request_status'
);

select ok(
  (select p.prosecdef from pg_proc p where p.oid = 'public.customer_cancel_draft_request(uuid)'::regprocedure),
  'strict cancellation is SECURITY DEFINER'
);

select is(
  (select p.provolatile::text from pg_proc p where p.oid = 'public.customer_cancel_draft_request(uuid)'::regprocedure),
  'v',
  'strict cancellation is VOLATILE'
);

select ok(
  (select coalesce(p.proconfig, '{}'::text[]) @> array['search_path=pg_catalog']
   from pg_proc p where p.oid = 'public.customer_cancel_draft_request(uuid)'::regprocedure),
  'strict cancellation uses the fixed pg_catalog search_path'
);

select unalike(
  lower(pg_get_functiondef('public.customer_cancel_draft_request(uuid)'::regprocedure)),
  '%execute %',
  'strict cancellation contains no dynamic SQL'
);

-- pgTAP names its positive SQL LIKE assertion alike(...).
select alike(
  lower(pg_get_functiondef('public.customer_cancel_draft_request(uuid)'::regprocedure)),
  '%auth.uid()%',
  'strict cancellation derives actor identity from auth.uid()'
);

select alike(
  lower(pg_get_functiondef('public.customer_cancel_draft_request(uuid)'::regprocedure)),
  '%for share%',
  'strict cancellation locks the actor profile row'
);

select alike(
  lower(pg_get_functiondef('public.customer_cancel_draft_request(uuid)'::regprocedure)),
  '%for update%',
  'strict cancellation locks the owned request row'
);

select unalike(
  lower(pg_get_functiondef('public.customer_cancel_draft_request(uuid)'::regprocedure)),
  '%select *%',
  'strict cancellation selects only required database fields'
);

select is(
  (select p.proargnames from pg_proc p where p.oid = 'public.customer_cancel_draft_request(uuid)'::regprocedure),
  array['p_request_id']::text[],
  'strict cancellation accepts only the request UUID parameter'
);

select is(
  (
    select count(*)
    from pg_proc p,
         lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where p.oid = 'public.customer_cancel_draft_request(uuid)'::regprocedure
      and a.grantee = 0
      and a.privilege_type = 'EXECUTE'
  ),
  0::bigint,
  'PUBLIC cannot execute strict cancellation'
);

select is(
  has_function_privilege('anon', 'public.customer_cancel_draft_request(uuid)', 'EXECUTE'),
  false,
  'anon cannot execute strict cancellation'
);

select is(
  has_function_privilege('service_role', 'public.customer_cancel_draft_request(uuid)', 'EXECUTE'),
  false,
  'service_role cannot execute the customer-only function'
);

select is(
  has_function_privilege('authenticated', 'public.customer_cancel_draft_request(uuid)', 'EXECUTE'),
  true,
  'authenticated can enter the strict function boundary'
);

select is(
  has_function_privilege('authenticated', 'public.customer_cancel_request(uuid,text)', 'EXECUTE'),
  false,
  'authenticated can no longer execute legacy draft/open cancellation'
);

select is(has_table_privilege('authenticated', 'public.service_requests', 'INSERT'), false,
  'strict cancellation adds no authenticated request INSERT grant');
select is(has_table_privilege('authenticated', 'public.service_requests', 'UPDATE'), false,
  'strict cancellation adds no authenticated request UPDATE grant');
select is(has_table_privilege('authenticated', 'public.service_requests', 'DELETE'), false,
  'strict cancellation adds no authenticated request DELETE grant');

-- 20-29. Authentication, protected profile authority, and ownership fail closed.
reset role;
set local request.jwt.claim.sub = '';
select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009101'),
  '42501:Authentication is required to cancel a draft', 'missing authentication is rejected safely');

select is(pg_temp.cancel_draft_error(null),
  '22023:Draft request ID is required', 'null request ID is rejected safely');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009101'),
  '42501:Draft cancellation is unavailable', 'active provider is rejected by protected profile role');

set local request.jwt.claim.role = 'customer';
select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009101'),
  '42501:Draft cancellation is unavailable', 'hostile JWT role metadata cannot override protected profile role');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';
select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009101'),
  '42501:Draft cancellation is unavailable', 'active admin profile is rejected');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009006';
select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009101'),
  '42501:Draft cancellation is unavailable', 'active support profile is rejected');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009003';
select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009101'),
  '42501:Draft cancellation is unavailable', 'restricted customer is rejected');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009004';
select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009101'),
  '42501:Draft cancellation is unavailable', 'suspended customer is rejected');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009005';
select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009101'),
  '42501:Draft cancellation is unavailable', 'closed customer is rejected');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009099';
select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009101'),
  '42501:Draft cancellation is unavailable', 'missing protected profile is rejected');

-- 30-40. Successful cancellation is minimal, atomic, and privacy-safe.
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009001';
select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009102'),
  '42501:Draft is not available for cancellation', 'cross-customer draft is rejected generically');

select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009999'),
  '42501:Draft is not available for cancellation', 'missing and cross-customer requests share the safe error');

select is(
  public.customer_cancel_draft_request('00000000-0000-0000-0000-000000009101')::text,
  'cancelled',
  'active customer cancels exactly one owned draft'
);

reset role;

select is(
  coalesce(current_setting('lekkadeall.allow_marketplace_state_transition', true), 'off'),
  'off',
  'state-transition guard is reset after successful cancellation'
);

select is(
  (select status::text from public.service_requests where id = '00000000-0000-0000-0000-000000009101'),
  'cancelled',
  'successful draft enters cancelled state'
);

select ok(
  (select cancelled_at is not null and updated_at > created_at
   from public.service_requests where id = '00000000-0000-0000-0000-000000009101'),
  'server cancellation timestamps are populated and advanced'
);

select ok(
  exists (
    select 1 from public.service_requests
    where id = '00000000-0000-0000-0000-000000009101'
      and customer_id = '00000000-0000-0000-0000-000000009001'
      and category_id = '00000000-0000-0000-0000-000000000100'
      and title = 'Strict success draft'
      and description = 'Safe service request fixture for draft cancellation testing.'
      and suburb = 'Die Bult'
      and city = 'Potchefstroom'
      and requested_start > now() + interval '7 days'
      and budget_minor = 81000
      and closes_at is null
      and published_at is null
      and awarded_at is null
  ),
  'cancellation preserves ownership and every public request field'
);

select is(
  (select count(*) from public.bids where request_id = '00000000-0000-0000-0000-000000009101')
  + (select count(*) from public.bookings where request_id = '00000000-0000-0000-0000-000000009101'),
  0::bigint,
  'successful cancellation creates or changes no bid or booking state'
);

select is(
  (select count(*) from public.audit_events
   where action = 'customer.service_request_draft_cancelled'
     and object_id = '00000000-0000-0000-0000-000000009101'),
  1::bigint,
  'successful cancellation appends exactly one audit event'
);

select ok(
  exists (
    select 1 from public.audit_events
    where action = 'customer.service_request_draft_cancelled'
      and object_type = 'service_request'
      and object_id = '00000000-0000-0000-0000-000000009101'
      and actor_id = '00000000-0000-0000-0000-000000009001'
      and reason = 'Customer cancelled own draft through controlled draft-only function'
      and metadata = jsonb_build_object(
        'request_id', '00000000-0000-0000-0000-000000009101'::uuid,
        'previous_status', 'draft',
        'new_status', 'cancelled'
      )
  ),
  'audit action, actor, fixed reason, and allowlisted metadata are exact'
);

select ok(
  (select lower(reason || metadata::text) !~
      '(strict success draft|ticket9a7-active@lekkadeall[.]test|082[0-9]{7}|token|raw_user_meta_data|raw_app_meta_data)'
   from public.audit_events
   where action = 'customer.service_request_draft_cancelled'
     and object_id = '00000000-0000-0000-0000-000000009101'),
  'audit output contains no request text, email, phone, token, Auth metadata, or client reason'
);

-- 41-55. Repeat, state, consistency, bid, and booking rejections change nothing.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009001';

select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009101'),
  '42501:Draft is not available for cancellation', 'duplicate cancellation is rejected');

reset role;
select is(
  (select count(*) from public.audit_events
   where action = 'customer.service_request_draft_cancelled'
     and object_id = '00000000-0000-0000-0000-000000009101'),
  1::bigint,
  'duplicate cancellation creates no second success audit event'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009001';

select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009103'),
  '42501:Draft is not available for cancellation', 'open request is rejected');
select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009104'),
  '42501:Draft is not available for cancellation', 'awarded request is rejected');
select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009105'),
  '42501:Draft is not available for cancellation', 'cancelled request is rejected');
select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009106'),
  '42501:Draft is not available for cancellation', 'expired request is rejected');
select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009107'),
  '42501:Draft is not available for cancellation', 'draft with closes_at is rejected');
select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009108'),
  '42501:Draft is not available for cancellation', 'draft with published_at is rejected');
select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009109'),
  '42501:Draft is not available for cancellation', 'draft with awarded_at is rejected');
select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009110'),
  '42501:Draft is not available for cancellation', 'draft with cancelled_at is rejected');
select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009111'),
  '42501:Draft is not available for cancellation', 'draft with any bid is rejected');
select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009112'),
  '42501:Draft is not available for cancellation', 'draft with accepted provider bid is rejected');
select is(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009113'),
  '42501:Draft is not available for cancellation', 'draft with booking is rejected');

reset role;

select is(
  (select count(*) from public.service_requests
   where id between '00000000-0000-0000-0000-000000009103'::uuid
                and '00000000-0000-0000-0000-000000009113'::uuid
     and status = case id
       when '00000000-0000-0000-0000-000000009103'::uuid then 'open'::public.request_status
       when '00000000-0000-0000-0000-000000009104'::uuid then 'awarded'::public.request_status
       when '00000000-0000-0000-0000-000000009105'::uuid then 'cancelled'::public.request_status
       when '00000000-0000-0000-0000-000000009106'::uuid then 'expired'::public.request_status
       else 'draft'::public.request_status
     end),
  11::bigint,
  'all rejected request fixtures retain their original status'
);

select is(
  (select count(*) from public.audit_events
   where action = 'customer.service_request_draft_cancelled'
     and object_id <> '00000000-0000-0000-0000-000000009101'),
  0::bigint,
  'rejected calls create no success audit events'
);

-- 56-62. Direct-DML, audit rollback, flag reset, and RLS regressions.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009001';
select is(pg_temp.try_direct_cancel_draft('00000000-0000-0000-0000-000000009130'), false,
  'authenticated customer still cannot directly update request state');
reset role;

create function pg_temp.fail_ticket9a7_audit()
returns trigger
language plpgsql
as $$
begin
  if new.action = 'customer.service_request_draft_cancelled'
     and new.object_id = '00000000-0000-0000-0000-000000009130' then
    raise exception 'Synthetic audit failure';
  end if;
  return new;
end;
$$;

create trigger fail_ticket9a7_audit_insert
before insert on public.audit_events
for each row execute function pg_temp.fail_ticket9a7_audit();

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009001';
select isnt(pg_temp.cancel_draft_error('00000000-0000-0000-0000-000000009130'),
  '<no error>', 'audit failure prevents a success result');
reset role;

drop trigger fail_ticket9a7_audit_insert on public.audit_events;

select is(
  (select status::text from public.service_requests where id = '00000000-0000-0000-0000-000000009130'),
  'draft',
  'audit failure rolls back the request transition'
);

select is(
  (select count(*) from public.audit_events
   where action = 'customer.service_request_draft_cancelled'
     and object_id = '00000000-0000-0000-0000-000000009130'),
  0::bigint,
  'audit failure leaves no partial success event'
);

select is(
  coalesce(current_setting('lekkadeall.allow_marketplace_state_transition', true), 'off'),
  'off',
  'state-transition guard is reset after function failure'
);

select ok(
  (select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'service_requests'),
  'Ticket 2 service_requests RLS remains enabled'
);

select is(
  (select count(*) from public.bids where id in (
    '00000000-0000-0000-0000-000000009201',
    '00000000-0000-0000-0000-000000009202',
    '00000000-0000-0000-0000-000000009203'
  )),
  3::bigint,
  'rejected cancellation never mutates or deletes provider bids'
);

select * from finish();

rollback;
