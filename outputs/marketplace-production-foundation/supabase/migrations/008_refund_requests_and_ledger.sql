-- Ticket 7B: refund requests and append-only refund event ledger.
-- This migration deliberately does not integrate a live payment provider, execute
-- real refunds, implement cash workflow, payout release/freeze, real webhooks, or UI.

create schema if not exists private;

create table if not exists public.refund_requests (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments(id) on delete restrict,
  booking_id uuid not null references public.bookings(id) on delete restrict,
  requested_by uuid not null references public.profiles(id) on delete restrict,
  requested_by_role text not null check (requested_by_role in ('customer', 'provider')),
  amount_minor integer not null check (amount_minor > 0),
  currency char(3) not null default 'ZAR' check (currency = 'ZAR'),
  reason_code text not null check (char_length(trim(reason_code)) between 2 and 80),
  reason_text text check (reason_text is null or char_length(reason_text) <= 1500),
  status text not null default 'requested' check (status in (
    'requested',
    'under_review',
    'approved',
    'rejected',
    'cancelled',
    'processing',
    'succeeded',
    'failed'
  )),
  admin_decision_by uuid references public.profiles(id) on delete restrict,
  admin_decision_at timestamptz,
  admin_decision_reason text check (admin_decision_reason is null or char_length(trim(admin_decision_reason)) between 3 and 1500),
  idempotency_key text,
  provider_name text not null default 'internal',
  provider_refund_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.refund_events (
  id uuid primary key default gen_random_uuid(),
  refund_request_id uuid not null references public.refund_requests(id) on delete restrict,
  payment_id uuid not null references public.payments(id) on delete restrict,
  booking_id uuid not null references public.bookings(id) on delete restrict,
  event_type text not null check (event_type in (
    'refund_requested',
    'refund_under_review',
    'refund_approved',
    'refund_rejected',
    'refund_cancelled',
    'refund_processing_recorded',
    'refund_succeeded_recorded',
    'refund_failed_recorded',
    'admin_note'
  )),
  amount_minor integer not null check (amount_minor > 0),
  currency char(3) not null default 'ZAR' check (currency = 'ZAR'),
  provider_name text not null default 'internal',
  provider_refund_reference text,
  provider_event_id text,
  idempotency_key text,
  actor_id uuid references public.profiles(id) on delete restrict,
  source text not null check (source in ('customer', 'provider', 'admin', 'system', 'webhook', 'manual_sandbox')),
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);

alter table public.refund_requests enable row level security;
alter table public.refund_events enable row level security;

drop index if exists public.refund_requests_actor_idempotency_uidx;
create unique index refund_requests_actor_idempotency_uidx
on public.refund_requests(requested_by, idempotency_key);

drop index if exists public.refund_events_provider_event_uidx;
create unique index refund_events_provider_event_uidx
on public.refund_events(provider_name, provider_event_id);

drop index if exists public.refund_events_idempotency_uidx;
create unique index refund_events_idempotency_uidx
on public.refund_events(provider_name, idempotency_key);

create index if not exists refund_requests_payment_idx
on public.refund_requests(payment_id, created_at desc);

create index if not exists refund_requests_booking_idx
on public.refund_requests(booking_id, created_at desc);

create index if not exists refund_events_refund_request_idx
on public.refund_events(refund_request_id, occurred_at desc);

create index if not exists refund_events_payment_idx
on public.refund_events(payment_id, occurred_at desc);

comment on table public.refund_requests is
  'Ticket 7B refund request workflow. Booking parties request refunds through safe functions only; admin/server decisions are trusted-function controlled. No live refund provider execution.';
comment on table public.refund_events is
  'Append-only Ticket 7B refund event ledger. Safe references/status metadata only; never card numbers, CVV, bank-login credentials, raw payment credentials, ID documents, or unredacted provider payloads.';

revoke all on public.refund_requests from anon, authenticated, service_role;
revoke all on public.refund_events from anon, authenticated, service_role;
grant select on public.refund_requests to authenticated;

drop policy if exists "booking parties read refund requests" on public.refund_requests;
create policy "booking parties read refund requests"
on public.refund_requests
for select
using (
  exists (
    select 1
    from public.bookings b
    where b.id = refund_requests.booking_id
      and auth.uid() in (b.customer_id, b.provider_id)
  )
);

create or replace function private.trusted_refund_update_allowed()
returns boolean
language sql
stable
set search_path = public
as $$
  select coalesce(current_setting('lekkadeall.allow_trusted_refund_update', true), 'off') = 'on';
$$;

create or replace function private.validate_safe_refund_metadata(p_metadata jsonb)
returns void
language plpgsql
stable
set search_path = public
as $$
declare
  v_text text := coalesce(p_metadata::text, '');
begin
  if v_text ~* '(card[_ -]?number|pan|cvv|cvc|bank[_ -]?login|bank[_ -]?password|raw[_ -]?payload|id[_ -]?document|identity[_ -]?document|passport|biometric|base64)' then
    raise exception 'Refund metadata contains prohibited sensitive material'
      using errcode = '22023';
  end if;
end;
$$;

create or replace function private.refund_reserved_minor(
  p_payment_id uuid,
  p_exclude_refund_request_id uuid default null
)
returns integer
language sql
stable
set search_path = public
as $$
  select coalesce(sum(rr.amount_minor), 0)::integer
  from public.refund_requests rr
  where rr.payment_id = p_payment_id
    and rr.status in ('requested', 'under_review', 'approved', 'processing')
    and (p_exclude_refund_request_id is null or rr.id <> p_exclude_refund_request_id);
$$;

create or replace function private.refund_remaining_minor(
  p_payment_id uuid,
  p_exclude_refund_request_id uuid default null
)
returns integer
language sql
stable
set search_path = public
as $$
  select greatest(
    0,
    p.amount_minor - p.refunded_minor - private.refund_reserved_minor(p_payment_id, p_exclude_refund_request_id)
  )::integer
  from public.payments p
  where p.id = p_payment_id;
$$;

create or replace function private.protect_refund_request_mutation()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if tg_op = 'DELETE' then
    if not private.trusted_refund_update_allowed() then
      raise exception 'refund_requests may not be deleted directly by frontend clients'
        using errcode = '42501';
    end if;

    return old;
  end if;

  if not private.trusted_refund_update_allowed() then
    raise exception 'refund_requests must be changed through trusted refund functions'
      using errcode = '42501';
  end if;

  if tg_op = 'UPDATE' then
    new.updated_at := now();
  end if;

  return new;
end;
$$;

create or replace function private.validate_refund_request_integrity()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_payment public.payments%rowtype;
begin
  select *
    into v_payment
  from public.payments
  where id = new.payment_id;

  if not found then
    raise exception 'Refund request payment_id % does not exist', new.payment_id
      using errcode = '23503';
  end if;

  if v_payment.booking_id <> new.booking_id then
    raise exception 'Refund request booking_id must match payment booking_id'
      using errcode = '23514';
  end if;

  if v_payment.currency <> new.currency then
    raise exception 'Refund request currency must match payment currency'
      using errcode = '23514';
  end if;

  if new.amount_minor > v_payment.amount_minor then
    raise exception 'Refund amount cannot exceed payment amount'
      using errcode = '23514';
  end if;

  if tg_op = 'INSERT'
     and v_payment.status not in ('paid', 'partially_refunded') then
    raise exception 'Only paid or partially_refunded payments can receive refund requests'
      using errcode = '23514';
  end if;

  if tg_op = 'INSERT'
     and new.amount_minor > private.refund_remaining_minor(new.payment_id, null) then
    raise exception 'Refund amount cannot exceed remaining refundable amount'
      using errcode = '23514';
  end if;

  if tg_op = 'UPDATE'
     and (
       new.payment_id is distinct from old.payment_id
       or new.booking_id is distinct from old.booking_id
       or new.amount_minor is distinct from old.amount_minor
       or new.currency is distinct from old.currency
     )
     and new.amount_minor > private.refund_remaining_minor(new.payment_id, new.id) then
    raise exception 'Refund amount cannot exceed remaining refundable amount'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists protect_refund_request_mutation on public.refund_requests;
create trigger protect_refund_request_mutation
before insert or update or delete on public.refund_requests
for each row execute function private.protect_refund_request_mutation();

drop trigger if exists validate_refund_request_integrity on public.refund_requests;
create trigger validate_refund_request_integrity
before insert or update of payment_id, booking_id, amount_minor, currency, status
on public.refund_requests
for each row execute function private.validate_refund_request_integrity();

create or replace function private.validate_refund_event_integrity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_refund public.refund_requests%rowtype;
begin
  select *
    into v_refund
  from public.refund_requests
  where id = new.refund_request_id;

  if not found then
    raise exception 'Refund event refund_request_id % does not exist', new.refund_request_id
      using errcode = '23503';
  end if;

  if v_refund.payment_id <> new.payment_id then
    raise exception 'Refund event payment_id must match refund request payment_id'
      using errcode = '23514';
  end if;

  if v_refund.booking_id <> new.booking_id then
    raise exception 'Refund event booking_id must match refund request booking_id'
      using errcode = '23514';
  end if;

  if v_refund.currency <> new.currency then
    raise exception 'Refund event currency must match refund request currency'
      using errcode = '23514';
  end if;

  if new.amount_minor > v_refund.amount_minor then
    raise exception 'Refund event amount cannot exceed refund request amount'
      using errcode = '23514';
  end if;

  perform private.validate_safe_refund_metadata(new.metadata);

  return new;
end;
$$;

create or replace function private.prevent_refund_event_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'refund_events are append-only'
    using errcode = '42501';
end;
$$;

drop trigger if exists validate_refund_event_integrity on public.refund_events;
create trigger validate_refund_event_integrity
before insert on public.refund_events
for each row execute function private.validate_refund_event_integrity();

drop trigger if exists refund_events_append_only on public.refund_events;
create trigger refund_events_append_only
before update or delete on public.refund_events
for each row execute function private.prevent_refund_event_mutation();

create or replace function private.record_refund_event(
  p_refund_request_id uuid,
  p_event_type text,
  p_actor_id uuid,
  p_source text,
  p_reason text,
  p_provider_name text default 'internal',
  p_provider_refund_reference text default null,
  p_provider_event_id text default null,
  p_idempotency_key text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_refund public.refund_requests%rowtype;
  v_event_id uuid;
  v_provider_name text := coalesce(nullif(trim(p_provider_name), ''), 'internal');
  v_metadata jsonb := coalesce(p_metadata, '{}'::jsonb);
begin
  perform private.validate_safe_refund_metadata(v_metadata);

  if p_idempotency_key is not null then
    select id
      into v_event_id
    from public.refund_events
    where provider_name = v_provider_name
      and idempotency_key = p_idempotency_key;

    if found then
      return v_event_id;
    end if;
  end if;

  if p_provider_event_id is not null then
    select id
      into v_event_id
    from public.refund_events
    where provider_name = v_provider_name
      and provider_event_id = p_provider_event_id;

    if found then
      return v_event_id;
    end if;
  end if;

  select *
    into v_refund
  from public.refund_requests
  where id = p_refund_request_id;

  if not found then
    raise exception 'Refund request % does not exist', p_refund_request_id
      using errcode = '02000';
  end if;

  insert into public.refund_events (
    refund_request_id,
    payment_id,
    booking_id,
    event_type,
    amount_minor,
    currency,
    provider_name,
    provider_refund_reference,
    provider_event_id,
    idempotency_key,
    actor_id,
    source,
    metadata
  ) values (
    v_refund.id,
    v_refund.payment_id,
    v_refund.booking_id,
    p_event_type,
    v_refund.amount_minor,
    v_refund.currency,
    v_provider_name,
    p_provider_refund_reference,
    p_provider_event_id,
    p_idempotency_key,
    p_actor_id,
    p_source,
    v_metadata || jsonb_build_object('reason', p_reason)
  )
  returning id into v_event_id;

  return v_event_id;
end;
$$;

create or replace function private.request_refund(
  p_payment_id uuid,
  p_amount_minor integer,
  p_reason_code text,
  p_reason_text text,
  p_idempotency_key text,
  p_expected_role text
)
returns uuid
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_payment public.payments%rowtype;
  v_booking public.bookings%rowtype;
  v_refund_id uuid;
begin
  if v_actor_id is null then
    raise exception 'Authentication is required to request a refund'
      using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_idempotency_key, '')), '') is null then
    raise exception 'Refund request idempotency key is required'
      using errcode = '23514';
  end if;

  select *
    into v_profile
  from public.profiles
  where id = v_actor_id;

  if not found
     or v_profile.account_status <> 'active'
     or v_profile.role::text <> p_expected_role then
    raise exception 'Actor is not an active %', p_expected_role
      using errcode = '42501';
  end if;

  select id
    into v_refund_id
  from public.refund_requests
  where requested_by = v_actor_id
    and idempotency_key = p_idempotency_key;

  if found then
    return v_refund_id;
  end if;

  select *
    into v_payment
  from public.payments
  where id = p_payment_id
  for update;

  if not found then
    raise exception 'Payment % does not exist', p_payment_id
      using errcode = '02000';
  end if;

  select *
    into v_booking
  from public.bookings
  where id = v_payment.booking_id;

  if not found then
    raise exception 'Payment booking % does not exist', v_payment.booking_id
      using errcode = '02000';
  end if;

  if p_expected_role = 'customer' and v_booking.customer_id <> v_actor_id then
    raise exception 'Customer can request refunds only for their own booking payment'
      using errcode = '42501';
  end if;

  if p_expected_role = 'provider' and v_booking.provider_id <> v_actor_id then
    raise exception 'Provider can request refunds only for their own booking payment'
      using errcode = '42501';
  end if;

  perform set_config('lekkadeall.allow_trusted_refund_update', 'on', true);

  begin
    insert into public.refund_requests (
      payment_id,
      booking_id,
      requested_by,
      requested_by_role,
      amount_minor,
      currency,
      reason_code,
      reason_text,
      status,
      idempotency_key,
      provider_name
    ) values (
      v_payment.id,
      v_payment.booking_id,
      v_actor_id,
      p_expected_role,
      p_amount_minor,
      v_payment.currency,
      p_reason_code,
      nullif(trim(coalesce(p_reason_text, '')), ''),
      'requested',
      p_idempotency_key,
      'internal'
    )
    returning id into v_refund_id;

    perform private.record_refund_event(
      v_refund_id,
      'refund_requested',
      v_actor_id,
      p_expected_role,
      p_reason_text,
      'internal',
      null,
      null,
      'refund-requested:' || p_idempotency_key,
      jsonb_build_object('reason_code', p_reason_code)
    );

    perform private.append_audit_event(
      v_actor_id,
      'refund.requested',
      'refund_request',
      v_refund_id::text,
      coalesce(nullif(trim(coalesce(p_reason_text, '')), ''), p_reason_code),
      jsonb_build_object(
        'payment_id', v_payment.id,
        'booking_id', v_payment.booking_id,
        'amount_minor', p_amount_minor,
        'requested_by_role', p_expected_role
      )
    );
  exception
    when others then
      perform set_config('lekkadeall.allow_trusted_refund_update', 'off', true);
      raise;
  end;

  perform set_config('lekkadeall.allow_trusted_refund_update', 'off', true);

  return v_refund_id;
end;
$$;

create or replace function public.customer_request_refund(
  p_payment_id uuid,
  p_amount_minor integer,
  p_reason_code text,
  p_reason_text text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = public, private, auth
as $$
begin
  return private.request_refund(
    p_payment_id,
    p_amount_minor,
    p_reason_code,
    p_reason_text,
    p_idempotency_key,
    'customer'
  );
end;
$$;

create or replace function public.provider_request_refund(
  p_payment_id uuid,
  p_amount_minor integer,
  p_reason_code text,
  p_reason_text text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = public, private, auth
as $$
begin
  return private.request_refund(
    p_payment_id,
    p_amount_minor,
    p_reason_code,
    p_reason_text,
    p_idempotency_key,
    'provider'
  );
end;
$$;

create or replace function private.require_refund_admin_reason(p_reason text)
returns void
language plpgsql
stable
set search_path = public
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Only platform admins or trusted server context may change refund decisions'
      using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'A non-empty refund admin reason is required'
      using errcode = '23514';
  end if;
end;
$$;

create or replace function public.admin_mark_refund_under_review(
  p_refund_request_id uuid,
  p_reason text,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_refund public.refund_requests%rowtype;
  v_event_id uuid;
  v_idempotency_key text;
begin
  perform private.require_refund_admin_reason(p_reason);

  select *
    into v_refund
  from public.refund_requests
  where id = p_refund_request_id
  for update;

  if not found then
    raise exception 'Refund request % does not exist', p_refund_request_id
      using errcode = '02000';
  end if;

  if v_refund.status not in ('requested', 'under_review') then
    raise exception 'Only requested refunds may move under review'
      using errcode = '23514';
  end if;

  v_idempotency_key := coalesce(nullif(trim(coalesce(p_idempotency_key, '')), ''), 'refund-under-review:' || p_refund_request_id::text);

  perform set_config('lekkadeall.allow_trusted_refund_update', 'on', true);

  begin
    update public.refund_requests
    set status = 'under_review'
    where id = p_refund_request_id;

    v_event_id := private.record_refund_event(
      p_refund_request_id,
      'refund_under_review',
      v_actor_id,
      'admin',
      p_reason,
      'internal',
      null,
      null,
      v_idempotency_key,
      '{}'::jsonb
    );

    perform private.append_audit_event(
      v_actor_id,
      'admin.refund_under_review',
      'refund_request',
      p_refund_request_id::text,
      p_reason,
      jsonb_build_object('refund_event_id', v_event_id)
    );
  exception
    when others then
      perform set_config('lekkadeall.allow_trusted_refund_update', 'off', true);
      raise;
  end;

  perform set_config('lekkadeall.allow_trusted_refund_update', 'off', true);

  return v_event_id;
end;
$$;

create or replace function public.admin_approve_refund(
  p_refund_request_id uuid,
  p_reason text,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_refund public.refund_requests%rowtype;
  v_event_id uuid;
  v_idempotency_key text;
begin
  perform private.require_refund_admin_reason(p_reason);

  select *
    into v_refund
  from public.refund_requests
  where id = p_refund_request_id
  for update;

  if not found then
    raise exception 'Refund request % does not exist', p_refund_request_id
      using errcode = '02000';
  end if;

  if v_refund.status not in ('requested', 'under_review', 'approved') then
    raise exception 'Only requested or under_review refunds may be approved'
      using errcode = '23514';
  end if;

  v_idempotency_key := coalesce(nullif(trim(coalesce(p_idempotency_key, '')), ''), 'refund-approved:' || p_refund_request_id::text);

  perform set_config('lekkadeall.allow_trusted_refund_update', 'on', true);

  begin
    update public.refund_requests
    set status = 'approved',
        admin_decision_by = v_actor_id,
        admin_decision_at = now(),
        admin_decision_reason = p_reason
    where id = p_refund_request_id;

    v_event_id := private.record_refund_event(
      p_refund_request_id,
      'refund_approved',
      v_actor_id,
      'admin',
      p_reason,
      'internal',
      null,
      null,
      v_idempotency_key,
      '{}'::jsonb
    );

    perform private.append_audit_event(
      v_actor_id,
      'admin.refund_approved',
      'refund_request',
      p_refund_request_id::text,
      p_reason,
      jsonb_build_object('refund_event_id', v_event_id)
    );
  exception
    when others then
      perform set_config('lekkadeall.allow_trusted_refund_update', 'off', true);
      raise;
  end;

  perform set_config('lekkadeall.allow_trusted_refund_update', 'off', true);

  return v_event_id;
end;
$$;

create or replace function public.admin_reject_refund(
  p_refund_request_id uuid,
  p_reason text,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_refund public.refund_requests%rowtype;
  v_event_id uuid;
  v_idempotency_key text;
begin
  perform private.require_refund_admin_reason(p_reason);

  select *
    into v_refund
  from public.refund_requests
  where id = p_refund_request_id
  for update;

  if not found then
    raise exception 'Refund request % does not exist', p_refund_request_id
      using errcode = '02000';
  end if;

  if v_refund.status not in ('requested', 'under_review', 'approved', 'rejected') then
    raise exception 'Only requested, under_review, or approved refunds may be rejected'
      using errcode = '23514';
  end if;

  v_idempotency_key := coalesce(nullif(trim(coalesce(p_idempotency_key, '')), ''), 'refund-rejected:' || p_refund_request_id::text);

  perform set_config('lekkadeall.allow_trusted_refund_update', 'on', true);

  begin
    update public.refund_requests
    set status = 'rejected',
        admin_decision_by = v_actor_id,
        admin_decision_at = now(),
        admin_decision_reason = p_reason
    where id = p_refund_request_id;

    v_event_id := private.record_refund_event(
      p_refund_request_id,
      'refund_rejected',
      v_actor_id,
      'admin',
      p_reason,
      'internal',
      null,
      null,
      v_idempotency_key,
      '{}'::jsonb
    );

    perform private.append_audit_event(
      v_actor_id,
      'admin.refund_rejected',
      'refund_request',
      p_refund_request_id::text,
      p_reason,
      jsonb_build_object('refund_event_id', v_event_id)
    );
  exception
    when others then
      perform set_config('lekkadeall.allow_trusted_refund_update', 'off', true);
      raise;
  end;

  perform set_config('lekkadeall.allow_trusted_refund_update', 'off', true);

  return v_event_id;
end;
$$;

create or replace function public.admin_record_refund_outcome(
  p_refund_request_id uuid,
  p_outcome_status text,
  p_provider_refund_reference text,
  p_idempotency_key text,
  p_reason text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_refund public.refund_requests%rowtype;
  v_payment public.payments%rowtype;
  v_event_id uuid;
  v_payment_event_id uuid;
  v_new_refunded_minor integer;
  v_new_payment_status text;
  v_event_type text;
  v_safe_metadata jsonb := coalesce(p_metadata, '{}'::jsonb);
begin
  perform private.require_refund_admin_reason(p_reason);
  perform private.validate_safe_refund_metadata(v_safe_metadata);

  if p_outcome_status not in ('processing', 'succeeded', 'failed') then
    raise exception 'Unsupported manual/sandbox refund outcome status %', p_outcome_status
      using errcode = '23514';
  end if;

  if nullif(trim(coalesce(p_idempotency_key, '')), '') is null then
    raise exception 'Refund outcome idempotency key is required'
      using errcode = '23514';
  end if;

  select id
    into v_event_id
  from public.refund_events
  where provider_name = 'manual_sandbox'
    and idempotency_key = p_idempotency_key;

  if found then
    return v_event_id;
  end if;

  select *
    into v_refund
  from public.refund_requests
  where id = p_refund_request_id
  for update;

  if not found then
    raise exception 'Refund request % does not exist', p_refund_request_id
      using errcode = '02000';
  end if;

  select *
    into v_payment
  from public.payments
  where id = v_refund.payment_id
  for update;

  if not found then
    raise exception 'Payment % does not exist', v_refund.payment_id
      using errcode = '02000';
  end if;

  if v_refund.status not in ('approved', 'processing') then
    raise exception 'Only approved or processing refunds may receive manual/sandbox outcomes'
      using errcode = '23514';
  end if;

  v_event_type := case p_outcome_status
    when 'processing' then 'refund_processing_recorded'
    when 'succeeded' then 'refund_succeeded_recorded'
    when 'failed' then 'refund_failed_recorded'
  end;

  perform set_config('lekkadeall.allow_trusted_refund_update', 'on', true);
  perform set_config('lekkadeall.allow_trusted_payment_update', 'on', true);

  begin
    if p_outcome_status = 'succeeded' then
      if v_payment.status not in ('paid', 'partially_refunded') then
        raise exception 'Only paid or partially_refunded payments can record successful refund outcomes'
          using errcode = '23514';
      end if;

      if v_refund.amount_minor > (v_payment.amount_minor - v_payment.refunded_minor) then
        raise exception 'Successful refund would exceed remaining refundable amount'
          using errcode = '23514';
      end if;

      v_new_refunded_minor := v_payment.refunded_minor + v_refund.amount_minor;
      v_new_payment_status := case
        when v_new_refunded_minor = v_payment.amount_minor then 'refunded'
        else 'partially_refunded'
      end;

      update public.payments
      set refunded_minor = v_new_refunded_minor,
          status = v_new_payment_status,
          updated_at = now()
      where id = v_payment.id;
    else
      v_new_payment_status := v_payment.status;
    end if;

    update public.refund_requests
    set status = p_outcome_status,
        provider_name = 'manual_sandbox',
        provider_refund_reference = nullif(trim(coalesce(p_provider_refund_reference, '')), '')
    where id = p_refund_request_id;

    v_event_id := private.record_refund_event(
      p_refund_request_id,
      v_event_type,
      v_actor_id,
      'manual_sandbox',
      p_reason,
      'manual_sandbox',
      nullif(trim(coalesce(p_provider_refund_reference, '')), ''),
      null,
      p_idempotency_key,
      v_safe_metadata || jsonb_build_object(
        'manual_sandbox_only', true,
        'real_money_moved', false
      )
    );

    if p_outcome_status = 'succeeded' then
      insert into public.payment_events (
        payment_id,
        booking_id,
        event_type,
        amount_minor,
        currency,
        provider_name,
        provider_event_id,
        idempotency_key,
        actor_id,
        source,
        metadata
      ) values (
        v_payment.id,
        v_payment.booking_id,
        'payment_status_changed',
        v_refund.amount_minor,
        v_payment.currency,
        'manual_sandbox',
        null,
        'payment-refund-outcome:' || p_idempotency_key,
        v_actor_id,
        'admin',
        jsonb_build_object(
          'refund_request_id', p_refund_request_id,
          'refund_event_id', v_event_id,
          'payment_status', v_new_payment_status,
          'refunded_minor', v_new_refunded_minor,
          'manual_sandbox_only', true,
          'real_money_moved', false
        )
      )
      returning id into v_payment_event_id;
    end if;

    perform private.append_audit_event(
      v_actor_id,
      'admin.refund_outcome_recorded',
      'refund_request',
      p_refund_request_id::text,
      p_reason,
      jsonb_build_object(
        'refund_event_id', v_event_id,
        'payment_event_id', v_payment_event_id,
        'outcome_status', p_outcome_status,
        'manual_sandbox_only', true,
        'real_money_moved', false
      )
    );
  exception
    when others then
      perform set_config('lekkadeall.allow_trusted_payment_update', 'off', true);
      perform set_config('lekkadeall.allow_trusted_refund_update', 'off', true);
      raise;
  end;

  perform set_config('lekkadeall.allow_trusted_payment_update', 'off', true);
  perform set_config('lekkadeall.allow_trusted_refund_update', 'off', true);

  return v_event_id;
end;
$$;

comment on function public.customer_request_refund(uuid, integer, text, text, text) is
  'Ticket 7B safe customer refund-request function. Creates request and ledger/audit rows only; does not execute real refunds.';
comment on function public.provider_request_refund(uuid, integer, text, text, text) is
  'Ticket 7B safe provider refund-request function. Creates request and ledger/audit rows only; does not execute real refunds.';
comment on function public.admin_record_refund_outcome(uuid, text, text, text, text, jsonb) is
  'Ticket 7B admin/manual-sandbox refund outcome recorder. It does not call a live payment provider and must not be treated as evidence that real money moved.';

revoke all on function private.trusted_refund_update_allowed() from public, anon, authenticated, service_role;
revoke all on function private.validate_safe_refund_metadata(jsonb) from public, anon, authenticated, service_role;
revoke all on function private.refund_reserved_minor(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function private.refund_remaining_minor(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function private.protect_refund_request_mutation() from public, anon, authenticated, service_role;
revoke all on function private.validate_refund_request_integrity() from public, anon, authenticated, service_role;
revoke all on function private.validate_refund_event_integrity() from public, anon, authenticated, service_role;
revoke all on function private.prevent_refund_event_mutation() from public, anon, authenticated, service_role;
revoke all on function private.record_refund_event(uuid, text, uuid, text, text, text, text, text, text, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.request_refund(uuid, integer, text, text, text, text) from public, anon, authenticated, service_role;
revoke all on function private.require_refund_admin_reason(text) from public, anon, authenticated, service_role;

revoke all on function public.customer_request_refund(uuid, integer, text, text, text) from public, anon;
revoke all on function public.provider_request_refund(uuid, integer, text, text, text) from public, anon;
revoke all on function public.admin_mark_refund_under_review(uuid, text, text) from public, anon;
revoke all on function public.admin_approve_refund(uuid, text, text) from public, anon;
revoke all on function public.admin_reject_refund(uuid, text, text) from public, anon;
revoke all on function public.admin_record_refund_outcome(uuid, text, text, text, text, jsonb) from public, anon;

grant execute on function public.customer_request_refund(uuid, integer, text, text, text) to authenticated, service_role;
grant execute on function public.provider_request_refund(uuid, integer, text, text, text) to authenticated, service_role;
grant execute on function public.admin_mark_refund_under_review(uuid, text, text) to authenticated, service_role;
grant execute on function public.admin_approve_refund(uuid, text, text) to authenticated, service_role;
grant execute on function public.admin_reject_refund(uuid, text, text) to authenticated, service_role;
grant execute on function public.admin_record_refund_outcome(uuid, text, text, text, text, jsonb) to authenticated, service_role;
