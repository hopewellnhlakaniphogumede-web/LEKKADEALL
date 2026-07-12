-- Ticket 7E: mock payment adapter and hosted checkout contract.
-- This migration creates deterministic mock/sandbox checkout and payment
-- outcome functions only. It deliberately does not integrate a live payment
-- provider, process real cards/EFTs/bank credentials, implement real signed
-- webhooks, or build UI.

create schema if not exists private;

alter table public.payments
  add column if not exists checkout_url text,
  add column if not exists checkout_expires_at timestamptz,
  add column if not exists checkout_idempotency_key text;

alter table public.payments
  drop constraint if exists payments_checkout_fields_safe_check,
  add constraint payments_checkout_fields_safe_check
    check (
      (
        checkout_url is null
        or (
          provider_name = 'mock'
          and checkout_url like 'https://mock-checkout.lekkadeall.test/%'
        )
      )
      and (
        checkout_idempotency_key is null
        or char_length(trim(checkout_idempotency_key)) between 8 and 200
      )
      and (
        checkout_expires_at is null
        or checkout_url is not null
      )
    );

create unique index if not exists payments_checkout_idempotency_uidx
on public.payments(checkout_idempotency_key)
where checkout_idempotency_key is not null;

comment on column public.payments.checkout_url is
  'Ticket 7E mock/sandbox hosted checkout URL. Must never contain card, CVV, bank-login, or raw credential material.';
comment on column public.payments.checkout_expires_at is
  'Ticket 7E expiry timestamp for mock/sandbox hosted checkout sessions.';
comment on column public.payments.checkout_idempotency_key is
  'Ticket 7E checkout creation idempotency key. Frontend users cannot mutate this directly.';

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
      'payout_reconciliation_checked',
      'mock_payment_paid',
      'mock_payment_failed',
      'mock_payment_duplicate_ignored',
      'mock_payment_out_of_order_rejected'
    ));

create or replace function private.validate_safe_mock_payment_metadata(p_metadata jsonb)
returns void
language plpgsql
stable
set search_path = public
as $$
declare
  v_metadata_text text := coalesce(p_metadata, '{}'::jsonb)::text;
begin
  if v_metadata_text ~* '(card_number|cardnumber|cvv|cvc|pan|expiry|bank_login|bank_password|bank_username|password|raw_payment_credential|raw_card|account_password)' then
    raise exception 'Mock payment metadata must not contain raw payment credentials'
      using errcode = '23514';
  end if;
end;
$$;

create or replace function public.validate_payment_provider_mode(
  p_app_env text,
  p_provider_mode text,
  p_webhook_secret_present boolean
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_app_env text := lower(nullif(trim(coalesce(p_app_env, '')), ''));
  v_provider_mode text := lower(nullif(trim(coalesce(p_provider_mode, '')), ''));
begin
  if v_app_env is null then
    raise exception 'Payment app environment is required'
      using errcode = '23514';
  end if;

  if v_provider_mode not in ('mock', 'sandbox', 'live') then
    raise exception 'Unsupported payment provider mode %', p_provider_mode
      using errcode = '23514';
  end if;

  if v_provider_mode = 'mock'
     and v_app_env not in ('local', 'development', 'dev', 'test', 'ci', 'sandbox') then
    raise exception 'Mock payment provider mode is not allowed outside local/CI/sandbox'
      using errcode = '42501';
  end if;

  if v_app_env in ('production', 'prod')
     and v_provider_mode in ('sandbox', 'live')
     and coalesce(p_webhook_secret_present, false) = false then
    raise exception 'Signed webhook secret is required for production payment provider mode'
      using errcode = '42501';
  end if;

  return true;
end;
$$;

create or replace function public.customer_create_mock_checkout_session(
  p_payment_id uuid,
  p_idempotency_key text,
  p_return_url text,
  p_cancel_url text
)
returns table (
  payment_id uuid,
  provider_name text,
  provider_reference text,
  checkout_url text,
  payment_status text,
  checkout_expires_at timestamptz
)
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_payment public.payments%rowtype;
  v_booking public.bookings%rowtype;
  v_event_id uuid;
  v_idempotency_key text := nullif(trim(coalesce(p_idempotency_key, '')), '');
  v_provider_reference text;
  v_checkout_url text;
  v_checkout_expires_at timestamptz;
  v_app_env text := coalesce(nullif(current_setting('lekkadeall.app_env', true), ''), 'local');
begin
  perform public.validate_payment_provider_mode(v_app_env, 'mock', false);

  if v_actor_id is null then
    raise exception 'Authentication is required to create checkout'
      using errcode = '42501';
  end if;

  if v_idempotency_key is null then
    raise exception 'A checkout idempotency key is required'
      using errcode = '23514';
  end if;

  if nullif(trim(coalesce(p_return_url, '')), '') is null
     or p_return_url !~* '^https?://'
     or char_length(p_return_url) > 2000 then
    raise exception 'A safe return_url is required'
      using errcode = '23514';
  end if;

  if nullif(trim(coalesce(p_cancel_url, '')), '') is null
     or p_cancel_url !~* '^https?://'
     or char_length(p_cancel_url) > 2000 then
    raise exception 'A safe cancel_url is required'
      using errcode = '23514';
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

  if not found or v_booking.customer_id <> v_actor_id then
    raise exception 'Only the booking customer can create checkout for this payment'
      using errcode = '42501';
  end if;

  select id
    into v_event_id
  from public.payment_events
  where provider_name = 'mock'
    and idempotency_key = v_idempotency_key
    and payment_id = p_payment_id
    and event_type = 'checkout_created';

  if found then
    if v_payment.status = 'checkout_created'
       and v_payment.checkout_idempotency_key = v_idempotency_key then
      return query
        select
          v_payment.id,
          v_payment.provider_name,
          v_payment.provider_reference,
          v_payment.checkout_url,
          v_payment.status,
          v_payment.checkout_expires_at;
      return;
    end if;

    raise exception 'Checkout idempotency key cannot be reused after payment leaves checkout_created'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.payment_events pe
    where pe.provider_name = 'mock'
      and pe.idempotency_key = v_idempotency_key
      and (
        pe.payment_id <> p_payment_id
        or pe.event_type <> 'checkout_created'
      )
  ) then
    raise exception 'Checkout idempotency key was already used for another payment/action'
      using errcode = '23505';
  end if;

  if v_payment.status = 'checkout_created' then
    if v_payment.checkout_idempotency_key = v_idempotency_key then
      return query
        select
          v_payment.id,
          v_payment.provider_name,
          v_payment.provider_reference,
          v_payment.checkout_url,
          v_payment.status,
          v_payment.checkout_expires_at;
      return;
    end if;

    raise exception 'Checkout already exists for this payment'
      using errcode = '23505';
  end if;

  if v_payment.status <> 'pending' then
    raise exception 'Checkout can only be created for pending payments'
      using errcode = '23514';
  end if;

  if v_payment.payment_method not in ('platform_online_pending', 'platform_online', 'sandbox_online', 'manual_sandbox_online') then
    raise exception 'Cash or off-platform payment methods cannot use hosted checkout'
      using errcode = '42501';
  end if;

  v_provider_reference := 'mock_checkout_' || md5(p_payment_id::text || ':' || v_idempotency_key);
  v_checkout_url := 'https://mock-checkout.lekkadeall.test/checkout/' || v_provider_reference;
  v_checkout_expires_at := now() + interval '30 minutes';

  perform set_config('lekkadeall.allow_trusted_payment_update', 'on', true);

  begin
    update public.payments
    set status = 'checkout_created',
        provider_name = 'mock',
        provider_reference = v_provider_reference,
        checkout_url = v_checkout_url,
        checkout_expires_at = v_checkout_expires_at,
        checkout_idempotency_key = v_idempotency_key,
        payment_method = 'sandbox_online',
        updated_at = now()
    where id = p_payment_id
    returning * into v_payment;

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
      'checkout_created',
      v_payment.amount_minor,
      v_payment.currency,
      'mock',
      v_provider_reference,
      v_idempotency_key,
      v_actor_id,
      'system',
      jsonb_build_object(
        'mock_adapter', true,
        'sandbox_only', true,
        'real_money_moved', false,
        'checkout_url', v_checkout_url,
        'checkout_expires_at', v_checkout_expires_at,
        'return_url_hosted_externally', true,
        'cancel_url_hosted_externally', true
      )
    )
    returning id into v_event_id;

    perform private.append_audit_event(
      v_actor_id,
      'customer.mock_checkout_created',
      'payment',
      p_payment_id::text,
      'Mock/sandbox checkout session created by booking customer',
      jsonb_build_object(
        'payment_event_id', v_event_id,
        'provider_reference', v_provider_reference,
        'real_money_moved', false
      )
    );
  exception
    when others then
      perform set_config('lekkadeall.allow_trusted_payment_update', 'off', true);
      raise;
  end;

  perform set_config('lekkadeall.allow_trusted_payment_update', 'off', true);

  return query
    select
      v_payment.id,
      v_payment.provider_name,
      v_payment.provider_reference,
      v_payment.checkout_url,
      v_payment.status,
      v_payment.checkout_expires_at;
end;
$$;

create or replace function public.admin_record_mock_payment_outcome(
  p_payment_id uuid,
  p_outcome_status text,
  p_provider_event_id text,
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
  v_payment public.payments%rowtype;
  v_event_id uuid;
  v_vendor_event_id uuid;
  v_outcome_status text := lower(nullif(trim(coalesce(p_outcome_status, '')), ''));
  v_provider_event_id text := nullif(trim(coalesce(p_provider_event_id, '')), '');
  v_idempotency_key text := nullif(trim(coalesce(p_idempotency_key, '')), '');
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_metadata jsonb := coalesce(p_metadata, '{}'::jsonb);
  v_event_type text;
  v_payload_hash text;
  v_app_env text := coalesce(nullif(current_setting('lekkadeall.app_env', true), ''), 'local');
begin
  perform public.validate_payment_provider_mode(v_app_env, 'mock', false);

  if not public.is_platform_admin() then
    raise exception 'Only platform admins or trusted server context may record mock payment outcomes'
      using errcode = '42501';
  end if;

  if v_reason is null then
    raise exception 'A non-empty mock payment outcome reason is required'
      using errcode = '23514';
  end if;

  if v_provider_event_id is null then
    raise exception 'A mock provider_event_id is required'
      using errcode = '23514';
  end if;

  if v_idempotency_key is null then
    raise exception 'A mock payment outcome idempotency key is required'
      using errcode = '23514';
  end if;

  if v_outcome_status not in ('paid', 'failed') then
    raise exception 'Mock payment outcome must be paid or failed'
      using errcode = '23514';
  end if;

  perform private.validate_safe_mock_payment_metadata(v_metadata);

  select id
    into v_event_id
  from public.payment_events
  where provider_name = 'mock'
    and idempotency_key = v_idempotency_key;

  if found then
    return v_event_id;
  end if;

  select id
    into v_event_id
  from public.payment_events
  where provider_name = 'mock'
    and provider_event_id = v_provider_event_id;

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

  if v_outcome_status = 'paid' and v_payment.status in ('refunded', 'partially_refunded') then
    raise exception 'Paid mock outcome cannot be applied after a refund'
      using errcode = '23514';
  end if;

  if v_outcome_status = 'failed' and v_payment.status = 'paid' then
    v_event_type := 'mock_payment_out_of_order_rejected';
    v_payload_hash := encode(digest(jsonb_build_object(
      'payment_id', p_payment_id,
      'provider_event_id', v_provider_event_id,
      'idempotency_key', v_idempotency_key,
      'outcome_status', v_outcome_status,
      'metadata', v_metadata,
      'real_money_moved', false
    )::text, 'sha256'), 'hex');

    v_vendor_event_id := private.record_vendor_event(
      'mock',
      v_provider_event_id,
      v_event_type,
      coalesce(v_payment.provider_reference, p_payment_id::text),
      v_payload_hash
    );

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
      v_event_type,
      0,
      v_payment.currency,
      'mock',
      v_provider_event_id,
      v_idempotency_key,
      v_actor_id,
      'admin',
      v_metadata || jsonb_build_object(
        'vendor_event_id', v_vendor_event_id,
        'payment_status_before', v_payment.status,
        'payment_status_after', v_payment.status,
        'mock_adapter', true,
        'sandbox_only', true,
        'real_money_moved', false,
        'out_of_order_rejected', true
      )
    )
    returning id into v_event_id;

    perform private.append_audit_event(
      v_actor_id,
      'admin.mock_payment_out_of_order_rejected',
      'payment',
      p_payment_id::text,
      v_reason,
      jsonb_build_object(
        'payment_event_id', v_event_id,
        'vendor_event_id', v_vendor_event_id,
        'provider_event_id', v_provider_event_id,
        'payment_status_after', v_payment.status,
        'real_money_moved', false
      )
    );

    return v_event_id;
  end if;

  if v_payment.status in ('refunded', 'partially_refunded') then
    raise exception 'Mock payment outcome cannot be applied to refunded payments'
      using errcode = '23514';
  end if;

  if v_payment.status in ('cancelled', 'expired') then
    raise exception 'Mock payment outcome cannot be applied to cancelled or expired payments'
      using errcode = '23514';
  end if;

  if v_outcome_status = 'paid' and v_payment.status not in ('pending', 'checkout_created') then
    raise exception 'Mock paid outcome can only be applied to pending or checkout_created payments'
      using errcode = '23514';
  end if;

  if v_outcome_status = 'failed' and v_payment.status not in ('pending', 'checkout_created', 'failed') then
    raise exception 'Mock failed outcome can only be applied to pending, checkout_created, or already failed payments'
      using errcode = '23514';
  end if;

  if v_payment.payment_method not in ('platform_online_pending', 'platform_online', 'sandbox_online', 'manual_sandbox_online') then
    raise exception 'Cash or off-platform payment methods cannot receive mock outcomes'
      using errcode = '42501';
  end if;

  v_event_type := case
    when v_outcome_status = 'paid' then 'mock_payment_paid'
    else 'mock_payment_failed'
  end;

  v_payload_hash := encode(digest(jsonb_build_object(
    'payment_id', p_payment_id,
    'provider_event_id', v_provider_event_id,
    'idempotency_key', v_idempotency_key,
    'outcome_status', v_outcome_status,
    'metadata', v_metadata,
    'real_money_moved', false
  )::text, 'sha256'), 'hex');

  v_vendor_event_id := private.record_vendor_event(
    'mock',
    v_provider_event_id,
    v_event_type,
    coalesce(v_payment.provider_reference, p_payment_id::text),
    v_payload_hash
  );

  perform set_config('lekkadeall.allow_trusted_payment_update', 'on', true);

  begin
    update public.payments
    set status = v_outcome_status,
        paid_at = case
          when v_outcome_status = 'paid' then coalesce(paid_at, now())
          else paid_at
        end,
        funded_at = case
          when v_outcome_status = 'paid' then coalesce(funded_at, now())
          else funded_at
        end,
        release_status = case
          when v_outcome_status = 'paid' and (release_paused or release_status = 'paused') then 'paused'
          when v_outcome_status = 'paid' then 'pending'
          else 'cancelled'
        end,
        provider_name = 'mock',
        provider_reference = coalesce(provider_reference, 'mock_payment_' || md5(p_payment_id::text)),
        payment_method = 'sandbox_online',
        updated_at = now()
    where id = p_payment_id
    returning * into v_payment;

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
      v_event_type,
      v_payment.amount_minor,
      v_payment.currency,
      'mock',
      v_provider_event_id,
      v_idempotency_key,
      v_actor_id,
      'admin',
      v_metadata || jsonb_build_object(
        'vendor_event_id', v_vendor_event_id,
        'payment_status_after', v_payment.status,
        'release_status_after', v_payment.release_status,
        'mock_adapter', true,
        'sandbox_only', true,
        'real_money_moved', false
      )
    )
    returning id into v_event_id;

    perform private.append_audit_event(
      v_actor_id,
      case
        when v_outcome_status = 'paid' then 'admin.mock_payment_paid'
        else 'admin.mock_payment_failed'
      end,
      'payment',
      p_payment_id::text,
      v_reason,
      jsonb_build_object(
        'payment_event_id', v_event_id,
        'vendor_event_id', v_vendor_event_id,
        'provider_event_id', v_provider_event_id,
        'payment_status_after', v_payment.status,
        'release_status_after', v_payment.release_status,
        'real_money_moved', false
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

comment on function public.validate_payment_provider_mode(text, text, boolean) is
  'Ticket 7E fail-closed payment provider mode validator. Mock mode is allowed only for local/CI/sandbox; production must not run mock mode.';
comment on function public.customer_create_mock_checkout_session(uuid, text, text, text) is
  'Ticket 7E booking-customer mock hosted checkout creator. Writes mock/sandbox payment and audit events only; never processes real payment credentials.';
comment on function public.admin_record_mock_payment_outcome(uuid, text, text, text, text, jsonb) is
  'Ticket 7E admin/server mock payment outcome recorder. Writes vendor/payment/audit events only; does not call a live provider and never proves real money moved.';

revoke all on function private.validate_safe_mock_payment_metadata(jsonb) from public, anon, authenticated, service_role;

revoke all on function public.validate_payment_provider_mode(text, text, boolean) from public, anon;
revoke all on function public.customer_create_mock_checkout_session(uuid, text, text, text) from public, anon;
revoke all on function public.admin_record_mock_payment_outcome(uuid, text, text, text, text, jsonb) from public, anon;

grant execute on function public.validate_payment_provider_mode(text, text, boolean) to authenticated, service_role;
grant execute on function public.customer_create_mock_checkout_session(uuid, text, text, text) to authenticated, service_role;
grant execute on function public.admin_record_mock_payment_outcome(uuid, text, text, text, text, jsonb) to authenticated, service_role;
