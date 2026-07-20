begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, auth;

select plan(81);

\ir rls_test_seed.inc

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000009801', 'ticket9a8-active@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000009802', 'ticket9a8-other@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000009803', 'ticket9a8-restricted@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000009804', 'ticket9a8-suspended@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000009805', 'ticket9a8-closed@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000009806', 'ticket9a8-support@lekkadeall.test');

set local lekkadeall.allow_privileged_profile_update = 'on';

update public.profiles as p
set display_name = v.display_name,
    account_status = v.account_status,
    updated_at = now()
from (values
  ('00000000-0000-0000-0000-000000009801'::uuid, 'Active Customer', 'active'),
  ('00000000-0000-0000-0000-000000009802'::uuid, 'Other Customer', 'active'),
  ('00000000-0000-0000-0000-000000009803'::uuid, 'Restricted Customer', 'restricted'),
  ('00000000-0000-0000-0000-000000009804'::uuid, 'Suspended Customer', 'suspended'),
  ('00000000-0000-0000-0000-000000009805'::uuid, 'Closed Customer', 'closed'),
  ('00000000-0000-0000-0000-000000009806'::uuid, 'Support User', 'active')
) as v(id, display_name, account_status)
where p.id = v.id;

update public.profiles
set role = 'support'::public.user_role,
    updated_at = now()
where id = '00000000-0000-0000-0000-000000009806';

set local lekkadeall.allow_privileged_profile_update = 'off';

insert into public.service_categories (id, slug, name, active) values
  ('00000000-0000-0000-0000-000000009880', 'ticket9a8-active', 'Ticket 9A-8 Active', true),
  ('00000000-0000-0000-0000-000000009881', 'ticket9a8-inactive', 'Ticket 9A-8 Inactive', false);

set local lekkadeall.allow_marketplace_state_transition = 'on';

insert into public.service_requests (
  id, customer_id, category_id, title, description, suburb, city,
  requested_start, budget_minor, status, closes_at,
  published_at, awarded_at, cancelled_at, created_at, updated_at
) values
  (
    '00000000-0000-0000-0000-000000009811', '00000000-0000-0000-0000-000000009801',
    '00000000-0000-0000-0000-000000000100', 'Successful edit draft',
    'Safe draft fixture for full replacement editing.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 81000,
    'draft', null, null, null, null, now() - interval '2 hours', now() - interval '2 hours'
  ),
  (
    '00000000-0000-0000-0000-000000009812', '00000000-0000-0000-0000-000000009802',
    '00000000-0000-0000-0000-000000000100', 'Other customer draft',
    'Safe draft fixture belonging to another customer.',
    'Miederpark', 'Potchefstroom', now() + interval '8 days', 82000,
    'draft', null, null, null, null, now() - interval '2 hours', now() - interval '2 hours'
  ),
  (
    '00000000-0000-0000-0000-000000009813', '00000000-0000-0000-0000-000000009801',
    '00000000-0000-0000-0000-000000000100', 'Open request fixture',
    'Safe open request fixture for update rejection.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 83000,
    'open', now() + interval '2 days', now(), null, null, now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009814', '00000000-0000-0000-0000-000000009801',
    '00000000-0000-0000-0000-000000000100', 'Awarded request fixture',
    'Safe awarded request fixture for update rejection.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 84000,
    'awarded', now() + interval '2 days', now(), now(), null, now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009815', '00000000-0000-0000-0000-000000009801',
    '00000000-0000-0000-0000-000000000100', 'Cancelled request fixture',
    'Safe cancelled request fixture for update rejection.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 85000,
    'cancelled', null, null, null, now(), now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009816', '00000000-0000-0000-0000-000000009801',
    '00000000-0000-0000-0000-000000000100', 'Expired request fixture',
    'Safe expired request fixture for update rejection.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 86000,
    'expired', now() - interval '1 hour', now() - interval '3 days', null, null, now() - interval '4 days', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009817', '00000000-0000-0000-0000-000000009801',
    '00000000-0000-0000-0000-000000000100', 'Inconsistent close draft',
    'Safe draft fixture with an inconsistent close timestamp.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 87000,
    'draft', now() + interval '2 days', null, null, null, now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009818', '00000000-0000-0000-0000-000000009801',
    '00000000-0000-0000-0000-000000000100', 'Inconsistent published draft',
    'Safe draft fixture with an inconsistent publish timestamp.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 88000,
    'draft', null, now(), null, null, now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009819', '00000000-0000-0000-0000-000000009801',
    '00000000-0000-0000-0000-000000000100', 'Inconsistent awarded draft',
    'Safe draft fixture with an inconsistent award timestamp.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 89000,
    'draft', null, null, now(), null, now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009820', '00000000-0000-0000-0000-000000009801',
    '00000000-0000-0000-0000-000000000100', 'Inconsistent cancelled draft',
    'Safe draft fixture with an inconsistent cancellation timestamp.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 90000,
    'draft', null, null, null, now(), now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009821', '00000000-0000-0000-0000-000000009801',
    '00000000-0000-0000-0000-000000000100', 'Bid contaminated draft',
    'Safe draft fixture with inconsistent provider bid state.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 91000,
    'draft', null, null, null, null, now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009822', '00000000-0000-0000-0000-000000009801',
    '00000000-0000-0000-0000-000000000100', 'Selected provider draft',
    'Safe draft fixture with an inconsistent accepted bid.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 92000,
    'draft', null, null, null, null, now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009823', '00000000-0000-0000-0000-000000009801',
    '00000000-0000-0000-0000-000000000100', 'Booked draft fixture',
    'Safe draft fixture with an inconsistent booking.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 93000,
    'draft', null, null, null, null, now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009824', '00000000-0000-0000-0000-000000009801',
    '00000000-0000-0000-0000-000000000100', 'No change draft fixture',
    'Safe draft fixture for complete no-op rejection.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 94000,
    'draft', null, null, null, null, now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009825', '00000000-0000-0000-0000-000000009801',
    '00000000-0000-0000-0000-000000000100', 'Validation target draft',
    'Safe draft fixture for validation rejection testing.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 95000,
    'draft', null, null, null, null, now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009826', '00000000-0000-0000-0000-000000009801',
    '00000000-0000-0000-0000-000000000100', 'Audit rollback draft',
    'Safe draft fixture for atomic audit rollback testing.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 96000,
    'draft', null, null, null, null, now() - interval '2 hours', now() - interval '1 hour'
  ),
  (
    '00000000-0000-0000-0000-000000009827', '00000000-0000-0000-0000-000000009801',
    '00000000-0000-0000-0000-000000000100', 'Deprecated address draft',
    'Safe draft fixture for deprecated address residue rejection.',
    'Die Bult', 'Potchefstroom', now() + interval '8 days', 97000,
    'draft', null, null, null, null, now() - interval '2 hours', now() - interval '1 hour'
  );

insert into public.bids (
  id, request_id, provider_id, amount_minor, currency, proposed_start,
  message, status, expires_at, accepted_at
) values
  (
    '00000000-0000-0000-0000-000000009841',
    '00000000-0000-0000-0000-000000009821',
    '00000000-0000-0000-0000-000000000011',
    70000, 'ZAR', now() + interval '8 days',
    'Inconsistent submitted bid fixture.', 'submitted', now() + interval '2 days', null
  ),
  (
    '00000000-0000-0000-0000-000000009842',
    '00000000-0000-0000-0000-000000009822',
    '00000000-0000-0000-0000-000000000011',
    71000, 'ZAR', now() + interval '8 days',
    'Inconsistent accepted bid fixture.', 'accepted', now() + interval '2 days', now()
  ),
  (
    '00000000-0000-0000-0000-000000009843',
    '00000000-0000-0000-0000-000000009823',
    '00000000-0000-0000-0000-000000000011',
    72000, 'ZAR', now() + interval '8 days',
    'Inconsistent booked bid fixture.', 'accepted', now() + interval '2 days', now()
  );

insert into public.bookings (
  id, public_reference, request_id, bid_id, customer_id, provider_id,
  service_amount_minor, platform_fee_minor, currency, scheduled_start, status
) values (
  '00000000-0000-0000-0000-000000009851', 'TICKET-NINE-A-EIGHT-BOOKING',
  '00000000-0000-0000-0000-000000009823', '00000000-0000-0000-0000-000000009843',
  '00000000-0000-0000-0000-000000009801', '00000000-0000-0000-0000-000000000011',
  72000, 3600, 'ZAR', now() + interval '8 days', 'scheduled'
);

set local lekkadeall.allow_marketplace_state_transition = 'off';

-- Build one historical-corruption fixture without weakening the production
-- trigger. The test transaction restores the trigger immediately and rolls
-- every fixture back at the end.
alter table public.service_requests disable trigger prevent_service_request_precise_address_write;
update public.service_requests
set precise_address_ciphertext = 'legacy-plaintext-must-be-rejected'
where id = '00000000-0000-0000-0000-000000009827';
alter table public.service_requests enable trigger prevent_service_request_precise_address_write;

create function pg_temp.update_draft_error(
  p_request_id uuid,
  p_category_id uuid default '00000000-0000-0000-0000-000000000100',
  p_title text default 'Updated safe title',
  p_description text default 'Updated safe public description for a service request.',
  p_suburb text default 'Miederpark',
  p_city text default 'Potchefstroom',
  p_requested_start timestamptz default now() + interval '9 days',
  p_budget_minor integer default 123400
)
returns text
language plpgsql
as $$
begin
  perform public.customer_update_draft_request(
    p_request_id,
    p_category_id,
    p_title,
    p_description,
    p_suburb,
    p_city,
    p_requested_start,
    p_budget_minor
  );
  return '<no error>';
exception
  when others then return sqlstate || ':' || sqlerrm;
end;
$$;

create function pg_temp.try_direct_edit_draft(p_request_id uuid)
returns boolean
language plpgsql
as $$
begin
  update public.service_requests
  set title = 'Direct browser edit must fail'
  where id = p_request_id;
  return true;
exception
  when others then return false;
end;
$$;

-- 1-21. Function contract, fixed authority, and restrictive grants.
select ok(
  to_regprocedure('public.customer_update_draft_request(uuid,uuid,text,text,text,text,timestamptz,integer)') is not null,
  'strict customer draft update function exists'
);

select ok(
  (select p.prorettype = 'uuid'::regtype
   from pg_proc p
   where p.oid = 'public.customer_update_draft_request(uuid,uuid,text,text,text,text,timestamptz,integer)'::regprocedure),
  'strict draft update returns only a UUID'
);

select is(
  (select p.proargnames
   from pg_proc p
   where p.oid = 'public.customer_update_draft_request(uuid,uuid,text,text,text,text,timestamptz,integer)'::regprocedure),
  array['p_request_id','p_category_id','p_title','p_description','p_suburb','p_city','p_requested_start','p_budget_minor']::text[],
  'function accepts exactly the eight reviewed parameters'
);

select ok(
  (select p.prosecdef
   from pg_proc p
   where p.oid = 'public.customer_update_draft_request(uuid,uuid,text,text,text,text,timestamptz,integer)'::regprocedure),
  'strict draft update is SECURITY DEFINER'
);

select is(
  (select p.provolatile::text
   from pg_proc p
   where p.oid = 'public.customer_update_draft_request(uuid,uuid,text,text,text,text,timestamptz,integer)'::regprocedure),
  'v',
  'strict draft update is VOLATILE'
);

select ok(
  (select coalesce(p.proconfig, '{}'::text[]) @> array['search_path=pg_catalog']
   from pg_proc p
   where p.oid = 'public.customer_update_draft_request(uuid,uuid,text,text,text,text,timestamptz,integer)'::regprocedure),
  'strict draft update uses the fixed pg_catalog search_path'
);

select unalike(
  lower(pg_get_functiondef('public.customer_update_draft_request(uuid,uuid,text,text,text,text,timestamptz,integer)'::regprocedure)),
  '%execute %',
  'strict draft update contains no dynamic SQL'
);

select alike(
  lower(pg_get_functiondef('public.customer_update_draft_request(uuid,uuid,text,text,text,text,timestamptz,integer)'::regprocedure)),
  '%auth.uid()%',
  'strict draft update derives actor identity from auth.uid()'
);

select alike(
  lower(pg_get_functiondef('public.customer_update_draft_request(uuid,uuid,text,text,text,text,timestamptz,integer)'::regprocedure)),
  '%from public.profiles as p%for share%',
  'strict draft update locks the actor profile before using role and status'
);

select alike(
  lower(pg_get_functiondef('public.customer_update_draft_request(uuid,uuid,text,text,text,text,timestamptz,integer)'::regprocedure)),
  '%from public.service_requests as sr%for update%',
  'strict draft update locks the owned request row'
);

select alike(
  lower(pg_get_functiondef('public.customer_update_draft_request(uuid,uuid,text,text,text,text,timestamptz,integer)'::regprocedure)),
  '%from public.service_categories as sc%for share%',
  'strict draft update locks the selected active category'
);

select unalike(
  lower(pg_get_functiondef('public.customer_update_draft_request(uuid,uuid,text,text,text,text,timestamptz,integer)'::regprocedure)),
  '%select *%',
  'strict draft update selects only explicit columns'
);

select unalike(
  lower(pg_get_functiondef('public.customer_update_draft_request(uuid,uuid,text,text,text,text,timestamptz,integer)'::regprocedure)),
  '%allow_marketplace_state_transition%',
  'content edit never enables the marketplace state-transition flag'
);

select is(
  (select count(*)
   from pg_proc p,
        lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
   where p.oid = 'public.customer_update_draft_request(uuid,uuid,text,text,text,text,timestamptz,integer)'::regprocedure
     and a.grantee = 0
     and a.privilege_type = 'EXECUTE'),
  0::bigint,
  'PUBLIC cannot execute strict draft update'
);

select is(has_function_privilege('anon', 'public.customer_update_draft_request(uuid,uuid,text,text,text,text,timestamptz,integer)', 'EXECUTE'), false,
  'anon cannot execute strict draft update');
select is(has_function_privilege('service_role', 'public.customer_update_draft_request(uuid,uuid,text,text,text,text,timestamptz,integer)', 'EXECUTE'), false,
  'service_role cannot execute the customer-only update');
select is(has_function_privilege('authenticated', 'public.customer_update_draft_request(uuid,uuid,text,text,text,text,timestamptz,integer)', 'EXECUTE'), true,
  'authenticated can enter the strict RPC boundary');
select is(has_table_privilege('authenticated', 'public.service_requests', 'INSERT'), false,
  'draft update adds no authenticated request INSERT grant');
select is(has_table_privilege('authenticated', 'public.service_requests', 'UPDATE'), false,
  'draft update adds no authenticated request UPDATE grant');
select is(has_table_privilege('authenticated', 'public.service_requests', 'DELETE'), false,
  'draft update adds no authenticated request DELETE grant');
select is(has_function_privilege('authenticated', 'private.assert_service_request_public_fields(text,text,text,text)', 'EXECUTE'), false,
  'authenticated still cannot execute the private public-field validator');

-- 22-34. Authentication, protected profile authority, and ownership fail closed.
reset role;
set local request.jwt.claim.sub = '';
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009811'),
  '42501:Authentication is required to update a draft', 'missing authentication is rejected safely');

select is(pg_temp.update_draft_error(null),
  '22023:Draft request ID is required', 'null request ID is rejected safely');

select is(pg_temp.update_draft_error(
    '00000000-0000-0000-0000-000000009811', p_category_id => null),
  '22023:Service category is required', 'null category ID is rejected safely');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009811'),
  '42501:Draft update is unavailable', 'active provider is rejected by protected profile role');

set local request.jwt.claim.role = 'customer';
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009811'),
  '42501:Draft update is unavailable', 'hostile JWT role metadata cannot override protected profile role');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009811'),
  '42501:Draft update is unavailable', 'active admin profile is rejected');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009806';
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009811'),
  '42501:Draft update is unavailable', 'active support profile is rejected');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009803';
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009811'),
  '42501:Draft update is unavailable', 'restricted customer is rejected');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009804';
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009811'),
  '42501:Draft update is unavailable', 'suspended customer is rejected');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009805';
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009811'),
  '42501:Draft update is unavailable', 'closed customer is rejected');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009899';
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009811'),
  '42501:Draft update is unavailable', 'missing protected profile is rejected');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009801';
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009812'),
  '42501:Draft is not available for update', 'cross-customer draft is rejected generically');
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009899'),
  '42501:Draft is not available for update', 'missing and cross-customer requests share the safe error');

-- 35-47. Category, schedule, budget, validator, and no-op behavior.
select is(pg_temp.update_draft_error(
    '00000000-0000-0000-0000-000000009825',
    p_category_id => '00000000-0000-0000-0000-000000009881'),
  '22023:Service category is unavailable', 'inactive category is rejected');

select is(pg_temp.update_draft_error(
    '00000000-0000-0000-0000-000000009825',
    p_category_id => '00000000-0000-0000-0000-000000009889'),
  '22023:Service category is unavailable', 'missing category is rejected');

select is(pg_temp.update_draft_error(
    '00000000-0000-0000-0000-000000009825',
    p_requested_start => now() - interval '1 minute'),
  '22023:Requested start must be in the future', 'past requested start is rejected');

select is(pg_temp.update_draft_error(
    '00000000-0000-0000-0000-000000009825',
    p_requested_start => null),
  '22023:Requested start must be in the future', 'null requested start is rejected');

select is(pg_temp.update_draft_error(
    '00000000-0000-0000-0000-000000009825',
    p_budget_minor => -1),
  '22023:Budget is invalid', 'negative budget is rejected');

select is(pg_temp.update_draft_error(
    '00000000-0000-0000-0000-000000009825',
    p_title => 'Repair at 14 Long Street'),
  '22023:Public title contains private or unsupported information', 'unsafe title is rejected by Ticket 9A-5 validation');

select is(pg_temp.update_draft_error(
    '00000000-0000-0000-0000-000000009825',
    p_description => 'Please call 082 123 4567 before starting the work.'),
  '22023:Public description contains private or unsupported information', 'unsafe description is rejected by Ticket 9A-5 validation');

select is(pg_temp.update_draft_error(
    '00000000-0000-0000-0000-000000009825',
    p_suburb => 'Unit 4'),
  '22023:Suburb contains private or unsupported information', 'unsafe suburb is rejected by Ticket 9A-5 validation');

select is(pg_temp.update_draft_error(
    '00000000-0000-0000-0000-000000009825',
    p_city => '<script>Cape Town</script>'),
  '22023:City contains private or unsupported information', 'unsafe city markup is rejected by Ticket 9A-5 validation');

select is(pg_temp.update_draft_error(
    '00000000-0000-0000-0000-000000009825',
    p_title => '  '),
  '22023:Public title is required', 'blank canonical title is rejected');

select is(
  (select pg_temp.update_draft_error(
      sr.id, sr.category_id, sr.title, sr.description, sr.suburb, sr.city,
      sr.requested_start, sr.budget_minor)
   from public.service_requests as sr
   where sr.id = '00000000-0000-0000-0000-000000009824'),
  '22023:No draft changes were provided', 'a complete canonical no-op is rejected');

select is(
  (select count(*) from public.audit_events
   where action = 'customer.service_request_draft_updated'
     and object_id = '00000000-0000-0000-0000-000000009824'),
  0::bigint,
  'no-op rejection writes no success audit event'
);

select ok(
  exists (
    select 1 from public.service_requests
    where id = '00000000-0000-0000-0000-000000009825'
      and title = 'Validation target draft'
      and description = 'Safe draft fixture for validation rejection testing.'
      and suburb = 'Die Bult'
      and city = 'Potchefstroom'
      and budget_minor = 95000
  ),
  'all rejected validation calls leave the target draft unchanged'
);

-- 48-61. Non-draft, inconsistent, bid, booking, and address residue rejection.
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009813'),
  '42501:Draft is not available for update', 'open request is rejected');
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009814'),
  '42501:Draft is not available for update', 'awarded request is rejected');
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009815'),
  '42501:Draft is not available for update', 'cancelled request is rejected');
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009816'),
  '42501:Draft is not available for update', 'expired request is rejected');
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009817'),
  '42501:Draft is not available for update', 'draft with closes_at is rejected');
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009818'),
  '42501:Draft is not available for update', 'draft with published_at is rejected');
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009819'),
  '42501:Draft is not available for update', 'draft with awarded_at is rejected');
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009820'),
  '42501:Draft is not available for update', 'draft with cancelled_at is rejected');
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009821'),
  '42501:Draft is not available for update', 'draft with any bid is rejected');
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009822'),
  '42501:Draft is not available for update', 'draft with an accepted provider bid is rejected');
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009823'),
  '42501:Draft is not available for update', 'draft with a booking is rejected');
select is(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009827'),
  '42501:Draft is not available for update', 'draft with deprecated public address residue is rejected');

select is(
  (select count(*) from public.audit_events
   where action = 'customer.service_request_draft_updated'),
  0::bigint,
  'all rejected calls have produced no success audit event'
);

select is(
  (select count(*) from public.bids where id in (
    '00000000-0000-0000-0000-000000009841',
    '00000000-0000-0000-0000-000000009842',
    '00000000-0000-0000-0000-000000009843'
  )),
  3::bigint,
  'rejected updates never mutate or delete provider bids'
);

-- 62-73. Successful full replacement is canonical, minimal, and audited.
select is(
  public.customer_update_draft_request(
    '00000000-0000-0000-0000-000000009811',
    '00000000-0000-0000-0000-000000009880',
    '  Repair 3 rooms  ',
    E'  Repair a stand mixer and repaint 3 rooms.\r\nUse a neutral finish.  ',
    '  Green Point  ',
    '  Cape Town  ',
    now() + interval '10 days',
    null
  ),
  '00000000-0000-0000-0000-000000009811'::uuid,
  'active customer updates exactly one owned draft'
);

reset role;

select ok(
  exists (
    select 1 from public.service_requests
    where id = '00000000-0000-0000-0000-000000009811'
      and customer_id = '00000000-0000-0000-0000-000000009801'
      and category_id = '00000000-0000-0000-0000-000000009880'
      and title = 'Repair 3 rooms'
      and description = E'Repair a stand mixer and repaint 3 rooms.\nUse a neutral finish.'
      and suburb = 'Green Point'
      and city = 'Cape Town'
      and requested_start = now() + interval '10 days'
      and budget_minor is null
  ),
  'all seven reviewed fields are replaced with canonical values'
);

select ok(
  exists (
    select 1 from public.service_requests
    where id = '00000000-0000-0000-0000-000000009811'
      and status = 'draft'
      and closes_at is null
      and published_at is null
      and awarded_at is null
      and cancelled_at is null
      and precise_address_ciphertext is null
  ),
  'workflow state and deprecated address remain unchanged and blocked'
);

select ok(
  (select updated_at > created_at
   from public.service_requests
   where id = '00000000-0000-0000-0000-000000009811'),
  'server updated_at advances after the controlled edit'
);

select is(
  coalesce(current_setting('lekkadeall.allow_marketplace_state_transition', true), 'off'),
  'off',
  'draft edit does not enable the marketplace state-transition guard'
);

select is(
  (select count(*) from public.audit_events
   where action = 'customer.service_request_draft_updated'
     and object_id = '00000000-0000-0000-0000-000000009811'),
  1::bigint,
  'successful draft edit appends exactly one audit event'
);

select ok(
  exists (
    select 1 from public.audit_events
    where action = 'customer.service_request_draft_updated'
      and object_type = 'service_request'
      and object_id = '00000000-0000-0000-0000-000000009811'
      and actor_id = '00000000-0000-0000-0000-000000009801'
      and reason = 'Customer updated own draft service request'
      and metadata = pg_catalog.jsonb_build_object(
        'request_id', '00000000-0000-0000-0000-000000009811'::uuid,
        'changed_fields', pg_catalog.to_jsonb(array[
          'category_id','title','description','suburb','city','requested_start','budget_minor'
        ]::text[])
      )
  ),
  'audit actor, action, fixed reason, and ordered changed-field allowlist are exact'
);

select ok(
  (select lower(reason || metadata::text) !~
      '(repair 3 rooms|stand mixer|green point|cape town|ticket9a8-active@lekkadeall[.]test|082[0-9]{7}|token|raw_user_meta_data|raw_app_meta_data)'
   from public.audit_events
   where action = 'customer.service_request_draft_updated'
     and object_id = '00000000-0000-0000-0000-000000009811'),
  'audit output contains no request text, location, email, phone, token, or Auth metadata'
);

select is(
  (select count(*) from public.bids where request_id = '00000000-0000-0000-0000-000000009811')
  + (select count(*) from public.bookings where request_id = '00000000-0000-0000-0000-000000009811'),
  0::bigint,
  'successful edit creates or changes no bid or booking state'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009801';

select is(pg_temp.update_draft_error(
    '00000000-0000-0000-0000-000000009811',
    '00000000-0000-0000-0000-000000009880',
    'Repair 3 rooms',
    E'Repair a stand mixer and repaint 3 rooms.\nUse a neutral finish.',
    'Green Point',
    'Cape Town',
    now() + interval '10 days',
    null),
  '22023:No draft changes were provided', 'repeat submission of identical values is rejected as a no-op');

reset role;
select is(
  (select count(*) from public.audit_events
   where action = 'customer.service_request_draft_updated'
     and object_id = '00000000-0000-0000-0000-000000009811'),
  1::bigint,
  'repeat no-op creates no duplicate audit event'
);

select ok(
  (select relrowsecurity
   from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'service_requests'),
  'Ticket 2 service_requests RLS remains enabled'
);

-- 74-81. Direct DML denial and atomic audit-failure rollback.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009801';
select is(pg_temp.try_direct_edit_draft('00000000-0000-0000-0000-000000009826'), false,
  'authenticated customer still cannot directly update request content');
reset role;

create function pg_temp.fail_ticket9a8_audit()
returns trigger
language plpgsql
as $$
begin
  if new.action = 'customer.service_request_draft_updated'
     and new.object_id = '00000000-0000-0000-0000-000000009826' then
    raise exception 'Synthetic audit failure';
  end if;
  return new;
end;
$$;

create trigger fail_ticket9a8_audit_insert
before insert on public.audit_events
for each row execute function pg_temp.fail_ticket9a8_audit();

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009801';
select isnt(pg_temp.update_draft_error('00000000-0000-0000-0000-000000009826'),
  '<no error>', 'audit failure prevents a success result');
reset role;

drop trigger fail_ticket9a8_audit_insert on public.audit_events;

select ok(
  exists (
    select 1 from public.service_requests
    where id = '00000000-0000-0000-0000-000000009826'
      and category_id = '00000000-0000-0000-0000-000000000100'
      and title = 'Audit rollback draft'
      and description = 'Safe draft fixture for atomic audit rollback testing.'
      and suburb = 'Die Bult'
      and city = 'Potchefstroom'
      and budget_minor = 96000
      and status = 'draft'
  ),
  'audit failure rolls back every requested field change'
);

select is(
  (select count(*) from public.audit_events
   where action = 'customer.service_request_draft_updated'
     and object_id = '00000000-0000-0000-0000-000000009826'),
  0::bigint,
  'audit failure leaves no partial success event'
);

select is(
  coalesce(current_setting('lekkadeall.allow_marketplace_state_transition', true), 'off'),
  'off',
  'audit failure cannot leak a marketplace state-transition bypass'
);

select is(has_function_privilege('authenticated', 'public.customer_cancel_request(uuid,text)', 'EXECUTE'), false,
  'Ticket 9A-7 legacy broad cancellation revoke remains intact');

select is(
  (select count(*) from public.bookings where id = '00000000-0000-0000-0000-000000009851'),
  1::bigint,
  'rejected draft edits never mutate or delete booking records'
);

select is(
  (select count(*) from public.audit_events
   where action = 'customer.service_request_draft_updated'),
  1::bigint,
  'only the one successful draft edit produced an audit event'
);

select * from finish();

rollback;
