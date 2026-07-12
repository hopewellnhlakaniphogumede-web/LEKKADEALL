begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, auth;

select plan(37);

\ir rls_test_seed.inc

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000013', 'provider-c-unapproved@lekkadeall.test'),
  ('00000000-0000-0000-0000-000000000014', 'provider-d-suspended@lekkadeall.test');

insert into public.profiles (id, role, display_name, city, account_status) values
  ('00000000-0000-0000-0000-000000000013', 'provider', 'Provider C Unapproved', 'Potchefstroom', 'active'),
  ('00000000-0000-0000-0000-000000000014', 'provider', 'Provider D Suspended', 'Potchefstroom', 'suspended');

insert into public.provider_profiles (
  user_id, business_name, verification_status, verification_reference,
  bank_name_match, review_status
) values
  (
    '00000000-0000-0000-0000-000000000013',
    'Provider C Unapproved Services',
    'verified',
    'ticket-7d-provider-c',
    true,
    'rejected'
  ),
  (
    '00000000-0000-0000-0000-000000000014',
    'Provider D Suspended Services',
    'verified',
    'ticket-7d-provider-d',
    true,
    'approved'
  );

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

create temporary table ticket7d_cases (
  case_key text primary key,
  request_id uuid not null,
  bid_id uuid not null,
  booking_id uuid not null,
  payment_id uuid not null,
  provider_id uuid not null,
  booking_status public.booking_status not null,
  payment_status text not null,
  amount_minor integer not null,
  refunded_minor integer not null default 0,
  release_status text not null default 'pending'
) on commit drop;

insert into ticket7d_cases (
  case_key, request_id, bid_id, booking_id, payment_id, provider_id,
  booking_status, payment_status, amount_minor, refunded_minor, release_status
) values
  ('ok', '00000000-0000-0000-0000-000000007101', '00000000-0000-0000-0000-000000007201', '00000000-0000-0000-0000-000000007301', '00000000-0000-0000-0000-000000007401', '00000000-0000-0000-0000-000000000011', 'completed', 'paid', 10000, 0, 'pending'),
  ('unpaid', '00000000-0000-0000-0000-000000007102', '00000000-0000-0000-0000-000000007202', '00000000-0000-0000-0000-000000007302', '00000000-0000-0000-0000-000000007402', '00000000-0000-0000-0000-000000000011', 'completed', 'pending', 10000, 0, 'not_applicable'),
  ('incomplete', '00000000-0000-0000-0000-000000007103', '00000000-0000-0000-0000-000000007203', '00000000-0000-0000-0000-000000007303', '00000000-0000-0000-0000-000000007403', '00000000-0000-0000-0000-000000000011', 'scheduled', 'paid', 10000, 0, 'pending'),
  ('full_refund', '00000000-0000-0000-0000-000000007104', '00000000-0000-0000-0000-000000007204', '00000000-0000-0000-0000-000000007304', '00000000-0000-0000-0000-000000007404', '00000000-0000-0000-0000-000000000011', 'completed', 'refunded', 10000, 10000, 'cancelled'),
  ('refund_requested', '00000000-0000-0000-0000-000000007105', '00000000-0000-0000-0000-000000007205', '00000000-0000-0000-0000-000000007305', '00000000-0000-0000-0000-000000007405', '00000000-0000-0000-0000-000000000011', 'completed', 'paid', 10000, 0, 'pending'),
  ('refund_under_review', '00000000-0000-0000-0000-000000007106', '00000000-0000-0000-0000-000000007206', '00000000-0000-0000-0000-000000007306', '00000000-0000-0000-0000-000000007406', '00000000-0000-0000-0000-000000000011', 'completed', 'paid', 10000, 0, 'pending'),
  ('refund_approved', '00000000-0000-0000-0000-000000007107', '00000000-0000-0000-0000-000000007207', '00000000-0000-0000-0000-000000007307', '00000000-0000-0000-0000-000000007407', '00000000-0000-0000-0000-000000000011', 'completed', 'paid', 10000, 0, 'pending'),
  ('refund_processing', '00000000-0000-0000-0000-000000007108', '00000000-0000-0000-0000-000000007208', '00000000-0000-0000-0000-000000007308', '00000000-0000-0000-0000-000000007408', '00000000-0000-0000-0000-000000000011', 'completed', 'paid', 10000, 0, 'pending'),
  ('dispute_open', '00000000-0000-0000-0000-000000007109', '00000000-0000-0000-0000-000000007209', '00000000-0000-0000-0000-000000007309', '00000000-0000-0000-0000-000000007409', '00000000-0000-0000-0000-000000000011', 'completed', 'paid', 10000, 0, 'pending'),
  ('provider_suspended', '00000000-0000-0000-0000-000000007110', '00000000-0000-0000-0000-000000007210', '00000000-0000-0000-0000-000000007310', '00000000-0000-0000-0000-000000007410', '00000000-0000-0000-0000-000000000014', 'completed', 'paid', 10000, 0, 'pending'),
  ('provider_unapproved', '00000000-0000-0000-0000-000000007111', '00000000-0000-0000-0000-000000007211', '00000000-0000-0000-0000-000000007311', '00000000-0000-0000-0000-000000007411', '00000000-0000-0000-0000-000000000013', 'completed', 'paid', 10000, 0, 'pending'),
  ('cash_attempt', '00000000-0000-0000-0000-000000007112', '00000000-0000-0000-0000-000000007212', '00000000-0000-0000-0000-000000007312', '00000000-0000-0000-0000-000000007412', '00000000-0000-0000-0000-000000000011', 'completed', 'paid', 10000, 0, 'pending');

set local lekkadeall.allow_marketplace_state_transition = 'on';

insert into public.service_requests (
  id, customer_id, category_id, title, description, suburb, city,
  requested_start, budget_minor, status, closes_at
)
select
  request_id,
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000100',
  'Ticket 7D ' || case_key,
  'Safe Ticket 7D payout release test request.',
  'Die Bult',
  'Potchefstroom',
  timestamptz '2026-08-01 10:00:00+02',
  amount_minor,
  'awarded',
  timestamptz '2026-07-31 10:00:00+02'
from ticket7d_cases;

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
  'Accepted Ticket 7D payout release test bid.',
  'accepted',
  timestamptz '2026-07-31 10:00:00+02'
from ticket7d_cases;

insert into public.bookings (
  id, public_reference, request_id, bid_id, customer_id, provider_id,
  service_amount_minor, platform_fee_minor, scheduled_start, status,
  completion_confirmed_at
)
select
  booking_id,
  'TICKET-7D-' || upper(case_key),
  request_id,
  bid_id,
  '00000000-0000-0000-0000-000000000001',
  provider_id,
  amount_minor,
  0,
  timestamptz '2026-08-01 10:00:00+02',
  booking_status,
  case when booking_status = 'completed' then now() else null end
from ticket7d_cases;

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
  'ticket-7d-' || case_key,
  payment_status,
  amount_minor,
  false,
  case when payment_status in ('paid', 'partially_refunded', 'refunded') then now() else null end,
  case when payment_status in ('paid', 'partially_refunded', 'refunded') then now() else null end,
  refunded_minor,
  release_status
from ticket7d_cases;

set local lekkadeall.allow_trusted_payment_update = 'off';

set local lekkadeall.allow_trusted_refund_update = 'on';

insert into public.refund_requests (
  id, payment_id, booking_id, requested_by, requested_by_role,
  amount_minor, reason_code, reason_text, status, idempotency_key
) values
  ('00000000-0000-0000-0000-000000007505', '00000000-0000-0000-0000-000000007405', '00000000-0000-0000-0000-000000007305', '00000000-0000-0000-0000-000000000001', 'customer', 1000, 'release_block', 'Ticket 7D requested refund blocker.', 'requested', 'ticket-7d-refund-requested'),
  ('00000000-0000-0000-0000-000000007506', '00000000-0000-0000-0000-000000007406', '00000000-0000-0000-0000-000000007306', '00000000-0000-0000-0000-000000000001', 'customer', 1000, 'release_block', 'Ticket 7D under review refund blocker.', 'under_review', 'ticket-7d-refund-under-review'),
  ('00000000-0000-0000-0000-000000007507', '00000000-0000-0000-0000-000000007407', '00000000-0000-0000-0000-000000007307', '00000000-0000-0000-0000-000000000001', 'customer', 1000, 'release_block', 'Ticket 7D approved refund blocker.', 'approved', 'ticket-7d-refund-approved'),
  ('00000000-0000-0000-0000-000000007508', '00000000-0000-0000-0000-000000007408', '00000000-0000-0000-0000-000000007308', '00000000-0000-0000-0000-000000000001', 'customer', 1000, 'release_block', 'Ticket 7D processing refund blocker.', 'processing', 'ticket-7d-refund-processing');

set local lekkadeall.allow_trusted_refund_update = 'off';

insert into public.disputes (
  id, public_reference, booking_id, opened_by, issue_code,
  description, status, assigned_to
) values (
  '00000000-0000-0000-0000-000000007609',
  'TICKET-7D-DISPUTE',
  '00000000-0000-0000-0000-000000007309',
  '00000000-0000-0000-0000-000000000001',
  'service_incomplete',
  'Ticket 7D open dispute release blocker.',
  'open',
  '00000000-0000-0000-0000-000000000099'
);

create function pg_temp.try_admin_mark_eligible(
  p_payment_id uuid,
  p_reason text,
  p_idempotency_key text
)
returns boolean
language plpgsql
as $$
begin
  perform public.admin_mark_release_eligible(p_payment_id, p_reason, p_idempotency_key);
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_admin_pause(
  p_payment_id uuid,
  p_reason text,
  p_idempotency_key text
)
returns boolean
language plpgsql
as $$
begin
  perform public.admin_pause_payment_release(p_payment_id, p_reason, p_idempotency_key);
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_admin_resume(
  p_payment_id uuid,
  p_reason text,
  p_idempotency_key text
)
returns boolean
language plpgsql
as $$
begin
  perform public.admin_resume_payment_release(p_payment_id, p_reason, p_idempotency_key);
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_admin_record_release(
  p_payment_id uuid,
  p_provider_reference text,
  p_amount_minor integer,
  p_reason text,
  p_idempotency_key text
)
returns boolean
language plpgsql
as $$
begin
  perform public.admin_record_payout_release(
    p_payment_id,
    p_provider_reference,
    p_amount_minor,
    p_reason,
    p_idempotency_key
  );
  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_direct_mark_release_eligible(p_payment_id uuid)
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.payments
  set release_status = 'eligible',
      release_eligible_at = now()
  where id = p_payment_id;

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_direct_mark_payment_released(p_payment_id uuid)
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.payments
  set release_status = 'released',
      released_at = now()
  where id = p_payment_id;

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.payment_event_count(p_provider_name text, p_idempotency_key text)
returns bigint
language sql
as $$
  select count(*)
  from public.payment_events
  where provider_name = p_provider_name
    and idempotency_key = p_idempotency_key;
$$;

create function pg_temp.audit_count(p_action text, p_object_id text)
returns bigint
language sql
as $$
  select count(*)
  from public.audit_events
  where action = p_action
    and object_id = p_object_id;
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
  where idempotency_key = 'ticket-7d-release-ok';

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
  where action = 'admin.payout_release_recorded'
    and object_id = '00000000-0000-0000-0000-000000007401';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_force_cash_release()
returns boolean
language plpgsql
as $$
begin
  perform set_config('lekkadeall.allow_trusted_payment_update', 'on', true);

  update public.payments
  set payment_method = 'off_platform_cash'
  where id = '00000000-0000-0000-0000-000000007412';

  perform set_config('lekkadeall.allow_trusted_payment_update', 'off', true);

  perform public.admin_mark_release_eligible(
    '00000000-0000-0000-0000-000000007412',
    'Cash/off-platform release attempt.',
    'ticket-7d-cash-eligible'
  );

  perform public.admin_record_payout_release(
    '00000000-0000-0000-0000-000000007412',
    'ticket-7d-cash-release',
    10000,
    'Cash/off-platform release attempt.',
    'ticket-7d-cash-release'
  );

  return true;
exception
  when others then
    perform set_config('lekkadeall.allow_trusted_payment_update', 'off', true);
    return false;
end;
$$;

create function pg_temp.try_provider_change_verification_status()
returns boolean
language plpgsql
as $$
begin
  update public.provider_profiles
  set verification_status = 'manual_review'
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
  where id = '00000000-0000-0000-0000-000000007303';

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
  where idempotency_key = 'refund-requested:ticket-7d-refund-smoke';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_admin_mark_eligible(
    '00000000-0000-0000-0000-000000007401',
    'Customer cannot mark release eligible.',
    'ticket-7d-customer-eligible'
  ),
  false,
  'customer cannot mark release as eligible'
);

select is(
  pg_temp.try_direct_mark_payment_released('00000000-0000-0000-0000-000000007401'),
  false,
  'customer cannot mark payment released'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_admin_mark_eligible(
    '00000000-0000-0000-0000-000000007401',
    'Provider cannot mark release eligible.',
    'ticket-7d-provider-eligible'
  ),
  false,
  'provider cannot mark release as eligible'
);

select is(
  pg_temp.try_direct_mark_payment_released('00000000-0000-0000-0000-000000007401'),
  false,
  'provider cannot mark payment released'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';

select is(
  pg_temp.try_admin_record_release('00000000-0000-0000-0000-000000007402', 'ticket-7d-unpaid-release', 10000, 'Unpaid release attempt.', 'ticket-7d-unpaid-release'),
  false,
  'admin/server cannot release unpaid payment'
);

select is(
  pg_temp.try_admin_record_release('00000000-0000-0000-0000-000000007403', 'ticket-7d-incomplete-release', 10000, 'Incomplete booking release attempt.', 'ticket-7d-incomplete-release'),
  false,
  'admin/server cannot release incomplete booking'
);

select is(
  pg_temp.try_admin_record_release('00000000-0000-0000-0000-000000007404', 'ticket-7d-full-refund-release', 10000, 'Fully refunded release attempt.', 'ticket-7d-full-refund-release'),
  false,
  'admin/server cannot release fully refunded payment'
);

select is(
  pg_temp.try_admin_record_release('00000000-0000-0000-0000-000000007405', 'ticket-7d-refund-requested-release', 10000, 'Requested refund release attempt.', 'ticket-7d-refund-requested-release'),
  false,
  'admin/server cannot release while refund is requested'
);

select is(
  pg_temp.try_admin_record_release('00000000-0000-0000-0000-000000007406', 'ticket-7d-refund-under-review-release', 10000, 'Under review refund release attempt.', 'ticket-7d-refund-under-review-release'),
  false,
  'admin/server cannot release while refund is under_review'
);

select is(
  pg_temp.try_admin_record_release('00000000-0000-0000-0000-000000007407', 'ticket-7d-refund-approved-release', 10000, 'Approved refund release attempt.', 'ticket-7d-refund-approved-release'),
  false,
  'admin/server cannot release while refund is approved'
);

select is(
  pg_temp.try_admin_record_release('00000000-0000-0000-0000-000000007408', 'ticket-7d-refund-processing-release', 10000, 'Processing refund release attempt.', 'ticket-7d-refund-processing-release'),
  false,
  'admin/server cannot release while refund is processing'
);

select is(
  pg_temp.try_admin_record_release('00000000-0000-0000-0000-000000007409', 'ticket-7d-dispute-release', 10000, 'Open dispute release attempt.', 'ticket-7d-dispute-release'),
  false,
  'admin/server cannot release while dispute is open'
);

select is(
  pg_temp.try_admin_record_release('00000000-0000-0000-0000-000000007410', 'ticket-7d-suspended-provider-release', 10000, 'Suspended provider release attempt.', 'ticket-7d-suspended-provider-release'),
  false,
  'admin/server cannot release when provider is suspended'
);

select is(
  pg_temp.try_admin_record_release('00000000-0000-0000-0000-000000007411', 'ticket-7d-unapproved-provider-release', 10000, 'Unapproved provider release attempt.', 'ticket-7d-unapproved-provider-release'),
  false,
  'admin/server cannot release when provider approval is revoked'
);

select is(
  pg_temp.try_admin_pause(
    '00000000-0000-0000-0000-000000007401',
    'Manual Ticket 7D pause.',
    'ticket-7d-pause-ok'
  ),
  true,
  'admin/server can pause release with a non-empty reason'
);

select is(
  pg_temp.try_admin_pause(
    '00000000-0000-0000-0000-000000007401',
    '',
    'ticket-7d-blank-pause'
  ),
  false,
  'blank pause reason is rejected'
);

select is(
  pg_temp.try_admin_resume(
    '00000000-0000-0000-0000-000000007401',
    '',
    'ticket-7d-blank-resume'
  ),
  false,
  'blank resume reason is rejected'
);

select is(
  pg_temp.try_admin_record_release(
    '00000000-0000-0000-0000-000000007401',
    'ticket-7d-blank-release',
    10000,
    '',
    'ticket-7d-blank-release'
  ),
  false,
  'blank release reason is rejected'
);

select is(
  pg_temp.try_admin_resume(
    '00000000-0000-0000-0000-000000007409',
    'Dispute blocker remains.',
    'ticket-7d-resume-blocked'
  ),
  false,
  'admin/server can resume release only after blockers are cleared'
);

select is(
  pg_temp.try_admin_resume(
    '00000000-0000-0000-0000-000000007401',
    'Manual Ticket 7D resume.',
    'ticket-7d-resume-ok'
  ),
  true,
  'admin/server can resume release after blockers are cleared'
);

select is(
  pg_temp.payment_event_count('internal', 'ticket-7d-pause-ok'),
  1::bigint,
  'release pause writes payment_events'
);

select is(
  pg_temp.audit_count('admin.payment_release_paused', '00000000-0000-0000-0000-000000007401'),
  1::bigint,
  'release pause writes audit_events'
);

select is(
  pg_temp.try_admin_mark_eligible(
    '00000000-0000-0000-0000-000000007401',
    'Release eligibility approved.',
    'ticket-7d-eligible-ok'
  ),
  true,
  'admin/server can mark release eligible when blockers are clear'
);

select is(
  pg_temp.payment_event_count('internal', 'ticket-7d-eligible-ok'),
  1::bigint,
  'release eligibility writes payment_events'
);

select is(
  pg_temp.try_admin_record_release(
    '00000000-0000-0000-0000-000000007401',
    'ticket-7d-manual-sandbox-release',
    10000,
    'Manual/sandbox payout release record.',
    'ticket-7d-release-ok'
  ),
  true,
  'admin/server can record manual/sandbox payout release when eligible'
);

select is(
  pg_temp.payment_event_count('manual_sandbox', 'ticket-7d-release-ok'),
  1::bigint,
  'payout release recording writes payment_events'
);

select is(
  pg_temp.audit_count('admin.payout_release_recorded', '00000000-0000-0000-0000-000000007401'),
  1::bigint,
  'payout release recording writes audit_events'
);

select is(
  pg_temp.try_admin_record_release(
    '00000000-0000-0000-0000-000000007401',
    'ticket-7d-manual-sandbox-release',
    10000,
    'Manual/sandbox payout release duplicate.',
    'ticket-7d-release-ok'
  ),
  true,
  'duplicate idempotency key returns existing payout release event'
);

select is(
  pg_temp.payment_event_count('manual_sandbox', 'ticket-7d-release-ok'),
  1::bigint,
  'duplicate idempotency key does not duplicate events'
);

select is(
  pg_temp.try_update_payment_event(),
  false,
  'Ticket 7A: payment_events remain append-only'
);

select is(
  pg_temp.try_update_audit_event(),
  false,
  'audit_events remain append-only'
);

select is(
  pg_temp.try_force_cash_release(),
  false,
  'Ticket 7C: cash/off-platform payment cannot be released'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.try_provider_change_verification_status(),
  false,
  'Ticket 1: provider self-verification remains blocked'
);

select is(
  pg_temp.try_select_private_request_address(),
  false,
  'Ticket 5: address privacy remains intact'
);

select is(
  pg_temp.try_direct_update_booking_status(),
  false,
  'Ticket 6: direct booking state mutation remains blocked'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_customer_update_service_category(),
  false,
  'Ticket 2: baseline RLS protections remain intact'
);

do $$
begin
  perform public.customer_request_refund(
    '00000000-0000-0000-0000-000000000501',
    1000,
    'payout_release_smoke',
    'Ticket 7D refund ledger smoke test.',
    'ticket-7d-refund-smoke'
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
