begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, auth;

select plan(48);

\ir rls_test_seed.inc

create temporary table ticket7b_ids (
  key text primary key,
  id uuid not null
) on commit drop;

grant select, insert, update, delete on table ticket7b_ids to anon, authenticated;

set local lekkadeall.allow_trusted_payment_update = 'on';

insert into public.payments (
  id,
  booking_id,
  provider_name,
  provider_reference,
  status,
  amount_minor,
  release_paused,
  paid_at,
  refunded_minor
) values (
  '00000000-0000-0000-0000-000000000902',
  '00000000-0000-0000-0000-000000000402',
  'mock',
  'ticket-7b-paid-payment',
  'paid',
  68250,
  false,
  now(),
  0
);

set local lekkadeall.allow_trusted_payment_update = 'off';

create function pg_temp.try_customer_request_refund(
  p_payment_id uuid,
  p_amount_minor integer,
  p_idempotency_key text
)
returns boolean
language plpgsql
as $$
begin
  perform public.customer_request_refund(
    p_payment_id,
    p_amount_minor,
    'service_issue',
    'Safe refund test reason.',
    p_idempotency_key
  );

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_provider_request_refund(
  p_payment_id uuid,
  p_amount_minor integer,
  p_idempotency_key text
)
returns boolean
language plpgsql
as $$
begin
  perform public.provider_request_refund(
    p_payment_id,
    p_amount_minor,
    'provider_goodwill',
    'Safe provider refund test reason.',
    p_idempotency_key
  );

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.visible_refund_request_count()
returns integer
language plpgsql
as $$
declare
  v_count integer;
begin
  select count(*) into v_count from public.refund_requests;
  return v_count;
exception
  when others then return -1;
end;
$$;

create function pg_temp.visible_refund_event_count()
returns integer
language plpgsql
as $$
declare
  v_count integer;
begin
  select count(*) into v_count from public.refund_events;
  return v_count;
exception
  when others then return -1;
end;
$$;

create function pg_temp.refund_request_summary(p_key text)
returns text
language plpgsql
as $$
declare
  v_summary text;
begin
  select concat_ws('|', rr.status, rr.amount_minor::text, rr.currency)
    into v_summary
  from public.refund_requests rr
  join ticket7b_ids i on i.id = rr.id
  where i.key = p_key;

  return coalesce(v_summary, '<none>');
exception
  when others then return '<denied>';
end;
$$;

create function pg_temp.try_direct_insert_refund_request()
returns boolean
language plpgsql
as $$
begin
  insert into public.refund_requests (
    payment_id,
    booking_id,
    requested_by,
    requested_by_role,
    amount_minor,
    reason_code,
    reason_text,
    status,
    idempotency_key
  ) values (
    '00000000-0000-0000-0000-000000000501',
    '00000000-0000-0000-0000-000000000401',
    auth.uid(),
    'customer',
    1000,
    'direct',
    'Direct frontend insert should fail.',
    'requested',
    'ticket-7b-direct-insert'
  );

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_direct_update_refund_request()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.refund_requests
  set status = 'approved'
  where id = (select id from ticket7b_ids where key = 'customer_refund');

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_direct_delete_refund_request()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  delete from public.refund_requests
  where id = (select id from ticket7b_ids where key = 'customer_refund');

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_direct_insert_refund_event()
returns boolean
language plpgsql
as $$
begin
  insert into public.refund_events (
    refund_request_id,
    payment_id,
    booking_id,
    event_type,
    amount_minor,
    source
  ) values (
    (select id from ticket7b_ids where key = 'customer_refund'),
    '00000000-0000-0000-0000-000000000501',
    '00000000-0000-0000-0000-000000000401',
    'admin_note',
    1000,
    'customer'
  );

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_direct_update_refund_event()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.refund_events
  set metadata = jsonb_build_object('tampered', true)
  where refund_request_id = (select id from ticket7b_ids where key = 'customer_refund');

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_direct_delete_refund_event()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  delete from public.refund_events
  where refund_request_id = (select id from ticket7b_ids where key = 'customer_refund');

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_insert_invalid_refund_status()
returns boolean
language plpgsql
as $$
begin
  perform set_config('lekkadeall.allow_trusted_refund_update', 'on', true);

  insert into public.refund_requests (
    payment_id,
    booking_id,
    requested_by,
    requested_by_role,
    amount_minor,
    reason_code,
    status,
    idempotency_key
  ) values (
    '00000000-0000-0000-0000-000000000501',
    '00000000-0000-0000-0000-000000000401',
    '00000000-0000-0000-0000-000000000001',
    'customer',
    1000,
    'invalid_status',
    'not_a_refund_status',
    'ticket-7b-invalid-status'
  );

  perform set_config('lekkadeall.allow_trusted_refund_update', 'off', true);
  return true;
exception
  when others then
    perform set_config('lekkadeall.allow_trusted_refund_update', 'off', true);
    return false;
end;
$$;

create function pg_temp.try_insert_invalid_refund_event_type()
returns boolean
language plpgsql
as $$
begin
  insert into public.refund_events (
    refund_request_id,
    payment_id,
    booking_id,
    event_type,
    amount_minor,
    source
  ) values (
    (select id from ticket7b_ids where key = 'customer_refund'),
    '00000000-0000-0000-0000-000000000501',
    '00000000-0000-0000-0000-000000000401',
    'not_a_refund_event',
    1000,
    'admin'
  );

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_admin_approve_refund(p_key text)
returns boolean
language plpgsql
as $$
begin
  perform public.admin_approve_refund(
    (select id from ticket7b_ids where key = p_key),
    'Normal user abuse attempt.'
  );

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_admin_reject_refund(p_key text)
returns boolean
language plpgsql
as $$
begin
  perform public.admin_reject_refund(
    (select id from ticket7b_ids where key = p_key),
    'Normal user abuse attempt.'
  );

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_admin_record_refund_outcome(
  p_key text,
  p_outcome_status text,
  p_idempotency_key text
)
returns boolean
language plpgsql
as $$
begin
  perform public.admin_record_refund_outcome(
    (select id from ticket7b_ids where key = p_key),
    p_outcome_status,
    'normal-user-provider-ref',
    p_idempotency_key,
    'Normal user abuse attempt.',
    jsonb_build_object('test', 'ticket-7b')
  );

  return true;
exception
  when others then return false;
end;
$$;

create function pg_temp.try_direct_payment_refund_mutation()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.payments
  set refunded_minor = 1000,
      status = 'partially_refunded'
  where id = '00000000-0000-0000-0000-000000000902';

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

create function pg_temp.try_update_payment_event()
returns boolean
language plpgsql
as $$
declare
  v_rows integer;
begin
  update public.payment_events
  set metadata = jsonb_build_object('tampered', true)
  where idempotency_key = 'payment-refund-outcome:ticket-7b-partial-outcome';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
exception
  when others then return false;
end;
$$;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

insert into ticket7b_ids(key, id)
select 'customer_refund',
       public.customer_request_refund(
         '00000000-0000-0000-0000-000000000501',
         10000,
         'service_issue',
         'Customer A safe refund request.',
         'ticket-7b-customer-request'
       );

select ok(
  (select id is not null from ticket7b_ids where key = 'customer_refund'),
  'customer can request refund for own booking payment'
);

insert into ticket7b_ids(key, id)
select 'customer_refund_duplicate',
       public.customer_request_refund(
         '00000000-0000-0000-0000-000000000501',
         10000,
         'service_issue',
         'Customer A duplicate safe refund request.',
         'ticket-7b-customer-request'
       );

select is(
  (select id from ticket7b_ids where key = 'customer_refund_duplicate'),
  (select id from ticket7b_ids where key = 'customer_refund'),
  'duplicate refund request idempotency key returns existing refund request'
);

reset role;

select is(
  (
    select count(*)
    from public.refund_events
    where idempotency_key = 'refund-requested:ticket-7b-customer-request'
  ),
  1::bigint,
  'duplicate refund request idempotency key does not duplicate refund event'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

insert into ticket7b_ids(key, id)
select 'provider_refund',
       public.provider_request_refund(
         '00000000-0000-0000-0000-000000000902',
         5000,
         'provider_goodwill',
         'Provider B safe refund request.',
         'ticket-7b-provider-request'
       );

select ok(
  (select id is not null from ticket7b_ids where key = 'provider_refund'),
  'provider can request refund for own booking payment'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

select is(
  pg_temp.try_customer_request_refund(
    '00000000-0000-0000-0000-000000000501',
    1000,
    'ticket-7b-customer-unrelated'
  ),
  false,
  'customer cannot request refund for unrelated payment'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

select is(
  pg_temp.try_provider_request_refund(
    '00000000-0000-0000-0000-000000000501',
    1000,
    'ticket-7b-provider-unrelated'
  ),
  false,
  'provider cannot request refund for unrelated payment'
);

reset role;

set local role anon;
set local request.jwt.claim.sub = '';

select is(
  pg_temp.visible_refund_request_count(),
  -1,
  'anonymous user cannot access refund_requests'
);

select is(
  pg_temp.visible_refund_event_count(),
  -1,
  'anonymous user cannot access refund_events'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

select is(
  (
    select count(*)
    from public.refund_requests
    where id = (select id from ticket7b_ids where key = 'customer_refund')
  ),
  0::bigint,
  'unrelated authenticated user cannot read refund requests'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.refund_request_summary('customer_refund'),
  'requested|10000|ZAR',
  'booking customer can read safe refund request summary'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';

select is(
  pg_temp.refund_request_summary('customer_refund'),
  'requested|10000|ZAR',
  'booking provider can read safe refund request summary'
);

select is(
  pg_temp.try_direct_insert_refund_request(),
  false,
  'frontend users cannot directly insert refund_requests'
);

select is(
  pg_temp.try_direct_update_refund_request(),
  false,
  'frontend users cannot directly update refund_requests'
);

select is(
  pg_temp.try_direct_delete_refund_request(),
  false,
  'frontend users cannot directly delete refund_requests'
);

select is(
  pg_temp.try_direct_insert_refund_event(),
  false,
  'frontend users cannot directly insert refund_events'
);

select is(
  pg_temp.try_direct_update_refund_event(),
  false,
  'frontend users cannot directly update refund_events'
);

select is(
  pg_temp.try_direct_delete_refund_event(),
  false,
  'frontend users cannot directly delete refund_events'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_customer_request_refund(
    '00000000-0000-0000-0000-000000000501',
    0,
    'ticket-7b-zero-amount'
  ),
  false,
  'refund amount must be greater than zero'
);

select is(
  pg_temp.try_customer_request_refund(
    '00000000-0000-0000-0000-000000000501',
    999999,
    'ticket-7b-exceeds-payment'
  ),
  false,
  'refund amount cannot exceed payment amount'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

insert into ticket7b_ids(key, id)
select 'customer_reject',
       public.customer_request_refund(
         '00000000-0000-0000-0000-000000000902',
         7000,
         'service_issue',
         'Customer B refund request for rejection.',
         'ticket-7b-customer-reject'
       );

select is(
  pg_temp.try_customer_request_refund(
    '00000000-0000-0000-0000-000000000902',
    60000,
    'ticket-7b-exceeds-remaining'
  ),
  false,
  'refund amount cannot exceed remaining refundable amount'
);

reset role;

select is(
  pg_temp.try_insert_invalid_refund_status(),
  false,
  'invalid refund status is rejected'
);

select is(
  pg_temp.try_insert_invalid_refund_event_type(),
  false,
  'invalid refund event type is rejected'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

select is(
  pg_temp.try_admin_approve_refund('provider_refund'),
  false,
  'customer cannot approve refund'
);

select is(
  pg_temp.try_admin_record_refund_outcome(
    'provider_refund',
    'succeeded',
    'ticket-7b-customer-succeeded-abuse'
  ),
  false,
  'customer cannot mark refund succeeded'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000012';

select is(
  pg_temp.try_admin_reject_refund('customer_reject'),
  false,
  'provider cannot reject refund'
);

select is(
  pg_temp.try_admin_record_refund_outcome(
    'customer_reject',
    'failed',
    'ticket-7b-provider-failed-abuse'
  ),
  false,
  'provider cannot mark refund failed'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';

select ok(
  public.admin_approve_refund(
    (select id from ticket7b_ids where key = 'provider_refund'),
    'Approved provider goodwill refund for sandbox test.',
    'ticket-7b-provider-approve'
  ) is not null,
  'admin/server can approve refund with refund event'
);

reset role;

select is(
  (
    select count(*)
    from public.audit_events
    where object_type = 'refund_request'
      and object_id = (select id::text from ticket7b_ids where key = 'provider_refund')
      and action = 'admin.refund_approved'
  ),
  1::bigint,
  'admin refund approval writes audit event'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';

select ok(
  public.admin_reject_refund(
    (select id from ticket7b_ids where key = 'customer_reject'),
    'Rejected refund request for sandbox test.',
    'ticket-7b-customer-reject-admin'
  ) is not null,
  'admin/server can reject refund with refund event'
);

reset role;

select is(
  (
    select count(*)
    from public.audit_events
    where object_type = 'refund_request'
      and object_id = (select id::text from ticket7b_ids where key = 'customer_reject')
      and action = 'admin.refund_rejected'
  ),
  1::bigint,
  'admin refund rejection writes audit event'
);

select is(
  (
    select refunded_minor
    from public.payments
    where id = '00000000-0000-0000-0000-000000000902'
  ),
  0,
  'rejected refund does not increase payments.refunded_minor'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';

select ok(
  public.admin_record_refund_outcome(
    (select id from ticket7b_ids where key = 'provider_refund'),
    'succeeded',
    'manual-sandbox-partial',
    'ticket-7b-partial-outcome',
    'Manual sandbox success only; no real provider refund executed.',
    jsonb_build_object('test', 'ticket-7b-partial')
  ) is not null,
  'admin/server can record manual-sandbox refund success outcome'
);

reset role;

select is(
  (
    select refunded_minor
    from public.payments
    where id = '00000000-0000-0000-0000-000000000902'
  ),
  5000,
  'trusted refund-success outcome updates payments.refunded_minor'
);

select is(
  (
    select status
    from public.payments
    where id = '00000000-0000-0000-0000-000000000902'
  ),
  'partially_refunded',
  'partial refund moves payment to partially_refunded'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

insert into ticket7b_ids(key, id)
select 'customer_full',
       public.customer_request_refund(
         '00000000-0000-0000-0000-000000000902',
         63250,
         'service_issue',
         'Customer B remaining refund request.',
         'ticket-7b-customer-full'
       );

reset role;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';

select ok(
  public.admin_approve_refund(
    (select id from ticket7b_ids where key = 'customer_full'),
    'Approved remaining refund for sandbox test.',
    'ticket-7b-full-approve'
  ) is not null,
  'admin/server can approve remaining full refund request'
);

select ok(
  public.admin_record_refund_outcome(
    (select id from ticket7b_ids where key = 'customer_full'),
    'succeeded',
    'manual-sandbox-full',
    'ticket-7b-full-outcome',
    'Manual sandbox full refund success only; no real provider refund executed.',
    jsonb_build_object('test', 'ticket-7b-full')
  ) is not null,
  'admin/server can record manual-sandbox full refund success outcome'
);

reset role;

select is(
  (
    select status
    from public.payments
    where id = '00000000-0000-0000-0000-000000000902'
  ),
  'refunded',
  'full refund moves payment to refunded'
);

select is(
  (
    select refunded_minor
    from public.payments
    where id = '00000000-0000-0000-0000-000000000902'
  ),
  68250,
  'full refund moves payments.refunded_minor to full payment amount'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000099';

select ok(
  public.admin_record_refund_outcome(
    (select id from ticket7b_ids where key = 'customer_full'),
    'succeeded',
    'manual-sandbox-full',
    'ticket-7b-full-outcome',
    'Duplicate manual sandbox full refund outcome should be idempotent.',
    jsonb_build_object('test', 'ticket-7b-full-duplicate')
  ) is not null,
  'duplicate refund outcome idempotency key returns existing refund event'
);

reset role;

select is(
  (
    select count(*)
    from public.refund_events
    where idempotency_key = 'ticket-7b-full-outcome'
  ),
  1::bigint,
  'duplicate idempotency key does not duplicate refund event'
);

select is(
  pg_temp.try_direct_update_refund_event(),
  false,
  'refund_events cannot be updated'
);

select is(
  pg_temp.try_direct_delete_refund_event(),
  false,
  'refund_events cannot be deleted'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

select is(
  pg_temp.try_direct_payment_refund_mutation(),
  false,
  'customer/provider direct payment refund mutation remains blocked'
);

reset role;

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

select * from finish();

rollback;
