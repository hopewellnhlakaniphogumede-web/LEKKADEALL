begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, auth;

select plan(58);

\ir rls_test_seed.inc

create temporary table ticket6_ids (
  name text primary key,
  id uuid
) on commit drop;

insert into public.service_categories (id, slug, name, active) values
  ('00000000-0000-0000-0000-000000000103', 'test-mobile-grooming', 'Test Mobile Grooming', true);

set local lekkadeall.allow_privileged_provider_profile_update = 'on';

update public.provider_profiles
set verification_status = 'verified',
    verification_reference = 'ticket-6-provider-a-approved',
    bank_name_match = true,
    review_status = 'approved',
    reviewed_by = '00000000-0000-0000-0000-000000000099',
    reviewed_at = now()
where user_id = '00000000-0000-0000-0000-000000000011';

set local lekkadeall.allow_privileged_provider_profile_update = 'off';

insert into public.provider_services (
  provider_id,
  category_id,
  description,
  base_price_minor,
  active
) values
  (
    '00000000-0000-0000-0000-000000000011',
    '00000000-0000-0000-0000-000000000100',
    'Ticket 6 approved provider cleaning service.',
    50000,
    true
  ),
  (
    '00000000-0000-0000-0000-000000000012',
    '00000000-0000-0000-0000-000000000100',
    'Ticket 6 provider B cleaning service.',
    55000,
    true
  );

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
  published_at
) values (
  '00000000-0000-0000-0000-000000000901',
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000100',
  'Expired ticket 6 request',
  'Expired open request used to prove bid denial after close time.',
  'Die Bult',
  'Potchefstroom',
  now() + interval '5 days',
  90000,
  'open',
  now() - interval '1 hour',
  now() - interval '2 hours'
);

insert into private.service_request_addresses (
  request_id,
  precise_address_ciphertext
) values (
  '00000000-0000-0000-0000-000000000901',
  'enc:ticket6-expired-address'
);

set local lekkadeall.allow_marketplace_state_transition = 'off';

create function pg_temp.try_create_customer_request(
  p_category_id uuid,
  p_title text,
  p_address text
)
returns uuid
language plpgsql
as $$
declare
  v_request_id uuid;
begin
  v_request_id := public.customer_create_draft_request(
    p_category_id,
    p_title,
    'Safe public description for the Ticket 6 state-machine test.',
    'Die Bult',
    'Potchefstroom',
    now() + interval '6 days',
    90000,
    p_address
  );

  return v_request_id;
exception
  when others then return null;
end;
$$;

create function pg_temp.try_publish_request(p_request_id uuid)
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

create function pg_temp.try_cancel_request(p_request_id uuid)
returns boolean
language plpgsql
as $$
begin
  perform public.customer_cancel_request(
    p_request_id,
    'Ticket 6 cancellation test'
  );

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_submit_bid(
  p_request_id uuid,
  p_amount_minor integer
)
returns uuid
language plpgsql
as $$
declare
  v_bid_id uuid;
begin
  v_bid_id := public.provider_submit_bid(
    p_request_id,
    p_amount_minor,
    now() + interval '5 days',
    'Ticket 6 provider bid.',
    array['Ticket 6 perk'],
    now() + interval '1 day'
  );

  return v_bid_id;
exception
  when others then return null;
end;
$$;

create function pg_temp.try_withdraw_bid(p_bid_id uuid)
returns boolean
language plpgsql
as $$
begin
  perform public.provider_withdraw_bid(
    p_bid_id,
    'Ticket 6 withdrawal test'
  );

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_accept_bid(p_bid_id uuid)
returns uuid
language plpgsql
as $$
declare
  v_booking_id uuid;
begin
  v_booking_id := public.customer_accept_bid(p_bid_id);
  return v_booking_id;
exception
  when others then return null;
end;
$$;

create function pg_temp.try_reveal_booking_address(p_booking_id uuid)
returns text
language plpgsql
as $$
declare
  v_precise_address text;
begin
  select precise_address_ciphertext
    into v_precise_address
  from public.reveal_confirmed_booking_address(p_booking_id);

  return coalesce(v_precise_address, '<null>');
exception
  when others then return '<denied>';
end;
$$;

create function pg_temp.try_mark_in_progress(p_booking_id uuid)
returns boolean
language plpgsql
as $$
begin
  perform public.booking_mark_in_progress(p_booking_id);
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_customer_complete(p_booking_id uuid)
returns boolean
language plpgsql
as $$
begin
  perform public.customer_confirm_completion(p_booking_id);
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_provider_complete(p_booking_id uuid)
returns boolean
language plpgsql
as $$
begin
  perform public.provider_confirm_completion(p_booking_id);
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_direct_update_request_status(p_request_id uuid)
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.service_requests
  set status = 'cancelled'
  where id = p_request_id;

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_direct_update_bid_status(p_bid_id uuid)
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.bids
  set status = 'withdrawn'
  where id = p_bid_id;

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_direct_update_booking_status(p_booking_id uuid)
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.bookings
  set status = 'completed'
  where id = p_booking_id;

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_direct_update_payment_state(p_booking_id uuid)
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.payments
  set status = 'funded',
      release_paused = false,
      funded_at = now()
  where booking_id = p_booking_id;

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_insert_mismatched_booking()
returns boolean
language plpgsql
as $$
begin
  perform set_config('lekkadeall.allow_marketplace_state_transition', 'on', true);

  insert into public.service_requests (
    id, customer_id, category_id, title, description, suburb, city,
    requested_start, budget_minor, status, closes_at
  ) values
    (
      '00000000-0000-0000-0000-000000000911',
      '00000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000100',
      'Mismatch source request',
      'Safe source request for mismatched booking test.',
      'Die Bult',
      'Potchefstroom',
      now() + interval '6 days',
      70000,
      'awarded',
      now() + interval '2 days'
    ),
    (
      '00000000-0000-0000-0000-000000000912',
      '00000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000100',
      'Mismatch target request',
      'Safe target request for mismatched booking test.',
      'Baillie Park',
      'Potchefstroom',
      now() + interval '6 days',
      70000,
      'awarded',
      now() + interval '2 days'
    );

  insert into public.bids (
    id, request_id, provider_id, amount_minor, proposed_start, message, status, expires_at
  ) values (
    '00000000-0000-0000-0000-000000000913',
    '00000000-0000-0000-0000-000000000911',
    '00000000-0000-0000-0000-000000000011',
    50000,
    now() + interval '5 days',
    'Accepted mismatched booking test bid.',
    'accepted',
    now() + interval '1 day'
  );

  insert into public.bookings (
    id, public_reference, request_id, bid_id, customer_id, provider_id,
    service_amount_minor, platform_fee_minor, scheduled_start, status
  ) values (
    '00000000-0000-0000-0000-000000000914',
    'TEST-MISMATCHED-BOOKING',
    '00000000-0000-0000-0000-000000000912',
    '00000000-0000-0000-0000-000000000913',
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000011',
    50000,
    2500,
    now() + interval '5 days',
    'scheduled'
  );

  perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
  return true;
exception
  when others then
    perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
    return false;
end;
$$;

create function pg_temp.try_insert_invalid_booking(p_case text)
returns boolean
language plpgsql
as $$
declare
  v_request_id uuid;
  v_bid_id uuid;
  v_booking_id uuid;
begin
  perform set_config('lekkadeall.allow_marketplace_state_transition', 'on', true);

  case p_case
    when 'wrong_customer' then
      v_request_id := '00000000-0000-0000-0000-000000000931';
      v_bid_id := '00000000-0000-0000-0000-000000000932';
      v_booking_id := '00000000-0000-0000-0000-000000000933';

      insert into public.service_requests (
        id, customer_id, category_id, title, description, suburb, city,
        requested_start, budget_minor, status, closes_at
      ) values (
        v_request_id,
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000100',
        'Wrong customer booking request',
        'Safe request for wrong customer booking test.',
        'Die Bult',
        'Potchefstroom',
        now() + interval '6 days',
        70000,
        'awarded',
        now() + interval '2 days'
      );

      insert into public.bids (
        id, request_id, provider_id, amount_minor, proposed_start, message, status, expires_at
      ) values (
        v_bid_id,
        v_request_id,
        '00000000-0000-0000-0000-000000000011',
        50000,
        now() + interval '5 days',
        'Accepted bid for wrong customer booking test.',
        'accepted',
        now() + interval '1 day'
      );

      insert into public.bookings (
        id, public_reference, request_id, bid_id, customer_id, provider_id,
        service_amount_minor, platform_fee_minor, scheduled_start, status
      ) values (
        v_booking_id,
        'TEST-WRONG-CUSTOMER-BOOKING',
        v_request_id,
        v_bid_id,
        '00000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-000000000011',
        50000,
        2500,
        now() + interval '5 days',
        'scheduled'
      );

    when 'wrong_provider' then
      v_request_id := '00000000-0000-0000-0000-000000000941';
      v_bid_id := '00000000-0000-0000-0000-000000000942';
      v_booking_id := '00000000-0000-0000-0000-000000000943';

      insert into public.service_requests (
        id, customer_id, category_id, title, description, suburb, city,
        requested_start, budget_minor, status, closes_at
      ) values (
        v_request_id,
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000100',
        'Wrong provider booking request',
        'Safe request for wrong provider booking test.',
        'Die Bult',
        'Potchefstroom',
        now() + interval '6 days',
        70000,
        'awarded',
        now() + interval '2 days'
      );

      insert into public.bids (
        id, request_id, provider_id, amount_minor, proposed_start, message, status, expires_at
      ) values (
        v_bid_id,
        v_request_id,
        '00000000-0000-0000-0000-000000000011',
        50000,
        now() + interval '5 days',
        'Accepted bid for wrong provider booking test.',
        'accepted',
        now() + interval '1 day'
      );

      insert into public.bookings (
        id, public_reference, request_id, bid_id, customer_id, provider_id,
        service_amount_minor, platform_fee_minor, scheduled_start, status
      ) values (
        v_booking_id,
        'TEST-WRONG-PROVIDER-BOOKING',
        v_request_id,
        v_bid_id,
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000012',
        50000,
        2500,
        now() + interval '5 days',
        'scheduled'
      );

    when 'wrong_amount' then
      v_request_id := '00000000-0000-0000-0000-000000000951';
      v_bid_id := '00000000-0000-0000-0000-000000000952';
      v_booking_id := '00000000-0000-0000-0000-000000000953';

      insert into public.service_requests (
        id, customer_id, category_id, title, description, suburb, city,
        requested_start, budget_minor, status, closes_at
      ) values (
        v_request_id,
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000100',
        'Wrong amount booking request',
        'Safe request for wrong amount booking test.',
        'Die Bult',
        'Potchefstroom',
        now() + interval '6 days',
        70000,
        'awarded',
        now() + interval '2 days'
      );

      insert into public.bids (
        id, request_id, provider_id, amount_minor, proposed_start, message, status, expires_at
      ) values (
        v_bid_id,
        v_request_id,
        '00000000-0000-0000-0000-000000000011',
        50000,
        now() + interval '5 days',
        'Accepted bid for wrong amount booking test.',
        'accepted',
        now() + interval '1 day'
      );

      insert into public.bookings (
        id, public_reference, request_id, bid_id, customer_id, provider_id,
        service_amount_minor, platform_fee_minor, scheduled_start, status
      ) values (
        v_booking_id,
        'TEST-WRONG-AMOUNT-BOOKING',
        v_request_id,
        v_bid_id,
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000011',
        49000,
        2450,
        now() + interval '5 days',
        'scheduled'
      );

    when 'duplicate_booking' then
      v_request_id := '00000000-0000-0000-0000-000000000961';
      v_bid_id := '00000000-0000-0000-0000-000000000962';
      v_booking_id := '00000000-0000-0000-0000-000000000963';

      insert into public.service_requests (
        id, customer_id, category_id, title, description, suburb, city,
        requested_start, budget_minor, status, closes_at
      ) values (
        v_request_id,
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000100',
        'Duplicate booking request',
        'Safe request for duplicate booking test.',
        'Die Bult',
        'Potchefstroom',
        now() + interval '6 days',
        70000,
        'awarded',
        now() + interval '2 days'
      );

      insert into public.bids (
        id, request_id, provider_id, amount_minor, proposed_start, message, status, expires_at
      ) values (
        v_bid_id,
        v_request_id,
        '00000000-0000-0000-0000-000000000011',
        50000,
        now() + interval '5 days',
        'Accepted bid for duplicate booking test.',
        'accepted',
        now() + interval '1 day'
      );

      insert into public.bookings (
        id, public_reference, request_id, bid_id, customer_id, provider_id,
        service_amount_minor, platform_fee_minor, scheduled_start, status
      ) values (
        v_booking_id,
        'TEST-DUPLICATE-BOOKING-A',
        v_request_id,
        v_bid_id,
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000011',
        50000,
        2500,
        now() + interval '5 days',
        'scheduled'
      );

      insert into public.bookings (
        id, public_reference, request_id, bid_id, customer_id, provider_id,
        service_amount_minor, platform_fee_minor, scheduled_start, status
      ) values (
        '00000000-0000-0000-0000-000000000964',
        'TEST-DUPLICATE-BOOKING-B',
        v_request_id,
        v_bid_id,
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000011',
        50000,
        2500,
        now() + interval '5 days',
        'scheduled'
      );

    else
      raise exception 'Unknown invalid booking case: %', p_case;
  end case;

  perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
  return true;
exception
  when others then
    perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
    return false;
end;
$$;

create function pg_temp.try_insert_second_accepted_bid()
returns boolean
language plpgsql
as $$
begin
  perform set_config('lekkadeall.allow_marketplace_state_transition', 'on', true);

  insert into public.service_requests (
    id, customer_id, category_id, title, description, suburb, city,
    requested_start, budget_minor, status, closes_at
  ) values (
    '00000000-0000-0000-0000-000000000921',
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000100',
    'Second accepted bid request',
    'Safe request for partial unique accepted bid test.',
    'Die Bult',
    'Potchefstroom',
    now() + interval '6 days',
    70000,
    'awarded',
    now() + interval '2 days'
  );

  insert into public.bids (
    id, request_id, provider_id, amount_minor, proposed_start, message, status, expires_at
  ) values
    (
      '00000000-0000-0000-0000-000000000922',
      '00000000-0000-0000-0000-000000000921',
      '00000000-0000-0000-0000-000000000011',
      50000,
      now() + interval '5 days',
      'First accepted bid.',
      'accepted',
      now() + interval '1 day'
    ),
    (
      '00000000-0000-0000-0000-000000000923',
      '00000000-0000-0000-0000-000000000921',
      '00000000-0000-0000-0000-000000000012',
      51000,
      now() + interval '5 days',
      'Second accepted bid should fail.',
      'accepted',
      now() + interval '1 day'
    );

  perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
  return true;
exception
  when others then
    perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
    return false;
end;
$$;

create function pg_temp.try_update_provider_verification()
returns boolean
language plpgsql
as $$
begin
  update public.provider_profiles
  set verification_status = 'rejected'
  where user_id = auth.uid();

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_customer_update_service_category()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.service_categories
  set active = false
  where id = '00000000-0000-0000-0000-000000000100';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_select_private_request_address(p_request_id uuid)
returns boolean
language plpgsql
as $$
declare
  v_precise_address text;
begin
  select precise_address_ciphertext
    into v_precise_address
  from private.service_request_addresses
  where request_id = p_request_id;

  return v_precise_address is not null;
exception
  when others then return false;
end;
$$;

-- 1-6. Customers create and publish only their own draft requests.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

insert into ticket6_ids (name, id)
select
  'main_request',
  pg_temp.try_create_customer_request(
    '00000000-0000-0000-0000-000000000100',
    'Ticket 6 main cleaning request',
    'enc:ticket6-main-address'
  );

select ok(
  (select id is not null from ticket6_ids where name = 'main_request'),
  'customer can create draft request through controlled function'
);

reset role;

select is(
  (
    select count(*)
    from public.service_requests sr
    join ticket6_ids ids on ids.id = sr.id
    where ids.name = 'main_request'
      and sr.customer_id = '00000000-0000-0000-0000-000000000001'
      and sr.status = 'draft'
  ),
  1::bigint,
  'created request is an owned draft'
);

select is(
  (
    select precise_address_ciphertext
    from private.service_request_addresses sra
    join ticket6_ids ids on ids.id = sra.request_id
    where ids.name = 'main_request'
  ),
  'enc:ticket6-main-address',
  'draft request exact address is stored in the private address table'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

select is(
  pg_temp.try_publish_request((select id from ticket6_ids where name = 'main_request')),
  false,
  'customer cannot publish another customer request'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_publish_request((select id from ticket6_ids where name = 'main_request')),
  true,
  'customer can publish own draft request'
);

reset role;

select is(
  (
    select status::text
    from public.service_requests sr
    join ticket6_ids ids on ids.id = sr.id
    where ids.name = 'main_request'
  ),
  'open',
  'published request enters open state'
);

-- 7-9. Customers can cancel own draft/open request only through the function.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

insert into ticket6_ids (name, id)
select
  'cancel_request',
  pg_temp.try_create_customer_request(
    '00000000-0000-0000-0000-000000000100',
    'Ticket 6 cancel request',
    'enc:ticket6-cancel-address'
  );

select ok(
  (select id is not null from ticket6_ids where name = 'cancel_request'),
  'customer can create draft request for cancellation'
);

select is(
  pg_temp.try_cancel_request((select id from ticket6_ids where name = 'cancel_request')),
  true,
  'customer can cancel own draft request through controlled function'
);

reset role;

select is(
  (
    select status::text
    from public.service_requests sr
    join ticket6_ids ids on ids.id = sr.id
    where ids.name = 'cancel_request'
  ),
  'cancelled',
  'cancelled request enters cancelled state'
);

-- 10-18. Provider bidding is approval/category/status gated.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

insert into ticket6_ids (name, id)
select
  'bid_a',
  pg_temp.try_submit_bid((select id from ticket6_ids where name = 'main_request'), 50000);

select ok(
  (select id is not null from ticket6_ids where name = 'bid_a'),
  'approved eligible provider can submit bid on open request'
);

reset role;

select is(
  (
    select count(*)
    from public.bids b
    join ticket6_ids ids on ids.id = b.id
    where ids.name = 'bid_a'
      and b.provider_id = '00000000-0000-0000-0000-000000000011'
      and b.status = 'submitted'
      and b.amount_minor = 50000
  ),
  1::bigint,
  'submitted provider bid has expected provider, amount, and status'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

select is(
  pg_temp.try_submit_bid((select id from ticket6_ids where name = 'main_request'), 54000),
  null::uuid,
  'unapproved provider cannot bid'
);

reset role;

set local lekkadeall.allow_privileged_provider_profile_update = 'on';

update public.provider_profiles
set verification_status = 'verified',
    verification_reference = 'ticket-6-provider-b-suspended',
    bank_name_match = true,
    review_status = 'suspended',
    reviewed_by = '00000000-0000-0000-0000-000000000099',
    reviewed_at = now()
where user_id = '00000000-0000-0000-0000-000000000012';

set local lekkadeall.allow_privileged_provider_profile_update = 'off';

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

select is(
  pg_temp.try_submit_bid((select id from ticket6_ids where name = 'main_request'), 54000),
  null::uuid,
  'suspended provider cannot bid'
);

reset role;

set local lekkadeall.allow_privileged_provider_profile_update = 'on';

update public.provider_profiles
set verification_status = 'verified',
    verification_reference = 'ticket-6-provider-b-approved',
    bank_name_match = true,
    review_status = 'approved',
    reviewed_by = '00000000-0000-0000-0000-000000000099',
    reviewed_at = now()
where user_id = '00000000-0000-0000-0000-000000000012';

set local lekkadeall.allow_privileged_provider_profile_update = 'off';

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

insert into ticket6_ids (name, id)
select
  'bid_b',
  pg_temp.try_submit_bid((select id from ticket6_ids where name = 'main_request'), 55000);

select ok(
  (select id is not null from ticket6_ids where name = 'bid_b'),
  'second approved eligible provider can submit competing bid'
);

reset role;

select is(
  (
    select status::text
    from public.bids b
    join ticket6_ids ids on ids.id = b.id
    where ids.name = 'bid_b'
  ),
  'submitted',
  'competing bid starts as submitted'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

insert into ticket6_ids (name, id)
select
  'ineligible_request',
  pg_temp.try_create_customer_request(
    '00000000-0000-0000-0000-000000000103',
    'Ticket 6 ineligible category request',
    'enc:ticket6-ineligible-address'
  );

select ok(
  (select id is not null from ticket6_ids where name = 'ineligible_request'),
  'customer can create draft request in second active category'
);

select is(
  pg_temp.try_publish_request((select id from ticket6_ids where name = 'ineligible_request')),
  true,
  'customer can publish second-category request'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_submit_bid((select id from ticket6_ids where name = 'ineligible_request'), 52000),
  null::uuid,
  'approved provider cannot bid without active service for request category'
);

reset role;

-- 19-23. Providers withdraw only their own submitted bid through the function.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

insert into ticket6_ids (name, id)
select
  'withdraw_request',
  pg_temp.try_create_customer_request(
    '00000000-0000-0000-0000-000000000100',
    'Ticket 6 withdraw request',
    'enc:ticket6-withdraw-address'
  );

select ok(
  (select id is not null from ticket6_ids where name = 'withdraw_request'),
  'customer can create request for withdrawal test'
);

select is(
  pg_temp.try_publish_request((select id from ticket6_ids where name = 'withdraw_request')),
  true,
  'customer can publish request for withdrawal test'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

insert into ticket6_ids (name, id)
select
  'withdraw_bid',
  pg_temp.try_submit_bid((select id from ticket6_ids where name = 'withdraw_request'), 51000);

select ok(
  (select id is not null from ticket6_ids where name = 'withdraw_bid'),
  'approved provider can submit bid for withdrawal test'
);

select is(
  pg_temp.try_withdraw_bid((select id from ticket6_ids where name = 'withdraw_bid')),
  true,
  'provider can withdraw own submitted bid through controlled function'
);

reset role;

select is(
  (
    select status::text
    from public.bids b
    join ticket6_ids ids on ids.id = b.id
    where ids.name = 'withdraw_bid'
  ),
  'withdrawn',
  'withdrawn bid enters withdrawn state'
);

-- 24-34. Customer accepts one valid bid atomically and competing bids are locked.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_submit_bid('00000000-0000-0000-0000-000000000901', 52000),
  null::uuid,
  'provider cannot bid after request close time'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

select is(
  pg_temp.try_accept_bid((select id from ticket6_ids where name = 'bid_a')),
  null::uuid,
  'customer cannot accept another customer request bid'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

insert into ticket6_ids (name, id)
select
  'booking',
  pg_temp.try_accept_bid((select id from ticket6_ids where name = 'bid_a'));

select ok(
  (select id is not null from ticket6_ids where name = 'booking'),
  'customer can accept valid bid on own request'
);

reset role;

select is(
  (
    select status::text
    from public.service_requests sr
    join ticket6_ids ids on ids.id = sr.id
    where ids.name = 'main_request'
  ),
  'awarded',
  'accepted bid awards the request'
);

select is(
  (
    select status::text
    from public.bids b
    join ticket6_ids ids on ids.id = b.id
    where ids.name = 'bid_a'
  ),
  'accepted',
  'accepted bid enters accepted state'
);

select is(
  (
    select status::text
    from public.bids b
    join ticket6_ids ids on ids.id = b.id
    where ids.name = 'bid_b'
  ),
  'declined',
  'accepting one bid declines competing submitted bids'
);

select is(
  (
    select count(*)
    from public.audit_events ae
    where (
      ae.action = 'customer.bid_accepted'
      and ae.object_id = (select id::text from ticket6_ids where name = 'bid_a')
    ) or (
      ae.action in ('booking.created', 'payment.intent_prepared')
      and ae.object_id = (select id::text from ticket6_ids where name = 'booking')
    )
  ),
  3::bigint,
  'accepting a bid writes bid, booking, and payment audit events'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_accept_bid((select id from ticket6_ids where name = 'bid_a')),
  null::uuid,
  'duplicate accept call is safely rejected'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

select is(
  pg_temp.try_submit_bid((select id from ticket6_ids where name = 'main_request'), 56000),
  null::uuid,
  'provider cannot bid on awarded request'
);

reset role;

select is(
  (
    select count(*)
    from public.bookings b
    join ticket6_ids booking_id on booking_id.id = b.id and booking_id.name = 'booking'
    where b.request_id = (select id from ticket6_ids where name = 'main_request')
      and b.bid_id = (select id from ticket6_ids where name = 'bid_a')
      and b.customer_id = '00000000-0000-0000-0000-000000000001'
      and b.provider_id = '00000000-0000-0000-0000-000000000011'
      and b.service_amount_minor = 50000
      and b.platform_fee_minor = 2500
      and b.currency = 'ZAR'
      and b.status = 'scheduled'
  ),
  1::bigint,
  'booking is created with correct request, bid, customer, provider, amount, fee, currency, and status'
);

select is(
  (
    select count(*)
    from public.payments p
    join ticket6_ids booking_id on booking_id.id = p.booking_id and booking_id.name = 'booking'
    where p.provider_name = 'internal_pending'
      and p.status = 'payment_pending'
      and p.amount_minor = 52500
      and p.currency = 'ZAR'
      and p.release_paused = true
      and p.funded_at is null
  ),
  1::bigint,
  'accepting a bid prepares a pending internal payment record without vendor credentials'
);

-- Direct frontend workflow mutation and invalid integrity states are blocked.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_direct_update_request_status((select id from ticket6_ids where name = 'main_request')),
  false,
  'frontend customer cannot directly update service_requests.status'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_direct_update_bid_status((select id from ticket6_ids where name = 'bid_a')),
  false,
  'frontend provider cannot directly update bids.status'
);

select is(
  pg_temp.try_direct_update_booking_status((select id from ticket6_ids where name = 'booking')),
  false,
  'frontend provider cannot directly update bookings.status'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_direct_update_payment_state((select id from ticket6_ids where name = 'booking')),
  false,
  'frontend customer cannot directly update payment/release state'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_direct_update_payment_state((select id from ticket6_ids where name = 'booking')),
  false,
  'frontend provider cannot directly update payment/release state'
);

reset role;

select is(
  pg_temp.try_insert_mismatched_booking(),
  false,
  'booking with bid from different request is rejected'
);

select is(
  pg_temp.try_insert_invalid_booking('wrong_customer'),
  false,
  'booking with customer that does not match request customer is rejected'
);

select is(
  pg_temp.try_insert_invalid_booking('wrong_provider'),
  false,
  'booking with provider that does not match accepted bid provider is rejected'
);

select is(
  pg_temp.try_insert_invalid_booking('wrong_amount'),
  false,
  'booking with service amount that does not match accepted bid amount is rejected'
);

select is(
  pg_temp.try_insert_invalid_booking('duplicate_booking'),
  false,
  'database prevents a second booking for the same request'
);

select is(
  pg_temp.try_insert_second_accepted_bid(),
  false,
  'database prevents more than one accepted bid per request'
);

-- Confirmed-booking address reveal and booking completion transitions still work safely.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_reveal_booking_address((select id from ticket6_ids where name = 'booking')),
  'enc:ticket6-main-address',
  'selected provider can reveal exact address after scheduled confirmed booking'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

select is(
  pg_temp.try_reveal_booking_address((select id from ticket6_ids where name = 'booking')),
  '<denied>',
  'unselected provider cannot reveal confirmed booking address'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_customer_complete((select id from ticket6_ids where name = 'booking')),
  false,
  'customer cannot confirm completion before booking is in_progress'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_mark_in_progress((select id from ticket6_ids where name = 'booking')),
  true,
  'selected provider can mark scheduled booking in progress'
);

reset role;

select is(
  (
    select status::text
    from public.bookings b
    join ticket6_ids ids on ids.id = b.id
    where ids.name = 'booking'
  ),
  'in_progress',
  'booking enters in_progress state'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_customer_complete((select id from ticket6_ids where name = 'booking')),
  true,
  'customer can confirm completion'
);

reset role;

select is(
  (
    select count(*)
    from public.bookings b
    join ticket6_ids ids on ids.id = b.id
    where ids.name = 'booking'
      and b.customer_completed_at is not null
      and b.status = 'in_progress'
  ),
  1::bigint,
  'customer completion is recorded while booking awaits provider confirmation'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_provider_complete((select id from ticket6_ids where name = 'booking')),
  true,
  'provider can confirm completion'
);

reset role;

select is(
  (
    select count(*)
    from public.bookings b
    join ticket6_ids ids on ids.id = b.id
    where ids.name = 'booking'
      and b.provider_completed_at is not null
      and b.customer_completed_at is not null
      and b.completion_confirmed_at is not null
      and b.status = 'completed'
  ),
  1::bigint,
  'booking completes after both parties confirm completion'
);

-- Ticket 1, Ticket 2, and Ticket 5 smoke protections remain intact.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_update_provider_verification(),
  false,
  'Ticket 1: provider still cannot change own verification status'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_customer_update_service_category(),
  false,
  'Ticket 2: customer still cannot mutate service categories'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_select_private_request_address((select id from ticket6_ids where name = 'main_request')),
  false,
  'Ticket 5: provider still cannot directly select private exact address rows'
);

reset role;

select ok(
  (
    select relrowsecurity
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'service_requests'
  ),
  'Ticket 2: service_requests RLS remains enabled'
);

select * from finish();

rollback;
