begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, auth;

select plan(24);

\ir rls_test_seed.inc

create function pg_temp.try_insert_invalid_payment_status()
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
    refunded_minor
  ) values (
    '00000000-0000-0000-0000-000000000991',
    '00000000-0000-0000-0000-000000000402',
    'mock',
    'ticket-7-invalid-status',
    'payment_pending',
    68250,
    true,
    0
  );

  perform set_config('lekkadeall.allow_trusted_payment_update', 'off', true);
  return true;
exception
  when others then
    perform set_config('lekkadeall.allow_trusted_payment_update', 'off', true);
    return false;
end;
$$;

create function pg_temp.try_update_ticket7_payment(
  p_status text default null,
  p_release_status text default null,
  p_refunded_minor integer default null,
  p_paid_at timestamptz default null,
  p_released_at timestamptz default null,
  p_provider_reference text default null
)
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.payments
  set status = coalesce(p_status, status),
      release_status = coalesce(p_release_status, release_status),
      refunded_minor = coalesce(p_refunded_minor, refunded_minor),
      paid_at = coalesce(p_paid_at, paid_at),
      released_at = coalesce(p_released_at, released_at),
      provider_reference = coalesce(p_provider_reference, provider_reference)
  where id = '00000000-0000-0000-0000-000000000902';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.visible_ticket7_payment_count()
returns integer
language plpgsql
as $$
declare
  v_count integer;
begin
  select count(*)
    into v_count
  from public.payments
  where id = '00000000-0000-0000-0000-000000000902';

  return v_count;
exception
  when others then return -1;
end;
$$;

create function pg_temp.ticket7_payment_summary()
returns text
language plpgsql
as $$
declare
  v_summary text;
begin
  select concat_ws('|', status, release_status, amount_minor::text, currency)
    into v_summary
  from public.payments
  where id = '00000000-0000-0000-0000-000000000902';

  return coalesce(v_summary, '<none>');
exception
  when others then return '<denied>';
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
  where idempotency_key = 'ticket-7-checkout-created';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_delete_payment_event()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  delete from public.payment_events
  where idempotency_key = 'ticket-7-checkout-created';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_call_admin_record_payment_event(
  p_idempotency_key text,
  p_payment_status text default 'checkout_created'
)
returns boolean
language plpgsql
as $$
begin
  perform public.admin_record_payment_event(
    '00000000-0000-0000-0000-000000000902',
    'payment_status_changed',
    p_payment_status,
    null,
    null,
    'mock',
    null,
    p_idempotency_key,
    'admin',
    jsonb_build_object('test', 'ticket-7a-abuse-check')
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

select is(
  pg_temp.try_insert_invalid_payment_status(),
  false,
  'invalid payment status is rejected'
);

set local lekkadeall.allow_trusted_payment_update = 'on';

insert into public.payments (
  id,
  booking_id,
  provider_name,
  provider_reference,
  status,
  amount_minor,
  release_paused,
  refunded_minor
) values (
  '00000000-0000-0000-0000-000000000902',
  '00000000-0000-0000-0000-000000000402',
  'internal_pending',
  null,
  'pending',
  68250,
  true,
  0
);

set local lekkadeall.allow_trusted_payment_update = 'off';

select is(
  (
    select count(*)
    from public.payment_events
    where payment_id = '00000000-0000-0000-0000-000000000902'
      and event_type = 'intent_prepared'
      and idempotency_key = 'payment-intent-prepared:00000000-0000-0000-0000-000000000902'
  ),
  1::bigint,
  'trusted pending payment creation writes an initial immutable payment event'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

select is(
  pg_temp.try_update_ticket7_payment('paid', null, null, now(), null, 'frontend-paid'),
  false,
  'customer cannot mark payment as paid'
);

select is(
  pg_temp.try_update_ticket7_payment('refunded', null, 68250, null, null, 'frontend-refunded'),
  false,
  'customer cannot mark payment as refunded'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

select is(
  pg_temp.try_update_ticket7_payment('paid', null, null, now(), null, 'provider-paid'),
  false,
  'provider cannot mark payment as paid'
);

select is(
  pg_temp.try_update_ticket7_payment(null, 'released', null, null, now(), 'provider-release'),
  false,
  'provider cannot mark payment as released'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.visible_ticket7_payment_count(),
  0,
  'unrelated users cannot read payment records'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

select is(
  pg_temp.ticket7_payment_summary(),
  'pending|paused|68250|ZAR',
  'booking customer can read safe payment summary'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

select is(
  pg_temp.ticket7_payment_summary(),
  'pending|paused|68250|ZAR',
  'booking provider can read safe payment summary'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

select is(
  pg_temp.try_call_admin_record_payment_event('ticket-7-customer-abuse'),
  false,
  'customer cannot call or abuse trusted payment event function'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

select is(
  pg_temp.try_call_admin_record_payment_event('ticket-7-provider-abuse'),
  false,
  'provider cannot call or abuse trusted payment event function'
);

reset role;

select is(
  (
    select count(*)
    from public.payment_events
    where idempotency_key in ('ticket-7-customer-abuse', 'ticket-7-provider-abuse')
  ),
  0::bigint,
  'failed normal-user trusted function calls create no payment events'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';

select is(
  pg_temp.try_call_admin_record_payment_event('ticket-7-invalid-status-function', 'not_a_payment_status'),
  false,
  'trusted payment event function rejects invalid payment status'
);

select ok(
  public.admin_record_payment_event(
    '00000000-0000-0000-0000-000000000902',
    'checkout_created',
    'checkout_created',
    null,
    null,
    'mock',
    'ticket-7-provider-event-checkout',
    'ticket-7-checkout-created',
    'admin',
    jsonb_build_object('test', 'ticket-7a')
  ) is not null,
  'trusted admin function can write a payment event'
);

reset role;

select is(
  (
    select status
    from public.payments
    where id = '00000000-0000-0000-0000-000000000902'
  ),
  'checkout_created',
  'trusted admin function can update constrained payment status'
);

select is(
  (
    select count(*)
    from public.payment_events
    where idempotency_key = 'ticket-7-checkout-created'
  ),
  1::bigint,
  'trusted admin function writes exactly one payment event for a new idempotency key'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';

select ok(
  public.admin_record_payment_event(
    '00000000-0000-0000-0000-000000000902',
    'checkout_created',
    'checkout_created',
    null,
    null,
    'mock',
    'ticket-7-provider-event-checkout',
    'ticket-7-checkout-created',
    'admin',
    jsonb_build_object('test', 'ticket-7a-duplicate')
  ) is not null,
  'duplicate idempotency key returns an existing payment event'
);

reset role;

select is(
  (
    select count(*)
    from public.payment_events
    where idempotency_key = 'ticket-7-checkout-created'
  ),
  1::bigint,
  'duplicate idempotency key does not create duplicate events'
);

select is(
  pg_temp.try_update_payment_event(),
  false,
  'payment_events cannot be updated'
);

select is(
  pg_temp.try_delete_payment_event(),
  false,
  'payment_events cannot be deleted'
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

select * from finish();

rollback;
