begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, auth;

select plan(48);

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

create temporary table ticket8a_cases (
  case_key text primary key,
  request_id uuid not null,
  bid_id uuid not null,
  booking_id uuid not null,
  payment_id uuid not null,
  customer_id uuid not null,
  provider_id uuid not null,
  provider_reference text not null unique,
  payment_status text not null,
  amount_minor integer not null,
  refunded_minor integer not null default 0,
  release_status text not null default 'not_applicable'
) on commit drop;

insert into ticket8a_cases (
  case_key, request_id, bid_id, booking_id, payment_id,
  customer_id, provider_id, provider_reference, payment_status,
  amount_minor, refunded_minor, release_status
) values
  ('paid_event', '00000000-0000-0000-0000-000000009101', '00000000-0000-0000-0000-000000009201', '00000000-0000-0000-0000-000000009301', '00000000-0000-0000-0000-000000009401', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', 'ticket-8a-paid', 'checkout_created', 21000, 0, 'not_applicable'),
  ('failed_event', '00000000-0000-0000-0000-000000009102', '00000000-0000-0000-0000-000000009202', '00000000-0000-0000-0000-000000009302', '00000000-0000-0000-0000-000000009402', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', 'ticket-8a-failed', 'checkout_created', 22000, 0, 'not_applicable'),
  ('failed_after_paid', '00000000-0000-0000-0000-000000009103', '00000000-0000-0000-0000-000000009203', '00000000-0000-0000-0000-000000009303', '00000000-0000-0000-0000-000000009403', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', 'ticket-8a-failed-after-paid', 'paid', 23000, 0, 'pending'),
  ('checkout_after_paid', '00000000-0000-0000-0000-000000009104', '00000000-0000-0000-0000-000000009204', '00000000-0000-0000-0000-000000009304', '00000000-0000-0000-0000-000000009404', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', 'ticket-8a-checkout-after-paid', 'paid', 24000, 0, 'pending'),
  ('paid_after_refunded', '00000000-0000-0000-0000-000000009105', '00000000-0000-0000-0000-000000009205', '00000000-0000-0000-0000-000000009305', '00000000-0000-0000-0000-000000009405', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', 'ticket-8a-paid-after-refunded', 'refunded', 25000, 25000, 'cancelled'),
  ('customer_abuse', '00000000-0000-0000-0000-000000009106', '00000000-0000-0000-0000-000000009206', '00000000-0000-0000-0000-000000009306', '00000000-0000-0000-0000-000000009406', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', 'ticket-8a-customer-abuse', 'checkout_created', 26000, 0, 'not_applicable'),
  ('checkout_smoke', '00000000-0000-0000-0000-000000009107', '00000000-0000-0000-0000-000000009207', '00000000-0000-0000-0000-000000009307', '00000000-0000-0000-0000-000000009407', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', 'ticket-8a-checkout-smoke', 'pending', 27000, 0, 'not_applicable');

set local lekkadeall.allow_marketplace_state_transition = 'on';

insert into public.service_requests (
  id, customer_id, category_id, title, description, suburb, city,
  requested_start, budget_minor, status, closes_at
)
select
  request_id,
  customer_id,
  '00000000-0000-0000-0000-000000000100',
  'Ticket 8A ' || case_key,
  'Safe Ticket 8A mock webhook processing test request.',
  'Die Bult',
  'Potchefstroom',
  timestamptz '2026-08-02 10:00:00+02',
  amount_minor,
  'awarded',
  timestamptz '2026-08-01 10:00:00+02'
from ticket8a_cases;

insert into public.bids (
  id, request_id, provider_id, amount_minor, proposed_start,
  message, status, expires_at
)
select
  bid_id,
  request_id,
  provider_id,
  amount_minor,
  timestamptz '2026-08-02 10:00:00+02',
  'Accepted Ticket 8A mock webhook test bid.',
  'accepted',
  timestamptz '2026-08-01 10:00:00+02'
from ticket8a_cases;

insert into public.bookings (
  id, public_reference, request_id, bid_id, customer_id, provider_id,
  service_amount_minor, platform_fee_minor, scheduled_start, status
)
select
  booking_id,
  'TICKET-8A-' || upper(case_key),
  request_id,
  bid_id,
  customer_id,
  provider_id,
  amount_minor,
  0,
  timestamptz '2026-08-02 10:00:00+02',
  'payment_pending'
from ticket8a_cases;

set local lekkadeall.allow_marketplace_state_transition = 'off';

set local lekkadeall.allow_trusted_payment_update = 'on';

insert into public.payments (
  id, booking_id, provider_name, provider_reference, status,
  amount_minor, release_paused, paid_at, funded_at, refunded_minor,
  release_status, payment_method
)
select
  payment_id,
  booking_id,
  'mock',
  provider_reference,
  payment_status,
  amount_minor,
  false,
  case when payment_status in ('paid', 'partially_refunded', 'refunded') then now() else null end,
  case when payment_status in ('paid', 'partially_refunded', 'refunded') then now() else null end,
  refunded_minor,
  release_status,
  'sandbox_online'
from ticket8a_cases;

set local lekkadeall.allow_trusted_payment_update = 'off';

create function pg_temp.try_admin_webhook(
  p_provider_event_id text,
  p_provider_reference text,
  p_event_type text,
  p_payload_hash text,
  p_idempotency_key text,
  p_metadata jsonb default jsonb_build_object('test', 'ticket-8a')
)
returns boolean
language plpgsql
as $$
begin
  perform public.admin_process_verified_mock_payment_webhook(
    p_provider_event_id,
    p_provider_reference,
    p_event_type,
    p_payload_hash,
    p_idempotency_key,
    p_metadata
  );

  return true;
exception
  when others then return false;
end;
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
  p_provider_event_id text,
  p_event_type text default null
)
returns bigint
language sql
security definer
set search_path = public, pg_temp
as $$
  select count(*)
  from public.payment_events
  where provider_name = 'mock'
    and provider_event_id = p_provider_event_id
    and (p_event_type is null or event_type = p_event_type)
    and coalesce(metadata ->> 'real_money_moved', 'false') = 'false';
$$;

create function pg_temp.vendor_event_count(
  p_provider_event_id text,
  p_payload_hash text default null
)
returns bigint
language sql
security definer
set search_path = public, pg_temp
as $$
  select count(*)
  from public.vendor_events
  where provider_name = 'mock'
    and provider_event_id = p_provider_event_id
    and (p_payload_hash is null or payload_hash = p_payload_hash);
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

create function pg_temp.try_update_payment_event()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.payment_events
  set metadata = jsonb_build_object('tampered', true)
  where provider_event_id = 'ticket-8a-webhook-paid';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
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
  where action like 'admin.mock_webhook%';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_direct_mark_payment_paid()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.payments
  set status = 'paid'
  where id = '00000000-0000-0000-0000-000000009406';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.raw_webhook_column_count()
returns bigint
language sql
as $$
  select count(*)
  from information_schema.columns
  where table_schema = 'public'
    and table_name in ('payments', 'payment_events', 'vendor_events')
    and column_name ~* '(raw.*body|raw.*payload|webhook_body|signature|secret)';
$$;

create function pg_temp.raw_webhook_metadata_count()
returns bigint
language sql
security definer
set search_path = public, pg_temp
as $$
  select count(*)
  from public.payment_events
  where provider_name = 'mock'
    and metadata::text ~* '(raw_body|raw_payload|webhook_body|signature_header|provider_signature|webhook_secret|card_number|cvv|bank_password)';
$$;

create function pg_temp.try_provider_change_verification_status()
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
    'ticket_8a_smoke',
    'Ticket 8A refund ledger smoke test.',
    'ticket-8a-refund-smoke'
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
  where idempotency_key = 'refund-requested:ticket-8a-refund-smoke';

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
  perform public.customer_select_cash_payment('00000000-0000-0000-0000-000000009306');
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
  where id = '00000000-0000-0000-0000-000000009403';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
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

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
select ok(not pg_temp.try_frontend_read_vendor_events(), 'vendor_events remains frontend-inaccessible');
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';
select ok(
  pg_temp.try_admin_webhook(
    'ticket-8a-webhook-paid',
    'ticket-8a-paid',
    'mock.payment.paid',
    'sha256:' || repeat('a', 64),
    'ticket-8a-webhook-paid',
    jsonb_build_object('test', 'ticket-8a-paid')
  ),
  'trusted mock webhook paid event updates payment once'
);
reset role;

select is(
  pg_temp.payment_summary('00000000-0000-0000-0000-000000009401'),
  'paid|pending|true',
  'paid webhook moves checkout_created payment to paid and release pending'
);
select is(pg_temp.vendor_event_count('ticket-8a-webhook-paid'), 1::bigint, 'paid event writes exactly one vendor_events row');
select is(pg_temp.payment_event_count('ticket-8a-webhook-paid', 'webhook_payment_paid'), 1::bigint, 'paid event writes exactly one payment_events row');
select is(pg_temp.audit_count('admin.mock_webhook_processed', '00000000-0000-0000-0000-000000009401'), 1::bigint, 'paid event writes exactly one audit_events row');

select ok(not pg_temp.try_update_payment_event(), 'payment_events append-only trigger rejects updates');
select ok(not pg_temp.try_update_audit_event(), 'audit_events append-only trigger rejects updates');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';
select ok(
  pg_temp.try_admin_webhook(
    'ticket-8a-webhook-paid',
    'ticket-8a-paid',
    'mock.payment.paid',
    'sha256:' || repeat('a', 64),
    'ticket-8a-webhook-paid',
    jsonb_build_object('test', 'ticket-8a-paid-duplicate')
  ),
  'duplicate provider_event_id with same payload_hash is idempotent'
);
reset role;

select is(pg_temp.vendor_event_count('ticket-8a-webhook-paid'), 1::bigint, 'duplicate provider_event_id does not duplicate vendor_events');
select is(pg_temp.payment_event_count('ticket-8a-webhook-paid', 'webhook_payment_paid'), 1::bigint, 'duplicate provider_event_id does not duplicate payment_events');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';
select ok(
  pg_temp.try_admin_webhook(
    'ticket-8a-webhook-paid',
    'ticket-8a-paid',
    'mock.payment.paid',
    'sha256:' || repeat('b', 64),
    'ticket-8a-webhook-paid-different-hash',
    jsonb_build_object('test', 'ticket-8a-paid-hash-mismatch')
  ),
  'duplicate provider_event_id with different payload_hash is hash-flagged without exception'
);
reset role;

select is(pg_temp.payment_summary('00000000-0000-0000-0000-000000009401'), 'paid|pending|true', 'different payload_hash duplicate does not mutate paid payment');
select is(pg_temp.audit_count('admin.mock_webhook_payload_hash_mismatch', '00000000-0000-0000-0000-000000009401'), 1::bigint, 'different payload_hash duplicate writes hash mismatch audit event');
select is(pg_temp.payment_event_count('ticket-8a-webhook-paid', 'webhook_payment_paid'), 1::bigint, 'different payload_hash duplicate does not duplicate payment_events');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';
select ok(
  pg_temp.try_admin_webhook(
    'ticket-8a-webhook-failed-after-paid',
    'ticket-8a-failed-after-paid',
    'mock.payment.failed',
    'sha256:' || repeat('c', 64),
    'ticket-8a-webhook-failed-after-paid',
    jsonb_build_object('test', 'ticket-8a-failed-after-paid')
  ),
  'failed-after-paid mock webhook is safely processed'
);
reset role;

select is(pg_temp.payment_summary('00000000-0000-0000-0000-000000009403'), 'paid|pending|true', 'failed-after-paid does not regress payment status');
select is(pg_temp.payment_event_count('ticket-8a-webhook-failed-after-paid', 'webhook_out_of_order_rejected'), 1::bigint, 'failed-after-paid writes out-of-order payment event');
select is(pg_temp.audit_count('admin.mock_webhook_out_of_order_rejected', '00000000-0000-0000-0000-000000009403'), 1::bigint, 'failed-after-paid writes out-of-order audit event');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';
select ok(
  pg_temp.try_admin_webhook(
    'ticket-8a-webhook-checkout-after-paid',
    'ticket-8a-checkout-after-paid',
    'mock.checkout.created',
    'sha256:' || repeat('d', 64),
    'ticket-8a-webhook-checkout-after-paid',
    jsonb_build_object('test', 'ticket-8a-checkout-after-paid')
  ),
  'checkout-created-after-paid mock webhook is safely processed'
);
reset role;

select is(pg_temp.payment_summary('00000000-0000-0000-0000-000000009404'), 'paid|pending|true', 'checkout-created-after-paid does not downgrade payment status');
select is(pg_temp.payment_event_count('ticket-8a-webhook-checkout-after-paid', 'webhook_out_of_order_rejected'), 1::bigint, 'checkout-created-after-paid writes out-of-order payment event');
select is(pg_temp.audit_count('admin.mock_webhook_out_of_order_rejected', '00000000-0000-0000-0000-000000009404'), 1::bigint, 'checkout-created-after-paid writes out-of-order audit event');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';
select ok(
  pg_temp.try_admin_webhook(
    'ticket-8a-webhook-paid-after-refunded',
    'ticket-8a-paid-after-refunded',
    'mock.payment.paid',
    'sha256:' || repeat('e', 64),
    'ticket-8a-webhook-paid-after-refunded',
    jsonb_build_object('test', 'ticket-8a-paid-after-refunded')
  ),
  'paid-after-refunded mock webhook is routed without payment mutation'
);
reset role;

select is(pg_temp.payment_summary('00000000-0000-0000-0000-000000009405'), 'refunded|cancelled|true', 'paid-after-refunded does not mutate payment status');
select is(pg_temp.payment_event_count('ticket-8a-webhook-paid-after-refunded', 'webhook_manual_review_required'), 1::bigint, 'paid-after-refunded writes manual-review payment event');
select is(pg_temp.audit_count('admin.mock_webhook_manual_review_required', '00000000-0000-0000-0000-000000009405'), 1::bigint, 'paid-after-refunded writes manual-review audit event');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';
select ok(
  pg_temp.try_admin_webhook(
    'ticket-8a-webhook-failed',
    'ticket-8a-failed',
    'mock.payment.failed',
    'sha256:' || repeat('f', 64),
    'ticket-8a-webhook-failed',
    jsonb_build_object('test', 'ticket-8a-failed')
  ),
  'trusted mock failed webhook updates checkout_created payment'
);
reset role;

select is(pg_temp.payment_summary('00000000-0000-0000-0000-000000009402'), 'failed|cancelled|false', 'failed webhook moves checkout_created payment to failed');
select is(pg_temp.payment_event_count('ticket-8a-webhook-failed', 'webhook_payment_failed'), 1::bigint, 'failed webhook writes payment event');
select is(pg_temp.vendor_event_count('ticket-8a-webhook-failed'), 1::bigint, 'failed webhook writes vendor event');
select is(pg_temp.audit_count('admin.mock_webhook_processed', '00000000-0000-0000-0000-000000009402'), 1::bigint, 'failed webhook writes audit event');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';
select ok(
  not pg_temp.try_admin_webhook(
    'ticket-8a-webhook-invalid',
    'ticket-8a-customer-abuse',
    'mock.payment.reversed',
    'sha256:' || repeat('1', 64),
    'ticket-8a-webhook-invalid',
    jsonb_build_object('test', 'ticket-8a-invalid')
  ),
  'invalid provider event type is rejected'
);
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
select ok(
  not pg_temp.try_admin_webhook(
    'ticket-8a-webhook-customer-abuse',
    'ticket-8a-customer-abuse',
    'mock.payment.paid',
    'sha256:' || repeat('2', 64),
    'ticket-8a-webhook-customer-abuse',
    jsonb_build_object('test', 'ticket-8a-customer-abuse')
  ),
  'normal customer cannot call webhook-processing function'
);
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select ok(
  not pg_temp.try_admin_webhook(
    'ticket-8a-webhook-provider-abuse',
    'ticket-8a-customer-abuse',
    'mock.payment.paid',
    'sha256:' || repeat('3', 64),
    'ticket-8a-webhook-provider-abuse',
    jsonb_build_object('test', 'ticket-8a-provider-abuse')
  ),
  'normal provider cannot call webhook-processing function'
);
select ok(not pg_temp.try_direct_mark_payment_paid(), 'frontend users cannot mark payments paid through direct table update');
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';
select ok(
  not pg_temp.try_admin_webhook(
    'ticket-8a-webhook-raw-body',
    'ticket-8a-customer-abuse',
    'mock.payment.paid',
    'sha256:' || repeat('4', 64),
    'ticket-8a-webhook-raw-body',
    jsonb_build_object('raw_body', '{"unsafe": true}')
  ),
  'raw webhook body metadata is rejected'
);
reset role;

select is(pg_temp.raw_webhook_column_count(), 0::bigint, 'no raw webhook body/signature/secret columns are stored');
select is(pg_temp.raw_webhook_metadata_count(), 0::bigint, 'no raw webhook body/signature/secret metadata is stored');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select ok(not pg_temp.try_provider_change_verification_status(), 'Ticket 1 role/provider self-verification protection remains intact');
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
select ok(not pg_temp.try_customer_update_service_category(), 'Ticket 2 baseline RLS category mutation protection remains intact');
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
select ok(not pg_temp.try_select_private_request_address(), 'Ticket 5 private address protection remains intact');
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
select ok(not pg_temp.try_direct_update_booking_status(), 'Ticket 6 booking state mutation protection remains intact');
reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
select ok(pg_temp.try_customer_request_refund_smoke(), 'Ticket 7B customer refund request function remains usable');
select ok(not pg_temp.try_update_refund_event(), 'Ticket 7B refund event ledger remains append-only');
select ok(not pg_temp.try_select_cash_payment(), 'Ticket 7C cash-disabled protection remains intact');
select ok(not pg_temp.try_direct_mark_payment_released(), 'Ticket 7D direct payout release mutation remains blocked');
select ok(not pg_temp.try_validate_provider_mode('production', 'mock', false), 'Ticket 7E mock provider mode remains fail-closed in production');
reset role;

select * from finish();

rollback;
