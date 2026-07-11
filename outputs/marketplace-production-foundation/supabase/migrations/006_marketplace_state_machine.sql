-- Ticket 6: request, bid, acceptance, and booking state machine.
-- Core marketplace state changes must happen through trusted transactional
-- functions. Frontend roles should not directly insert/update/delete request,
-- bid, booking, or payment workflow rows.

create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon;
revoke all on schema private from authenticated;

alter table public.service_requests
  add column if not exists published_at timestamptz,
  add column if not exists awarded_at timestamptz,
  add column if not exists cancelled_at timestamptz;

alter table public.bids
  add column if not exists accepted_at timestamptz,
  add column if not exists declined_at timestamptz,
  add column if not exists withdrawn_at timestamptz;

alter table public.bookings
  add column if not exists in_progress_at timestamptz,
  add column if not exists customer_completed_at timestamptz,
  add column if not exists provider_completed_at timestamptz,
  add column if not exists cancelled_at timestamptz;

comment on table public.service_requests is
  'Ticket 6 state machine: draft -> open -> awarded|cancelled|expired. Frontend clients must use customer_create_draft_request, customer_publish_request, and customer_cancel_request for state changes.';
comment on table public.bids is
  'Ticket 6 state machine: submitted -> accepted|declined|withdrawn|expired. Frontend clients must use provider_submit_bid, provider_withdraw_bid, and customer_accept_bid for state changes.';
comment on table public.bookings is
  'Ticket 6 state machine: scheduled -> in_progress -> completed, with future payment/refund/dispute transitions handled by later tickets. Frontend clients must use booking/customer/provider confirmation functions for state changes.';
comment on table public.payments is
  'Payment state is server/vendor controlled. Ticket 6 creates only a pending internal payment record; real payment/refund/webhook handling remains a later ticket.';

create unique index if not exists bids_one_accepted_per_request_idx
on public.bids(request_id)
where status = 'accepted';

create or replace function private.marketplace_state_transition_allowed()
returns boolean
language sql
stable
set search_path = public
as $$
  select coalesce(
    current_setting('lekkadeall.allow_marketplace_state_transition', true),
    'off'
  ) = 'on';
$$;

create or replace function private.calculate_platform_fee_minor(
  p_service_amount_minor integer
)
returns integer
language sql
immutable
set search_path = public
as $$
  select greatest(0, ceiling(coalesce(p_service_amount_minor, 0)::numeric * 0.05)::integer);
$$;

create or replace function private.protect_service_request_business_state()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if tg_op = 'DELETE' then
    if not private.marketplace_state_transition_allowed() then
      raise exception 'service_requests may not be deleted directly by frontend clients'
        using errcode = '42501';
    end if;

    return old;
  end if;

  if not private.marketplace_state_transition_allowed() then
    if tg_op = 'INSERT' then
      raise exception 'service_requests must be created through customer_create_draft_request'
        using errcode = '42501';
    end if;

    if new.status is distinct from old.status
       or new.closes_at is distinct from old.closes_at
       or new.published_at is distinct from old.published_at
       or new.awarded_at is distinct from old.awarded_at
       or new.cancelled_at is distinct from old.cancelled_at then
      raise exception 'service request workflow fields must be changed through marketplace state-machine functions'
        using errcode = '42501';
    end if;
  end if;

  if tg_op = 'UPDATE' then
    new.updated_at := now();
  end if;

  return new;
end;
$$;

create or replace function private.protect_bid_business_state()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if tg_op = 'DELETE' then
    if not private.marketplace_state_transition_allowed() then
      raise exception 'bids may not be deleted directly by frontend clients'
        using errcode = '42501';
    end if;

    return old;
  end if;

  if not private.marketplace_state_transition_allowed() then
    if tg_op = 'INSERT' then
      raise exception 'bids must be created through provider_submit_bid'
        using errcode = '42501';
    end if;

    raise exception 'bid workflow/commercial fields must be changed through marketplace state-machine functions'
      using errcode = '42501';
  end if;

  if tg_op = 'UPDATE' then
    new.updated_at := now();
  end if;

  return new;
end;
$$;

create or replace function private.protect_booking_business_state()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if tg_op = 'DELETE' then
    if not private.marketplace_state_transition_allowed() then
      raise exception 'bookings may not be deleted directly by frontend clients'
        using errcode = '42501';
    end if;

    return old;
  end if;

  if not private.marketplace_state_transition_allowed() then
    raise exception 'booking workflow fields must be changed through marketplace state-machine functions'
      using errcode = '42501';
  end if;

  if tg_op = 'UPDATE' then
    new.updated_at := now();
  end if;

  return new;
end;
$$;

create or replace function private.protect_payment_business_state()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if tg_op = 'DELETE' then
    if not private.marketplace_state_transition_allowed() then
      raise exception 'payments may not be deleted directly by frontend clients'
        using errcode = '42501';
    end if;

    return old;
  end if;

  if not private.marketplace_state_transition_allowed() then
    raise exception 'payment and release state must be changed through trusted server/payment functions'
      using errcode = '42501';
  end if;

  if tg_op = 'UPDATE' then
    new.updated_at := now();
  end if;

  return new;
end;
$$;

create or replace function private.validate_booking_integrity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bid public.bids%rowtype;
  v_request public.service_requests%rowtype;
begin
  select *
    into v_bid
  from public.bids
  where id = new.bid_id;

  if not found then
    raise exception 'Booking bid % does not exist', new.bid_id
      using errcode = '23503';
  end if;

  select *
    into v_request
  from public.service_requests
  where id = new.request_id;

  if not found then
    raise exception 'Booking request % does not exist', new.request_id
      using errcode = '23503';
  end if;

  if v_bid.request_id <> new.request_id then
    raise exception 'Booking bid must belong to booking request'
      using errcode = '23514';
  end if;

  if v_request.customer_id <> new.customer_id then
    raise exception 'Booking customer must match request customer'
      using errcode = '23514';
  end if;

  if v_bid.provider_id <> new.provider_id then
    raise exception 'Booking provider must match bid provider'
      using errcode = '23514';
  end if;

  if v_bid.status <> 'accepted' then
    raise exception 'Booking bid must be accepted before booking creation'
      using errcode = '23514';
  end if;

  if v_bid.amount_minor <> new.service_amount_minor then
    raise exception 'Booking amount must match accepted bid amount'
      using errcode = '23514';
  end if;

  if v_bid.currency <> new.currency then
    raise exception 'Booking currency must match accepted bid currency'
      using errcode = '23514';
  end if;

  if v_bid.proposed_start <> new.scheduled_start then
    raise exception 'Booking scheduled_start must match accepted bid proposed_start'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists protect_service_request_business_state on public.service_requests;
create trigger protect_service_request_business_state
before insert or update or delete on public.service_requests
for each row execute function private.protect_service_request_business_state();

drop trigger if exists protect_bid_business_state on public.bids;
create trigger protect_bid_business_state
before insert or update or delete on public.bids
for each row execute function private.protect_bid_business_state();

drop trigger if exists validate_booking_integrity on public.bookings;
create trigger validate_booking_integrity
before insert or update of request_id, bid_id, customer_id, provider_id, service_amount_minor, currency, scheduled_start
on public.bookings
for each row execute function private.validate_booking_integrity();

drop trigger if exists protect_booking_business_state on public.bookings;
create trigger protect_booking_business_state
before insert or update or delete on public.bookings
for each row execute function private.protect_booking_business_state();

drop trigger if exists protect_payment_business_state on public.payments;
create trigger protect_payment_business_state
before insert or update or delete on public.payments
for each row execute function private.protect_payment_business_state();

drop policy if exists "customer owns requests" on public.service_requests;
drop policy if exists "customer reads own service requests" on public.service_requests;
create policy "customer reads own service requests"
on public.service_requests
for select
using (auth.uid() = customer_id);

drop policy if exists "provider owns bids" on public.bids;
drop policy if exists "provider reads own bids" on public.bids;
create policy "provider reads own bids"
on public.bids
for select
using (auth.uid() = provider_id);

revoke insert, update, delete on public.service_requests from anon, authenticated;
revoke insert, update, delete on public.bids from anon, authenticated;
revoke insert, update, delete on public.bookings from anon, authenticated;
revoke insert, update, delete on public.payments from anon, authenticated;

grant select on public.bids to authenticated;
grant select on public.bookings to authenticated;
grant select on public.payments to authenticated;

create or replace function public.customer_create_draft_request(
  p_category_id uuid,
  p_title text,
  p_description text,
  p_suburb text,
  p_city text,
  p_requested_start timestamptz,
  p_budget_minor integer default null,
  p_precise_address_ciphertext text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_request_id uuid;
begin
  if v_actor_id is null then
    raise exception 'Authentication is required to create a request'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = v_actor_id
      and p.role = 'customer'
      and p.account_status = 'active'
  ) then
    raise exception 'Only active customers may create service requests'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.service_categories sc
    where sc.id = p_category_id
      and sc.active = true
  ) then
    raise exception 'Service category is unavailable'
      using errcode = '22023';
  end if;

  if p_requested_start <= now() then
    raise exception 'Requested start must be in the future'
      using errcode = '22023';
  end if;

  if p_budget_minor is not null and p_budget_minor < 0 then
    raise exception 'Budget cannot be negative'
      using errcode = '22023';
  end if;

  if p_precise_address_ciphertext is not null
     and nullif(trim(p_precise_address_ciphertext), '') is null then
    raise exception 'Precise address ciphertext cannot be blank'
      using errcode = '22023';
  end if;

  perform set_config('lekkadeall.allow_marketplace_state_transition', 'on', true);

  begin
    insert into public.service_requests (
      customer_id,
      category_id,
      title,
      description,
      suburb,
      city,
      requested_start,
      budget_minor,
      status,
      closes_at
    ) values (
      v_actor_id,
      p_category_id,
      trim(p_title),
      trim(p_description),
      trim(p_suburb),
      trim(p_city),
      p_requested_start,
      p_budget_minor,
      'draft',
      null
    )
    returning id into v_request_id;

    if nullif(trim(coalesce(p_precise_address_ciphertext, '')), '') is not null then
      insert into private.service_request_addresses (
        request_id,
        customer_id,
        precise_address_ciphertext
      ) values (
        v_request_id,
        v_actor_id,
        trim(p_precise_address_ciphertext)
      );

      perform private.append_audit_event(
        v_actor_id,
        'customer.request_address_upserted',
        'service_request',
        v_request_id::text,
        'Customer added draft request precise address during request creation',
        jsonb_build_object('request_id', v_request_id, 'customer_id', v_actor_id)
      );
    end if;

    perform private.append_audit_event(
      v_actor_id,
      'customer.service_request_draft_created',
      'service_request',
      v_request_id::text,
      'Customer created draft service request',
      jsonb_build_object('request_id', v_request_id, 'category_id', p_category_id)
    );
  exception
    when others then
      perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
      raise;
  end;

  perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);

  return v_request_id;
end;
$$;

create or replace function public.customer_publish_request(
  p_request_id uuid,
  p_closes_at timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_request public.service_requests%rowtype;
  v_closes_at timestamptz;
begin
  if v_actor_id is null then
    raise exception 'Authentication is required to publish a request'
      using errcode = '42501';
  end if;

  select *
    into v_request
  from public.service_requests
  where id = p_request_id
  for update;

  if not found or v_request.customer_id <> v_actor_id then
    raise exception 'Request not found or not owned by caller'
      using errcode = '42501';
  end if;

  if v_request.status <> 'draft' then
    raise exception 'Only draft requests may be published'
      using errcode = '42501';
  end if;

  if v_request.requested_start <= now() then
    raise exception 'Requested start must be in the future'
      using errcode = '22023';
  end if;

  if public.service_request_description_has_exact_address_risk(v_request.description) then
    raise exception 'Public request description appears to contain exact address material'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from private.service_request_addresses sra
    where sra.request_id = p_request_id
      and sra.customer_id = v_actor_id
  ) then
    raise exception 'Precise address must be saved before publishing the request'
      using errcode = '42501';
  end if;

  v_closes_at := coalesce(
    p_closes_at,
    least(now() + interval '3 days', v_request.requested_start - interval '1 hour')
  );

  if v_closes_at <= now() or v_closes_at >= v_request.requested_start then
    raise exception 'Request close time must be in the future and before the requested start'
      using errcode = '22023';
  end if;

  perform set_config('lekkadeall.allow_marketplace_state_transition', 'on', true);

  begin
    update public.service_requests
    set status = 'open',
        closes_at = v_closes_at,
        published_at = now(),
        updated_at = now()
    where id = p_request_id;

    perform private.append_audit_event(
      v_actor_id,
      'customer.service_request_published',
      'service_request',
      p_request_id::text,
      'Customer published draft service request',
      jsonb_build_object('request_id', p_request_id, 'closes_at', v_closes_at)
    );
  exception
    when others then
      perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
      raise;
  end;

  perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
end;
$$;

create or replace function public.customer_cancel_request(
  p_request_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_request public.service_requests%rowtype;
begin
  if v_actor_id is null then
    raise exception 'Authentication is required to cancel a request'
      using errcode = '42501';
  end if;

  select *
    into v_request
  from public.service_requests
  where id = p_request_id
  for update;

  if not found or v_request.customer_id <> v_actor_id then
    raise exception 'Request not found or not owned by caller'
      using errcode = '42501';
  end if;

  if v_request.status not in ('draft', 'open') then
    raise exception 'Only draft or open requests may be cancelled'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.bookings b
    where b.request_id = p_request_id
  ) then
    raise exception 'Requests with bookings cannot be cancelled through this draft/open cancellation function'
      using errcode = '42501';
  end if;

  perform set_config('lekkadeall.allow_marketplace_state_transition', 'on', true);

  begin
    update public.service_requests
    set status = 'cancelled',
        cancelled_at = now(),
        updated_at = now()
    where id = p_request_id;

    update public.bids
    set status = 'declined',
        declined_at = now(),
        updated_at = now()
    where request_id = p_request_id
      and status = 'submitted';

    perform private.append_audit_event(
      v_actor_id,
      'customer.service_request_cancelled',
      'service_request',
      p_request_id::text,
      p_reason,
      jsonb_build_object('request_id', p_request_id)
    );
  exception
    when others then
      perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
      raise;
  end;

  perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
end;
$$;

create or replace function public.provider_submit_bid(
  p_request_id uuid,
  p_amount_minor integer,
  p_proposed_start timestamptz,
  p_message text default null,
  p_perks text[] default '{}'::text[],
  p_expires_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_request public.service_requests%rowtype;
  v_bid_id uuid;
  v_expires_at timestamptz;
begin
  if v_actor_id is null then
    raise exception 'Authentication is required to submit a bid'
      using errcode = '42501';
  end if;

  if not public.is_approved_provider(v_actor_id) then
    raise exception 'Only active approved providers may submit bids'
      using errcode = '42501';
  end if;

  select *
    into v_request
  from public.service_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Request % does not exist', p_request_id
      using errcode = '02000';
  end if;

  if v_request.customer_id = v_actor_id then
    raise exception 'Providers cannot bid on their own customer request'
      using errcode = '42501';
  end if;

  if v_request.status <> 'open' then
    raise exception 'Providers can bid only on open requests'
      using errcode = '42501';
  end if;

  if v_request.closes_at is null or v_request.closes_at <= now() then
    raise exception 'Request is closed for bidding'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.provider_services ps
    where ps.provider_id = v_actor_id
      and ps.category_id = v_request.category_id
      and ps.active = true
  ) then
    raise exception 'Provider is not eligible for this request category'
      using errcode = '42501';
  end if;

  if p_amount_minor <= 0 then
    raise exception 'Bid amount must be positive'
      using errcode = '22023';
  end if;

  if p_proposed_start <= now() then
    raise exception 'Proposed start must be in the future'
      using errcode = '22023';
  end if;

  v_expires_at := coalesce(
    p_expires_at,
    least(now() + interval '2 days', v_request.closes_at)
  );

  if v_expires_at <= now() or v_expires_at > v_request.closes_at then
    raise exception 'Bid expiry must be in the future and no later than request close time'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.bids b
    where b.request_id = p_request_id
      and b.provider_id = v_actor_id
  ) then
    raise exception 'Provider already has a bid on this request'
      using errcode = '23505';
  end if;

  perform set_config('lekkadeall.allow_marketplace_state_transition', 'on', true);

  begin
    insert into public.bids (
      request_id,
      provider_id,
      amount_minor,
      proposed_start,
      message,
      perks,
      status,
      expires_at
    ) values (
      p_request_id,
      v_actor_id,
      p_amount_minor,
      p_proposed_start,
      nullif(trim(coalesce(p_message, '')), ''),
      coalesce(p_perks, '{}'::text[]),
      'submitted',
      v_expires_at
    )
    returning id into v_bid_id;

    perform private.append_audit_event(
      v_actor_id,
      'provider.bid_submitted',
      'bid',
      v_bid_id::text,
      'Provider submitted bid through controlled function',
      jsonb_build_object(
        'request_id', p_request_id,
        'provider_id', v_actor_id,
        'amount_minor', p_amount_minor,
        'expires_at', v_expires_at
      )
    );
  exception
    when others then
      perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
      raise;
  end;

  perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);

  return v_bid_id;
end;
$$;

create or replace function public.provider_withdraw_bid(
  p_bid_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_bid public.bids%rowtype;
begin
  if v_actor_id is null then
    raise exception 'Authentication is required to withdraw a bid'
      using errcode = '42501';
  end if;

  select *
    into v_bid
  from public.bids
  where id = p_bid_id
  for update;

  if not found or v_bid.provider_id <> v_actor_id then
    raise exception 'Bid not found or not owned by caller'
      using errcode = '42501';
  end if;

  if v_bid.status <> 'submitted' then
    raise exception 'Only submitted bids may be withdrawn'
      using errcode = '42501';
  end if;

  if v_bid.expires_at <= now() then
    raise exception 'Expired bids cannot be withdrawn through the provider withdrawal function'
      using errcode = '42501';
  end if;

  perform set_config('lekkadeall.allow_marketplace_state_transition', 'on', true);

  begin
    update public.bids
    set status = 'withdrawn',
        withdrawn_at = now(),
        updated_at = now()
    where id = p_bid_id;

    perform private.append_audit_event(
      v_actor_id,
      'provider.bid_withdrawn',
      'bid',
      p_bid_id::text,
      p_reason,
      jsonb_build_object('request_id', v_bid.request_id, 'provider_id', v_actor_id)
    );
  exception
    when others then
      perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
      raise;
  end;

  perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
end;
$$;

create or replace function public.customer_accept_bid(
  p_bid_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_bid public.bids%rowtype;
  v_request public.service_requests%rowtype;
  v_booking_id uuid;
  v_platform_fee_minor integer;
begin
  if v_actor_id is null then
    raise exception 'Authentication is required to accept a bid'
      using errcode = '42501';
  end if;

  select *
    into v_bid
  from public.bids
  where id = p_bid_id
  for update;

  if not found then
    raise exception 'Bid % does not exist', p_bid_id
      using errcode = '02000';
  end if;

  select *
    into v_request
  from public.service_requests
  where id = v_bid.request_id
  for update;

  if not found or v_request.customer_id <> v_actor_id then
    raise exception 'Request not found or not owned by caller'
      using errcode = '42501';
  end if;

  if v_request.status <> 'open' then
    raise exception 'Only open requests may accept bids'
      using errcode = '42501';
  end if;

  if v_request.closes_at is null or v_request.closes_at <= now() then
    raise exception 'Request is closed for bid acceptance'
      using errcode = '42501';
  end if;

  if v_bid.request_id <> v_request.id then
    raise exception 'Bid does not belong to this request'
      using errcode = '23514';
  end if;

  if v_bid.status <> 'submitted' then
    raise exception 'Only submitted bids may be accepted'
      using errcode = '42501';
  end if;

  if v_bid.expires_at <= now() then
    raise exception 'Expired bids may not be accepted'
      using errcode = '42501';
  end if;

  if not public.is_approved_provider(v_bid.provider_id) then
    raise exception 'Bid provider is no longer active and approved'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.provider_services ps
    where ps.provider_id = v_bid.provider_id
      and ps.category_id = v_request.category_id
      and ps.active = true
  ) then
    raise exception 'Bid provider is no longer eligible for this request category'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.bookings b
    where b.request_id = v_request.id
  ) then
    raise exception 'A booking already exists for this request'
      using errcode = '23505';
  end if;

  v_platform_fee_minor := private.calculate_platform_fee_minor(v_bid.amount_minor);

  perform set_config('lekkadeall.allow_marketplace_state_transition', 'on', true);

  begin
    update public.bids
    set status = 'accepted',
        accepted_at = now(),
        updated_at = now()
    where id = v_bid.id;

    update public.bids
    set status = 'declined',
        declined_at = now(),
        updated_at = now()
    where request_id = v_request.id
      and id <> v_bid.id
      and status = 'submitted';

    update public.service_requests
    set status = 'awarded',
        awarded_at = now(),
        updated_at = now()
    where id = v_request.id;

    insert into public.bookings (
      public_reference,
      request_id,
      bid_id,
      customer_id,
      provider_id,
      service_amount_minor,
      platform_fee_minor,
      currency,
      scheduled_start,
      status
    ) values (
      'LD-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12)),
      v_request.id,
      v_bid.id,
      v_request.customer_id,
      v_bid.provider_id,
      v_bid.amount_minor,
      v_platform_fee_minor,
      v_bid.currency,
      v_bid.proposed_start,
      'scheduled'
    )
    returning id into v_booking_id;

    insert into public.payments (
      booking_id,
      provider_name,
      provider_reference,
      status,
      amount_minor,
      currency,
      release_paused,
      funded_at,
      refunded_minor
    ) values (
      v_booking_id,
      'internal_pending',
      null,
      'payment_pending',
      v_bid.amount_minor + v_platform_fee_minor,
      v_bid.currency,
      true,
      null,
      0
    );

    perform private.append_audit_event(
      v_actor_id,
      'customer.bid_accepted',
      'bid',
      v_bid.id::text,
      'Customer accepted provider bid through controlled transaction',
      jsonb_build_object(
        'request_id', v_request.id,
        'booking_id', v_booking_id,
        'provider_id', v_bid.provider_id
      )
    );

    perform private.append_audit_event(
      v_actor_id,
      'booking.created',
      'booking',
      v_booking_id::text,
      'Booking created from accepted bid',
      jsonb_build_object(
        'request_id', v_request.id,
        'bid_id', v_bid.id,
        'customer_id', v_request.customer_id,
        'provider_id', v_bid.provider_id,
        'status', 'scheduled'
      )
    );

    perform private.append_audit_event(
      v_actor_id,
      'payment.intent_prepared',
      'booking',
      v_booking_id::text,
      'Internal pending payment record prepared; real payment integration remains a later ticket',
      jsonb_build_object(
        'booking_id', v_booking_id,
        'amount_minor', v_bid.amount_minor + v_platform_fee_minor,
        'currency', v_bid.currency
      )
    );
  exception
    when others then
      perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
      raise;
  end;

  perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);

  return v_booking_id;
end;
$$;

create or replace function public.booking_mark_in_progress(
  p_booking_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_booking public.bookings%rowtype;
begin
  if v_actor_id is null then
    raise exception 'Authentication is required to mark a booking in progress'
      using errcode = '42501';
  end if;

  select *
    into v_booking
  from public.bookings
  where id = p_booking_id
  for update;

  if not found or v_booking.provider_id <> v_actor_id then
    raise exception 'Booking not found for selected provider'
      using errcode = '42501';
  end if;

  if v_booking.status not in ('scheduled', 'funded') then
    raise exception 'Only scheduled or funded bookings may be marked in progress'
      using errcode = '42501';
  end if;

  perform set_config('lekkadeall.allow_marketplace_state_transition', 'on', true);

  begin
    update public.bookings
    set status = 'in_progress',
        in_progress_at = coalesce(in_progress_at, now()),
        updated_at = now()
    where id = p_booking_id;

    perform private.append_audit_event(
      v_actor_id,
      'booking.in_progress_marked',
      'booking',
      p_booking_id::text,
      'Selected provider marked booking in progress',
      jsonb_build_object('booking_id', p_booking_id)
    );
  exception
    when others then
      perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
      raise;
  end;

  perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
end;
$$;

create or replace function public.customer_confirm_completion(
  p_booking_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_booking public.bookings%rowtype;
  v_will_complete boolean;
begin
  if v_actor_id is null then
    raise exception 'Authentication is required to confirm completion'
      using errcode = '42501';
  end if;

  select *
    into v_booking
  from public.bookings
  where id = p_booking_id
  for update;

  if not found or v_booking.customer_id <> v_actor_id then
    raise exception 'Booking not found for customer'
      using errcode = '42501';
  end if;

  if v_booking.status = 'completed' and v_booking.customer_completed_at is not null then
    return;
  end if;

  if v_booking.status <> 'in_progress' then
    raise exception 'Booking must be in_progress before completion can be confirmed'
      using errcode = '42501';
  end if;

  v_will_complete := v_booking.provider_completed_at is not null;

  perform set_config('lekkadeall.allow_marketplace_state_transition', 'on', true);

  begin
    update public.bookings
    set customer_completed_at = coalesce(customer_completed_at, now()),
        status = case when v_will_complete then 'completed'::public.booking_status else status end,
        completion_confirmed_at = case when v_will_complete then coalesce(completion_confirmed_at, now()) else completion_confirmed_at end,
        updated_at = now()
    where id = p_booking_id;

    perform private.append_audit_event(
      v_actor_id,
      'booking.customer_completion_confirmed',
      'booking',
      p_booking_id::text,
      'Customer confirmed booking completion',
      jsonb_build_object('booking_id', p_booking_id, 'completed', v_will_complete)
    );

    if v_will_complete then
      perform private.append_audit_event(
        v_actor_id,
        'booking.completed',
        'booking',
        p_booking_id::text,
        'Booking completed after both parties confirmed completion',
        jsonb_build_object('booking_id', p_booking_id)
      );
    end if;
  exception
    when others then
      perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
      raise;
  end;

  perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
end;
$$;

create or replace function public.provider_confirm_completion(
  p_booking_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_actor_id uuid := auth.uid();
  v_booking public.bookings%rowtype;
  v_will_complete boolean;
begin
  if v_actor_id is null then
    raise exception 'Authentication is required to confirm completion'
      using errcode = '42501';
  end if;

  select *
    into v_booking
  from public.bookings
  where id = p_booking_id
  for update;

  if not found or v_booking.provider_id <> v_actor_id then
    raise exception 'Booking not found for selected provider'
      using errcode = '42501';
  end if;

  if v_booking.status = 'completed' and v_booking.provider_completed_at is not null then
    return;
  end if;

  if v_booking.status <> 'in_progress' then
    raise exception 'Booking must be in_progress before completion can be confirmed'
      using errcode = '42501';
  end if;

  v_will_complete := v_booking.customer_completed_at is not null;

  perform set_config('lekkadeall.allow_marketplace_state_transition', 'on', true);

  begin
    update public.bookings
    set provider_completed_at = coalesce(provider_completed_at, now()),
        status = case when v_will_complete then 'completed'::public.booking_status else status end,
        completion_confirmed_at = case when v_will_complete then coalesce(completion_confirmed_at, now()) else completion_confirmed_at end,
        updated_at = now()
    where id = p_booking_id;

    perform private.append_audit_event(
      v_actor_id,
      'booking.provider_completion_confirmed',
      'booking',
      p_booking_id::text,
      'Provider confirmed booking completion',
      jsonb_build_object('booking_id', p_booking_id, 'completed', v_will_complete)
    );

    if v_will_complete then
      perform private.append_audit_event(
        v_actor_id,
        'booking.completed',
        'booking',
        p_booking_id::text,
        'Booking completed after both parties confirmed completion',
        jsonb_build_object('booking_id', p_booking_id)
      );
    end if;
  exception
    when others then
      perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
      raise;
  end;

  perform set_config('lekkadeall.allow_marketplace_state_transition', 'off', true);
end;
$$;

comment on function public.customer_create_draft_request(uuid, text, text, text, text, timestamptz, integer, text) is
  'Creates a draft service request for an active customer and optionally stores exact address ciphertext in the private address table.';
comment on function public.customer_publish_request(uuid, timestamptz) is
  'Publishes an owned draft request after address and public-description validation.';
comment on function public.customer_cancel_request(uuid, text) is
  'Cancels an owned draft/open request before provider selection and declines submitted bids.';
comment on function public.provider_submit_bid(uuid, integer, timestamptz, text, text[], timestamptz) is
  'Creates a submitted bid for an active approved provider eligible for the request category.';
comment on function public.provider_withdraw_bid(uuid, text) is
  'Withdraws an owned submitted bid before acceptance.';
comment on function public.customer_accept_bid(uuid) is
  'Atomically accepts one valid bid, declines competing bids, awards the request, creates a scheduled booking, prepares a pending payment record, and writes audit events.';
comment on function public.booking_mark_in_progress(uuid) is
  'Selected provider marks a scheduled/funded booking in progress.';
comment on function public.customer_confirm_completion(uuid) is
  'Customer completion confirmation after in_progress; booking completes only after both customer and provider have confirmed.';
comment on function public.provider_confirm_completion(uuid) is
  'Provider completion confirmation after in_progress; booking completes only after both customer and provider have confirmed.';

revoke all on function private.marketplace_state_transition_allowed() from public, anon, authenticated;
revoke all on function private.calculate_platform_fee_minor(integer) from public, anon, authenticated;
revoke all on function private.protect_service_request_business_state() from public, anon, authenticated;
revoke all on function private.protect_bid_business_state() from public, anon, authenticated;
revoke all on function private.protect_booking_business_state() from public, anon, authenticated;
revoke all on function private.protect_payment_business_state() from public, anon, authenticated;
revoke all on function private.validate_booking_integrity() from public, anon, authenticated;

revoke all on function public.customer_create_draft_request(uuid, text, text, text, text, timestamptz, integer, text) from public, anon;
grant execute on function public.customer_create_draft_request(uuid, text, text, text, text, timestamptz, integer, text) to authenticated, service_role;

revoke all on function public.customer_publish_request(uuid, timestamptz) from public, anon;
grant execute on function public.customer_publish_request(uuid, timestamptz) to authenticated, service_role;

revoke all on function public.customer_cancel_request(uuid, text) from public, anon;
grant execute on function public.customer_cancel_request(uuid, text) to authenticated, service_role;

revoke all on function public.provider_submit_bid(uuid, integer, timestamptz, text, text[], timestamptz) from public, anon;
grant execute on function public.provider_submit_bid(uuid, integer, timestamptz, text, text[], timestamptz) to authenticated, service_role;

revoke all on function public.provider_withdraw_bid(uuid, text) from public, anon;
grant execute on function public.provider_withdraw_bid(uuid, text) to authenticated, service_role;

revoke all on function public.customer_accept_bid(uuid) from public, anon;
grant execute on function public.customer_accept_bid(uuid) to authenticated, service_role;

revoke all on function public.booking_mark_in_progress(uuid) from public, anon;
grant execute on function public.booking_mark_in_progress(uuid) to authenticated, service_role;

revoke all on function public.customer_confirm_completion(uuid) from public, anon;
grant execute on function public.customer_confirm_completion(uuid) to authenticated, service_role;

revoke all on function public.provider_confirm_completion(uuid) from public, anon;
grant execute on function public.provider_confirm_completion(uuid) to authenticated, service_role;
