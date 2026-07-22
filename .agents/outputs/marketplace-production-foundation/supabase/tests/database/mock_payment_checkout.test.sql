begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, auth;

select plan(50);

\ir rls_test_seed.inc

set local lekkadeall.allow_privileged_provider_profile_update = 'on';

update public.provider_profiles
set verification_status = 'verified',
    review_status = 'approved',
    bank_name_match = true
where user_id in (
  '00000000-0000-0000-0000-000000000011',
  '00000000-0000-0000-0000-000000000012'
);

set local lekkadeall.allow_privileged_provider_profile_update = 'off';

create temporary table ticket7e_cases (
  case_key text primary key,
  request_id uuid not null,
  bid_id uuid not null,
  booking_id uuid not null,
  payment_id uuid not null,
  customer_id uuid not null,
  provider_id uuid not null,
  payment_status text not null,
  amount_minor integer not null,
  refunded_minor integer not null default 0,
  release_status text not null default 'not_applicable'
) on commit drop;

insert into ticket7e_cases (
  case_key, request_id, bid_id, booking_id, payment_id,
  customer_id, provider_id, payment_status, amount_minor, refunded_minor,
  release_status
) values
  ('own_checkout', '00000000-0000-0000-0000-000000008101', '00000000-0000-0000-0000-000000008201', '00000000-0000-0000-0000-000000008301', '00000000-0000-0000-0000-000000008401', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', 'pending', 12000, 0, 'not_applicable'),
  ('other_customer', '00000000-0000-0000-0000-000000008102', '00000000-0000-0000-0000-000000008202', '00000000-0000-0000-0000-000000008302', '00000000-0000-0000-0000-000000008402', '00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000012', 'pending', 13000, 0, 'not_applicable'),
  ('paid_checkout', '00000000-0000-0000-0000-000000008103', '00000000-0000-0000-0000-000000008203', '00000000-0000-0000-0000-000000008303', '00000000-0000-0000-0000-000000008403', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', 'paid', 14000, 0, 'pending'),
  ('refunded_checkout', '00000000-0000-0000-0000-000000008104', '00000000-0000-0000-0000-000000008204', '00000000-0000-0000-0000-000000008304', '00000000-0000-0000-0000-000000008404', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', 'refunded', 15000, 15000, 'cancelled'),
  ('failed_checkout', '00000000-0000-0000-0000-000000008105', '00000000-0000-0000-0000-000000008205', '00000000-0000-0000-0000-000000008305', '00000000-0000-0000-0000-000000008405', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', 'failed', 16000, 0, 'cancelled'),
  ('cancelled_checkout', '00000000-0000-0000-0000-000000008106', '00000000-0000-0000-0000-000000008206', '00000000-0000-0000-0000-000000008306', '00000000-0000-0000-0000-000000008406', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', 'cancelled', 17000, 0, 'cancelled'),
  ('expired_checkout', '00000000-0000-0000-0000-000000008107', '00000000-0000-0000-0000-000000008207', '00000000-0000-0000-0000-000000008307', '00000000-0000-0000-0000-000000008407', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', 'expired', 18000, 0, 'cancelled'),
  ('cash_attempt', '00000000-0000-0000-0000-000000008108', '00000000-0000-0000-0000-000000008208', '00000000-0000-0000-0000-000000008308', '00000000-0000-0000-0000-000000008408', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', 'pending', 19000, 0, 'not_applicable'),
  ('failed_outcome', '00000000-0000-0000-0000-000000008109', '00000000-0000-0000-0000-000000008209', '00000000-0000-0000-0000-000000008309', '00000000-0000-0000-0000-000000008409', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', 'checkout_created', 20000, 0, 'not_applicable');

set local lekkadeall.allow_marketplace_state_transition = 'on';

insert into public.service_requests (
  id, customer_id, category_id, title, description, suburb, city,
  requested_start, budget_minor, status, closes_at
)
select
  request_id,
  customer_id,
  '00000000-0000-0000-0000-000000000100',
  'Ticket 7E ' || case_key,
  'Safe Ticket 7E mock payment checkout test request.',
  'Die Bult',
  'Potchefstroom',
  timestamptz '2026-08-01 10:00:00+02',
  amount_minor,
  'awarded',
  timestamptz '2026-07-31 10:00:00+02'
from ticket7e_cases;

insert into public.bids (
  id, request_id, provider_id, amount_minor, proposed_start,
  message, status, expires_at
)
select
  bid_id,
  request_id,
  provider_id,
  amount_minor,
  timestamptz '2026-08-01 10:00:00+02',
  'Accepted Ticket 7E mock checkout test bid.',
  'accepted',
  timestamptz '2026-07-31 10:00:00+02'
from ticket7e_cases;

insert into public.bookings (
  id, public_reference, request_id, bid_id, customer_id, provider_id,
  service_amount_minor, platform_fee_minor, scheduled_start, status
)
select
  booking_id,
  'TICKET-7E-' || upper(case_key),
  request_id,
  bid_id,
  customer_id,
  provider_id,
  amount_minor,
  0,
  timestamptz '2026-08-01 10:00:00+02',
  'payment_pending'
from ticket7e_cases;

set local lekkadeall.allow_marketplace_state_transition = 'off';

set local lekkadeall.allow_trusted_payment_update = 'on';

insert into public.payments (
  id, booking_id, provider_name, provider_reference, status,
  amount_minor, release_paused, paid_at, funded_at, refunded_minor,
  release_status
)
select
  payment_id,
  booking_id,
  'mock',
  'ticket-7e-' || case_key,
  payment_status,
  amount_minor,
  false,
  case when payment_status in ('paid', 'partially_refunded', 'refunded') then now() else null end,
  case when payment_status in ('paid', 'partially_refunded', 'refunded') then now() else null end,
  refunded_minor,
  release_status
from ticket7e_cases;

set local lekkadeall.allow_trusted_payment_update = 'off';

create function pg_temp.try_customer_checkout(
  p_payment_id uuid,
  p_idempotency_key text
)
returns boolean
language plpgsql
as $$
begin
  perform *
  from public.customer_create_mock_checkout_session(
    p_payment_id,
    p_idempotency_key,
    'https://app.lekkadeall.test/return',
    'https://app.lekkadeall.test/cancel'
  );

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_checkout_after_cash_marker()
returns boolean
language plpgsql
as $$
begin
  perform set_config('lekkadeall.allow_trusted_payment_update', 'on', true);

  update public.payments
  set payment_method = 'off_platform_cash'
  where id = '00000000-0000-0000-0000-000000008408';

  perform set_config('lekkadeall.allow_trusted_payment_update', 'off', true);

  perform *
  from public.customer_create_mock_checkout_session(
    '00000000-0000-0000-0000-000000008408',
    'ticket-7e-cash-checkout',
    'https://app.lekkadeall.test/return',
    'https://app.lekkadeall.test/cancel'
  );

  return true;
exception
  when others then
    perform set_config('lekkadeall.allow_trusted_payment_update', 'off', true);
    return false;
end;
$$;

create function pg_temp.checkout_summary(p_payment_id uuid)
returns text
language sql
security definer
set search_path = public, pg_temp
as $$
  select concat_ws(
    '|',
    status,
    provider_name,
    checkout_idempotency_key,
    (provider_reference like 'mock_checkout_%')::text,
    (checkout_url like 'https://mock-checkout.lekkadeall.test/%')::text
  )
  from public.payments
  where id = p_payment_id;
$$;

create function pg_temp.payment_summary(p_payment_id uuid)
returns text
language sql
security definer
set search_path = public, pg_temp
as $$
  select concat_ws('|', status, release_status, (paid_at is not null)::text)
  from public.payments
  where id = p_payment_id;
$$;

create function pg_temp.payment_event_count(
  p_provider_name text,
  p_idempotency_key text,
  p_event_type text default null
)
returns bigint
language sql
security definer
set search_path = public, pg_temp
as $$
  select count(*)
  from public.payment_events
  where provider_name = p_provider_name
    and idempotency_key = p_idempotency_key
    and (p_event_type is null or event_type = p_event_type)
    and coalesce(metadata ->> 'real_money_moved', 'false') = 'false';
$$;

create function pg_temp.vendor_event_count(
  p_provider_name text,
  p_provider_event_id text
)
returns bigint
language sql
security definer
set search_path = public, pg_temp
as $$
  select count(*)
  from public.vendor_events
  where provider_name = p_provider_name
    and provider_event_id = p_provider_event_id;
$$;

create function pg_temp.audit_count(
  p_action text,
  p_object_id text
)
returns bigint
language sql
security definer
set search_path = public, pg_temp
as $$
  select count(*)
  from public.audit_events
  where action = p_action
    and object_id = p_object_id;
$$;

create function pg_temp.try_direct_update_payment_status()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.payments
  set status = 'checkout_created'
  where id = '00000000-0000-0000-0000-000000008401';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_admin_mock_outcome(
  p_payment_id uuid,
  p_outcome_status text,
  p_provider_event_id text,
  p_idempotency_key text
)
returns boolean
language plpgsql
as $$
begin
  perform public.admin_record_mock_payment_outcome(
    p_payment_id,
    p_outcome_status,
    p_provider_event_id,
    p_idempotency_key,
    'Ticket 7E mock payment outcome test.',
    jsonb_build_object('test', 'ticket-7e')
  );

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_validate_provider_mode(
  p_app_env text,
  p_provider_mode text,
  p_webhook_secret_present boolean
)
returns boolean
language plpgsql
as $$
begin
  perform public.validate_payment_provider_mode(
    p_app_env,
    p_provider_mode,
    p_webhook_secret_present
  );

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.credential_column_count()
returns bigint
language sql
as $$
  select count(*)
  from information_schema.columns
  where table_schema = 'public'
    and table_name in ('payments', 'payment_events', 'vendor_events')
    and column_name ~* '(card|cvv|cvc|bank_login|bank_password|credential|pan)';
$$;

create function pg_temp.credential_metadata_count()
returns bigint
language sql
security definer
set search_path = public, pg_temp
as $$
  select count(*)
  from public.payment_events
  where metadata::text ~* '(card_number|cardnumber|cvv|cvc|bank_login|bank_password|raw_payment_credential|raw_card)';
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
  where idempotency_key = 'ticket-7e-paid-outcome';

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
  where idempotency_key = 'ticket-7e-paid-outcome';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_frontend_read_vendor_events()
returns boolean
language plpgsql
as $$
declare
  v_count integer;
begin
  select count(*)
    into v_count
  from public.vendor_events;

  return v_count >= 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_update_audit_event()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.audit_events
  set metadata = jsonb_build_object('tampered', true)
  where action in ('customer.mock_checkout_created', 'admin.mock_payment_paid');

  get diagnostics v_rows = row_count;
  return v_rows > 0;
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

create function pg_temp.try_customer_request_refund_smoke()
returns boolean
language plpgsql
as $$
begin
  perform public.customer_request_refund(
    '00000000-0000-0000-0000-000000000501',
    1000,
    'ticket_7e_smoke',
    'Ticket 7E refund ledger smoke test.',
    'ticket-7e-refund-smoke'
  );

  return true;
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
  where idempotency_key = 'refund-requested:ticket-7e-refund-smoke';

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
  perform public.customer_select_cash_payment('00000000-0000-0000-0000-000000008301');
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_direct_mark_payment_released()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.payments
  set release_status = 'released',
      released_at = now()
  where id = '00000000-0000-0000-0000-000000008401';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_customer_checkout(
    '00000000-0000-0000-0000-000000008401',
    'ticket-7e-checkout-own'
  ),
  true,
  'customer can create checkout for own pending payment'
);

select is(
  pg_temp.checkout_summary('00000000-0000-0000-0000-000000008401'),
  'checkout_created|mock|ticket-7e-checkout-own|true|true',
  'checkout creation moves payment status to checkout_created and stores safe mock references'
);

select is(
  pg_temp.payment_event_count('mock', 'ticket-7e-checkout-own', 'checkout_created'),
  1::bigint,
  'checkout creation writes exactly one payment_events row'
);

select is(
  pg_temp.audit_count('customer.mock_checkout_created', '00000000-0000-0000-0000-000000008401'),
  1::bigint,
  'checkout creation writes an audit_events row'
);

select is(
  pg_temp.try_customer_checkout(
    '00000000-0000-0000-0000-000000008401',
    'ticket-7e-checkout-own'
  ),
  true,
  'duplicate checkout idempotency key returns existing checkout'
);

select is(
  pg_temp.payment_event_count('mock', 'ticket-7e-checkout-own', 'checkout_created'),
  1::bigint,
  'duplicate checkout idempotency key does not duplicate events'
);

select is(
  pg_temp.try_customer_checkout(
    '00000000-0000-0000-0000-000000008402',
    'ticket-7e-other-customer'
  ),
  false,
  'customer cannot create checkout for another customer payment'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_customer_checkout(
    '00000000-0000-0000-0000-000000008401',
    'ticket-7e-checkout-own'
  ),
  false,
  'provider cannot create or replay checkout for customer payment'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_customer_checkout(
    '00000000-0000-0000-0000-000000008403',
    'ticket-7e-paid-checkout'
  ),
  false,
  'checkout cannot be created for paid payment'
);

select is(
  pg_temp.try_customer_checkout(
    '00000000-0000-0000-0000-000000008404',
    'ticket-7e-refunded-checkout'
  ),
  false,
  'checkout cannot be created for refunded payment'
);

select is(
  pg_temp.try_customer_checkout(
    '00000000-0000-0000-0000-000000008405',
    'ticket-7e-failed-checkout'
  ),
  false,
  'checkout cannot be created for failed payment'
);

select is(
  pg_temp.try_customer_checkout(
    '00000000-0000-0000-0000-000000008406',
    'ticket-7e-cancelled-checkout'
  ),
  false,
  'checkout cannot be created for cancelled payment'
);

select is(
  pg_temp.try_customer_checkout(
    '00000000-0000-0000-0000-000000008407',
    'ticket-7e-expired-checkout'
  ),
  false,
  'checkout cannot be created for expired payment'
);

select is(
  pg_temp.try_checkout_after_cash_marker(),
  false,
  'checkout cannot be created for cash/off-platform method'
);

select is(
  pg_temp.try_direct_update_payment_status(),
  false,
  'normal user cannot directly set payments.status = checkout_created'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';

select is(
  pg_temp.try_admin_mock_outcome(
    '00000000-0000-0000-0000-000000008401',
    'not_a_payment_status',
    'ticket-7e-provider-invalid',
    'ticket-7e-invalid-outcome'
  ),
  false,
  'admin mock outcome rejects invalid outcome status'
);

select is(
  pg_temp.try_admin_mock_outcome(
    '00000000-0000-0000-0000-000000008404',
    'paid',
    'ticket-7e-provider-paid-after-refund',
    'ticket-7e-paid-after-refund'
  ),
  false,
  'admin mock paid outcome is rejected after refund'
);

select is(
  pg_temp.try_admin_mock_outcome(
    '00000000-0000-0000-0000-000000008401',
    'paid',
    'ticket-7e-provider-paid',
    'ticket-7e-paid-outcome'
  ),
  true,
  'mock paid outcome can be recorded by admin/server'
);

select is(
  pg_temp.payment_summary('00000000-0000-0000-0000-000000008401'),
  'paid|pending|true',
  'mock paid outcome sets payment status, release status, and paid_at'
);

select is(
  pg_temp.payment_event_count('mock', 'ticket-7e-paid-outcome', 'mock_payment_paid'),
  1::bigint,
  'mock paid outcome writes payment event with real_money_moved=false'
);

select is(
  pg_temp.vendor_event_count('mock', 'ticket-7e-provider-paid'),
  1::bigint,
  'mock paid outcome writes vendor event'
);

select is(
  pg_temp.audit_count('admin.mock_payment_paid', '00000000-0000-0000-0000-000000008401'),
  1::bigint,
  'mock paid outcome writes audit event'
);

select is(
  pg_temp.try_admin_mock_outcome(
    '00000000-0000-0000-0000-000000008401',
    'paid',
    'ticket-7e-provider-paid',
    'ticket-7e-paid-outcome'
  ),
  true,
  'duplicate mock provider event returns existing payment event'
);

select is(
  pg_temp.payment_event_count('mock', 'ticket-7e-paid-outcome', 'mock_payment_paid'),
  1::bigint,
  'duplicate mock provider event does not duplicate payment events'
);

select is(
  pg_temp.try_admin_mock_outcome(
    '00000000-0000-0000-0000-000000008401',
    'failed',
    'ticket-7e-provider-failed-after-paid',
    'ticket-7e-failed-after-paid'
  ),
  true,
  'out-of-order failed-after-paid is safely ignored/rejected without crashing'
);

select is(
  pg_temp.payment_summary('00000000-0000-0000-0000-000000008401'),
  'paid|pending|true',
  'out-of-order failed-after-paid does not regress payment status'
);

select is(
  pg_temp.payment_event_count('mock', 'ticket-7e-failed-after-paid', 'mock_payment_out_of_order_rejected'),
  1::bigint,
  'out-of-order failed-after-paid writes a safe rejection ledger event'
);

select is(
  pg_temp.try_admin_mock_outcome(
    '00000000-0000-0000-0000-000000008409',
    'failed',
    'ticket-7e-provider-failed',
    'ticket-7e-failed-outcome'
  ),
  true,
  'mock failed outcome can be recorded by admin/server'
);

select is(
  pg_temp.payment_summary('00000000-0000-0000-0000-000000008409'),
  'failed|cancelled|false',
  'mock failed outcome sets payment status to failed and release_status to cancelled'
);

select is(
  pg_temp.payment_event_count('mock', 'ticket-7e-failed-outcome', 'mock_payment_failed'),
  1::bigint,
  'mock failed outcome writes payment event'
);

select is(
  pg_temp.vendor_event_count('mock', 'ticket-7e-provider-failed'),
  1::bigint,
  'mock failed outcome writes vendor event'
);

select is(
  pg_temp.audit_count('admin.mock_payment_failed', '00000000-0000-0000-0000-000000008409'),
  1::bigint,
  'mock failed outcome writes audit event'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_admin_mock_outcome(
    '00000000-0000-0000-0000-000000008409',
    'paid',
    'ticket-7e-customer-abuse',
    'ticket-7e-customer-abuse'
  ),
  false,
  'customer cannot call or abuse admin mock outcome function'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_admin_mock_outcome(
    '00000000-0000-0000-0000-000000008409',
    'paid',
    'ticket-7e-provider-abuse',
    'ticket-7e-provider-abuse'
  ),
  false,
  'provider cannot call or abuse admin mock outcome function'
);

reset role;

select is(
  pg_temp.try_validate_provider_mode('production', 'mock', false),
  false,
  'mock mode cannot run when production environment flag is true'
);

select is(
  pg_temp.try_validate_provider_mode('sandbox', 'mock', false),
  true,
  'mock mode is allowed for sandbox/local/CI style environments'
);

select is(
  pg_temp.credential_column_count(),
  0::bigint,
  'no card/CVV/bank credential columns are created'
);

select is(
  pg_temp.credential_metadata_count(),
  0::bigint,
  'no raw card/CVV/bank credential data is written to payment metadata'
);

select is(
  pg_temp.try_update_payment_event(),
  false,
  'payment_events remain append-only'
);

select is(
  pg_temp.try_delete_payment_event(),
  false,
  'payment_events cannot be deleted'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_frontend_read_vendor_events(),
  false,
  'vendor_events remain frontend-inaccessible'
);

reset role;

select is(
  pg_temp.try_update_audit_event(),
  false,
  'audit_events remain append-only'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_provider_change_verification_status(),
  false,
  'Ticket 1: role/provider verification protections remain intact'
);

select is(
  pg_temp.try_select_private_request_address(),
  false,
  'Ticket 5: address privacy remains intact'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_customer_update_service_category(),
  false,
  'Ticket 2: baseline RLS protections remain intact'
);

select is(
  pg_temp.try_direct_update_booking_status(),
  false,
  'Ticket 6: direct booking state mutation remains blocked'
);

select is(
  pg_temp.try_customer_request_refund_smoke(),
  true,
  'Ticket 7B: customer refund request path still works'
);

reset role;

select is(
  pg_temp.try_update_refund_event(),
  false,
  'Ticket 7B: refund_events remain append-only'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_select_cash_payment(),
  false,
  'Ticket 7C: cash-disabled policy remains intact'
);

select is(
  pg_temp.try_direct_mark_payment_released(),
  false,
  'Ticket 7D: frontend users cannot bypass payout release controls'
);

reset role;

select * from finish();

rollback;
