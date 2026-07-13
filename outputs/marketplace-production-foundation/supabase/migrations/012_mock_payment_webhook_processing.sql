-- Ticket 8A: mock/sandbox payment webhook database foundation.
-- This migration models database-side handling after a future trusted server
-- route has already verified the webhook signature. It deliberately does not
-- implement live provider webhooks, HTTP routes, Edge Functions, real webhook
-- secrets, real card/EFT processing, raw provider payload storage, or UI.

create schema if not exists private;

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
      'mock_payment_out_of_order_rejected',
      'webhook_checkout_created',
      'webhook_payment_paid',
      'webhook_payment_failed',
      'webhook_payment_expired',
      'webhook_payment_cancelled',
      'webhook_out_of_order_rejected',
      'webhook_manual_review_required'
    ));

create or replace function private.validate_safe_mock_webhook_metadata(p_metadata jsonb)
returns void
language plpgsql
stable
set search_path = public
as $$
declare
  v_metadata_text text := coalesce(p_metadata, '{}'::jsonb)::text;
begin
  if v_metadata_text ~* '(raw[_ -]?(body|payload|webhook)|webhook[_ -]?(body|secret)|signature[_ -]?(header|value|secret)|provider[_ -]?signature|card[_ -]?number|cardnumber|cvv|cvc|pan|expiry|bank[_ -]?login|bank[_ -]?password|bank[_ -]?username|raw[_ -]?payment[_ -]?credential|raw[_ -]?card|account[_ -]?password)' then
    raise exception 'Mock webhook metadata must not contain raw payloads, signatures, secrets, or payment credentials'
      using errcode = '23514';
  end if;
end;
$$;

create or replace function public.admin_process_verified_mock_payment_webhook(
  provider_event_id text,
  provider_reference text,
  event_type text,
  payload_hash text,
  idempotency_key text,
  metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_provider_name text := 'mock';
  v_provider_event_id text := nullif(trim(coalesce(provider_event_id, '')), '');
  v_provider_reference text := nullif(trim(coalesce(provider_reference, '')), '');
  v_event_type text := lower(nullif(trim(coalesce(event_type, '')), ''));
  v_payload_hash text := lower(nullif(trim(coalesce(payload_hash, '')), ''));
  v_idempotency_key text := nullif(trim(coalesce(idempotency_key, '')), '');
  v_metadata jsonb := coalesce(metadata, '{}'::jsonb);
  v_payment public.payments%rowtype;
  v_existing_vendor public.vendor_events%rowtype;
  v_vendor_event_id uuid;
  v_existing_payment_event_id uuid;
  v_payment_event_id uuid;
  v_target_status text;
  v_ledger_event_type text;
  v_processing_event_type text;
  v_status_before text;
  v_status_after text;
  v_release_status_after text;
  v_should_update_payment boolean := false;
  v_should_mark_paid boolean := false;
  v_audit_action text;
  v_audit_reason text;
  v_amount_minor integer;
  v_app_env text := coalesce(nullif(current_setting('lekkadeall.app_env', true), ''), 'local');
begin
  perform public.validate_payment_provider_mode(v_app_env, 'mock', false);

  if not public.is_platform_admin() then
    raise exception 'Only platform admins or trusted server context may process mock payment webhooks'
      using errcode = '42501';
  end if;

  if v_provider_event_id is null then
    raise exception 'A mock webhook provider_event_id is required'
      using errcode = '23514';
  end if;

  if v_provider_reference is null then
    raise exception 'A mock webhook provider_reference is required'
      using errcode = '23514';
  end if;

  if v_payload_hash is null or v_payload_hash !~ '^(sha256:)?[a-f0-9]{64}$' then
    raise exception 'A safe sha256 payload_hash is required'
      using errcode = '23514';
  end if;

  if v_idempotency_key is null then
    raise exception 'A mock webhook idempotency_key is required'
      using errcode = '23514';
  end if;

  perform private.validate_safe_mock_webhook_metadata(v_metadata);

  v_target_status := case v_event_type
    when 'mock.checkout.created' then 'checkout_created'
    when 'mock.payment.paid' then 'paid'
    when 'mock.payment.failed' then 'failed'
    when 'mock.payment.expired' then 'expired'
    when 'mock.payment.cancelled' then 'cancelled'
    else null
  end;

  if v_target_status is null then
    raise exception 'Unsupported mock webhook event type %', event_type
      using errcode = '23514';
  end if;

  v_ledger_event_type := case v_target_status
    when 'checkout_created' then 'webhook_checkout_created'
    when 'paid' then 'webhook_payment_paid'
    when 'failed' then 'webhook_payment_failed'
    when 'expired' then 'webhook_payment_expired'
    when 'cancelled' then 'webhook_payment_cancelled'
  end;

  select *
    into v_payment
  from public.payments
  where provider_name = v_provider_name
    and provider_reference = v_provider_reference
  for update;

  if not found then
    raise exception 'Payment with provider_reference % does not exist', v_provider_reference
      using errcode = '02000';
  end if;

  if v_payment.payment_method not in ('platform_online_pending', 'platform_online', 'sandbox_online', 'manual_sandbox_online') then
    raise exception 'Cash or off-platform payment methods cannot receive mock webhooks'
      using errcode = '42501';
  end if;

  select *
    into v_existing_vendor
  from public.vendor_events
  where provider_name = v_provider_name
    and provider_event_id = v_provider_event_id;

  if found then
    if v_existing_vendor.payload_hash = v_payload_hash then
      select id
        into v_existing_payment_event_id
      from public.payment_events
      where provider_name = v_provider_name
        and provider_event_id = v_provider_event_id
      order by occurred_at
      limit 1;

      return v_existing_payment_event_id;
    end if;

    perform private.append_audit_event(
      v_actor_id,
      'admin.mock_webhook_payload_hash_mismatch',
      'payment',
      v_payment.id::text,
      'Duplicate mock webhook provider_event_id arrived with a different payload_hash; payment state was not mutated.',
      jsonb_build_object(
        'provider_event_id', v_provider_event_id,
        'provider_reference', v_provider_reference,
        'existing_payload_hash', v_existing_vendor.payload_hash,
        'incoming_payload_hash', v_payload_hash,
        'payment_status_after', v_payment.status,
        'mock_adapter', true,
        'sandbox_only', true,
        'real_money_moved', false
      )
    );

    return null;
  end if;

  select id
    into v_existing_payment_event_id
  from public.payment_events
  where provider_name = v_provider_name
    and idempotency_key = v_idempotency_key;

  if found then
    return v_existing_payment_event_id;
  end if;

  v_status_before := v_payment.status;
  v_status_after := v_payment.status;
  v_release_status_after := v_payment.release_status;
  v_processing_event_type := v_ledger_event_type;
  v_audit_action := 'admin.mock_webhook_processed';
  v_audit_reason := 'Verified mock/sandbox payment webhook processed.';
  v_amount_minor := v_payment.amount_minor;

  if v_target_status = 'checkout_created' then
    if v_payment.status in ('pending', 'checkout_created') then
      v_should_update_payment := true;
      v_status_after := 'checkout_created';
      v_release_status_after := v_payment.release_status;
    else
      v_processing_event_type := 'webhook_out_of_order_rejected';
      v_audit_action := 'admin.mock_webhook_out_of_order_rejected';
      v_audit_reason := 'Out-of-order mock checkout-created webhook ignored; payment state was not downgraded.';
      v_amount_minor := 0;
    end if;
  elsif v_target_status = 'paid' then
    if v_payment.status in ('pending', 'checkout_created') then
      v_should_update_payment := true;
      v_should_mark_paid := true;
      v_status_after := 'paid';
      v_release_status_after := case
        when v_payment.release_paused or v_payment.release_status = 'paused' then 'paused'
        else 'pending'
      end;
    elsif v_payment.status in ('refunded', 'partially_refunded') then
      v_processing_event_type := 'webhook_manual_review_required';
      v_audit_action := 'admin.mock_webhook_manual_review_required';
      v_audit_reason := 'Mock paid webhook arrived after refund state; payment state was not mutated and requires manual review.';
      v_amount_minor := 0;
    else
      v_processing_event_type := 'webhook_out_of_order_rejected';
      v_audit_action := 'admin.mock_webhook_out_of_order_rejected';
      v_audit_reason := 'Out-of-order mock paid webhook ignored; payment state was not downgraded.';
      v_amount_minor := 0;
    end if;
  elsif v_target_status in ('failed', 'expired', 'cancelled') then
    if v_payment.status in ('pending', 'checkout_created') then
      v_should_update_payment := true;
      v_status_after := v_target_status;
      v_release_status_after := 'cancelled';
    else
      v_processing_event_type := 'webhook_out_of_order_rejected';
      v_audit_action := 'admin.mock_webhook_out_of_order_rejected';
      v_audit_reason := 'Out-of-order mock terminal webhook ignored; payment state was not regressed.';
      v_amount_minor := 0;
    end if;
  end if;

  insert into public.vendor_events (
    provider_name,
    provider_event_id,
    event_type,
    related_reference,
    payload_hash,
    processed_at
  ) values (
    v_provider_name,
    v_provider_event_id,
    v_processing_event_type,
    v_provider_reference,
    v_payload_hash,
    now()
  )
  on conflict (provider_name, provider_event_id) do nothing
  returning id into v_vendor_event_id;

  if v_vendor_event_id is null then
    select id
      into v_vendor_event_id
    from public.vendor_events
    where provider_name = v_provider_name
      and provider_event_id = v_provider_event_id;
  end if;

  if v_should_update_payment then
    perform set_config('lekkadeall.allow_trusted_payment_update', 'on', true);

    begin
      update public.payments
      set status = v_status_after,
          provider_name = v_provider_name,
          provider_reference = v_provider_reference,
          payment_method = 'sandbox_online',
          paid_at = case
            when v_should_mark_paid then coalesce(paid_at, now())
            else paid_at
          end,
          funded_at = case
            when v_should_mark_paid then coalesce(funded_at, now())
            else funded_at
          end,
          release_status = v_release_status_after,
          updated_at = now()
      where id = v_payment.id
      returning * into v_payment;
    exception
      when others then
        perform set_config('lekkadeall.allow_trusted_payment_update', 'off', true);
        raise;
    end;

    perform set_config('lekkadeall.allow_trusted_payment_update', 'off', true);
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
    v_payment.id,
    v_payment.booking_id,
    v_processing_event_type,
    v_amount_minor,
    v_payment.currency,
    v_provider_name,
    v_provider_event_id,
    v_idempotency_key,
    v_actor_id,
    'webhook',
    v_metadata || jsonb_build_object(
      'vendor_event_id', v_vendor_event_id,
      'provider_reference', v_provider_reference,
      'provider_event_type', v_event_type,
      'payload_hash', v_payload_hash,
      'payment_status_before', v_status_before,
      'payment_status_after', v_payment.status,
      'release_status_after', v_payment.release_status,
      'state_changed', v_should_update_payment,
      'out_of_order_rejected', v_processing_event_type = 'webhook_out_of_order_rejected',
      'manual_review_required', v_processing_event_type = 'webhook_manual_review_required',
      'mock_adapter', true,
      'sandbox_only', true,
      'real_money_moved', false
    )
  )
  returning id into v_payment_event_id;

  perform private.append_audit_event(
    v_actor_id,
    v_audit_action,
    'payment',
    v_payment.id::text,
    v_audit_reason,
    jsonb_build_object(
      'payment_event_id', v_payment_event_id,
      'vendor_event_id', v_vendor_event_id,
      'provider_event_id', v_provider_event_id,
      'provider_reference', v_provider_reference,
      'provider_event_type', v_event_type,
      'payment_status_before', v_status_before,
      'payment_status_after', v_payment.status,
      'release_status_after', v_payment.release_status,
      'state_changed', v_should_update_payment,
      'mock_adapter', true,
      'sandbox_only', true,
      'real_money_moved', false
    )
  );

  return v_payment_event_id;
end;
$$;

comment on function public.admin_process_verified_mock_payment_webhook(text, text, text, text, text, jsonb) is
  'Ticket 8A trusted database-side mock/sandbox webhook processor. It assumes signature verification already succeeded in a future server route, stores only safe metadata and payload_hash, uses vendor_events for idempotency, and never stores raw webhook bodies or processes real money.';

revoke all on function private.validate_safe_mock_webhook_metadata(jsonb) from public, anon, authenticated, service_role;

revoke all on function public.admin_process_verified_mock_payment_webhook(text, text, text, text, text, jsonb) from public, anon;
grant execute on function public.admin_process_verified_mock_payment_webhook(text, text, text, text, text, jsonb) to authenticated, service_role;
