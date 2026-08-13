-- Ticket 10D: provider bidding is one actor-derived, privacy-safe boundary.
-- Browser roles receive no raw bid table access and cannot submit free-form
-- bid content or control workflow-owned bid fields.

create function private.provider_marketplace_eligibility_is_current(
  p_provider_id pg_catalog.uuid,
  p_decision_at pg_catalog.timestamptz
)
returns pg_catalog.bool
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select case when p_provider_id is not null
                    and p_decision_at is not null
                    and (
    select
      profile.role = 'provider'::public.user_role
      and profile.account_status = 'active'
      and provider.review_status = 'approved'
      and provider.verification_status not in (
        'rejected'::public.verification_status,
        'expired'::public.verification_status
      )
      and eligibility.status = 'approved'
      and eligibility.basis = 'manual_pilot'
      and eligibility.policy_version = 'provider-eligibility-v1'
      and eligibility.expires_at > p_decision_at
      and eligibility.current_decision_id is not null
      and eligibility.reviewer_id is not null
      and eligibility.reason_code is not null
    from public.profiles as profile
    join public.provider_profiles as provider
      on provider.user_id = profile.id
    join private.provider_marketplace_eligibility as eligibility
      on eligibility.provider_id = provider.user_id
    where profile.id = p_provider_id
  ) is true then true else false end
$$;

create function private.provider_request_is_discoverable(
  p_provider_id pg_catalog.uuid,
  p_request_id pg_catalog.uuid,
  p_decision_at pg_catalog.timestamptz
)
returns pg_catalog.bool
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select case when private.provider_marketplace_eligibility_is_current(
    p_provider_id,
    p_decision_at
  ) and exists (
    select 1
    from public.service_requests as request
    join public.service_categories as category
      on category.id = request.category_id
     and category.active = true
    join public.provider_services as service
      on service.provider_id = p_provider_id
     and service.category_id = request.category_id
     and service.active = true
    where request.id = p_request_id
      and request.status = 'open'::public.request_status
      and request.published_at is not null
      and request.published_at <= p_decision_at
      and request.closes_at is not null
      and request.closes_at > p_decision_at
      and request.requested_start > p_decision_at
      and request.closes_at < request.requested_start
      and request.awarded_at is null
      and request.cancelled_at is null
      and request.precise_address_ciphertext is null
      and request.title = private.canonicalize_service_request_public_field(
        'title', request.title
      )
      and request.description = private.canonicalize_service_request_public_field(
        'description', request.description
      )
      and request.suburb = private.canonicalize_service_request_public_field(
        'suburb', request.suburb
      )
      and request.city = private.canonicalize_service_request_public_field(
        'city', request.city
      )
      and private.service_request_public_field_violation(
        'title', request.title
      ) is null
      and private.service_request_public_field_violation(
        'description', request.description
      ) is null
      and private.service_request_public_field_violation(
        'suburb', request.suburb
      ) is null
      and private.service_request_public_field_violation(
        'city', request.city
      ) is null
  ) then true else false end
$$;

revoke all on function private.provider_marketplace_eligibility_is_current(
  pg_catalog.uuid,
  pg_catalog.timestamptz
) from public, anon, authenticated, service_role;

revoke all on function private.provider_request_is_discoverable(
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.timestamptz
) from public, anon, authenticated, service_role;

-- Keep Ticket 10C discovery on the same canonical request predicate. The
-- wall-clock decision is captured only after the authority locks are held.
create or replace function public.provider_list_discoverable_requests(
  p_page_size pg_catalog.int4 default 20,
  p_cursor_published_at pg_catalog.timestamptz default null,
  p_cursor_request_id pg_catalog.uuid default null
)
returns table (
  request_id pg_catalog.uuid,
  category_id pg_catalog.uuid,
  title pg_catalog.text,
  description pg_catalog.text,
  suburb pg_catalog.text,
  city pg_catalog.text,
  requested_start pg_catalog.timestamptz,
  budget_minor pg_catalog.int4,
  closes_at pg_catalog.timestamptz,
  published_at pg_catalog.timestamptz
)
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor_id pg_catalog.uuid := auth.uid();
  v_now pg_catalog.timestamptz;
begin
  if v_actor_id is null then
    raise exception 'Provider request discovery is unavailable'
      using errcode = '42501';
  end if;

  if p_page_size is null
     or p_page_size < 1
     or p_page_size > 50
     or (p_cursor_published_at is null) <> (p_cursor_request_id is null) then
    raise exception 'Provider request discovery is unavailable'
      using errcode = '22023';
  end if;

  begin
    perform private.require_provider_marketplace_eligibility(v_actor_id);
  exception
    when others then
      raise exception 'Provider request discovery is unavailable'
        using errcode = '42501';
  end;

  v_now := pg_catalog.clock_timestamp();
  if not private.provider_marketplace_eligibility_is_current(v_actor_id, v_now) then
    raise exception 'Provider request discovery is unavailable'
      using errcode = '42501';
  end if;

  return query
  select
    request.id,
    request.category_id,
    request.title,
    request.description,
    request.suburb,
    request.city,
    request.requested_start,
    request.budget_minor,
    request.closes_at,
    request.published_at
  from public.service_requests as request
  where private.provider_request_is_discoverable(
      v_actor_id,
      request.id,
      v_now
    )
    and (
      p_cursor_published_at is null
      or request.published_at < p_cursor_published_at
      or (
        request.published_at = p_cursor_published_at
        and request.id < p_cursor_request_id
      )
    )
  order by request.published_at desc, request.id desc
  limit p_page_size;
end;
$$;

-- Raw bid rows include provider identities and legacy free-form fields. Ticket
-- 10D leaves no direct browser read or mutation path to this table.
drop policy if exists "provider reads own bids" on public.bids;
drop policy if exists "customer sees request bids" on public.bids;
revoke select, insert, update, delete on public.bids
  from public, anon, authenticated;

-- Remove the legacy free-form browser contracts before adding the narrowed
-- signatures. Existing internal state-machine functions do not call them.
revoke all on function public.provider_submit_bid(
  pg_catalog.uuid,
  pg_catalog.int4,
  pg_catalog.timestamptz,
  pg_catalog.text,
  pg_catalog.text[],
  pg_catalog.timestamptz
) from public, anon, authenticated, service_role;

revoke all on function public.provider_withdraw_bid(
  pg_catalog.uuid,
  pg_catalog.text
) from public, anon, authenticated, service_role;

drop function public.provider_submit_bid(
  pg_catalog.uuid,
  pg_catalog.int4,
  pg_catalog.timestamptz,
  pg_catalog.text,
  pg_catalog.text[],
  pg_catalog.timestamptz
);

drop function public.provider_withdraw_bid(
  pg_catalog.uuid,
  pg_catalog.text
);

create function public.provider_submit_bid(
  p_request_id pg_catalog.uuid,
  p_amount_minor pg_catalog.int4
)
returns pg_catalog.uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor_id pg_catalog.uuid := auth.uid();
  v_bid_id pg_catalog.uuid;
  v_request_customer_id pg_catalog.uuid;
  v_category_id pg_catalog.uuid;
  v_requested_start pg_catalog.timestamptz;
  v_closes_at pg_catalog.timestamptz;
  v_now pg_catalog.timestamptz;
  v_existing_amount pg_catalog.int4;
  v_existing_currency pg_catalog.bpchar;
  v_existing_start pg_catalog.timestamptz;
  v_existing_status public.bid_status;
  v_existing_expires_at pg_catalog.timestamptz;
  v_existing_message pg_catalog.text;
  v_existing_perks pg_catalog.text[];
begin
  if v_actor_id is null then
    raise exception 'Provider bid is unavailable' using errcode = '42501';
  end if;

  if p_request_id is null
     or p_amount_minor is null
     or p_amount_minor < 1
     or p_amount_minor > 100000000 then
    raise exception 'Provider bid is unavailable' using errcode = '22023';
  end if;

  -- If this can be a replay, take the bid lock before authority/request locks.
  -- Acceptance and withdrawal also begin with this bid lock, avoiding a
  -- reverse edge for an already-existing bid.
  select
    bid.id,
    bid.amount_minor,
    bid.currency,
    bid.proposed_start,
    bid.status,
    bid.expires_at,
    bid.message,
    bid.perks
    into
      v_bid_id,
      v_existing_amount,
      v_existing_currency,
      v_existing_start,
      v_existing_status,
      v_existing_expires_at,
      v_existing_message,
      v_existing_perks
  from public.bids as bid
  where bid.request_id = p_request_id
    and bid.provider_id = v_actor_id
  for update;

  begin
    perform private.require_provider_marketplace_eligibility(v_actor_id);
  exception
    when others then
      raise exception 'Provider bid is unavailable' using errcode = '42501';
  end;

  select
    request.customer_id,
    request.category_id,
    request.requested_start,
    request.closes_at
    into
      v_request_customer_id,
      v_category_id,
      v_requested_start,
      v_closes_at
  from public.service_requests as request
  where request.id = p_request_id
  for update;

  if not found then
    raise exception 'Provider bid is unavailable' using errcode = '42501';
  end if;

  perform category.id
  from public.service_categories as category
  where category.id = v_category_id
    and category.active = true
  for share;

  if not found then
    raise exception 'Provider bid is unavailable' using errcode = '42501';
  end if;

  perform service.provider_id
  from public.provider_services as service
  where service.provider_id = v_actor_id
    and service.category_id = v_category_id
    and service.active = true
  for share;

  if not found then
    raise exception 'Provider bid is unavailable' using errcode = '42501';
  end if;

  v_now := pg_catalog.clock_timestamp();
  if v_request_customer_id = v_actor_id
     or not private.provider_request_is_discoverable(
       v_actor_id,
       p_request_id,
       v_now
     ) then
    raise exception 'Provider bid is unavailable' using errcode = '42501';
  end if;

  -- A concurrent first submission is serialized by the request lock. Observe
  -- it here before deciding whether this call is an exact replay.
  if v_bid_id is null then
    select
      bid.id,
      bid.amount_minor,
      bid.currency,
      bid.proposed_start,
      bid.status,
      bid.expires_at,
      bid.message,
      bid.perks
      into
        v_bid_id,
        v_existing_amount,
        v_existing_currency,
        v_existing_start,
        v_existing_status,
        v_existing_expires_at,
        v_existing_message,
        v_existing_perks
    from public.bids as bid
    where bid.request_id = p_request_id
      and bid.provider_id = v_actor_id
    for update;
  end if;

  if v_bid_id is not null then
    if v_existing_amount = p_amount_minor
       and v_existing_currency = 'ZAR'::pg_catalog.bpchar
       and v_existing_start = v_requested_start
       and v_existing_status = 'submitted'::public.bid_status
       and v_existing_expires_at = v_closes_at
       and v_existing_message is null
       and coalesce(pg_catalog.cardinality(v_existing_perks), 0) = 0 then
      return v_bid_id;
    end if;

    raise exception 'Provider bid is unavailable' using errcode = '40001';
  end if;

  perform pg_catalog.set_config(
    'lekkadeall.allow_marketplace_state_transition',
    'on',
    true
  );

  begin
    insert into public.bids (
      request_id,
      provider_id,
      amount_minor,
      currency,
      proposed_start,
      message,
      perks,
      status,
      expires_at
    ) values (
      p_request_id,
      v_actor_id,
      p_amount_minor,
      'ZAR',
      v_requested_start,
      null,
      '{}'::pg_catalog.text[],
      'submitted'::public.bid_status,
      v_closes_at
    )
    returning id into v_bid_id;

    perform private.append_audit_event(
      v_actor_id,
      'provider.bid_submitted',
      'bid',
      v_bid_id::pg_catalog.text,
      'Provider submitted bid through controlled boundary',
      pg_catalog.jsonb_build_object(
        'request_id', p_request_id,
        'amount_minor', p_amount_minor,
        'expires_at', v_closes_at
      )
    );
  exception
    when others then
      perform pg_catalog.set_config(
        'lekkadeall.allow_marketplace_state_transition',
        'off',
        true
      );
      raise;
  end;

  perform pg_catalog.set_config(
    'lekkadeall.allow_marketplace_state_transition',
    'off',
    true
  );
  return v_bid_id;
end;
$$;

create function public.provider_withdraw_bid(
  p_bid_id pg_catalog.uuid
)
returns public.bid_status
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor_id pg_catalog.uuid := auth.uid();
  v_provider_id pg_catalog.uuid;
  v_request_id pg_catalog.uuid;
  v_status public.bid_status;
  v_expires_at pg_catalog.timestamptz;
  v_booking_id pg_catalog.uuid;
  v_rows pg_catalog.int4;
begin
  if v_actor_id is null or p_bid_id is null then
    raise exception 'Provider bid is unavailable' using errcode = '42501';
  end if;

  select
    bid.provider_id,
    bid.request_id,
    bid.status,
    bid.expires_at
    into
      v_provider_id,
      v_request_id,
      v_status,
      v_expires_at
  from public.bids as bid
  where bid.id = p_bid_id
  for update;

  if not found or v_provider_id <> v_actor_id then
    raise exception 'Provider bid is unavailable' using errcode = '42501';
  end if;

  select booking.id
    into v_booking_id
  from public.bookings as booking
  where booking.bid_id = p_bid_id
  for share;

  if v_booking_id is not null then
    raise exception 'Provider bid is unavailable' using errcode = '42501';
  end if;

  if v_status = 'withdrawn'::public.bid_status then
    return 'withdrawn'::public.bid_status;
  end if;

  if v_status <> 'submitted'::public.bid_status
     or v_expires_at <= pg_catalog.clock_timestamp() then
    raise exception 'Provider bid is unavailable' using errcode = '42501';
  end if;

  perform pg_catalog.set_config(
    'lekkadeall.allow_marketplace_state_transition',
    'on',
    true
  );

  begin
    update public.bids as bid
    set status = 'withdrawn'::public.bid_status,
        withdrawn_at = pg_catalog.clock_timestamp(),
        updated_at = pg_catalog.clock_timestamp()
    where bid.id = p_bid_id
      and bid.provider_id = v_actor_id
      and bid.status = 'submitted'::public.bid_status;

    get diagnostics v_rows = row_count;
    if v_rows <> 1 then
      raise exception 'Provider bid is unavailable' using errcode = '42501';
    end if;

    perform private.append_audit_event(
      v_actor_id,
      'provider.bid_withdrawn',
      'bid',
      p_bid_id::pg_catalog.text,
      'Provider withdrew bid through controlled boundary',
      pg_catalog.jsonb_build_object('request_id', v_request_id)
    );
  exception
    when others then
      perform pg_catalog.set_config(
        'lekkadeall.allow_marketplace_state_transition',
        'off',
        true
      );
      raise;
  end;

  perform pg_catalog.set_config(
    'lekkadeall.allow_marketplace_state_transition',
    'off',
    true
  );
  return 'withdrawn'::public.bid_status;
end;
$$;

create function public.provider_read_own_bid(
  p_request_id pg_catalog.uuid
)
returns table (
  bid_id pg_catalog.uuid,
  request_id pg_catalog.uuid,
  amount_minor pg_catalog.int4,
  currency pg_catalog.bpchar,
  proposed_start pg_catalog.timestamptz,
  status public.bid_status,
  expires_at pg_catalog.timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  v_actor_id pg_catalog.uuid := auth.uid();
begin
  if v_actor_id is null or p_request_id is null then
    raise exception 'Provider bid is unavailable' using errcode = '42501';
  end if;

  return query
  select
    bid.id,
    bid.request_id,
    bid.amount_minor,
    bid.currency,
    bid.proposed_start,
    bid.status,
    bid.expires_at
  from public.bids as bid
  where bid.provider_id = v_actor_id
    and bid.request_id = p_request_id;
end;
$$;

comment on function public.provider_submit_bid(
  pg_catalog.uuid,
  pg_catalog.int4
) is
  'Ticket 10D authenticated provider bidding: submits or exactly replays one minimal server-owned bid for a request still discoverable to the current eligible actor.';

comment on function public.provider_withdraw_bid(pg_catalog.uuid) is
  'Ticket 10D risk-reducing provider withdrawal: transitions one owned submitted unlinked bid once and returns the stable withdrawn terminal result on replay.';

comment on function public.provider_read_own_bid(pg_catalog.uuid) is
  'Ticket 10D provider-owned reconciliation read: returns only seven reviewed bid fields for the authenticated actor and request.';

revoke all on function public.provider_submit_bid(
  pg_catalog.uuid,
  pg_catalog.int4
) from public, anon, authenticated, service_role;

revoke all on function public.provider_withdraw_bid(
  pg_catalog.uuid
) from public, anon, authenticated, service_role;

revoke all on function public.provider_read_own_bid(
  pg_catalog.uuid
) from public, anon, authenticated, service_role;

grant execute on function public.provider_submit_bid(
  pg_catalog.uuid,
  pg_catalog.int4
) to authenticated;

grant execute on function public.provider_withdraw_bid(
  pg_catalog.uuid
) to authenticated;

grant execute on function public.provider_read_own_bid(
  pg_catalog.uuid
) to authenticated;
