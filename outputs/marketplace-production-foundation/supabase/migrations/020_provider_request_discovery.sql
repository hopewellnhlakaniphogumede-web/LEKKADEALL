-- Ticket 10C: provider request discovery is one narrow, actor-derived read
-- boundary. Provider browser clients no longer receive open requests through
-- a raw table policy or the legacy broadly-filterable summary RPC.

drop policy if exists "approved providers see open requests"
  on public.service_requests;

revoke all on function public.list_provider_open_request_summaries(
  pg_catalog.text,
  pg_catalog.uuid,
  pg_catalog.int4
) from public, anon, authenticated, service_role;

drop function public.list_provider_open_request_summaries(
  pg_catalog.text,
  pg_catalog.uuid,
  pg_catalog.int4
);

create function public.provider_list_discoverable_requests(
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
  v_now pg_catalog.timestamptz := pg_catalog.statement_timestamp();
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

  -- Reuse the Ticket 10B profile -> provider profile -> eligibility lock
  -- order. A concurrent authority transition must serialize with this read.
  begin
    perform private.require_provider_marketplace_eligibility(v_actor_id);
  exception
    when others then
      raise exception 'Provider request discovery is unavailable'
        using errcode = '42501';
  end;

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
  join public.service_categories as category
    on category.id = request.category_id
   and category.active = true
  join public.provider_services as service
    on service.provider_id = v_actor_id
   and service.category_id = request.category_id
   and service.active = true
  where request.status = 'open'::public.request_status
    and request.published_at is not null
    and request.published_at <= v_now
    and request.closes_at is not null
    and request.closes_at > v_now
    and request.requested_start > v_now
    and request.closes_at < request.requested_start
    and request.awarded_at is null
    and request.cancelled_at is null
    and request.precise_address_ciphertext is null
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
    ) is null
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

comment on function public.provider_list_discoverable_requests(
  pg_catalog.int4,
  pg_catalog.timestamptz,
  pg_catalog.uuid
) is
  'Ticket 10C authenticated provider discovery: returns only ten privacy-screened fields for internally consistent open requests matching the caller current eligibility and active service categories, using bounded keyset pagination.';

revoke all on function public.provider_list_discoverable_requests(
  pg_catalog.int4,
  pg_catalog.timestamptz,
  pg_catalog.uuid
) from public, anon, authenticated, service_role;

grant execute on function public.provider_list_discoverable_requests(
  pg_catalog.int4,
  pg_catalog.timestamptz,
  pg_catalog.uuid
) to authenticated;
