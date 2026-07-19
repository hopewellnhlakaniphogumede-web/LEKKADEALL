begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, auth;

select plan(95);

\ir rls_test_seed.inc

create temporary table ticket9a5_ids (
  name text primary key,
  id uuid
) on commit drop;

grant select, insert, update, delete on table ticket9a5_ids to authenticated;

create temporary table ticket9a5_counts (
  name text primary key,
  value bigint not null
) on commit drop;

grant select, insert on table ticket9a5_counts to authenticated;

create function pg_temp.try_create_public_field_draft(
  p_title text,
  p_description text,
  p_suburb text,
  p_city text
)
returns uuid
language plpgsql
as $$
declare
  v_request_id uuid;
begin
  v_request_id := public.customer_create_draft_request(
    '00000000-0000-0000-0000-000000000100',
    p_title,
    p_description,
    p_suburb,
    p_city,
    now() + interval '7 days',
    75000,
    null
  );
  return v_request_id;
exception
  when others then return null;
end;
$$;

create function pg_temp.public_field_draft_error(
  p_title text,
  p_description text,
  p_suburb text,
  p_city text
)
returns text
language plpgsql
as $$
begin
  perform public.customer_create_draft_request(
    '00000000-0000-0000-0000-000000000100',
    p_title,
    p_description,
    p_suburb,
    p_city,
    now() + interval '7 days',
    null,
    null
  );
  return '<no error>';
exception
  when others then return sqlerrm;
end;
$$;

create function pg_temp.try_publish_public_field_request(p_request_id uuid)
returns boolean
language plpgsql
as $$
begin
  perform public.customer_publish_request(
    p_request_id,
    now() + interval '2 days'
  );
  return true;
exception
  when others then return false;
end;
$$;

-- 1-14. Private authority, privileges, trigger, RLS, and browser DML remain safe.
select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = any (array[
        'canonicalize_service_request_public_field',
        'service_request_public_field_has_forbidden_unicode',
        'service_request_public_field_privacy_risk',
        'service_request_public_field_violation',
        'assert_service_request_public_fields',
        'enforce_service_request_public_fields'
      ])
  ),
  6::bigint,
  'all six Ticket 9A-5 private validation helpers exist'
);

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = any (array[
        'canonicalize_service_request_public_field',
        'service_request_public_field_has_forbidden_unicode',
        'service_request_public_field_privacy_risk',
        'service_request_public_field_violation',
        'assert_service_request_public_fields',
        'enforce_service_request_public_fields'
      ])
      and p.prosecdef
  ),
  6::bigint,
  'all private validation helpers are SECURITY DEFINER'
);

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = any (array[
        'canonicalize_service_request_public_field',
        'service_request_public_field_has_forbidden_unicode',
        'service_request_public_field_privacy_risk',
        'service_request_public_field_violation',
        'assert_service_request_public_fields',
        'enforce_service_request_public_fields'
      ])
      and coalesce(p.proconfig, '{}'::text[]) @> array['search_path=pg_catalog']
  ),
  6::bigint,
  'all private validation helpers use the fixed pg_catalog search_path'
);

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = any (array[
        'canonicalize_service_request_public_field',
        'service_request_public_field_has_forbidden_unicode',
        'service_request_public_field_privacy_risk',
        'service_request_public_field_violation',
        'assert_service_request_public_fields',
        'enforce_service_request_public_fields'
      ])
      and exists (
        select 1
        from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
        where a.grantee = 0
          and a.privilege_type = 'EXECUTE'
      )
  ),
  0::bigint,
  'PUBLIC has no direct execute privilege on private validation helpers'
);

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = any (array[
        'canonicalize_service_request_public_field',
        'service_request_public_field_has_forbidden_unicode',
        'service_request_public_field_privacy_risk',
        'service_request_public_field_violation',
        'assert_service_request_public_fields',
        'enforce_service_request_public_fields'
      ])
      and has_function_privilege('anon', p.oid, 'EXECUTE')
  ),
  0::bigint,
  'anon cannot execute private validation helpers'
);

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = any (array[
        'canonicalize_service_request_public_field',
        'service_request_public_field_has_forbidden_unicode',
        'service_request_public_field_privacy_risk',
        'service_request_public_field_violation',
        'assert_service_request_public_fields',
        'enforce_service_request_public_fields'
      ])
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ),
  0::bigint,
  'authenticated cannot execute private validation helpers'
);

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = any (array[
        'canonicalize_service_request_public_field',
        'service_request_public_field_has_forbidden_unicode',
        'service_request_public_field_privacy_risk',
        'service_request_public_field_violation',
        'assert_service_request_public_fields',
        'enforce_service_request_public_fields'
      ])
      and has_function_privilege('service_role', p.oid, 'EXECUTE')
  ),
  0::bigint,
  'service_role has no direct execute privilege on private validation helpers'
);

select ok(
  exists (
    select 1
    from pg_trigger t
    where t.tgrelid = 'public.service_requests'::regclass
      and t.tgname = 'enforce_service_request_public_fields'
      and not t.tgisinternal
      and t.tgenabled = 'O'
  ),
  'service_requests has the enabled Ticket 9A-5 trigger backstop'
);

select is(
  (
    select has_function_privilege('authenticated', p.oid, 'EXECUTE')
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'customer_create_draft_request'
      and p.pronargs = 8
  ),
  true,
  'authenticated retains the reviewed draft-creation RPC'
);

select is(
  (
    select has_function_privilege('anon', p.oid, 'EXECUTE')
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'customer_create_draft_request'
      and p.pronargs = 8
  ),
  false,
  'anon cannot execute draft creation'
);

select is(
  (select relrowsecurity from pg_class where oid = 'public.service_requests'::regclass),
  true,
  'service_requests RLS remains enabled'
);

select is(
  has_table_privilege('authenticated', 'public.service_requests', 'INSERT'),
  false,
  'authenticated still cannot insert service_requests directly'
);

select is(
  has_table_privilege('authenticated', 'public.service_requests', 'UPDATE'),
  false,
  'authenticated still cannot update service_requests directly'
);

select is(
  has_table_privilege('authenticated', 'public.service_requests', 'DELETE'),
  false,
  'authenticated still cannot delete service_requests directly'
);

-- 15-34. Canonical structural rules for all public fields.
select is(
  private.service_request_public_field_violation(c.field_name, c.value),
  c.expected,
  c.label
)
from (values
  ('title', null::text, 'required'::text, 'null title is rejected'),
  ('title', '   ', 'required', 'blank title is rejected after canonical trim'),
  ('title', 'abc', null, 'minimum title length is accepted'),
  ('title', repeat('a', 120), null, 'maximum title length is accepted'),
  ('title', 'ab', 'invalid_length', 'short title is rejected'),
  ('title', repeat('a', 121), 'invalid_length', 'long title is rejected'),
  ('description', 'abcdefghij', null, 'minimum description length is accepted'),
  ('description', repeat('a', 3000), null, 'maximum description length is accepted'),
  ('description', 'too short', 'invalid_length', 'short description is rejected'),
  ('description', repeat('a', 3001), 'invalid_length', 'long description is rejected'),
  ('suburb', 'AB', null, 'minimum suburb length is accepted'),
  ('city', repeat('a', 121), 'invalid_length', 'long city is rejected'),
  ('title', E'Safe\ntitle', 'unsupported_format', 'title must be single line'),
  ('description', E'First line\nSecond line', null, 'description permits LF paragraph breaks'),
  ('description', E'Safe text\twith tab', 'unsupported_format', 'description rejects tabs'),
  ('description', E'Safe text\rwith CR', 'unsupported_format', 'description rejects lone carriage return'),
  ('title', 'Safe' || chr(8238) || 'title', 'unsupported_format', 'bidi override is rejected'),
  ('city', 'Cape' || chr(8203) || ' Town', 'unsupported_format', 'zero-width character is rejected'),
  ('description', 'Please do <b>careful repairs</b>.', 'unsafe_markup', 'literal markup is rejected'),
  ('description', 'Please run &lt;script&gt;alert safely.', 'unsafe_markup', 'encoded script-like markup is rejected')
) as c(field_name, value, expected, label);

-- 35-37. Stored representation is the representation that was validated.
select is(
  private.canonicalize_service_request_public_field('title', '  Paint walls  '),
  'Paint walls',
  'canonicalizer trims public title'
);

select is(
  private.canonicalize_service_request_public_field('description', E'  First line\r\nSecond line  '),
  E'First line\nSecond line',
  'canonicalizer converts description CRLF to LF'
);

select is(
  private.canonicalize_service_request_public_field('title', U&'Cafe\0301 walls'),
  U&'Caf\00E9 walls',
  'canonicalizer stores NFC text'
);

-- 38-61. Required exact-location, contact, URL/social, GPS, and code risks.
select is(
  private.service_request_public_field_privacy_risk(c.field_name, c.value),
  true,
  c.label
)
from (values
  ('description', 'Please come to 14 Long Street for the work.', 'English numbered street address is rejected'),
  ('description', 'Die werk is by 22 Kerkstraat Straat.', 'Afrikaans street designator is rejected'),
  ('suburb', 'Unit 4B', 'unit identifier is rejected'),
  ('description', 'Use Room 203 for the repair.', 'room identifier is rejected'),
  ('description', 'Meet at Flat 7.', 'flat identifier is rejected'),
  ('description', 'The work is in Apartment 12A.', 'apartment identifier is rejected'),
  ('description', 'Meet in the complex Waterfall View.', 'complex name after location cue is rejected'),
  ('description', 'Work is at Waterfall Estate.', 'named estate after location cue is rejected'),
  ('title', 'Repair at Stand 442', 'stand identifier is rejected'),
  ('description', 'The property is Erf 913.', 'erf identifier is rejected'),
  ('description', 'Service needed on Plot 27.', 'plot identifier is rejected'),
  ('description', 'Work is required at Farm 81.', 'farm identifier is rejected'),
  ('description', 'GPS is -26.2041, 28.0473.', 'decimal GPS pair is rejected'),
  ('description', 'Latitude: -26.2041', 'labelled GPS value is rejected'),
  ('description', U&'26\00B0 12.5\0027 S, 28\00B0 02.5\0027 E', 'DMS coordinates are rejected'),
  ('description', 'Call 082 123 4567 on arrival.', 'South African phone number is rejected'),
  ('description', 'Email customer@example.co.za for details.', 'email address is rejected'),
  ('description', 'Open https://example.co.za/details.', 'schemed URL is rejected'),
  ('description', 'Details are on example.co.za.', 'bare South African domain is rejected'),
  ('description', 'Message @private_handle for details.', 'social handle is rejected'),
  ('description', 'WhatsApp me before the job.', 'WhatsApp instruction is rejected'),
  ('description', 'Contact me when you arrive.', 'private contact instruction is rejected'),
  ('description', 'Gate code 9911 must be used.', 'gate code is rejected'),
  ('description', 'Security PIN A9B2 is active.', 'security PIN is rejected')
) as c(field_name, value, label);

-- 62-67. South African/local service false-positive fixtures remain usable.
select is(
  (
    select count(*)
    from (values
      ('Cape Town'), ('Johannesburg'), ('Gqeberha'), ('Makhanda'),
      ('Mbombela'), ('Polokwane'), ('Bloemfontein'), ('Potchefstroom'),
      ('Die Bult'), ('Cape Town CBD'), ('Bo-Kaap'), ('uMhlanga'), ('L''Agulhas')
    ) as safe(value)
    where private.service_request_public_field_privacy_risk('suburb', safe.value)
  ),
  0::bigint,
  'representative South African locality names are not privacy false positives'
);

select is(
  (
    select count(*)
    from (values
      ('Diepsloot Ext 2'), ('Soweto Zone 6'), ('Section 21'),
      ('Ward 3'), ('Phase 2')
    ) as safe(value)
    where private.service_request_public_field_privacy_risk('suburb', safe.value)
  ),
  0::bigint,
  'reviewed numbered locality forms are not blanket-rejected'
);

select is(
  (
    select count(*)
    from (values
      ('Paint 3 rooms and install 4 lights.'),
      ('Replace 2 taps with a budget of R500.'),
      ('Service the Centurion D5 Evo gate motor.')
    ) as safe(value)
    where private.service_request_public_field_privacy_risk('description', safe.value)
  ),
  0::bigint,
  'quantities budgets and model numbers are not phone/address false positives'
);

select is(
  (
    select count(*)
    from (values
      ('Repair a complex electrical fault.'),
      ('Repair a stand mixer.'),
      ('Apartment cleaning is required.'),
      ('Replace damaged block paving.')
    ) as safe(value)
    where private.service_request_public_field_privacy_risk('description', safe.value)
  ),
  0::bigint,
  'context-sensitive address words remain valid in ordinary service text'
);

select is(
  private.service_request_public_field_violation(
    'description',
    'The exact address and access details will be shared securely after booking.'
  ),
  null::text,
  'safe private-sharing guidance is accepted when no secret or location is present'
);

select is(
  private.service_request_public_field_violation(
    'description',
    'Repair O''Reilly-style shelving in the living area.'
  ),
  null::text,
  'ordinary apostrophes and hyphens remain valid'
);

-- 68-72. Ticket 5 compatibility helper delegates to the shared classifier.
select is(
  public.service_request_description_has_exact_address_risk(
    'Please clean the kitchen and bathroom. The exact address will be shared after booking.'
  ),
  false,
  'compatibility helper preserves the existing safe-description behavior'
);

select is(
  public.service_request_description_has_exact_address_risk('Please come to 12 Church Street.'),
  true,
  'compatibility helper still detects a numbered street'
);

select is(
  public.service_request_description_has_exact_address_risk('GPS is -26.714500, 27.097000.'),
  true,
  'compatibility helper still detects GPS coordinates'
);

select is(
  public.service_request_description_has_exact_address_risk('Call 082 123 4567 when outside.'),
  true,
  'compatibility helper still detects South African phone numbers'
);

select is(
  public.service_request_description_has_exact_address_risk('Email customer@example.co.za for details.'),
  true,
  'compatibility helper now uses the shared expanded contact classifier'
);

-- 73-83. Hostile clients cannot bypass validation through draft creation.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

insert into ticket9a5_counts (name, value)
select 'customer_a_visible_requests_before_rejections', count(*)
from public.service_requests;

select is(
  pg_temp.try_create_public_field_draft(
    'Repair at 14 Long Street',
    'Repair the living room walls safely.',
    'Die Bult',
    'Potchefstroom'
  ),
  null::uuid,
  'unsafe title prevents draft creation'
);

select is(
  pg_temp.try_create_public_field_draft(
    'Repair living room',
    'Email customer@example.co.za before starting.',
    'Die Bult',
    'Potchefstroom'
  ),
  null::uuid,
  'unsafe description prevents draft creation'
);

select is(
  pg_temp.try_create_public_field_draft(
    'Repair living room',
    'Repair the living room walls safely.',
    'Unit 4B',
    'Potchefstroom'
  ),
  null::uuid,
  'unsafe suburb prevents draft creation'
);

select is(
  pg_temp.try_create_public_field_draft(
    'Repair living room',
    'Repair the living room walls safely.',
    'Die Bult',
    'Gate code 9911'
  ),
  null::uuid,
  'unsafe city prevents draft creation'
);

select is(
  (select count(*) from public.service_requests),
  (
    select value
    from ticket9a5_counts
    where name = 'customer_a_visible_requests_before_rejections'
  ),
  'rejected draft calls create no customer-visible request rows under RLS'
);

select is(
  pg_temp.public_field_draft_error(
    'Repair at 14 Long Street',
    'Repair the living room walls safely.',
    'Die Bult',
    'Potchefstroom'
  ),
  'Public title contains private or unsupported information',
  'draft rejection uses the reviewed privacy-safe field message'
);

select unalike(
  pg_temp.public_field_draft_error(
    'Repair at 14 Long Street',
    'Repair the living room walls safely.',
    'Die Bult',
    'Potchefstroom'
  ),
  '%14 Long Street%',
  'draft rejection does not echo the matched sensitive text'
);

insert into ticket9a5_ids (name, id)
select 'safe_draft', pg_temp.try_create_public_field_draft(
  '  Paint 3 rooms  ',
  E'  Repair walls\r\nand ceiling safely.  ',
  '  Die Bult  ',
  '  Potchefstroom  '
);

select ok(
  (select id is not null from ticket9a5_ids where name = 'safe_draft'),
  'safe South African draft is created through the trusted RPC'
);

select is(
  (
    select sr.title
    from public.service_requests sr
    join ticket9a5_ids i on i.id = sr.id
    where i.name = 'safe_draft'
  ),
  'Paint 3 rooms',
  'draft RPC stores the validated canonical title'
);

select is(
  (
    select sr.description
    from public.service_requests sr
    join ticket9a5_ids i on i.id = sr.id
    where i.name = 'safe_draft'
  ),
  E'Repair walls\nand ceiling safely.',
  'draft RPC stores the validated canonical multiline description'
);

-- audit_events is intentionally unavailable to authenticated browser roles.
-- Restore the test-owner role before checking the server-written audit row.
reset role;

select is(
  (
    select count(*)
    from public.audit_events ae
    join ticket9a5_ids i on i.id::text = ae.object_id
    where i.name = 'safe_draft'
      and ae.action = 'customer.service_request_draft_created'
  ),
  1::bigint,
  'successful validated draft creation keeps the privacy-safe audit event'
);

-- 84-93. Table backstop catches direct/internal writes and opening legacy rows.
set local lekkadeall.allow_marketplace_state_transition = 'on';

select throws_ok(
  $$
    insert into public.service_requests (
      id, customer_id, category_id, title, description, suburb, city,
      requested_start, budget_minor, status, closes_at
    ) values (
      '00000000-0000-0000-0000-000000000952',
      '00000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000100',
      'Repair at 14 Long Street',
      'Safe direct-insert trigger description.',
      'Die Bult',
      'Potchefstroom',
      now() + interval '8 days',
      70000,
      'draft',
      null
    )
  $$,
  '22023',
  'Public title contains private or unsupported information',
  'table trigger rejects an unsafe privileged insert'
);

select is(
  (
    select count(*)
    from public.service_requests
    where id = '00000000-0000-0000-0000-000000000952'
  ),
  0::bigint,
  'failed trigger insert leaves no request row'
);

select throws_ok(
  $$
    update public.service_requests
    set description = 'Email customer@example.co.za for access.'
    where id = '00000000-0000-0000-0000-000000000203'
  $$,
  '22023',
  'Public description contains private or unsupported information',
  'table trigger rejects an unsafe privileged public-field update'
);

select is(
  (
    select description
    from public.service_requests
    where id = '00000000-0000-0000-0000-000000000203'
  ),
  'Draft request with safe public description for Customer B.',
  'failed trigger update leaves the existing value unchanged'
);

select lives_ok(
  $$
    insert into public.service_requests (
      id, customer_id, category_id, title, description, suburb, city,
      requested_start, budget_minor, status, closes_at
    ) values (
      '00000000-0000-0000-0000-000000000950',
      '00000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000100',
      '  Install 4 lights  ',
      E'  Install lights\r\nand test the switches safely.  ',
      '  Die Bult  ',
      '  Potchefstroom  ',
      now() + interval '8 days',
      70000,
      'draft',
      null
    )
  $$,
  'table trigger accepts and canonicalizes a safe privileged insert'
);

select is(
  (
    select title
    from public.service_requests
    where id = '00000000-0000-0000-0000-000000000950'
  ),
  'Install 4 lights',
  'table trigger stores canonical title'
);

select is(
  (
    select description
    from public.service_requests
    where id = '00000000-0000-0000-0000-000000000950'
  ),
  E'Install lights\nand test the switches safely.',
  'table trigger stores canonical description'
);

set local lekkadeall.allow_marketplace_state_transition = 'off';

-- Simulate a pre-Ticket-9A-5 legacy draft without changing production rules.
alter table public.service_requests disable trigger enforce_service_request_public_fields;
set local lekkadeall.allow_marketplace_state_transition = 'on';

insert into public.service_requests (
  id, customer_id, category_id, title, description, suburb, city,
  requested_start, budget_minor, status, closes_at
) values (
  '00000000-0000-0000-0000-000000000951',
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000100',
  'Repair at 14 Long Street',
  'Legacy draft with an otherwise safe public description.',
  'Die Bult',
  'Potchefstroom',
  now() + interval '8 days',
  70000,
  'draft',
  null
);

set local lekkadeall.allow_marketplace_state_transition = 'off';
alter table public.service_requests enable trigger enforce_service_request_public_fields;

insert into private.service_request_addresses (
  request_id,
  precise_address_ciphertext
) values (
  '00000000-0000-0000-0000-000000000951',
  'enc:ticket9a5-legacy-address'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_publish_public_field_request('00000000-0000-0000-0000-000000000951'),
  false,
  'transition-to-open trigger atomically rejects an unsafe legacy draft'
);

reset role;

select is(
  (
    select status::text
    from public.service_requests
    where id = '00000000-0000-0000-0000-000000000951'
  ),
  'draft',
  'failed legacy publication leaves status draft'
);

select is(
  (
    select count(*)
    from public.audit_events
    where action = 'customer.service_request_published'
      and object_id = '00000000-0000-0000-0000-000000000951'
  ),
  0::bigint,
  'failed legacy publication writes no publication success audit'
);

-- 94-95. Ticket 5 address isolation and compatibility access remain intact.
select is(
  has_column_privilege(
    'authenticated',
    'public.service_requests',
    'precise_address_ciphertext',
    'SELECT'
  ),
  false,
  'authenticated still cannot select the deprecated public address column'
);

select is(
  (
    select has_function_privilege('authenticated', p.oid, 'EXECUTE')
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'service_request_description_has_exact_address_risk'
      and p.pronargs = 1
  ),
  true,
  'authenticated retains the Ticket 5 compatibility preflight function'
);

select * from finish();
rollback;
