-- Ticket 7D: payout release, payout freeze, and dispute-aware release blocking.
-- This migration implements internal/manual-sandbox release controls only.
-- It deliberately does not execute real provider bank payouts, call a live payment
-- provider, implement payout webhooks, implement payout reconciliation, implement
-- cash payout release, or build UI.

create schema if not exists private;

alter table public.payments
  add column if not exists release_paused_at timestamptz,
  add column if not exists release_paused_by uuid references public.profiles(id) on delete restrict,
  add column if not exists release_pause_reason text,
  add column if not exists release_hold_until timestamptz,
  add column if not exists release_eligible_at timestamptz,
  add column if not exists release_provider_reference text,
  add column if not exists release_idempotency_key text;

alter table public.payments
  drop constraint if exists payments_release_pause_reason_check,
  add constraint payments_release_pause_reason_check
    check (
      release_pause_reason is null
      or char_length(trim(release_pause_reason)) between 3 and 1500
    );

create unique index if not exists payments_release_provider_reference_uidx
on public.payments(release_provider_reference)
where release_provider_reference is not null;

comment on column public.payments.release_paused_at is
  'Ticket 7D timestamp for trusted/admin payout release pause. No frontend role may update this directly.';
comment on column public.payments.release_paused_by is
  'Ticket 7D actor that paused payout release through trusted/admin logic.';
comment on column public.payments.release_pause_reason is
  'Ticket 7D reason for the current payout release pause/hold.';
comment on column public.payments.release_hold_until is
  'Ticket 7D optional administrative hold timestamp. Hold enforcement is trusted-function controlled.';
comment on column public.payments.release_eligible_at is
  'Ticket 7D timestamp set when trusted/admin logic marks payout release eligible.';
comment on column public.payments.release_provider_reference is
  'Ticket 7D manual/sandbox payout-release reference. This is not proof of a live provider payout.';
comment on column public.payments.release_idempotency_key is
  'Ticket 7D idempotency key for the latest trusted payout release state transition.';

alter table public.payment_events
  drop constraint if exists payment_events_event_type_check,
  add constraint payment_events_event_type_check
    check (event_type in (
      'intent_prepared',
      'checkout_created',
      'payment_status_changed',
      'payment_marked_paid',
      'payment_failed',
      'payment_expired',
      'payment_cancelled',
      'release_status_changed',
      'admin_note',
      'release_paused',
      'release_resumed',
      'release_eligible',
      'release_cancelled',
      'payout_release_recorded',
      'payout_release_failed',
      'payout_reconciliation_checked'
    ));

create or replace function private.require_payout_admin_reason(
  p_reason text,
  p_idempotency_key text
)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  v_idempotency_key text := nullif(trim(coalesce(p_idempotency_key, '')), '');
begin
  if not public.is_platform_admin() then
    raise exception 'Only platform admins or trusted server context may control payout release'
      using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'A non-empty payout release reason is required'
      using errcode = '23514';
  end if;

  if v_idempotency_key is null then
    raise exception 'A payout release idempotency key is required'
      using errcode = '23514';
  end if;

  return v_idempotency_key;
end;
$$;

create or replace function private.payout_release_blockers(
  p_payment_id uuid,
  p_ignore_release_paused boolean default false
)
returns text[]
language plpgsql
stable
security definer
set search_path = public, private
as $$
declare
  v_payment public.payments%rowtype;
  v_booking public.bookings%rowtype;
  v_provider_profile public.provider_profiles%rowtype;
  v_provider_account_status text;
  v_blockers text[] := '{}'::text[];
begin
  select *
    into v_payment
  from public.payments
  where id = p_payment_id;

  if not found then
    return array['payment_not_found'];
  end if;

  select *
    into v_booking
  from public.bookings
  where id = v_payment.booking_id;

  if not found then
    v_blockers := array_append(v_blockers, 'booking_not_found');
  else
    if v_booking.status <> 'completed' then
      v_blockers := array_append(v_blockers, 'booking_not_completed');
    end if;

    select *
      into v_provider_profile
    from public.provider_profiles
    where user_id = v_booking.provider_id;

    if not found then
      v_blockers := array_append(v_blockers, 'provider_not_found');
    else
      select account_status
        into v_provider_account_status
      from public.profiles
      where id = v_booking.provider_id;

      if v_provider_account_status <> 'active' then
        v_blockers := array_append(v_blockers, 'provider_account_not_active');
      end if;

      if v_provider_profile.review_status <> 'approved' then
        v_blockers := array_append(v_blockers, 'provider_not_approved');
      end if;

      if v_provider_profile.verification_status <> 'verified' then
        v_blockers := array_append(v_blockers, 'provider_not_verified');
      end if;
    end if;
  end if;

  if v_payment.status not in ('paid', 'partially_refunded') then
    v_blockers := array_append(v_blockers, 'payment_not_paid');
  end if;

  if v_payment.payment_method not in (
    'platform_online_pending',
    'platform_online',
    'sandbox_online',
    'manual_sandbox_online'
  ) then
    v_blockers := array_append(v_blockers, 'payment_method_not_releasable');
  end if;

  if v_payment.release_status in ('released', 'cancelled') then
    v_blockers := array_append(v_blockers, 'release_terminal');
  end if;

  if not p_ignore_release_paused and v_payment.release_paused then
    v_blockers := array_append(v_blockers, 'release_paused');
  end if;

  if v_payment.refunded_minor >= v_payment.amount_minor then
    v_blockers := array_append(v_blockers, 'fully_refunded');
  end if;

  if (v_payment.amount_minor - v_payment.refunded_minor) <= 0 then
    v_blockers := array_append(v_blockers, 'no_releasable_amount');
  end if;

  if exists (
    select 1
    from public.refund_requests rr
    where rr.payment_id = v_payment.id
      and rr.status in ('requested', 'under_review', 'approved', 'processing')
  ) then
    v_blockers := array_append(v_blockers, 'active_refund');
  end if;

  if exists (
    select 1
    from public.disputes d
    where d.booking_id = v_payment.booking_id
      and d.status in ('open', 'awaiting_customer', 'awaiting_provider', 'under_review', 'appealed')
  ) then
    v_blockers := array_append(v_blockers, 'active_dispute');
  end if;

  return v_blockers;
end;
$$;

create or replace function private.record_payout_payment_event(
  p_payment_id uuid,
  p_booking_id uuid,
  p_currency char(3),
  p_event_type text,
  p_actor_id uuid,
  p_amount_minor integer,
  p_provider_name text,
  p_provider_event_id text,
  p_idempotency_key text,
  p_metadata jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event_id uuid;
  v_provider_name text := coalesce(nullif(trim(p_provider_name), ''), 'internal');
  v_idempotency_key text := nullif(trim(coalesce(p_idempotency_key, '')), '');
begin
  if v_idempotency_key is not null then
    select id
      into v_event_id
    from public.payment_events
    where provider_name = v_provider_name
      and idempotency_key = v_idempotency_key;

    if found then
      return v_event_id;
    end if;
  end if;

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
    p_payment_id,
    p_booking_id,
    p_event_type,
    p_amount_minor,
    p_currency,
    v_provider_name,
    nullif(trim(coalesce(p_provider_event_id, '')), ''),
    v_idempotency_key,
    p_actor_id,
    'admin',
    coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict (provider_name, idempotency_key) do nothing
  returning id into v_event_id;

  if v_event_id is null and v_idempotency_key is not null then
    select id
      into v_event_id
    from public.payment_events
    where provider_name = v_provider_name
      and idempotency_key = v_idempotency_key;
  end if;

  return v_event_id;
end;
$$;

create or replace function public.admin_pause_payment_release(
  p_payment_id uuid,
  p_reason text,
  p_idempotency_key text
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
  v_idempotency_key text;
begin
  v_idempotency_key := private.require_payout_admin_reason(p_reason, p_idempotency_key);

  select id
    into v_event_id
  from public.payment_events
  where provider_name = 'internal'
    and idempotency_key = v_idempotency_key;

  if found then
    return v_event_id;
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

  if v_payment.release_status in ('released', 'cancelled') then
    raise exception 'Terminal release status cannot be paused'
      using errcode = '23514';
  end if;

  perform set_config('lekkadeall.allow_trusted_payment_update', 'on', true);

  begin
    update public.payments
    set release_paused = true,
        release_status = 'paused',
        release_paused_at = now(),
        release_paused_by = v_actor_id,
        release_pause_reason = p_reason,
        release_idempotency_key = v_idempotency_key,
        updated_at = now()
    where id = p_payment_id
    returning * into v_payment;

    v_event_id := private.record_payout_payment_event(
      v_payment.id,
      v_payment.booking_id,
      v_payment.currency,
      'release_paused',
      v_actor_id,
      0,
      'internal',
      null,
      v_idempotency_key,
      jsonb_build_object(
        'release_status_after', 'paused',
        'release_paused', true,
        'manual_sandbox_only', true,
        'real_money_moved', false
      )
    );

    perform private.append_audit_event(
      v_actor_id,
      'admin.payment_release_paused',
      'payment',
      p_payment_id::text,
      p_reason,
      jsonb_build_object(
        'payment_event_id', v_event_id,
        'release_status_after', 'paused'
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

create or replace function public.admin_resume_payment_release(
  p_payment_id uuid,
  p_reason text,
  p_idempotency_key text
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
  v_idempotency_key text;
  v_blockers text[];
  v_releasable_minor integer;
begin
  v_idempotency_key := private.require_payout_admin_reason(p_reason, p_idempotency_key);

  select id
    into v_event_id
  from public.payment_events
  where provider_name = 'internal'
    and idempotency_key = v_idempotency_key;

  if found then
    return v_event_id;
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

  v_blockers := private.payout_release_blockers(p_payment_id, true);

  if coalesce(array_length(v_blockers, 1), 0) > 0 then
    raise exception 'Payment release cannot be resumed because blockers remain: %', array_to_string(v_blockers, ',')
      using errcode = '23514';
  end if;

  v_releasable_minor := v_payment.amount_minor - v_payment.refunded_minor;

  perform set_config('lekkadeall.allow_trusted_payment_update', 'on', true);

  begin
    update public.payments
    set release_paused = false,
        release_status = 'pending',
        release_paused_at = null,
        release_paused_by = null,
        release_pause_reason = null,
        release_hold_until = null,
        release_idempotency_key = v_idempotency_key,
        updated_at = now()
    where id = p_payment_id
    returning * into v_payment;

    v_event_id := private.record_payout_payment_event(
      v_payment.id,
      v_payment.booking_id,
      v_payment.currency,
      'release_resumed',
      v_actor_id,
      v_releasable_minor,
      'internal',
      null,
      v_idempotency_key,
      jsonb_build_object(
        'release_status_after', 'pending',
        'release_paused', false,
        'manual_sandbox_only', true,
        'real_money_moved', false
      )
    );

    perform private.append_audit_event(
      v_actor_id,
      'admin.payment_release_resumed',
      'payment',
      p_payment_id::text,
      p_reason,
      jsonb_build_object(
        'payment_event_id', v_event_id,
        'release_status_after', 'pending'
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

create or replace function public.admin_mark_release_eligible(
  p_payment_id uuid,
  p_reason text,
  p_idempotency_key text
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
  v_idempotency_key text;
  v_blockers text[];
  v_releasable_minor integer;
begin
  v_idempotency_key := private.require_payout_admin_reason(p_reason, p_idempotency_key);

  select id
    into v_event_id
  from public.payment_events
  where provider_name = 'internal'
    and idempotency_key = v_idempotency_key;

  if found then
    return v_event_id;
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

  v_blockers := private.payout_release_blockers(p_payment_id, false);

  if coalesce(array_length(v_blockers, 1), 0) > 0 then
    raise exception 'Payment release cannot become eligible because blockers remain: %', array_to_string(v_blockers, ',')
      using errcode = '23514';
  end if;

  v_releasable_minor := v_payment.amount_minor - v_payment.refunded_minor;

  perform set_config('lekkadeall.allow_trusted_payment_update', 'on', true);

  begin
    update public.payments
    set release_status = 'eligible',
        release_eligible_at = now(),
        release_idempotency_key = v_idempotency_key,
        updated_at = now()
    where id = p_payment_id
    returning * into v_payment;

    v_event_id := private.record_payout_payment_event(
      v_payment.id,
      v_payment.booking_id,
      v_payment.currency,
      'release_eligible',
      v_actor_id,
      v_releasable_minor,
      'internal',
      null,
      v_idempotency_key,
      jsonb_build_object(
        'release_status_after', 'eligible',
        'releasable_amount_minor', v_releasable_minor,
        'manual_sandbox_only', true,
        'real_money_moved', false
      )
    );

    perform private.append_audit_event(
      v_actor_id,
      'admin.payment_release_eligible',
      'payment',
      p_payment_id::text,
      p_reason,
      jsonb_build_object(
        'payment_event_id', v_event_id,
        'release_status_after', 'eligible',
        'releasable_amount_minor', v_releasable_minor
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

create or replace function public.admin_record_payout_release(
  p_payment_id uuid,
  p_provider_reference text,
  p_amount_minor integer,
  p_reason text,
  p_idempotency_key text
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
  v_idempotency_key text;
  v_provider_reference text := nullif(trim(coalesce(p_provider_reference, '')), '');
  v_blockers text[];
  v_releasable_minor integer;
begin
  v_idempotency_key := private.require_payout_admin_reason(p_reason, p_idempotency_key);

  if v_provider_reference is null then
    raise exception 'A payout release provider/reference value is required'
      using errcode = '23514';
  end if;

  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'Payout release amount must be greater than zero'
      using errcode = '23514';
  end if;

  select id
    into v_event_id
  from public.payment_events
  where provider_name = 'manual_sandbox'
    and idempotency_key = v_idempotency_key;

  if found then
    return v_event_id;
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

  v_blockers := private.payout_release_blockers(p_payment_id, false);

  if coalesce(array_length(v_blockers, 1), 0) > 0 then
    raise exception 'Payment cannot be released because blockers remain: %', array_to_string(v_blockers, ',')
      using errcode = '23514';
  end if;

  if v_payment.release_status <> 'eligible' then
    raise exception 'Payment must be marked release eligible before payout release can be recorded'
      using errcode = '23514';
  end if;

  v_releasable_minor := v_payment.amount_minor - v_payment.refunded_minor;

  if p_amount_minor <> v_releasable_minor then
    raise exception 'Payout release amount must equal releasable payment amount'
      using errcode = '23514';
  end if;

  perform set_config('lekkadeall.allow_trusted_payment_update', 'on', true);

  begin
    update public.payments
    set release_status = 'released',
        release_paused = false,
        released_at = now(),
        release_provider_reference = v_provider_reference,
        release_idempotency_key = v_idempotency_key,
        updated_at = now()
    where id = p_payment_id
    returning * into v_payment;

    v_event_id := private.record_payout_payment_event(
      v_payment.id,
      v_payment.booking_id,
      v_payment.currency,
      'payout_release_recorded',
      v_actor_id,
      p_amount_minor,
      'manual_sandbox',
      v_provider_reference,
      v_idempotency_key,
      jsonb_build_object(
        'release_provider_reference', v_provider_reference,
        'releasable_amount_minor', v_releasable_minor,
        'manual_sandbox_only', true,
        'real_money_moved', false,
        'live_provider_payout_executed', false
      )
    );

    perform private.append_audit_event(
      v_actor_id,
      'admin.payout_release_recorded',
      'payment',
      p_payment_id::text,
      p_reason,
      jsonb_build_object(
        'payment_event_id', v_event_id,
        'release_provider_reference', v_provider_reference,
        'releasable_amount_minor', v_releasable_minor,
        'manual_sandbox_only', true,
        'real_money_moved', false,
        'live_provider_payout_executed', false
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

comment on function public.admin_pause_payment_release(uuid, text, text) is
  'Ticket 7D trusted admin/server release-pause function. Writes payment/audit events only; does not execute real payouts.';
comment on function public.admin_resume_payment_release(uuid, text, text) is
  'Ticket 7D trusted admin/server release-resume function. Requires blockers to be cleared and writes payment/audit events only.';
comment on function public.admin_mark_release_eligible(uuid, text, text) is
  'Ticket 7D trusted admin/server release-eligibility function. Does not execute real payouts.';
comment on function public.admin_record_payout_release(uuid, text, integer, text, text) is
  'Ticket 7D trusted manual/sandbox payout-release recorder. It does not call a live provider and must not be treated as proof that real money moved.';

revoke all on function private.require_payout_admin_reason(text, text) from public, anon, authenticated, service_role;
revoke all on function private.payout_release_blockers(uuid, boolean) from public, anon, authenticated, service_role;
revoke all on function private.record_payout_payment_event(uuid, uuid, character, text, uuid, integer, text, text, text, jsonb) from public, anon, authenticated, service_role;

revoke all on function public.admin_pause_payment_release(uuid, text, text) from public, anon;
revoke all on function public.admin_resume_payment_release(uuid, text, text) from public, anon;
revoke all on function public.admin_mark_release_eligible(uuid, text, text) from public, anon;
revoke all on function public.admin_record_payout_release(uuid, text, integer, text, text) from public, anon;
grant execute on function public.admin_pause_payment_release(uuid, text, text) to authenticated, service_role;
grant execute on function public.admin_resume_payment_release(uuid, text, text) to authenticated, service_role;
grant execute on function public.admin_mark_release_eligible(uuid, text, text) to authenticated, service_role;
grant execute on function public.admin_record_payout_release(uuid, text, integer, text, text) to authenticated, service_role;
