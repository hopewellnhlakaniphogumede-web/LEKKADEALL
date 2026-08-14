-- Ticket 10E: customer-owned current-bid viewing.
-- Bid identifiers become customer-visible only after the legacy acceptance
-- mutation is removed from every browser-accessible and general server role.

revoke all on function public.customer_accept_bid(pg_catalog.uuid)
  from public, anon, authenticated, service_role;

create function public.customer_list_current_bids(
  p_request_id pg_catalog.uuid,
  p_cursor_submitted_at pg_catalog.timestamptz default null,
  p_cursor_bid_id pg_catalog.uuid default null
)
returns table (
  bid_id pg_catalog.uuid,
  amount_minor pg_catalog.int4,
  currency pg_catalog.bpchar,
  proposed_start pg_catalog.timestamptz,
  status public.bid_status,
  expires_at pg_catalog.timestamptz,
  submitted_at pg_catalog.timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  v_actor_id pg_catalog.uuid := auth.uid();
  v_category_id pg_catalog.uuid;
  v_requested_start pg_catalog.timestamptz;
  v_closes_at pg_catalog.timestamptz;
  v_decision_at pg_catalog.timestamptz := pg_catalog.statement_timestamp();
begin
  begin
    if v_actor_id is null
       or p_request_id is null
       or p_request_id = '00000000-0000-0000-0000-000000000000'::pg_catalog.uuid
       or (p_cursor_submitted_at is null) <> (p_cursor_bid_id is null)
       or p_cursor_submitted_at > v_decision_at
       or p_cursor_bid_id = '00000000-0000-0000-0000-000000000000'::pg_catalog.uuid then
      raise exception 'Customer bid viewing is unavailable'
        using errcode = '42501';
    end if;

    select
      request.category_id,
      request.requested_start,
      request.closes_at
      into
        v_category_id,
        v_requested_start,
        v_closes_at
    from public.profiles as profile
    join public.service_requests as request
      on request.customer_id = profile.id
    join public.service_categories as category
      on category.id = request.category_id
     and category.active = true
    where profile.id = v_actor_id
      and profile.role = 'customer'::public.user_role
      and profile.account_status = 'active'
      and request.id = p_request_id
      and request.status = 'open'::public.request_status
      and request.published_at is not null
      and request.published_at <= v_decision_at
      and request.closes_at is not null
      and request.closes_at > v_decision_at
      and request.requested_start > v_decision_at
      and request.closes_at < request.requested_start
      and request.awarded_at is null
      and request.cancelled_at is null
      and request.title = private.canonicalize_service_request_public_field(
        'title',
        request.title
      )
      and request.description = private.canonicalize_service_request_public_field(
        'description',
        request.description
      )
      and request.suburb = private.canonicalize_service_request_public_field(
        'suburb',
        request.suburb
      )
      and request.city = private.canonicalize_service_request_public_field(
        'city',
        request.city
      )
      and private.service_request_public_field_violation(
        'title',
        request.title
      ) is null
      and private.service_request_public_field_violation(
        'description',
        request.description
      ) is null
      and private.service_request_public_field_violation(
        'suburb',
        request.suburb
      ) is null
      and private.service_request_public_field_violation(
        'city',
        request.city
      ) is null;

    if not found then
      raise exception 'Customer bid viewing is unavailable'
        using errcode = '42501';
    end if;

    return query
    select
      bid.id,
      bid.amount_minor,
      bid.currency,
      bid.proposed_start,
      bid.status,
      bid.expires_at,
      bid.created_at
    from public.bids as bid
    join public.provider_services as service
      on service.provider_id = bid.provider_id
     and service.category_id = v_category_id
     and service.active = true
    where bid.request_id = p_request_id
      and bid.status = 'submitted'::public.bid_status
      and bid.amount_minor between 1 and 100000000
      and bid.currency = 'ZAR'::pg_catalog.bpchar
      and bid.proposed_start = v_requested_start
      and bid.expires_at = v_closes_at
      and bid.expires_at > v_decision_at
      and bid.created_at <= v_decision_at
      and bid.updated_at = bid.created_at
      and bid.message is null
      and coalesce(pg_catalog.cardinality(bid.perks), 0) = 0
      and bid.accepted_at is null
      and bid.declined_at is null
      and bid.withdrawn_at is null
      and private.provider_marketplace_eligibility_is_current(
        bid.provider_id,
        v_decision_at
      )
      and (
        p_cursor_submitted_at is null
        or bid.created_at > p_cursor_submitted_at
        or (
          bid.created_at = p_cursor_submitted_at
          and bid.id > p_cursor_bid_id
        )
      )
    order by bid.created_at asc, bid.id asc
    limit 20;
  exception
    when others then
      raise exception 'Customer bid viewing is unavailable'
        using errcode = '42501';
  end;
end;
$$;

comment on function public.customer_list_current_bids(
  pg_catalog.uuid,
  pg_catalog.timestamptz,
  pg_catalog.uuid
) is
  'Ticket 10E authenticated customer read: lists a fixed page of seven canonical current-bid fields for one owned live request without exposing provider identity or adding acceptance capability.';

revoke all on function public.customer_list_current_bids(
  pg_catalog.uuid,
  pg_catalog.timestamptz,
  pg_catalog.uuid
) from public, anon, authenticated, service_role;

grant execute on function public.customer_list_current_bids(
  pg_catalog.uuid,
  pg_catalog.timestamptz,
  pg_catalog.uuid
) to authenticated;
