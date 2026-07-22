begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, auth;

select plan(22);

\ir rls_test_seed.inc

create function pg_temp.try_trusted_insert_payment_method(
  p_payment_id uuid,
  p_payment_method text
)
returns boolean
language plpgsql
as $$
begin
  perform set_config('lekkadeall.allow_trusted_payment_update', 'on', true);

  insert into public.payments (
    id,
    booking_id,
    provider_name,
    provider_reference,
    status,
    amount_minor,
    release_paused,
    refunded_minor,
    payment_method
  ) values (
    p_payment_id,
    '00000000-0000-0000-0000-000000000402',
    'mock',
    'ticket-7c-' || p_payment_method,
    'pending',
    68250,
    false,
    0,
    p_payment_method
  );

  perform set_config('lekkadeall.allow_trusted_payment_update', 'off', true);
  return true;
exception
  when others then
    perform set_config('lekkadeall.allow_trusted_payment_update', 'off', true);
    return false;
end;
$$;

create function pg_temp.try_direct_insert_cash_payment()
returns boolean
language plpgsql
as $$
begin
  insert into public.payments (
    booking_id,
    provider_name,
    provider_reference,
    status,
    amount_minor,
    payment_method
  ) values (
    '00000000-0000-0000-0000-000000000402',
    'cash',
    'frontend-cash-attempt',
    'pending',
    68250,
    'cash'
  );

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_frontend_switch_payment_to_cash()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.payments
  set payment_method = 'cash'
  where id = '00000000-0000-0000-0000-000000000902';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_select_cash_payment()
returns boolean
language plpgsql
as $$
begin
  perform public.customer_select_cash_payment('00000000-0000-0000-0000-000000000402');
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_provider_select_cash_payment()
returns boolean
language plpgsql
as $$
begin
  perform public.provider_select_cash_payment('00000000-0000-0000-0000-000000000402');
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_trusted_update_payment_cash(
  p_payment_method text,
  p_status text default null,
  p_release_status text default null
)
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  perform set_config('lekkadeall.allow_trusted_payment_update', 'on', true);

  update public.payments
  set payment_method = coalesce(p_payment_method, payment_method),
      status = coalesce(p_status, status),
      release_status = coalesce(p_release_status, release_status)
  where id = '00000000-0000-0000-0000-000000000902';

  get diagnostics v_rows = row_count;
  perform set_config('lekkadeall.allow_trusted_payment_update', 'off', true);
  return v_rows > 0;
exception
  when others then
    perform set_config('lekkadeall.allow_trusted_payment_update', 'off', true);
    return false;
end;
$$;

create function pg_temp.try_cash_payout_release_event()
returns boolean
language plpgsql
as $$
begin
  insert into public.payment_events (
    payment_id,
    booking_id,
    event_type,
    amount_minor,
    currency,
    provider_name,
    idempotency_key,
    source,
    metadata
  ) values (
    '00000000-0000-0000-0000-000000000902',
    '00000000-0000-0000-0000-000000000402',
    'release_status_changed',
    0,
    'ZAR',
    'cash',
    'ticket-7c-cash-payout-release',
    'admin',
    jsonb_build_object(
      'payment_method', 'off_platform_cash',
      'release_status', 'released'
    )
  );

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_provider_change_verification_status()
returns boolean
language plpgsql
as $$
begin
  update public.provider_profiles
  set verification_status = 'verified'
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

create function pg_temp.try_select_private_request_address()
returns boolean
language plpgsql
as $$
declare
  v_count integer;
begin
  select count(*)
    into v_count
  from private.service_request_addresses
  where request_id = '00000000-0000-0000-0000-000000000201';

  return v_count > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_direct_update_booking_status()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.bookings
  set status = 'completed',
      completion_confirmed_at = now()
  where id = '00000000-0000-0000-0000-000000000402';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_update_payment_event()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.payment_events
  set metadata = jsonb_build_object('tampered', true)
  where payment_id = '00000000-0000-0000-0000-000000000902';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_update_refund_event()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.refund_events
  set metadata = jsonb_build_object('tampered', true)
  where idempotency_key = 'refund-requested:ticket-7c-refund-smoke';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

select is(
  pg_temp.try_trusted_insert_payment_method(
    '00000000-0000-0000-0000-000000000991',
    'cash'
  ),
  false,
  'cash payment method is rejected'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

select is(
  pg_temp.try_direct_insert_cash_payment(),
  false,
  'customer cannot create cash payment directly'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

select is(
  pg_temp.try_direct_insert_cash_payment(),
  false,
  'provider cannot create cash payment directly'
);

reset role;

select is(
  pg_temp.try_trusted_insert_payment_method(
    '00000000-0000-0000-0000-000000000992',
    'off_platform_cash'
  ),
  false,
  'off_platform_cash payment method is rejected'
);

select is(
  pg_temp.try_trusted_insert_payment_method(
    '00000000-0000-0000-0000-000000000902',
    'platform_online_pending'
  ),
  true,
  'existing online/sandbox payment flow remains compatible'
);

select is(
  (
    select payment_method
    from public.payments
    where id = '00000000-0000-0000-0000-000000000902'
  ),
  'platform_online_pending',
  'new MVP payment rows use non-cash payment method marker'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

select is(
  pg_temp.try_frontend_switch_payment_to_cash(),
  false,
  'customer cannot switch an online payment to cash'
);

select is(
  pg_temp.try_select_cash_payment(),
  false,
  'customer cash selection function rejects for MVP'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

select is(
  pg_temp.try_frontend_switch_payment_to_cash(),
  false,
  'provider cannot switch an online payment to cash'
);

select is(
  pg_temp.try_provider_select_cash_payment(),
  false,
  'provider cash selection function rejects for MVP'
);

reset role;

select is(
  pg_temp.try_trusted_update_payment_cash('cash_confirmed', null, null),
  false,
  'no booking/payment can become cash_confirmed'
);

select is(
  pg_temp.try_trusted_update_payment_cash('cash', 'paid', null),
  false,
  'cash cannot set payments.status to paid'
);

select is(
  pg_temp.try_trusted_update_payment_cash('off_platform_cash', 'refunded', null),
  false,
  'cash cannot set payments.status to refunded'
);

select is(
  pg_temp.try_trusted_update_payment_cash('cash', null, 'released'),
  false,
  'cash cannot set payments.release_status to released'
);

select is(
  pg_temp.try_cash_payout_release_event(),
  false,
  'cash cannot create payout-release-like payment events'
);

select is(
  (
    select count(*)
    from public.payments
    where payment_method in ('cash', 'off_platform_cash', 'cash_confirmed')
  ),
  0::bigint,
  'no payment row has a cash payment method'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_provider_change_verification_status(),
  false,
  'Ticket 1: provider self-verification remains blocked'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_customer_update_service_category(),
  false,
  'Ticket 2: customer cannot mutate service categories'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_select_private_request_address(),
  false,
  'Ticket 5: provider cannot directly select private address storage'
);

select is(
  pg_temp.try_direct_update_booking_status(),
  false,
  'Ticket 6: direct booking state mutation remains blocked'
);

reset role;

select is(
  pg_temp.try_update_payment_event(),
  false,
  'Ticket 7A: payment_events remain append-only'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

do $$
begin
  perform public.customer_request_refund(
    '00000000-0000-0000-0000-000000000501',
    1000,
    'cash_policy_smoke',
    'Ticket 7C refund ledger smoke test.',
    'ticket-7c-refund-smoke'
  );
end;
$$;

reset role;

select is(
  pg_temp.try_update_refund_event(),
  false,
  'Ticket 7B: refund_events remain append-only'
);

select * from finish();

rollback;
