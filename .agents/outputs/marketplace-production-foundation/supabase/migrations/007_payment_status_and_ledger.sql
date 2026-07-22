-- Ticket 7A: constrain payment status and add an append-only payment event ledger.
-- This migration deliberately does not integrate a live payment provider, refunds,
-- cash workflow, payout release, or real webhook handlers.

create schema if not exists private;

update public.payments
set status = case status
  when 'payment_pending' then 'pending'
  when 'created' then 'pending'
  when 'funded' then 'paid'
  when 'refund_pending' then 'partially_refunded'
  when 'release_pending' then 'paid'
  when 'released' then 'paid'
  when 'disputed' then 'paid'
  else status
end;

alter table public.payments
  add column if not exists release_status text,
  add column if not exists paid_at timestamptz;

update public.payments
set paid_at = coalesce(paid_at, funded_at)
where status in ('paid', 'partially_refunded', 'refunded')
  and paid_at is null;

update public.payments
set release_status = case
  when released_at is not null then 'released'
  when release_paused then 'paused'
  when status in ('paid', 'partially_refunded') then 'pending'
  when status in ('cancelled', 'failed', 'expired', 'refunded') then 'cancelled'
  else 'not_applicable'
end
where release_status is null;

alter table public.payments
  alter column release_status set default 'not_applicable',
  alter column release_status set not null;

alter table public.payments
  drop constraint if exists payments_status_check,
  drop constraint if exists payments_payment_status_check,
  drop constraint if exists payments_release_status_check,
  drop constraint if exists payments_paid_at_status_check,
  add constraint payments_payment_status_check
    check (status in (
      'pending',
      'checkout_created',
      'paid',
      'failed',
      'expired',
      'cancelled',
      'partially_refunded',
      'refunded'
    )),
  add constraint payments_release_status_check
    check (release_status in (
      'not_applicable',
      'pending',
      'paused',
      'eligible',
      'released',
      'cancelled'
    )),
  add constraint payments_paid_at_status_check
    check (paid_at is null or status in ('paid', 'partially_refunded', 'refunded'));

comment on column public.payments.status is
  'Ticket 7A constrained payment status. Current column name is status; semantically this is payment_status. Allowed MVP values: pending, checkout_created, paid, failed, expired, cancelled, partially_refunded, refunded.';
comment on column public.payments.release_status is
  'Ticket 7A release/payout status, intentionally separate from payment status. Payout release execution remains a later ticket.';
comment on column public.payments.paid_at is
  'Timestamp set by trusted payment/server logic when payment is confirmed paid. Frontend users cannot update this directly.';

create table if not exists public.payment_events (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments(id) on delete restrict,
  booking_id uuid not null references public.bookings(id) on delete restrict,
  event_type text not null check (event_type in (
    'intent_prepared',
    'checkout_created',
    'payment_status_changed',
    'payment_marked_paid',
    'payment_failed',
    'payment_expired',
    'payment_cancelled',
    'release_status_changed',
    'admin_note'
  )),
  amount_minor integer not null check (amount_minor >= 0),
  currency char(3) not null default 'ZAR' check (currency = 'ZAR'),
  provider_name text not null,
  provider_event_id text,
  idempotency_key text,
  actor_id uuid references public.profiles(id),
  source text not null check (source in ('system', 'admin', 'webhook', 'migration')),
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);

alter table public.payment_events enable row level security;

drop index if exists public.payment_events_provider_event_uidx;
create unique index payment_events_provider_event_uidx
on public.payment_events(provider_name, provider_event_id);

drop index if exists public.payment_events_idempotency_uidx;
create unique index payment_events_idempotency_uidx
on public.payment_events(provider_name, idempotency_key);

create index if not exists payment_events_payment_idx
on public.payment_events(payment_id, occurred_at desc);

create index if not exists payment_events_booking_idx
on public.payment_events(booking_id, occurred_at desc);

comment on table public.payment_events is
  'Append-only payment event ledger. Contains safe references/status metadata only; never card numbers, CVV, bank-login credentials, or raw payment credentials.';

revoke all on public.payment_events from anon, authenticated, service_role;

create or replace function private.trusted_payment_update_allowed()
returns boolean
language sql
stable
set search_path = public
as $$
  select coalesce(current_setting('lekkadeall.allow_trusted_payment_update', true), 'off') = 'on'
      or coalesce(current_setting('lekkadeall.allow_marketplace_state_transition', true), 'off') = 'on';
$$;

create or replace function private.protect_payment_business_state()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if tg_op = 'DELETE' then
    if not private.trusted_payment_update_allowed() then
      raise exception 'payments may not be deleted directly by frontend clients'
        using errcode = '42501';
    end if;

    return old;
  end if;

  if not private.trusted_payment_update_allowed() then
    raise exception 'payment and release state must be changed through trusted server/payment functions'
      using errcode = '42501';
  end if;

  if new.release_paused = true and new.release_status = 'not_applicable' then
    new.release_status := 'paused';
  end if;

  if new.status = 'paid' and new.paid_at is null then
    new.paid_at := coalesce(new.funded_at, now());
  end if;

  if tg_op = 'UPDATE' then
    new.updated_at := now();
  end if;

  return new;
end;
$$;

drop trigger if exists protect_payment_business_state on public.payments;
create trigger protect_payment_business_state
before insert or update or delete on public.payments
for each row execute function private.protect_payment_business_state();

create or replace function private.validate_payment_event_integrity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.payments%rowtype;
begin
  select *
    into v_payment
  from public.payments
  where id = new.payment_id;

  if not found then
    raise exception 'Payment event payment_id % does not exist', new.payment_id
      using errcode = '23503';
  end if;

  if v_payment.booking_id <> new.booking_id then
    raise exception 'Payment event booking_id must match payment booking_id'
      using errcode = '23514';
  end if;

  if v_payment.currency <> new.currency then
    raise exception 'Payment event currency must match payment currency'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists validate_payment_event_integrity on public.payment_events;
create trigger validate_payment_event_integrity
before insert on public.payment_events
for each row execute function private.validate_payment_event_integrity();

create or replace function private.prevent_payment_event_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'payment_events are append-only'
    using errcode = '42501';
end;
$$;

drop trigger if exists payment_events_append_only on public.payment_events;
create trigger payment_events_append_only
before update or delete on public.payment_events
for each row execute function private.prevent_payment_event_mutation();

create or replace function private.record_initial_payment_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
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
    new.id,
    new.booking_id,
    'intent_prepared',
    new.amount_minor,
    new.currency,
    coalesce(nullif(trim(new.provider_name), ''), 'internal'),
    null,
    'payment-intent-prepared:' || new.id::text,
    null,
    'system',
    jsonb_build_object(
      'payment_status', new.status,
      'release_status', new.release_status
    )
  )
  on conflict (provider_name, idempotency_key) do nothing;

  return new;
end;
$$;

drop trigger if exists record_initial_payment_event on public.payments;
create trigger record_initial_payment_event
after insert on public.payments
for each row execute function private.record_initial_payment_event();

create or replace function public.admin_record_payment_event(
  p_payment_id uuid,
  p_event_type text,
  p_payment_status text default null,
  p_release_status text default null,
  p_amount_minor integer default null,
  p_provider_name text default 'internal',
  p_provider_event_id text default null,
  p_idempotency_key text default null,
  p_source text default 'admin',
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_payment public.payments%rowtype;
  v_event_id uuid;
  v_provider_name text := coalesce(nullif(trim(p_provider_name), ''), 'internal');
  v_metadata jsonb := coalesce(p_metadata, '{}'::jsonb);
begin
  if not public.is_platform_admin() then
    raise exception 'Only platform admins or trusted server context may record payment events'
      using errcode = '42501';
  end if;

  if p_payment_status in ('partially_refunded', 'refunded') then
    raise exception 'Refund transitions are not implemented in Ticket 7A'
      using errcode = '42501';
  end if;

  if p_release_status = 'released' then
    raise exception 'Payout release is not implemented in Ticket 7A'
      using errcode = '42501';
  end if;

  if p_idempotency_key is not null then
    select id
      into v_event_id
    from public.payment_events
    where provider_name = v_provider_name
      and idempotency_key = p_idempotency_key;

    if found then
      return v_event_id;
    end if;
  end if;

  if p_provider_event_id is not null then
    select id
      into v_event_id
    from public.payment_events
    where provider_name = v_provider_name
      and provider_event_id = p_provider_event_id;

    if found then
      return v_event_id;
    end if;
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

  perform set_config('lekkadeall.allow_trusted_payment_update', 'on', true);

  begin
    update public.payments
    set status = coalesce(p_payment_status, status),
        release_status = coalesce(p_release_status, release_status),
        paid_at = case
          when p_payment_status = 'paid' then coalesce(paid_at, now())
          else paid_at
        end,
        updated_at = now()
    where id = p_payment_id;

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
      p_event_type,
      coalesce(p_amount_minor, v_payment.amount_minor),
      v_payment.currency,
      v_provider_name,
      p_provider_event_id,
      p_idempotency_key,
      v_actor_id,
      coalesce(nullif(trim(p_source), ''), 'admin'),
      v_metadata
    )
    returning id into v_event_id;

    perform private.append_audit_event(
      v_actor_id,
      'admin.payment_event_recorded',
      'payment',
      p_payment_id::text,
      'Trusted payment event recorded through Ticket 7A ledger function',
      jsonb_build_object(
        'payment_event_id', v_event_id,
        'event_type', p_event_type,
        'payment_status', p_payment_status,
        'release_status', p_release_status
      )
    );
  exception
    when others then
      perform set_config('lekkadeall.allow_trusted_payment_update', 'off', true);
      raise;
  end;

  perform set_config('lekkadeall.allow_trusted_payment_update', 'off', true);

  return v_event_id;
end;
$$;

comment on function public.admin_record_payment_event(uuid, text, text, text, integer, text, text, text, text, jsonb) is
  'Admin/server-controlled Ticket 7A helper for internal payment status changes and append-only payment event creation. No live provider integration, refunds, cash workflow, payout release, or real webhook handling.';

revoke all on function private.trusted_payment_update_allowed() from public, anon, authenticated, service_role;
revoke all on function private.protect_payment_business_state() from public, anon, authenticated, service_role;
revoke all on function private.validate_payment_event_integrity() from public, anon, authenticated, service_role;
revoke all on function private.prevent_payment_event_mutation() from public, anon, authenticated, service_role;
revoke all on function private.record_initial_payment_event() from public, anon, authenticated, service_role;

revoke all on function public.admin_record_payment_event(uuid, text, text, text, integer, text, text, text, text, jsonb) from public, anon;
grant execute on function public.admin_record_payment_event(uuid, text, text, text, integer, text, text, text, text, jsonb) to authenticated, service_role;
