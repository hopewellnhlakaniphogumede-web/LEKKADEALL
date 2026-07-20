-- Ticket 9A-8: strict customer-owned draft content updates.
-- The browser receives one full-replacement RPC for reviewed public draft
-- fields. Workflow state, ownership, exact address, bids, and bookings remain
-- outside this function's authority.

create or replace function public.customer_update_draft_request(
  p_request_id uuid,
  p_category_id uuid,
  p_title text,
  p_description text,
  p_suburb text,
  p_city text,
  p_requested_start timestamptz,
  p_budget_minor integer
)
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role public.user_role;
  v_account_status text;
  v_current_category_id uuid;
  v_current_title text;
  v_current_description text;
  v_current_suburb text;
  v_current_city text;
  v_current_requested_start timestamptz;
  v_current_budget_minor integer;
  v_request_status public.request_status;
  v_closes_at timestamptz;
  v_published_at timestamptz;
  v_awarded_at timestamptz;
  v_cancelled_at timestamptz;
  v_deprecated_address text;
  v_title text;
  v_description text;
  v_suburb text;
  v_city text;
  v_changed_fields text[] := array[]::text[];
  v_changed_rows integer;
  v_changed_at timestamptz;
begin
  if p_request_id is null then
    raise exception 'Draft request ID is required'
      using errcode = '22023';
  end if;

  if p_category_id is null then
    raise exception 'Service category is required'
      using errcode = '22023';
  end if;

  if v_actor_id is null then
    raise exception 'Authentication is required to update a draft'
      using errcode = '42501';
  end if;

  select p.role, p.account_status
    into v_actor_role, v_account_status
  from public.profiles as p
  where p.id = v_actor_id
  for share;

  if not found
     or v_actor_role <> 'customer'::public.user_role
     or v_account_status <> 'active' then
    raise exception 'Draft update is unavailable'
      using errcode = '42501';
  end if;

  select
    sr.category_id,
    sr.title,
    sr.description,
    sr.suburb,
    sr.city,
    sr.requested_start,
    sr.budget_minor,
    sr.status,
    sr.closes_at,
    sr.published_at,
    sr.awarded_at,
    sr.cancelled_at,
    sr.precise_address_ciphertext
    into
      v_current_category_id,
      v_current_title,
      v_current_description,
      v_current_suburb,
      v_current_city,
      v_current_requested_start,
      v_current_budget_minor,
      v_request_status,
      v_closes_at,
      v_published_at,
      v_awarded_at,
      v_cancelled_at,
      v_deprecated_address
  from public.service_requests as sr
  where sr.id = p_request_id
    and sr.customer_id = v_actor_id
  for update;

  if not found
     or v_request_status <> 'draft'::public.request_status
     or v_closes_at is not null
     or v_published_at is not null
     or v_awarded_at is not null
     or v_cancelled_at is not null
     or v_deprecated_address is not null then
    raise exception 'Draft is not available for update'
      using errcode = '42501';
  end if;

  -- A valid private draft cannot have provider selection, any bid, or a
  -- booking. Fail closed on every related row rather than repairing state.
  if exists (
    select 1
    from public.bids as b
    where b.request_id = p_request_id
  ) or exists (
    select 1
    from public.bookings as b
    where b.request_id = p_request_id
  ) then
    raise exception 'Draft is not available for update'
      using errcode = '42501';
  end if;

  perform 1
  from public.service_categories as sc
  where sc.id = p_category_id
    and sc.active = true
  for share;

  if not found then
    raise exception 'Service category is unavailable'
      using errcode = '22023';
  end if;

  if p_requested_start is null or p_requested_start <= pg_catalog.now() then
    raise exception 'Requested start must be in the future'
      using errcode = '22023';
  end if;

  if p_budget_minor is not null and p_budget_minor < 0 then
    raise exception 'Budget is invalid'
      using errcode = '22023';
  end if;

  v_title := private.canonicalize_service_request_public_field('title', p_title);
  v_description := private.canonicalize_service_request_public_field('description', p_description);
  v_suburb := private.canonicalize_service_request_public_field('suburb', p_suburb);
  v_city := private.canonicalize_service_request_public_field('city', p_city);

  perform private.assert_service_request_public_fields(
    v_title,
    v_description,
    v_suburb,
    v_city
  );

  if p_category_id is distinct from v_current_category_id then
    v_changed_fields := pg_catalog.array_append(v_changed_fields, 'category_id');
  end if;
  if v_title is distinct from v_current_title then
    v_changed_fields := pg_catalog.array_append(v_changed_fields, 'title');
  end if;
  if v_description is distinct from v_current_description then
    v_changed_fields := pg_catalog.array_append(v_changed_fields, 'description');
  end if;
  if v_suburb is distinct from v_current_suburb then
    v_changed_fields := pg_catalog.array_append(v_changed_fields, 'suburb');
  end if;
  if v_city is distinct from v_current_city then
    v_changed_fields := pg_catalog.array_append(v_changed_fields, 'city');
  end if;
  if p_requested_start is distinct from v_current_requested_start then
    v_changed_fields := pg_catalog.array_append(v_changed_fields, 'requested_start');
  end if;
  if p_budget_minor is distinct from v_current_budget_minor then
    v_changed_fields := pg_catalog.array_append(v_changed_fields, 'budget_minor');
  end if;

  if pg_catalog.cardinality(v_changed_fields) = 0 then
    raise exception 'No draft changes were provided'
      using errcode = '22023';
  end if;

  v_changed_at := pg_catalog.clock_timestamp();

  -- This is deliberately a content-only update. Do not enable the Ticket 6
  -- marketplace state-transition flag here.
  update public.service_requests as sr
  set category_id = p_category_id,
      title = v_title,
      description = v_description,
      suburb = v_suburb,
      city = v_city,
      requested_start = p_requested_start,
      budget_minor = p_budget_minor,
      updated_at = v_changed_at
  where sr.id = p_request_id
    and sr.customer_id = v_actor_id
    and sr.status = 'draft'::public.request_status
    and sr.closes_at is null
    and sr.published_at is null
    and sr.awarded_at is null
    and sr.cancelled_at is null
    and sr.precise_address_ciphertext is null;

  get diagnostics v_changed_rows = row_count;
  if v_changed_rows <> 1 then
    raise exception 'Draft is not available for update'
      using errcode = '42501';
  end if;

  perform private.append_audit_event(
    v_actor_id,
    'customer.service_request_draft_updated',
    'service_request',
    p_request_id::text,
    'Customer updated own draft service request',
    pg_catalog.jsonb_build_object(
      'request_id', p_request_id,
      'changed_fields', pg_catalog.to_jsonb(v_changed_fields)
    )
  );

  return p_request_id;
end;
$$;

comment on function public.customer_update_draft_request(
  uuid, uuid, text, text, text, text, timestamptz, integer
) is
  'Ticket 9A-8 customer-only RPC: atomically replaces reviewed public fields on one owned, internally consistent draft with no bids or bookings and writes a fixed privacy-safe audit event.';

comment on table public.service_requests is
  'Ticket 6/9A-7/9A-8 controlled workflow: browser clients create drafts through customer_create_draft_request, edit reviewed fields through customer_update_draft_request, and cancel owned drafts through customer_cancel_draft_request. Publication and exact address remain separately blocked in the frontend.';

revoke all on function public.customer_update_draft_request(
  uuid, uuid, text, text, text, text, timestamptz, integer
) from public, anon, authenticated, service_role;

grant execute on function public.customer_update_draft_request(
  uuid, uuid, text, text, text, text, timestamptz, integer
) to authenticated;
